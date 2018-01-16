#!/usr/bin/env python3

import json
import socket
import subprocess
import sys
import time


def edit_temp_file(temp_file):
    ''' string -> string
    '''
    subprocess.call(['vim', temp_file])

    with open(temp_file, 'r') as fd:
        output = fd.read()

    try:
        output = json.dumps(json.loads(output))

    except json.decoder.JSONDecodeError:
        print('error: file has JSON formatting errors')
        time.sleep(1)
        edit_temp_file(temp_file)

    else:
        return output


def main():
    ''' string -> io
    '''
    edit_mode = False
    remote = ('localhost', 9999)
    args = sys.argv[1:]

    if args[-1] == 'edit':
        edit_mode = True
        temp_file = '/tmp/apocrypha-' + '-'.join(args[:-1]) + '.json'

    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.connect(remote)

    query = '\n'.join(args) + '\n'
    sock.sendall(query.encode('utf-8'))
    sock.shutdown(socket.SHUT_WR)

    result = ''
    while True:
        data = sock.recv(1024)

        if not data:
            sock.close()
            break
        else:
            result += data.decode('utf-8')

    # usual case
    if not edit_mode:
        print(result.strip('\n'))
        return

    # user wants to edit
    #   - write result to temp file
    #   - open with vim
    #   - send temp file back to server
    with open(temp_file, 'w+') as fd:
        fd.write(result)

    output = edit_temp_file(temp_file)

    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.connect(remote)

    query = args[:-1] + ['--set', output]
    query = '\n'.join(query) + '\n'

    sock.sendall(query.encode('utf-8'))
    sock.close()


if __name__ == '__main__':
    main()