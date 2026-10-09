"""Read-only LX corpus audit against the production framed SourceHost protocol.

Reports omit media URLs and tokens. Each script has its own process; no user
profile is opened. Run again with the same inputs to compare runtime versions.
"""
import argparse
import concurrent.futures
import hashlib
import json
import os
from pathlib import Path
import queue
import re
import struct
import subprocess
import threading
import time
import urllib.request
import urllib.parse


def safe(value):
    return re.sub(r'https?://[^\s\"\'<>]+', '[URL]', str(value))[:2000]


class Host:
    def __init__(self, executable, standalone=False):
        root = Path(__file__).resolve().parents[1]
        env = os.environ.copy()
        bins = [executable.parent, Path('F:/QT/6.11.2/mingw_64/bin'),
                Path('F:/QT/Tools/mingw1310_64/bin'), root/'.vcpkg_installed/x64-mingw-dynamic/bin']
        env['PATH'] = os.pathsep.join(map(str, bins)) + os.pathsep + env['PATH']
        if standalone:
            system = Path(os.environ['SystemRoot'])
            env['PATH'] = os.pathsep.join(map(str, [executable.parent, system/'System32', system]))
            for variable in ['QT_PLUGIN_PATH', 'QML2_IMPORT_PATH', 'QML_IMPORT_PATH',
                             'QT_QPA_PLATFORM_PLUGIN_PATH', 'QMMP_PLUGINS']:
                env.pop(variable, None)
        self.process = subprocess.Popen([str(executable)], stdin=subprocess.PIPE,
            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, env=env,
            creationflags=subprocess.CREATE_NO_WINDOW)
        self.messages = queue.Queue()
        def read():
            try:
                while True:
                    header = self.process.stdout.read(4)
                    if len(header) != 4:
                        break
                    size = struct.unpack('>I', header)[0]
                    if size > 1024*1024:
                        break
                    self.messages.put(json.loads(self.process.stdout.read(size)))
            finally:
                self.messages.put(None)
        self.reader = threading.Thread(target=read, daemon=True)
        self.reader.start()

    def call(self, kind, request_id, payload, timeout):
        raw = json.dumps(dict(protocolVersion=1, messageType=kind,
                             requestId=request_id, payload=payload)).encode()
        self.process.stdin.write(struct.pack('>I', len(raw))+raw)
        self.process.stdin.flush()
        end = time.monotonic()+timeout
        while time.monotonic() < end:
            try:
                message = self.messages.get(timeout=max(.01, end-time.monotonic()))
            except queue.Empty:
                return {'messageType': 'timeout', 'payload': {'code': 'audit.timeout'}}
            if message is None:
                return {'messageType': 'exit', 'payload': {'code': 'audit.host-exited'}}
            if message.get('requestId') == request_id:
                return message
        return {'messageType': 'timeout', 'payload': {'code': 'audit.timeout'}}

    def close(self):
        if self.process.poll() is None:
            self.process.kill()
        self.process.wait()
        self.reader.join(timeout=2)
        for pipe in (self.process.stdin, self.process.stdout):
            pipe.close()


SAMPLES = {
    'wy': dict(source='wy', songmid='186016', id='186016', name='晴天', singer='周杰伦', albumName='叶惠美'),
    'kw': dict(source='kw', songmid='450444', rid='450444', name='晴天', singer='周杰伦', albumName='叶惠美'),
}


def fetch_online(url, directory):
    parsed = urllib.parse.urlsplit(url)
    report = {'endpoint': parsed.netloc+parsed.path}
    if '卡密' in url:
        return dict(report, result='requires-user-key')
    try:
        request = urllib.request.Request(urllib.parse.quote(url, safe=':/?&=#%+,.@~!()*;[]-'),
                                         headers={'User-Agent': 'LX-Source-Contract-Audit/1.0'})
        with urllib.request.urlopen(request, timeout=15) as response:
            data = response.read(1024*1024+1)
        if not data or len(data) > 1024*1024 or data.lstrip().lower().startswith((b'<!doctype', b'<html')):
            return dict(report, result='invalid-script-download')
        name = hashlib.sha256(url.encode()).hexdigest()[:12]+'.js'
        target = directory/name
        target.write_bytes(data)
        return dict(report, result='downloaded', file=name, bytes=len(data))
    except Exception as error:
        return dict(report, result='download-failed', error=safe(error))


def probe_media(url):
    # Only inspect a bounded prefix. Never persist signed addresses or content.
    try:
        request = urllib.request.Request(url, headers={'Range': 'bytes=0-4095'})
        with urllib.request.urlopen(request, timeout=10) as response:
            data = response.read(4096)
            status = response.status
            content_type = response.headers.get('Content-Type', '').split(';')[0]
        if data.startswith(b'fLaC') or (data.startswith(b'ID3') and b'fLaC' in data):
            signature = 'flac'
        elif data.startswith(b'ID3') or (len(data) > 1 and data[0] == 255 and data[1] & 224 == 224):
            signature = 'mpeg-audio'
        elif data.startswith(b'OggS'):
            signature = 'ogg'
        elif len(data) >= 12 and data[4:8] == b'ftyp':
            signature = 'mp4'
        elif data.startswith(b'RIFF') and data[8:12] == b'WAVE':
            signature = 'wav'
        else:
            signature = 'unrecognized'
        return dict(status=status, contentType=content_type, prefixBytes=len(data), signature=signature)
    except Exception as error:
        return dict(error=safe(error))


def audit(executable, path, resolve_timeout, inspect_media=False):
    report = {'file': path.name, 'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}
    host = Host(executable)
    try:
        start = time.monotonic()
        load = host.call('loadPlugin', 'load', {'path': str(path.resolve())}, 65)
        report['loadSeconds'] = round(time.monotonic()-start, 3)
        report['load'] = load['messageType']
        if load['messageType'] != 'result':
            report['error'] = safe(load['payload'])
        else:
            sources = load['payload'].get('sources', {})
            report['sources'] = sources
            report['resolutions'] = []
            for platform, sample in SAMPLES.items():
                info = sources.get(platform, {})
                if 'musicUrl' not in info.get('actions', []):
                    continue
                choices = info.get('qualitys', [])
                quality = '128k' if '128k' in choices else ('320k' if '320k' in choices else next(iter(choices), ''))
                start = time.monotonic()
                response = host.call('resolveMusicUrl', 'resolve-'+platform,
                    {'source': platform, 'type': quality, 'musicInfo': sample}, resolve_timeout)
                row = {'platform': platform, 'quality': quality, 'result': response['messageType'],
                       'seconds': round(time.monotonic()-start, 3)}
                if response['messageType'] == 'result':
                    data = response['payload'].get('data', {})
                    row['urlReturned'] = bool(data.get('url')) if isinstance(data, dict) else bool(data)
                    if inspect_media and row['urlReturned']:
                        row['media'] = probe_media(data.get('url') if isinstance(data, dict) else data)
                else:
                    row['error'] = safe(response['payload'])
                report['resolutions'].append(row)
                if response['messageType'] == 'timeout':
                    host.call('cancel', 'cancel-'+platform, {'requestId': 'resolve-'+platform}, 2)
    except Exception as error:
        report['error'] = safe(error)
    finally:
        host.close()
    return report


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--root', type=Path, required=True)
    ap.add_argument('--host', type=Path, required=True)
    ap.add_argument('--output', type=Path, required=True)
    ap.add_argument('--timeout', type=float, default=16)
    ap.add_argument('--workers', type=int, default=3)
    ap.add_argument('--fetch-online', action='store_true')
    ap.add_argument('--samples', type=Path, help='JSON map of platform to genuine LX musicInfo')
    ap.add_argument('--probe-media', action='store_true', help='Inspect a bounded prefix of returned streams')
    args = ap.parse_args()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    if args.samples:
        SAMPLES.clear()
        SAMPLES.update(json.loads(args.samples.read_text(encoding='utf-8')))
    scripts = sorted(args.root.rglob('*.js'))
    if args.fetch_online:
        urls = sorted(set(url.rstrip('。') for path in args.root.rglob('*.txt')
            for url in re.findall(r'https?://[^\s<>，（）]+', path.read_text(encoding='utf-8-sig'))))
        directory = args.output.parent/'online-scripts'
        directory.mkdir(exist_ok=True)
        with concurrent.futures.ThreadPoolExecutor(max_workers=args.workers) as pool:
            downloads = list(pool.map(lambda url: fetch_online(url, directory), urls))
        args.output.with_suffix('.downloads.json').write_text(
            json.dumps(downloads, ensure_ascii=False, indent=2), encoding='utf-8')
        scripts.extend(directory/item['file'] for item in downloads if item['result']=='downloaded')
    reports = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.workers) as pool:
        jobs = [pool.submit(audit, args.host.resolve(), path, args.timeout, args.probe_media) for path in scripts]
        for job in concurrent.futures.as_completed(jobs):
            result = job.result()
            reports.append(result)
            args.output.write_text(json.dumps(reports, ensure_ascii=False, indent=2), encoding='utf-8')
            print(json.dumps(result, ensure_ascii=True), flush=True)


if __name__ == '__main__':
    main()
