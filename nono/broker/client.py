#!/usr/bin/env python3
"""Pass one tuios command to the tuios broker (broker.py) and print its answer
as tuios would: stdout, stderr and the exit code. nono/shims/tuios runs this
for a call the daemon refused with `forbidden`."""

import json
import os
import pathlib
import socket
import sys

SOCKET = pathlib.Path.home() / ".local/state/nono-broker/broker.sock"


def main():
    request = {"argv": sys.argv[1:], "cwd": os.getcwd()}
    try:
        with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as s:
            s.connect(str(SOCKET))
            s.sendall((json.dumps(request) + "\n").encode())
            data = b""
            while not data.endswith(b"\n"):
                chunk = s.recv(65536)
                if not chunk:
                    break
                data += chunk
        reply = json.loads(data)
    except (OSError, ValueError) as e:
        sys.stderr.write(f"tuios: forbidden, and the tuios broker did not answer ({e}). "
                         "Ask the user to run this command.\n")
        return 1
    sys.stdout.write(reply.get("stdout", ""))
    sys.stderr.write(reply.get("stderr", ""))
    return int(reply.get("rc", 1))


if __name__ == "__main__":
    sys.exit(main())
