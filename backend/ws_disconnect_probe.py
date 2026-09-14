"""Ad-hoc probe: connect to the listener/user chat websocket and simulate
(a) an abrupt TCP kill (app force-closed) and (b) a silent network loss
(airplane mode: TCP stays half-open, nothing is ever sent again).

Usage: python ws_disconnect_probe.py <port> <role> <token> <mode>
  mode = kill | silent
"""
import asyncio
import base64
import os
import socket
import sys
import time


async def main():
    port, role, token, mode = int(sys.argv[1]), sys.argv[2], sys.argv[3], sys.argv[4]
    path = f"/chat/ws/{role}?token={token}"
    key = base64.b64encode(os.urandom(16)).decode()
    req = (
        f"GET {path} HTTP/1.1\r\nHost: 127.0.0.1:{port}\r\nUpgrade: websocket\r\n"
        f"Connection: Upgrade\r\nSec-WebSocket-Key: {key}\r\nSec-WebSocket-Version: 13\r\n\r\n"
    )
    s = socket.create_connection(("127.0.0.1", port))
    s.sendall(req.encode())
    resp = s.recv(4096)
    print(f"[{time.strftime('%X')}] handshake:", resp.split(b"\r\n")[0].decode())
    assert b" 101 " in resp, resp
    print(f"[{time.strftime('%X')}] connected, waiting 3s so the server registers us")
    await asyncio.sleep(3)
    if mode == "kill":
        # RST instead of a graceful close frame, like a killed process / dead radio
        s.setsockopt(socket.SOL_SOCKET, socket.SO_LINGER, b"\x01\x00\x00\x00\x00\x00\x00\x00")
        s.close()
        print(f"[{time.strftime('%X')}] socket aborted (RST sent)")
    elif mode == "close":
        # Proper close frame (opcode 0x8, masked, code 1000) like the Flutter
        # app's sink.close() on app pause.
        s.sendall(b"\x88\x82" + b"\x00\x00\x00\x00" + (1000).to_bytes(2, "big"))
        print(f"[{time.strftime('%X')}] close frame sent")
        await asyncio.sleep(1)
        s.close()
    elif mode == "supersede":
        # Second connection from the same account should evict the first one
        # without the account being marked offline in between.
        key2 = base64.b64encode(os.urandom(16)).decode()
        s2 = socket.create_connection(("127.0.0.1", port))
        s2.sendall(req.replace(key, key2).encode())
        assert b" 101 " in s2.recv(4096)
        print(f"[{time.strftime('%X')}] second connection opened; first should now be evicted")
        await asyncio.sleep(3)
        s2.setsockopt(socket.SOL_SOCKET, socket.SO_LINGER, b"\x01\x00\x00\x00\x00\x00\x00\x00")
        s2.close()
        s.close()
        print(f"[{time.strftime('%X')}] both sockets closed")
    else:
        # Keep the TCP socket open but never read/write again. Server pings
        # are simply never answered — exactly what a phone in airplane mode
        # or a suspended app looks like from the server side.
        print(f"[{time.strftime('%X')}] going silent for 90s (no pongs, no app pings)")
        await asyncio.sleep(90)
        s.close()
        print(f"[{time.strftime('%X')}] silent probe done")


asyncio.run(main())
