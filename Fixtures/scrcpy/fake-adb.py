#!/usr/bin/python3
"""No-device executable peer for the production scrcpy adapter. Never invokes adb."""
import json
import pathlib
import socket
import struct
import sys
import time

root = pathlib.Path(__file__).parent
args = sys.argv[1:]
assert args[:2] == ['-s', 'FAKE-SERIAL'], args
args = args[2:]
with (root / 'commands.jsonl').open('a') as log:
    log.write(json.dumps(args) + '\n')
if args[0] == 'push':
    sys.exit(0)
if args[0] == 'forward':
    if args[1] == '--remove':
        (root / 'cleaned').write_text('yes')
    else:
        with socket.socket() as probe:
            probe.bind(('127.0.0.1', 0))
            port = probe.getsockname()[1]
        (root / 'port').write_text(str(port))
        print(port)
    sys.exit(0)
if args[:2] == ['shell', 'rm']:
    sys.exit(0)
assert 'com.genymobile.scrcpy.Server' in args
for flag in ['3.3.4', 'video=false', 'audio=false', 'control=true', 'clipboard_autosync=false', 'power_on=false']:
    assert flag in args
with socket.socket() as server:
    server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    server.bind(('127.0.0.1', int((root / 'port').read_text())))
    server.listen()
    premature, _ = server.accept()
    premature.close()  # Real ADB forward can accept before the remote server is listening.
    conn, _ = server.accept()
    with conn:
        assert 'send_dummy_byte=true' in args
        conn.sendall(b'\0')
        conn.settimeout(5)
        def read(n):
            data = b''
            while len(data) < n:
                chunk = conn.recv(n - len(data))
                if not chunk:
                    sys.exit(0)
                data += chunk
            return data
        text = 'Galaxy 한글😀'.encode()
        while True:
            kind = read(1)[0]
            if kind == 8:
                assert read(1) == b'\0'  # no COPY key
                if (root / 'deny').exists():
                    continue
                wire = b'\0' + struct.pack('>I', len(text)) + text
                conn.sendall(wire[:3])
                time.sleep(.002)
                conn.sendall(wire[3:])
            elif kind == 9:
                seq = read(8)
                assert read(1) == b'\0'  # paste=false
                size = struct.unpack('>I', read(4))[0]
                text = read(size)
                if (root / 'reject-write').exists():
                    text = b'conflict'
                (root / 'write-size').write_text(str(size))
                conn.sendall(b'\1' + seq)
            else:
                raise AssertionError('Unexpected input injection type')
