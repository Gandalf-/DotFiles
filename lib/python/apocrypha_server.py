#!/usr/bin/env python3

'''
Apocrypha Server

    TCP network server that listens for database requests
'''

import apocrypha
import os
import socketserver
import time

database = None
db_path = os.path.expanduser('~') + '/.db.json'


class ApocryphaServer(apocrypha.Apocrypha):

    def __init__(self, path):
        ''' filepath -> ApocryphaServer

        @path       full path to the database json file

        headless=True means that results get saved to self.output, which we
        return to the client instead of printing to stdout
        '''
        apocrypha.Apocrypha.__init__(
            self, path, add_context=False, headless=True)

    def action(self, args, read_only=False):
        ''' list of string, maybe bool -> none

        @args       arguments from the user
        @read_only  do not write changes to the database file

        This overrides the default, which saves the database after giving the
        response to the user to only give the response
        '''
        key = ''.join(args)

        if key in self.cache:
            self.output = self.cache[key]

        else:
            self._action(self.db, args, create=True)
            self.cache[key] = self.output


class Handler(socketserver.BaseRequestHandler):
    '''
    The request handler class for our server.

    It is instantiated once per connection to the server, and must
    override the handle() method to implement communication to the
    client.
    '''
    def handle(self):
        ''' none -> none

        self.request is the TCP socket connected to the client
        '''

        # get query, parse into arguments
        start = int(round(time.time() * 100000))
        self.data = ''
        while True:
            data = self.request.recv(1024).strip().decode("utf-8")

            if not data:
                break
            else:
                self.data += data

        args = self.data.split('\n') if self.data else []

        if len(args) > 0 and args[0] == '-c':
            args = args[1:]
            database.add_context = True

        result = ''
        try:
            # send the arguments to the Apocrypha instance, read_only=True
            # means that we don't write out the changes immediately

            database.action(args, read_only=True)
            result = '\n'.join(database.output)

        except apocrypha.ApocryphaError as error:
            # user, usage error
            result = str(error)

        finally:
            if result:
                result += '\n'

        # send reply to client
        self.request.sendall(result.encode('utf-8'))
        end = int(round(time.time() * 100000))

        # reset output, save changes if needed
        database.add_context = False
        database.output = []
        database.save_db()

        print('query: ({t:4}) {a}'.format(t=end-start, a=str(args)[:50]))


class Server(socketserver.TCPServer):
    '''
    TCPServer that allows address reuse
    '''
    allow_reuse_address = True


if __name__ == '__main__':
    host, port = '0.0.0.0', 9999

    # create the ApocryphaServer instance
    database = ApocryphaServer(db_path)

    # Create the server, binding to localhost on port 9999
    server = Server((host, port), Handler)

    try:
        print('starting')
        server.serve_forever()

    except KeyboardInterrupt:
        print('exiting')
