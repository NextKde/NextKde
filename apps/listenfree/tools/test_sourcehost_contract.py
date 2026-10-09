"""Deterministic contract tests of the real native SourceHost executable."""
import argparse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
from pathlib import Path
import tempfile
import threading
import time
import unittest
from urllib.parse import parse_qs

from audit_source_corpus import Host

HOST_PATH = None
STANDALONE = False


class Handler(BaseHTTPRequestHandler):
    requests = []
    def log_message(self, *args):
        pass
    def do_GET(self):
        self.respond()
    def do_POST(self):
        self.respond()
    def do_DELETE(self):
        self.respond()
    def respond(self):
        body = self.rfile.read(int(self.headers.get('content-length', '0')))
        self.requests.append((self.command, self.path, body))
        if self.path == '/scalar':
            code, data = 200, b'42'
        elif self.path == '/binary':
            code, data = 200, bytes([0, 255, 128, 65])
        elif self.path == '/form':
            code, data = 200, json.dumps(parse_qs(body.decode())).encode()
        else:
            code, data = int(self.path.strip('/') or '200'), b'{"code":429,"message":"busy"}'
        self.send_response(code)
        self.send_header('Content-Length', str(len(data)))
        self.send_header('X-Contract', 'present')
        self.end_headers()
        self.wfile.write(data)


class Contract(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()
        cls.url = 'http://127.0.0.1:'+str(cls.server.server_port)
    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()
        cls.thread.join()
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.host = Host(HOST_PATH, standalone=STANDALONE)
        self.addCleanup(self.temp.cleanup)
        self.addCleanup(self.host.close)
    def load(self, script, expected='result', request='load'):
        path = Path(self.temp.name)/(request+'.js')
        path.write_text(script, encoding='utf-8')
        response = self.host.call('loadPlugin', request, {'path': str(path)}, 4)
        self.assertEqual(response['messageType'], expected, response)
        return response
    def resolve(self, request='resolve', ident='test', timeout=4):
        return self.host.call('resolveMusicUrl', request, dict(source='kw', type='128k',
            musicInfo={'id': ident, 'songmid': '450444', 'source': 'kw'}), timeout)
    def result(self, response):
        self.assertEqual(response['messageType'], 'result', response)
        self.assertEqual(response['payload']['data']['url'], 'https://media.invalid/ok.mp3')

    INIT = "lx.send(lx.EVENT_NAMES.inited,{sources:{kw:{type:'music',actions:['musicUrl'],qualitys:['128k']}}});"
    OK = "return 'https://media.invalid/ok.mp3';"

    def test_browser_environment_and_binary_buffers(self):
        self.load("""
if (window !== globalThis || self !== globalThis) throw Error('aliases');
const url = new URL('../a b?x=1', 'https://example.org/base/path');
url.searchParams.append('q', 'a+b &中');
if (url.href !== 'https://example.org/a%20b?x=1&q=a%2Bb+%26%E4%B8%AD') throw Error(url.href);
if (new URLSearchParams({q:'a+b &中'}).get('q') !== 'a+b &中') throw Error('query');
if (new URL('https://例子.测试/').hostname !== 'xn--fsqu00a.xn--0zwm56d') throw Error('idna');
const data = Buffer.from(new Uint8Array([0,255,128,65]));
if (data[1] !== 255 || !Buffer.isBuffer(data) || !(data instanceof Uint8Array)) throw Error('buffer');
data[3] = 66;
if (data.toString('hex') !== '00ff8042' || data.subarray(1,3).toString('hex') !== 'ff80') throw Error('bytes');
if (Buffer.from([228,184,173]).toString() !== '中') throw Error('utf8');
if (atob(btoa(String.fromCharCode(0,255))) !== String.fromCharCode(0,255)) throw Error('base64');
console.group('test');console.groupCollapsed();console.groupEnd();console.table({a:1});console.count();
"""+self.INIT+"lx.on(lx.EVENT_NAMES.request, async()=>{"+self.OK+"});")
        self.result(self.resolve())

    def test_timer_initialization_and_resolution(self):
        self.load("setTimeout(()=>{"+self.INIT+"},25);"+
            "lx.on(lx.EVENT_NAMES.request,()=>new Promise(resolve=>setTimeout(()=>resolve('https://media.invalid/ok.mp3'),25)));")
        self.result(self.resolve())

    def test_http_error_responses_and_scalar_json(self):
        for status in [404, 429, 500, 503]:
            self.load(self.INIT+f"""
lx.on(lx.EVENT_NAMES.request,()=>new Promise((resolve,reject)=>{{
  setTimeout(()=>lx.request('{self.url}/{status}',{{}},(err,resp,body)=>{{
    if(err) return reject(err);
    if(resp.statusCode !== {status} || !resp.statusMessage || resp.headers['x-contract'] !== 'present' ||
       body.message !== 'busy' || resp.body !== body) return reject(Error('http contract'));
    resolve('https://media.invalid/ok.mp3');
  }}),10);
}}));""", request='load-'+str(status))
            self.result(self.resolve('resolve-'+str(status)))
        self.load(self.INIT+f"""
lx.on(lx.EVENT_NAMES.request,()=>new Promise((resolve,reject)=>lx.request('{self.url}/scalar',{{}},(err,resp,body)=>{{
 if(err || body !== 42 || resp.body !== 42) return reject(Error('scalar'));
 resolve('https://media.invalid/ok.mp3');
}})));""", request='load-scalar')
        self.result(self.resolve('resolve-scalar'))

    def test_binary_response_and_delete_body(self):
        self.load(self.INIT+f"""
lx.on(lx.EVENT_NAMES.request,()=>new Promise((resolve,reject)=>lx.request('{self.url}/binary',{{
 method:'DELETE',body:Buffer.from([0,255,128,65])
}},(err,resp)=>{{
 if(err || !Buffer.isBuffer(resp.raw) || resp.raw[1] !== 255 || resp.raw.toString('hex') !== '00ff8041')
    return reject(Error('raw bytes'));
 resolve('https://media.invalid/ok.mp3');
}})));""")
        self.result(self.resolve())
        self.assertEqual(Handler.requests[-1], ('DELETE', '/binary', bytes([0,255,128,65])))

    def test_form_reserved_characters_and_numbers(self):
        self.load(self.INIT+f"""
lx.on(lx.EVENT_NAMES.request,()=>new Promise((resolve,reject)=>lx.request('{self.url}/form',{{
 method:'POST',form:{{q:'a+b &中',count:12,enabled:true}}
}},(err,resp,body)=>{{
 if(err || body.q[0] !== 'a+b &中' || body.count[0] !== '12' || body.enabled[0] !== 'true')
   return reject(Error('form serialization'));
 resolve('https://media.invalid/ok.mp3');
}})));""")
        self.result(self.resolve())

    def test_crypto_strings_typed_arrays_and_empty_zlib(self):
        # Expected ciphertext is from Node createCipheriv, the LX implementation.
        self.load(self.INIT+"""
lx.on(lx.EVENT_NAMES.request,async()=>{
 const {crypto,buffer,zlib} = lx.utils;
 if(crypto.md5(Buffer.from([0,255,128,65])) !== 'f18b726f4fc449cfd32cbe8e92bceb40') throw Error('binary MD5');
 const cbc = crypto.aesEncrypt('中文 binary','aes-128-cbc','0123456789abcdef','abcdef9876543210');
 const ecb = crypto.aesEncrypt(new Uint8Array(Buffer.from('中文 binary')),'aes-128-ecb',Buffer.from('0123456789abcdef'),null);
 if(!Buffer.isBuffer(cbc) || cbc.toString('hex') !== 'c419ebababf3867cbc17a830a2ef5915' ||
    ecb.toString('hex') !== '66d5ea002fa2f099c8c7a715c773fbc5') throw Error('AES contract');
 if(crypto.randomBytes(0).length !== 0 || crypto.randomBytes(24).length !== 24) throw Error('random bytes');
 for(const bytes of [Buffer.alloc(0),Buffer.from([0,255,128,65])]) {
   const decoded = await zlib.inflate(await zlib.deflate(bytes));
   if(!Buffer.isBuffer(decoded) || !bytes.equals(decoded)) throw Error('zlib round trip');
 }
 let rejected = false;
 try { await zlib.inflate(Buffer.from('invalid compressed data')); } catch(_) { rejected = true; }
 if(!rejected || buffer.bufToString(String.fromCharCode(0,255),'hex') !== '00ff') throw Error('binary contract');
 return 'https://media.invalid/ok.mp3';
});""")
        self.result(self.resolve())

    def test_callback_exception_still_drains_settled_promises(self):
        for kind in ['timer', 'network']:
            callback = "resolve('https://media.invalid/ok.mp3'); throw Error('background after settlement');"
            start = ('setTimeout(()=>{'+callback+'},10)' if kind == 'timer' else
                     f"lx.request('{self.url}/200',{{}},()=>{{{callback}}})")
            self.load(self.INIT+"lx.on(lx.EVENT_NAMES.request,()=>new Promise(resolve=>{"+start+"}));",
                      request='load-'+kind)
            self.result(self.resolve('resolve-'+kind))

    def test_cancel_stops_timer_and_its_network_chain(self):
        before = len(Handler.requests)
        self.load(self.INIT+f"""
lx.on(lx.EVENT_NAMES.request,()=>new Promise(resolve=>setTimeout(()=>{{
 lx.request('{self.url}/200',{{}},()=>resolve('https://media.invalid/ok.mp3'));
}},150)));""")
        self.assertEqual(self.resolve(timeout=.02)['messageType'], 'timeout')
        self.host.call('cancel','cancel',{'requestId':'resolve'},2)
        time.sleep(.25)
        self.assertEqual(len(Handler.requests), before)
        self.load(self.INIT+"lx.on(lx.EVENT_NAMES.request,async()=>{"+self.OK+"});", request='reload')
        self.result(self.resolve('new-resolve'))

    def test_background_rejection_preserves_ready_source(self):
        self.load(self.INIT+"""
setTimeout(()=>{ lx.send(lx.EVENT_NAMES.updateAlert,{desc:'invalid extension'}); },10);
lx.on(lx.EVENT_NAMES.request,()=>new Promise(resolve=>setTimeout(()=>resolve('https://media.invalid/ok.mp3'),50)));
""")
        self.result(self.resolve())
        self.result(self.resolve('again'))

    def test_error_before_initialization_is_terminal(self):
        self.load("setTimeout(()=>{throw Error('before init');},10);", expected='error')
        self.assertEqual(self.resolve()['payload']['code'], 'plugin.not-loaded')

    def test_timer_resource_failure_is_bounded(self):
        self.load(self.INIT+"""
lx.on(lx.EVENT_NAMES.request,()=>new Promise(resolve=>setTimeout(()=>{while(true) {}},10)));
""")
        response = self.resolve()
        self.assertEqual(response['messageType'], 'error', response)
        self.assertEqual(response['payload']['code'], 'plugin.runtime-failed')
        self.assertEqual(self.resolve('after')['payload']['code'], 'plugin.not-loaded')


if __name__ == '__main__':
    ap = argparse.ArgumentParser()
    ap.add_argument('--host', type=Path, required=True)
    ap.add_argument('--standalone', action='store_true')
    args, remainder = ap.parse_known_args()
    HOST_PATH = args.host.resolve()
    STANDALONE = args.standalone
    unittest.main(argv=[__file__]+remainder, verbosity=2)
