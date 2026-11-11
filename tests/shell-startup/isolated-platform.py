#!/usr/bin/env python3
"""Read-through test proxy: confine shell state writes and reject session mutations.

Usage: isolated-platform.py SOCKET STATE_DIRECTORY [UPSTREAM_SOCKET]
Use with KOS_PLATFORM_SOCKET and a test entrypoint with its own StateDir pragma.
The optional upstream supplies real read snapshots; no wallpaper/theme/shortcut
operation is forwarded. This keeps visual startup tests out of session settings.
"""
import asyncio
import json
import pathlib
import sys

socket_path = pathlib.Path(sys.argv[1])
state = pathlib.Path(sys.argv[2]).resolve()
upstream = sys.argv[3] if len(sys.argv) > 3 else None
READS = {
    "session.visibility", "application.widget-snapshot", "appmenu.active",
    "audio.get", "bluetooth.list", "display.outputs.get", "file.trash-state",
    "network.refresh", "network.traffic", "power.profiles", "power.battery",
    "nightlight.get", "keepawake.get", "tray.identify",
}

async def serve(reader, writer):
    upstream_reader = upstream_writer = None
    if upstream:
        upstream_reader, upstream_writer = await asyncio.open_unix_connection(upstream)

    async def relay():
        while line := await upstream_reader.readline():
            writer.write(line)
            await writer.drain()

    relay_task = asyncio.create_task(relay()) if upstream_reader else None
    try:
        while line := await reader.readline():
            request = json.loads(line)
            op, payload = request.get('operation'), request.get('payload', {})
            response = dict(version=1, requestId=request.get('requestId'), ok=True, result={})
            if op in ('state.read', 'state.write'):
                # Discard the caller's state namespace; keep its component directory.
                component = pathlib.Path(payload.get('dir', '')).name
                path = (state / component / payload.get('file', '')).resolve()
                if not path.is_relative_to(state):
                    raise ValueError('state path escaped test directory')
                if op == 'state.read':
                    response['result'] = dict(exists=path.exists(), data=path.read_text() if path.exists() else '')
                else:
                    path.parent.mkdir(parents=True, exist_ok=True)
                    path.write_text(payload['data'])
            elif op == 'platform.ping':
                response['result'] = dict(capabilities=['state.read', 'state.write'])
            elif upstream_writer and op in READS:
                upstream_writer.write(line)
                await upstream_writer.drain()
                continue
            else:
                response.update(ok=False, error=dict(code='test-isolation', message='Session writes disabled in startup test'))
            writer.write((json.dumps(response) + '\n').encode())
            await writer.drain()
    finally:
        if relay_task:
            relay_task.cancel()
        if upstream_writer:
            upstream_writer.close()
        writer.close()

async def main():
    state.mkdir(parents=True, exist_ok=True)
    server = await asyncio.start_unix_server(serve, path=str(socket_path))
    print('isolated platform ready: ' + str(socket_path), flush=True)
    async with server:
        await server.serve_forever()

asyncio.run(main())
