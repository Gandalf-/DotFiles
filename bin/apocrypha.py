#!/usr/bin/env python3

'''
Apocrypha

    A flexible, json based database that supports
    - strings, lists, dictionaries
    - references to other keys
    - arbitrary depth indexing and assignment
    - symbolic links to other keys at any level
    - server and client for performance
'''

import json
import pprint
import sys
import threading


class ApocryphaError(Exception):
    pass


class Apocrypha(object):

    type_error = 'cannot index through value. {a} -> {b} -> ?, {b} :: value'

    def __init__(self, path, add_context=False, headless=False):
        ''' string, maybe bool, maybe bool -> Apocrypha

        @path       full path to the database json file
        @context    add context to output, instead of "value", "key = value"
        @headless   don't write to stdout, save in self.output
        '''
        self.add_context = add_context
        self.flush = False
        self.headless = headless

        data = threading.local()
        data.output = []
        self.output = data.output

        self.path = path
        self.lock = threading.Lock()

        with open(path, 'r') as fd:
            self.db = json.load(fd)

    def action(self, args, read_only=False):
        ''' list of string, maybe bool -> none

        @args       arguments from the user
        @read_only  do not write changes to the database file

        Perform the database actions required from the arguments, handle
        output and save changes if required
        '''
        self._action(self.db, self.db, args, create=True)

        if not self.headless:
            print('\n'.join(self.output))

        if not read_only:
            self.save_db()

    def save_db(self):
        ''' none -> none

        Normalize and write out the database, but only if self.flush is True
        '''

        self.lock.acquire()

        if self.flush:
            self.normalize(self.db)

            # write the updated values back out
            with open(self.path, 'w') as fd:
                json.dump(self.db, fd, sort_keys=True)

        self.lock.release()

    def assign(self, base, left, right):
        ''' dict, any, any -> none
        '''
        self.lock.acquire()

        base[left] = right

        self.lock.release()

    def _action(self, db, base, keys, create=False):
        ''' dict, dict, list of string -> bool

        Move through the input arguments to
            - index further into the database
            - delete keys
            - assign values to keys
        '''
        last_base = {}

        for i, key in enumerate(keys):

            # assignment
            if key == '=':
                left = keys[i - 1]
                right = keys[i + 1:]

                # single = string, multi = list
                right = right[0] if len(right) == 1 else right

                self.assign(last_base, left, right)
                self.flush = True
                return

            # append a value or values to a list
            elif key == '+':
                left = keys[i - 1]      # string
                right = keys[i + 1:]    # list of string

                # creation of a new value
                if not last_base[left]:
                    if len(right) == 1:
                        right = right[0]

                    self.assign(last_base, left, right)

                # value exists but not a list, create list and add
                elif not isinstance(last_base[left], list):
                    # last_base[left] = [last_base[left]] + right
                    self.assign(last_base, left, [last_base[left]] + right)

                # add to existing list
                else:
                    self.lock.acquire()
                    last_base[left] += right
                    self.lock.release()

                self.flush = True
                return

            # print the keys defined at this level
            elif key == 'keys':
                for base_key in base.keys():
                    self.display(base_key)
                return

            # open up this level in Vim for modification
            elif key == 'edit':
                self.output = [json.dumps(base, indent=4, sort_keys=True)]
                return

            elif key == '--set':
                left = keys[i - 1]

                try:
                    right = json.loads(keys[i + 1])

                except json.decoder.JSONDecodeError:
                    self.error('malformed json')

                if right:

                    if last_base:
                        self.assign(last_base, left, right)
                    else:
                        # global overwrite
                        self.lock.acquire()
                        self.db = right
                        self.lock.release()

                    self.flush = True
                return

            # remove a value from a list
            elif key == '-':
                left = keys[i - 1]
                right = keys[i + 1]

                self.lock.acquire()
                self.list_remove(left, right, last_base)
                self.lock.release()

                if len(last_base[left]) == 1:
                    last_base[left] = last_base[left][0]

                self.flush = True
                return

            # wildcard, value -> key
            elif key == '@':
                self.search(db, keys[i + 1], keys[:i])
                return

            # remove
            elif key == 'del':
                self.lock.acquire()
                del(last_base[keys[i - 1]])
                self.lock.release()

                self.flush = True
                return

            # index
            else:

                # keep track of the level before so we can modify this level
                last_base = base
                key_is_reference = False
                base_is_reference = False

                if key[0] == '!':
                    key = key[1:]
                    key_is_reference = True

                if isinstance(base, str) and base[0] == '!':
                    base = base[1:]
                    base_is_reference = True

                try:
                    if base_is_reference:
                        # we're rebasing ourselves on the dereferenced value of
                        # our current base. we keep all arguments
                        #
                        # this means that we're trying to index through a
                        # reference
                        self.dereference(base, keys[i:], create=True)
                        return

                    base = base[key]

                    if key_is_reference:
                        # this means we're trying to get the value of a
                        # reference
                        self.dereference(base, keys[i + 1:], True)
                        return

                except KeyError:
                    if not create:
                        self.error(key + ' not found')

                    # create a new key
                    base[key] = {}
                    base = base[key]

                except TypeError:
                    self.error(Apocrypha.type_error.format(a=base, b=key))

        # context = keys[-1] if len(keys) > 0 else None
        self.display(base, ' = '.join(keys[:-1]))

    def dereference(self, base, args, create):
        ''' list of string, int, dict, dict, bool -> none

        @keys   list of database keys to check
        @i      position in the input keys
        @base   current object that we're working with, corresponds to a
                "level" in the database
        @create whether or not to add new indexes to the database, if false
                will throw an error if an index that doesn't exist is accessed

        Dereferences always start at the top level of the database, hence the
            action(db, db, ...)

            $ d pointer = value
            $ d !pointer
            value

        Spaces are significant in value being treated as references. A space
        denotes a new level of indexing from the top level

            $ d pointer = 'one two'
            $ d one two = value
            $ d !pointer
            value
        '''

        # current value is a string
        if isinstance(base, str):
            self._action(
                self.db, self.db,
                base.split(' ') + args, create=create)

        # current value is iterable
        else:
            for reference in base:
                self._action(
                    self.db, self.db,
                    reference.split(' ') + args, create=create)

    def display(self, value, context=None):
        ''' any, maybe string -> none

        @value      string, list or dict to add to output
        @context    additional information to include in output

        Figure out what a value is, and print it correctly, dereferences
        symlinks automatically
        '''
        if not value:
            return

        result, base = [], ''

        if context and self.add_context:
            base = context + ' = '

        # string
        if isinstance(value, str):
            if value[0] == '!':
                value = value[1:]
                self.dereference(value, [], False)
            else:
                result += [base + str(value)]

        # list
        elif isinstance(value, list):
            for elem in value:
                if elem[0] == '!':
                    elem = elem[1:]
                    self.dereference(elem, [], False)
                else:
                    result += [base + str(elem)]

        # dict
        else:
            result += [base + pprint.pformat(value)]

        self.output += result

    def search(self, base, key, context):
        ''' any, string, list of string -> none

        @base       the object to search through
        @key        value to find
        @context    additional information to pass onto display()

        Recursively search through the base dictionary, print out all the keys
        that have the given value '''

        # list
        if isinstance(base, list):
            for e in [_ for _ in base if _ == key]:
                if e == key:
                    self.display(
                        context[-1], context=' = '.join(context[:-1]))
            return

        # dict
        for k, v in base.items():
            if v == key:
                self.display(k, context=' = '.join(context))

            elif isinstance(v, dict) or isinstance(v, list):
                self.search(v, key, context + [k])

    def error(self, message):
        ''' string -> none | IO

        @message    description of the error that occurred
        #impure     self.output

        Send an error to the user and stop execution
        '''
        message = 'error: ' + message

        if self.headless:
            self.output += [message]
            raise ApocryphaError(message)

        print(message)
        sys.exit(1)

    def list_remove(self, left, right, base):
        ''' string, string, dict -> none
        '''
        fuzzy = False
        if right[0] == '`':
            fuzzy = True
            right = right[1:]

        if not isinstance(base[left], list):
            self.error('cannot subtract from non list value')

        try:
            if fuzzy:
                right = [_ for _ in base[left] if right in _].pop()

            base[left].remove(right)

        except (IndexError, ValueError):
            self.error('{a} not in {b}'.format(a=right, b=left))

    def normalize(self, db):
        ''' dict -> none

        Finds lists of a single element and converts them into singletons
        '''

        for k, v in list(db.items()):
            if not v:
                del(db[k])

            if isinstance(v, list) and len(v) == 1:
                db[k] = v[0]

            if isinstance(v, dict):
                self.normalize(v)
