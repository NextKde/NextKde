import 'core-js/actual/url';
import 'core-js/actual/url-search-params';
import 'core-js/actual/atob';
import 'core-js/actual/btoa';
import { Buffer } from 'buffer';

// Native crypto and IPC use explicit Base64 across the engine boundary. The
// plugin-facing value remains a real indexed Uint8Array / Node Buffer.
Object.defineProperty(Buffer.prototype, '__lf_base64', {
  get() { return this.toString('base64'); }
});
globalThis.Buffer = Buffer;
