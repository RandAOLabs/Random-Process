// hbclient.mjs — minimal, dependency-free HyperBEAM (httpsig@1.0) client.
//
// Reimplements the server-side encoder found in HyperBEAM at
//   src/preloaded/codec/dev_httpsig_conv.erl   (message -> headers + multipart body)
//   src/preloaded/codec/dev_httpsig.erl        (content-digest, signature base)
//   src/preloaded/codec/dev_httpsig_siginfo.erl(signature / signature-input headers)
//   src/preloaded/codec/dev_structured.erl     (rich types -> TABM + ao-types)
//
// Node >= 18. Uses only node:crypto.

import crypto from 'node:crypto';
// One copy of the slot-settle policy, shared with `src/lib/hyperbeam.ts`.
import { settleHead } from './slot-settle.mjs';

const CRLF = '\r\n';
const MAX_HEADER_LENGTH = 4096;
const DERIVED_COMPONENTS = new Set([
  'method', 'target-uri', 'authority', 'scheme',
  'request-target', 'path', 'query', 'query-param'
]);

/* ------------------------------------------------------------------ *
 * base64 helpers                                                      *
 * ------------------------------------------------------------------ */
const b64url = (buf) => Buffer.from(buf).toString('base64url');           // no padding
const b64urlDec = (s) => Buffer.from(s, 'base64url');
const b64std = (buf) => Buffer.from(buf).toString('base64');              // padded
const sha256 = (b) => crypto.createHash('sha256').update(b).digest();

/* ------------------------------------------------------------------ *
 * Structured Fields (RFC 9651) — only the serialisation we need        *
 * ------------------------------------------------------------------ */
function sfString(s) {
  return '"' + String(s).replace(/\\/g, '\\\\').replace(/"/g, '\\"') + '"';
}
function sfBareItem(v) {
  if (v && v.__sf === 'binary') return ':' + b64std(v.value) + ':';
  if (v && v.__sf === 'token') return String(v.value);
  if (v && v.__sf === 'string') return sfString(v.value);
  if (typeof v === 'number') return String(v);
  return sfString(v);
}
const sfBin = (buf) => ({ __sf: 'binary', value: buf });
const sfTok = (s) => ({ __sf: 'token', value: s });
const sfStr = (s) => ({ __sf: 'string', value: s });

function sfParams(params) {
  // params: array of [name, value]
  return params.map(([k, v]) => ';' + k + '=' + sfBareItem(v)).join('');
}
function sfInnerList(items, params) {
  return '(' + items.map((i) => sfBareItem(i)).join(' ') + ')' + sfParams(params || []);
}
function sfDict(entries) {
  // entries: array of [key, serialisedValueString]
  return entries.map(([k, v]) => k + '=' + v).join(', ');
}

/* ------------------------------------------------------------------ *
 * Erlang-compatible ordering: binaries compare byte-wise, shorter      *
 * prefix first.  That is exactly Buffer.compare.                       *
 * ------------------------------------------------------------------ */
function binCmp(a, b) {
  return Buffer.compare(Buffer.from(a, 'binary'), Buffer.from(b, 'binary'));
}
const sortedKeys = (obj) => Object.keys(obj).sort(binCmp);

/* ------------------------------------------------------------------ *
 * hb_escape                                                           *
 * ------------------------------------------------------------------ */
function encodeHeaderValue(v) {
  // hb_escape:encode_header/1 — only \\, CR and LF are escaped.
  const s = Buffer.isBuffer(v) ? v.toString('latin1') : String(v);
  return s.replace(/\\/g, '\\\\').replace(/\r/g, '\\r').replace(/\n/g, '\\n');
}
function decodeHeaderValue(s) {
  let out = '';
  for (let i = 0; i < s.length; i++) {
    if (s[i] === '\\' && i + 1 < s.length) {
      const n = s[i + 1];
      if (n === '\\') { out += '\\'; i++; continue; }
      if (n === 'r') { out += '\r'; i++; continue; }
      if (n === 'n') { out += '\n'; i++; continue; }
    }
    out += s[i];
  }
  return out;
}
const URI_SAFE = /^[a-z0-9.\-_/?&]*$/;
function escapeKey(k) {
  if (URI_SAFE.test(k)) return k;
  let out = '';
  for (const byte of Buffer.from(k, 'utf8')) {
    const c = String.fromCharCode(byte);
    if (/[a-z0-9.\-_/?&]/.test(c)) out += c;
    else out += '%' + byte.toString(16).toUpperCase().padStart(2, '0');
  }
  return out;
}
const IS_ID = (k) => /^[a-zA-Z0-9_-]{43}$/.test(k);

/* ------------------------------------------------------------------ *
 * structured@1.0  ->  TABM                                            *
 * A TABM node is: Buffer (leaf) | { key: TABMnode }  plus `ao-types`.  *
 * ------------------------------------------------------------------ */
function isPlainObject(v) {
  return v !== null && typeof v === 'object' && !Buffer.isBuffer(v) && !Array.isArray(v);
}

function toTabm(value) {
  if (Buffer.isBuffer(value)) return value;
  if (typeof value === 'string') return Buffer.from(value, 'utf8');
  if (Array.isArray(value)) {
    const numbered = {};
    value.forEach((v, i) => { numbered[String(i + 1)] = v; });
    const m = toTabm(numbered);
    const types = parseAoTypes(m['ao-types']);
    types['.'] = 'list';
    m['ao-types'] = Buffer.from(encodeAoTypes(types), 'utf8');
    return m;
  }
  if (isPlainObject(value)) {
    const types = {};
    const out = {};
    for (const key of sortedKeys(value)) {
      if (key === 'commitments' || key === 'priv' || key.startsWith('priv/')) continue;
      const v = value[key];
      if (v === undefined) continue;
      if (typeof v === 'string' || Buffer.isBuffer(v)) {
        out[key] = toTabm(v);
      } else if (Array.isArray(v) || isPlainObject(v)) {
        out[key] = toTabm(v);
      } else if (typeof v === 'number') {
        if (Number.isInteger(v)) { types[key] = 'integer'; out[key] = Buffer.from(String(v)); }
        else { types[key] = 'float'; out[key] = Buffer.from(String(v)); }
      } else if (typeof v === 'boolean' || v === null) {
        types[key] = 'atom';
        out[key] = Buffer.from(v === null ? 'null' : String(v));
      }
    }
    if (Object.keys(types).length) out['ao-types'] = Buffer.from(encodeAoTypes(types), 'utf8');
    return out;
  }
  return Buffer.from(String(value), 'utf8');
}

function encodeAoTypes(types) {
  if (process.env.HB_HTTPSIG === 'legacy') {
    return sfDict(sortedKeys(types).map((k) => [escapeKey(k), sfString(types[k])]));
  }
  return encodeAoTypesV011(types);
}

/** HyperBEAM v0.11 `ao-types` (`dev_structured:encode_ao_types/2`): a member per
 * TYPE whose inner list holds that type's keys, types and keys each sorted by
 * their bytes, a key as a string, or as a byte sequence if it has a byte
 * outside 0x20-0x7e. v0.11 still reads the old `key="type"` form, but stores
 * the message re-encoded in this one, so a signature over the old bytes no
 * longer verifies once the message is read back. */
const byBytes = (a, b) => Buffer.compare(Buffer.from(a), Buffer.from(b));
function encodeAoTypesV011(types) {
  const groups = new Map();
  for (const key of Object.keys(types).sort(byBytes)) {
    const type = types[key];
    if (!groups.has(type)) groups.set(type, []);
    groups.get(type).push(key);
  }
  return [...groups.keys()].sort(byBytes).map((type) =>
    type + '=(' + groups.get(type).map((key) =>
      /^[ -~]*$/.test(key) ? sfString(key) : ':' + b64std(Buffer.from(key)) + ':'
    ).join(' ') + ')'
  ).join(', ');
}

/** Read either `ao-types` form: v0.11's `type=("key" ...)` or `key="type"`. */
function parseAoTypes(bin) {
  if (!bin) return {};
  const s = Buffer.isBuffer(bin) ? bin.toString('utf8') : String(bin);
  const out = {};
  for (const m of s.matchAll(/([a-z0-9*_.-]+)=\(([^)]*)\)/g)) {
    for (const k of m[2].matchAll(/"((?:[^"\\]|\\.)*)"|:([A-Za-z0-9+/=]*):/g)) {
      const key = k[1] !== undefined ? k[1].replace(/\\(.)/g, '$1') : Buffer.from(k[2], 'base64').toString('utf8');
      out[key] = m[1];
    }
  }
  for (const part of s.split(',')) {
    const m = part.trim().match(/^([^=(]+)="([^"]*)"$/);
    if (m) out[m[1]] = m[2];
  }
  return out;
}

/* ------------------------------------------------------------------ *
 * TABM -> httpsig@1.0  (dev_httpsig_conv:to/3)                        *
 * ------------------------------------------------------------------ */
function inlineKey(msg) {
  const explicit = msg['ao-body-key'];
  if (explicit !== undefined) {
    return { extra: {}, key: Buffer.isBuffer(explicit) ? explicit.toString() : String(explicit) };
  }
  if (Object.prototype.hasOwnProperty.call(msg, 'body')) return { extra: {}, key: 'body' };
  if (Object.prototype.hasOwnProperty.call(msg, 'data')) {
    return { extra: { 'ao-body-key': Buffer.from('data') }, key: 'data' };
  }
  return { extra: {}, key: 'body' };
}

/** group_maps/4 — flatten nested part maps into `parent/child` part names. */
function groupMaps(map, parent, top) {
  const flattened = {};
  for (const key of sortedKeys(map)) {
    const value = map[key];
    const normKey = key; // hb_ao:normalize_key/1 is the identity for binaries
    const flatK = parent === '' ? normKey : parent + '/' + normKey;
    if (isPlainObject(value)) {
      if (Object.keys(value).length === 0) {
        top[flatK] = { 'ao-types': Buffer.from('empty-message') };
      } else {
        top = groupMaps(value, flatK, top);
      }
    } else {
      const buf = Buffer.isBuffer(value) ? value : Buffer.from(String(value));
      if (normKey === 'content-disposition' || buf.length > MAX_HEADER_LENGTH) {
        top[flatK] = buf;
      } else {
        flattened[normKey] = buf;
      }
    }
  }
  if (Object.keys(flattened).length === 0) return top;
  if (parent === '') return Object.assign({}, top, flattened);
  top[parent] = flattened;
  return top;
}

/** encode_http_flat_msg/2 — a flat map of binaries into an HTTP header block. */
function encodeFlatMsg(msg) {
  const headerKeys = sortedKeys(msg).filter((k) => k !== 'body' && k !== 'priv');
  const headers = headerKeys
    .map((k) => Buffer.concat([Buffer.from(k + ': '), asBuf(msg[k])]))
    .reduce((acc, b, i) => (i === 0 ? [b] : acc.concat([Buffer.from(CRLF), b])), []);
  const head = Buffer.concat(headers);
  const body = msg.body === undefined ? Buffer.alloc(0) : asBuf(msg.body);
  if (body.length === 0) return head;
  return Buffer.concat([head, Buffer.from(CRLF + CRLF), body]);
}
const asBuf = (v) => (Buffer.isBuffer(v) ? v : Buffer.from(String(v)));

function encodeBodyPart(partName, part, inlKey) {
  const disposition =
    partName === inlKey ? 'inline' : `form-data;name="${partName}"`;
  if (isPlainObject(part)) {
    return encodeFlatMsg(Object.assign({}, part, {
      'content-disposition': Buffer.from(disposition)
    }));
  }
  return Buffer.concat([
    Buffer.from('content-disposition: ' + disposition + CRLF + CRLF),
    asBuf(part)
  ]);
}

/**
 * Encode a TABM into { headers: {k: string}, body: Buffer|null }.
 * Mirrors do_to/3 exactly, including the content-digest.
 */
function tabmToHttp(tabm) {
  const stripped = {};
  for (const k of Object.keys(tabm)) {
    if (['commitments', 'signature', 'signature-input', 'priv'].includes(k)) continue;
    stripped[IS_ID(k) ? escapeKey(k) : k] = tabm[k];
  }
  const { extra, key: inlKey } = inlineKey(stripped);

  const headers = {};
  const bodyMap = {};
  for (const [k, v] of Object.entries(extra)) headers[k] = v;

  for (const key of sortedKeys(stripped)) {
    const value = stripped[key];
    if (key === 'body') { bodyMap['body'] = value; continue; }
    if (key === inlKey) { bodyMap[inlKey] = value; continue; }
    if (isPlainObject(value)) { bodyMap[key] = value; continue; }
    const buf = asBuf(value);
    if (buf.length <= MAX_HEADER_LENGTH) headers[key] = buf;
    else bodyMap[key] = buf;
  }

  const grouped = groupMaps(bodyMap, '', {});
  const gKeys = sortedKeys(grouped);

  let body = null;
  if (gKeys.length === 0) {
    body = null;
  } else if (gKeys.length === 1 && gKeys[0] === inlKey && Buffer.isBuffer(grouped[inlKey])) {
    body = grouped[inlKey];
  } else {
    const parts = gKeys.map((k) => {
      const v = grouped[k];
      if (isPlainObject(v) && Object.keys(v).length === 1 &&
          Object.prototype.hasOwnProperty.call(v, 'body')) {
        return encodeBodyPart(k + '/body', v, 'body');
      }
      return encodeBodyPart(k, v, inlKey);
    });
    const joined = parts.reduce(
      (acc, p, i) => (i === 0 ? [p] : acc.concat([Buffer.from(CRLF), p])), []);
    const boundary = b64url(sha256(Buffer.concat(joined)));
    const withMarkers = parts.reduce(
      (acc, p, i) => acc.concat(
        i === 0 ? [] : [Buffer.from(CRLF)],
        [Buffer.from('--' + boundary + CRLF), p]
      ), []);
    body = Buffer.concat([
      Buffer.concat(withMarkers),
      Buffer.from(CRLF + '--' + boundary + '--')
    ]);
    headers['content-type'] = Buffer.from(`multipart/form-data; boundary="${boundary}"`);
  }

  const outHeaders = {};
  for (const k of Object.keys(headers)) outHeaders[k] = encodeHeaderValue(headers[k]);
  if (body && body.length) {
    outHeaders['content-digest'] = 'sha-256=:' + b64std(sha256(body)) + ':';
  }
  return { headers: outHeaders, body };
}

/* ------------------------------------------------------------------ *
 * Signature base (dev_httpsig:signature_base/3)                        *
 * ------------------------------------------------------------------ */
function addDerivedSpecifiers(keys) {
  return keys.map((k) => {
    const bare = k.startsWith('@') ? k.slice(1) : k;
    return DERIVED_COMPONENTS.has(bare) ? '@' + bare : bare;
  });
}

function signatureBase(encHeaders, committed, params) {
  const lines = committed.map((name) => {
    const v = encHeaders[name];
    if (v === undefined) {
      throw new Error('missing_key_for_signature_component_line: ' + name);
    }
    return `"${name}": ${v}`;
  });
  const paramsLine = sfInnerList(
    addDerivedSpecifiers(committed).map((k) => sfStr(k)),
    params
  );
  return Buffer.from(lines.join('\n') + '\n"@signature-params": ' + paramsLine, 'utf8');
}

/** the RFC-9421 params, in the order HyperBEAM emits them */
function commitmentParams({ alg, bundle, created, expires, keyid, nonce, tag, publicKey }) {
  const out = [];
  if (alg !== undefined) out.push(['alg', sfStr(alg)]);
  if (bundle !== undefined) out.push(['bundle', sfStr(bundle)]);
  if (created !== undefined) out.push(['created', created]);
  if (expires !== undefined) out.push(['expires', expires]);
  if (keyid !== undefined) out.push(['keyid', sfStr(keyid)]);
  if (nonce !== undefined) out.push(['nonce', sfStr(nonce)]);
  if (publicKey !== undefined) out.push(['public-key', sfStr(publicKey)]);
  if (tag !== undefined) out.push(['tag', sfStr(tag)]);
  return out;
}

/**
 * The HyperBEAM v0.11 committer URI of an address: `uri-did-ar-<L><B>`, the
 * address in lowercase with `_` as `-`, then 9 base36 digits of a 46-bit mask
 * -- one bit per character (1 for a capital or `_`), then 3 type bits (000: an
 * address of no stated key type, the form v0.11 uses for a committer).
 * Mirrors `hb_committer:encode/2`.
 */
export function committerUri(address) {
  const lower = address.toLowerCase().replace(/_/g, '-');
  let mask = 0n;
  for (const c of address) mask = (mask << 1n) | ((c >= 'A' && c <= 'Z') || c === '_' ? 1n : 0n);
  return 'uri-did-ar-' + lower + (mask << 3n).toString(36).padStart(9, '0');
}

/**
 * Which httpsig form to sign in. v0.11 nodes identify the signer by its
 * committer URI in `keyid` and take the key from a `public-key` parameter;
 * older nodes read `keyid="publickey:<base64 key>"`. v0.11 is the default;
 * `HB_HTTPSIG=legacy` selects the old form for an older node.
 */
function keyParams(jwk) {
  if (process.env.HB_HTTPSIG === 'legacy') {
    return { keyid: 'publickey:' + b64std(pubKeyBuf(jwk)) };
  }
  return { keyid: committerUri(jwkToAddress(jwk)), publicKey: b64url(pubKeyBuf(jwk)) };
}

/* ------------------------------------------------------------------ *
 * RSA-PSS-SHA512 with an Arweave JWK                                   *
 * ------------------------------------------------------------------ */
function jwkToPrivateKey(jwk) {
  return crypto.createPrivateKey({ key: { ...jwk, kty: 'RSA' }, format: 'jwk' });
}
function pubKeyBuf(jwk) { return b64urlDec(jwk.n); }              // raw modulus
export function ownerToAddress(nB64url) { return b64url(sha256(b64urlDec(nB64url))); }
export function jwkToAddress(jwk) { return ownerToAddress(jwk.n); }

function rsaPssSign(jwk, data) {
  return crypto.sign('sha512', data, {
    key: jwkToPrivateKey(jwk),
    padding: crypto.constants.RSA_PKCS1_PSS_PADDING,
    saltLength: 64 // SHA-512 digest length; ar_wallet/rsa_pss uses saltLen == hashLen
  });
}
function rsaPssVerify(modulusBuf, data, sig) {
  const jwk = { kty: 'RSA', n: b64url(modulusBuf), e: 'AQAB' };
  const key = crypto.createPublicKey({ key: jwk, format: 'jwk' });
  return crypto.verify('sha512', data, {
    key, padding: crypto.constants.RSA_PKCS1_PSS_PADDING, saltLength: 64
  }, sig);
}

/* ------------------------------------------------------------------ *
 * Nested (sub-message) commitments.                                    *
 *                                                                      *
 * A HyperBEAM node, on decoding a request, gives every *unsigned*       *
 * sub-message an implicit `hmac-sha256` commitment keyed `constant:ao`. *
 * Those commitments are then part of the message, and re-encoding the   *
 * message emits them as extra multipart parts named                     *
 *   <path>/commitments/<id>   and   <path>/commitments/<id>/committed   *
 * which changes the body bytes -- and therefore the content-digest.     *
 * A client that does not pre-compute them can never produce a           *
 * verifiable multipart message.                                         *
 * ------------------------------------------------------------------ */

/** wire (httpsig) committed-key list -> AO-Core message key list */
function wireToMessageKeys(wire, bodyKeys, headers) {
  let out = [];
  for (const k of wire) {
    if (k === 'content-digest') out.push(...bodyKeys);
    else out.push(k);
  }
  if (headers['ao-body-key'] !== undefined) {
    const abk = String(headers['ao-body-key']);
    out = out.flatMap((k) => (k === 'body' ? [abk] : [k])).filter((k) => k !== 'ao-body-key');
  }
  if (/^multipart\//.test(String(headers['content-type'] || ''))) {
    out = out.filter((k) => k !== 'content-type');
  }
  return out;
}

function isListTabm(sub) {
  const t = parseAoTypes(sub['ao-types']);
  return t['.'] === 'list';
}

/** Attach the implicit `constant:ao` hmac commitment to a TABM sub-message. */
function hmacCommit(subTabm) {
  const bare = { ...subTabm };
  delete bare.commitments;
  const { headers } = tabmToHttp(bare);
  const wire = sortedKeys(headers).filter((k) => k !== 'signature' && k !== 'signature-input');
  const params = commitmentParams({ alg: 'hmac-sha256', keyid: 'constant:ao' });
  const base = signatureBase(headers, wire, params);
  const mac = crypto.createHmac('sha256', 'constant:ao').update(base).digest();
  const id = b64url(mac);
  const rawInputs = sortedKeys(bare);
  const bodyKeys = rawInputs.filter((k) => headers[k] === undefined && headers[k + '+link'] === undefined);
  const committed = wireToMessageKeys(wire, bodyKeys, headers);
  return {
    ...subTabm,
    commitments: {
      [id]: {
        'commitment-device': Buffer.from('httpsig@1.0'),
        committed: toTabm(committed),
        keyid: Buffer.from('constant:ao'),
        signature: Buffer.from(id),
        type: Buffer.from('hmac-sha256')
      }
    }
  };
}

/** Recursively give every unsigned sub-message its implicit hmac commitment. */
function withNestedHmacs(tabm) {
  if (!isPlainObject(tabm)) return tabm;
  const out = {};
  for (const [k, v] of Object.entries(tabm)) {
    if (k === 'commitments') { out[k] = v; continue; }
    if (isPlainObject(v)) {
      const inner = withNestedHmacs(v);
      out[k] = (isListTabm(v) || v.commitments) ? inner : hmacCommit(inner);
    } else out[k] = v;
  }
  return out;
}

/* ------------------------------------------------------------------ *
 * Commit: message -> fully-signed { headers, body }                    *
 * ------------------------------------------------------------------ */
/**
 * Wall time between two `process.hrtime.bigint()` readings, in milliseconds.
 *
 * Signing is not one cost. Encoding a message to its signature base walks the
 * whole TABM and is proportional to how much the message carries; the RSA-PSS
 * operation over that base is a fixed cost that does not care. A single
 * "time to sign" number cannot say which of those moved, which is exactly the
 * question a round-trip regression asks, so the phases are timed separately
 * and carried out on the result rather than re-derived by each caller.
 */
const durMs = (from, to) => Number(to - from) / 1e6;

export function commit(msg, jwk, opts = {}) {
  // v0.11 refuses the nested hmac commitments older nodes expect on a nested
  // message (its hmac form changed), and accepts the nested message without.
  const { bundle = 'true', nestedHmacs = process.env.HB_HTTPSIG === 'legacy', ...params0 } = opts;
  const tEncode = process.hrtime.bigint();
  const tabm = nestedHmacs ? withNestedHmacs(toTabm(msg)) : toTabm(msg);
  const { headers, body } = tabmToHttp(tabm);

  // default committed set == every encoded header, sorted (Erlang flat-map order)
  const committed = sortedKeys(headers).filter(
    (k) => k !== 'signature' && k !== 'signature-input'
  );

  const params = commitmentParams({ alg: 'rsa-pss-sha512', bundle, ...keyParams(jwk), ...params0 });
  const base = signatureBase(headers, committed, params);
  const tSign = process.hrtime.bigint();
  const sig = rsaPssSign(jwk, base);
  const tSeal = process.hrtime.bigint();
  const name = 'comm-' + b64url(sha256(sig)).toLowerCase();

  const outHeaders = { ...headers };
  outHeaders['signature'] = sfDict([[name, ':' + b64std(sig) + ':']]);
  outHeaders['signature-input'] = sfDict([[name, sfInnerList(
    addDerivedSpecifiers(committed).map((k) => sfStr(k)), params)]]);

  return {
    headers: outHeaders, body, signatureBase: base, committed, sigName: name,
    timing: {
      encodeMs: durMs(tEncode, tSign),
      signMs: durMs(tSign, tSeal),
      sealMs: durMs(tSeal, process.hrtime.bigint()),
    },
  };
}

/* ------------------------------------------------------------------ *
 * Verification of an inbound (node-signed) message — used as an oracle *
 * ------------------------------------------------------------------ */
export function verifyHeaders(headersObj, bodyBuf) {
  const headers = {};
  for (const [k, v] of Object.entries(headersObj)) headers[k.toLowerCase()] = v;
  const sigHdr = headers['signature'];
  const sigInHdr = headers['signature-input'];
  if (!sigHdr || !sigInHdr) return { ok: false, reason: 'no signature headers' };

  const enc = { ...headers };
  delete enc['signature']; delete enc['signature-input'];
  if (bodyBuf && bodyBuf.length) {
    enc['content-digest'] = 'sha-256=:' + b64std(sha256(bodyBuf)) + ':';
  }

  const results = [];
  for (const [name, inner] of splitSfDict(sigInHdr)) {
    const sigEntry = splitSfDict(sigHdr).find(([n]) => n === name);
    if (!sigEntry) continue;
    const sig = Buffer.from(sigEntry[1].replace(/^:|:$/g, ''), 'base64');
    const m = inner.match(/^\(([^)]*)\)(.*)$/);
    const committed = (m[1].match(/"([^"]*)"/g) || []).map((s) => s.slice(1, -1));
    const params = [];
    const paramRe = /;([a-z0-9_.\-*]+)=(?:"((?:[^"\\]|\\.)*)"|([^;]+))/g;
    let pm;
    while ((pm = paramRe.exec(m[2])) !== null) {
      params.push([pm[1], pm[2] !== undefined
        ? sfStr(pm[2].replace(/\\(.)/g, '$1'))
        : (/^-?\d+$/.test(pm[3]) ? Number(pm[3]) : sfStr(pm[3]))]);
    }
    const alg = params.find(([k]) => k === 'alg');
    const keyidP = params.find(([k]) => k === 'keyid');
    const bare = committed.map((k) => (k.startsWith('@') ? k.slice(1) : k));
    const base = signatureBase(enc, bare, params);
    if (!alg || alg[1].value !== 'rsa-pss-sha512') {
      results.push({ name, alg: alg && alg[1].value, ok: null, base });
      continue;
    }
    const modulus = Buffer.from(String(keyidP[1].value).replace(/^publickey:/, ''), 'base64');
    results.push({
      name, alg: 'rsa-pss-sha512',
      ok: rsaPssVerify(modulus, base, sig),
      address: b64url(sha256(modulus)),
      base
    });
  }
  return results;
}

function splitSfDict(str) {
  // members are `key=value`, value may contain quoted strings / (...) groups
  const out = [];
  let depth = 0, inStr = false, cur = '';
  for (let i = 0; i < str.length; i++) {
    const c = str[i];
    if (inStr) { cur += c; if (c === '\\') { cur += str[++i]; } else if (c === '"') inStr = false; continue; }
    if (c === '"') { inStr = true; cur += c; continue; }
    if (c === '(') depth++;
    if (c === ')') depth--;
    if (c === ',' && depth === 0) { out.push(cur); cur = ''; continue; }
    cur += c;
  }
  if (cur.trim()) out.push(cur);
  return out.map((s) => {
    const t = s.trim();
    const i = t.indexOf('=');
    return [t.slice(0, i), t.slice(i + 1)];
  });
}

/* ------------------------------------------------------------------ *
 * HTTP plumbing                                                        *
 * ------------------------------------------------------------------ */
let httpRequests = 0;

export function httpRequestCount() {
  return httpRequests;
}

export function resetHttpRequestCount() {
  const previous = httpRequests;
  httpRequests = 0;
  return previous;
}

async function send(node, path, method, headers, body) {
  const url = transportNode(node) + (path.startsWith('/') ? path : '/' + path);
  httpRequests += 1;
  const res = await fetch(url, {
    method,
    headers: { ...headers, 'accept-bundle': 'true' },
    body: body && body.length ? body : undefined,
    redirect: 'follow'
  });
  const buf = Buffer.from(await res.arrayBuffer());
  const h = {};
  res.headers.forEach((v, k) => { h[k] = v; });
  return { status: res.status, headers: h, body: buf, url };
}

/**
 * Optional HTTP transport override used by deployments running behind the
 * browser relay.  `node` remains the canonical public scheduler identity that
 * is sealed into process/config manifests; only the actual HTTP destination is
 * replaced.  Keeping those two concerns separate prevents a temporary
 * localhost relay URL from leaking into a live deployment.
 */
export function transportNode(node) {
  return (process.env.NODE_TRANSPORT_URL || node).replace(/\/$/, '');
}

function hbError(res) {
  const t = res.body.toString();
  const m = t.match(/Error details:([\s\S]*?)<\/pre>/);
  const dec = (x) => x.replace(/&quot;/g, '"').replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>').replace(/&amp;/g, '&').replace(/&#39;/g, "'");
  if (m) return dec(m[1]).replace(/\s+/g, ' ').trim();
  return res.headers['details'] || t.slice(0, 400);
}

/** POST a signed message. Returns { status, headers, body }. */
export async function postSigned(node, path, msg, jwk, opts = {}) {
  const { headers, body, signatureBase: base, committed, timing } = commit(msg, jwk, opts);
  const tPost = process.hrtime.bigint();
  const res = await send(node, path, 'POST', headers, body);
  const postMs = durMs(tPost, process.hrtime.bigint());
  res.request = { headers, body, base, committed };
  res.timing = { ...timing, postMs, bytes: body ? body.length : 0 };
  return res;
}

/** Look up a node's own scheduler address. */
export async function nodeAddress(node) {
  const r = await send(node, '/~meta@1.0/info/address', 'GET', { accept: 'text/plain' });
  return r.body.toString().trim();
}

/**
 * Spawn a native Lua process@1.0 on `node` (`lua@5.3a` by default).
 * Returns the process id.
 */
export async function spawnProcess({
  node, jwk, lua, scheduler, authority, executionDevice = 'lua@5.3a', ...fields
}) {
  const sched = scheduler || (await nodeAddress(node));
  const me = jwkToAddress(jwk);
  const proc = {
    device: 'process@1.0',
    type: 'Process',
    'scheduler-device': 'scheduler@1.0',
    'execution-device': executionDevice,
    'scheduler-location': sched,
    authority: authority || [me, sched],
    'random-seed': String(Math.floor(Math.random() * 1e9)),
    ...(lua ? { module: { 'content-type': 'application/lua', body: lua } } : {}),
    ...fields
  };
  return scheduleProcess(node, jwk, proc);
}

/** Spawn a pre-cached Rust/WASM process using HyperBEAM's JSON interface.
 *
 * `image` is deliberately an immutable content id, not a local filename, and
 * `dev_wasm` resolves it through `hb_cache:read` at init. That read falls back
 * to `hb_store_gateway`, so an ordinary Arweave transaction id resolves —
 * measured: the node serves the aos module
 * `Do_Uc2Sju_ffp6Ev0AnLVdPtot15rvMjP-a9VVaA5fM` as application/wasm without
 * ever having held it. `battle-fleet/image.mjs` publishes the worker that way,
 * so no node operator or `cache_writers` entry is involved. */
export async function spawnWasmProcess({
  node, jwk, image, imageBytes, scheduler, authority, deviceStack, ...fields
}) {
  const sched = scheduler || (await nodeAddress(node));
  return scheduleProcess(node, jwk, wasmProcessDefinition({
    image, imageBytes, scheduler: sched, authority, deviceStack, ...fields,
  }));
}

/** Pure process-definition builder, exported so deployment compatibility can
 * be tested without mutating a public scheduler. */
export function wasmProcessDefinition({
  image, imageBytes, scheduler, authority, deviceStack, randomSeed, ...fields
}) {
  // Two ways to name the module, and they are not interchangeable.
  //
  // `image` is a content id, which `dev_wasm:init/3` resolves with
  // `hb_cache:read(Id)` and then reads the `body` key OF THE RESULT. A message
  // the node pulled from a gateway does not have one: `dev_tx`/`ans104@1.0`
  // decoding puts a transaction's payload under `data`, so the read succeeds,
  // `body` is `not_found`, and the process dies at init inside
  // `hb_beamr:start(not_found, wasm)` with a bare `function_clause`. Measured on
  // hyperbeam.tylerw.ai against our own published module and against the aos
  // module `Do_Uc2Sju...` alike: `GET /<id>/data` serves the bytes and
  // `GET /<id>/body` 404s for both. An `image` id therefore only works when the
  // bytes are in the NODE's own cache as a message with a `body` -- which is
  // what `dev_wasm:cache_wasm_image/2` and `/~cache@1.0/write` do, and both are
  // gated on the node's `cache_writers` list.
  //
  // `imageBytes` needs no such privilege. `dev_wasm` also accepts `image` as a
  // MESSAGE and reads `body` from it directly, so the module travels inside the
  // signed process definition as `image/body`. It costs one copy of the binary
  // per spawn and binds the exact executable into the immutable process, which
  // is the property the fleet wanted from an image id anyway.
  if (imageBytes && image) {
    throw new Error('Pass either a WASM image id or inline imageBytes, not both');
  }
  if (imageBytes) {
    if (!Buffer.isBuffer(imageBytes) || imageBytes.length === 0) {
      throw new Error('WASM imageBytes must be a non-empty Buffer');
    }
  } else if (!/^[A-Za-z0-9_-]{43}$/.test(image || '')) {
    throw new Error('WASM image must be a 43-character cached content id');
  }
  if (!/^[A-Za-z0-9_-]{43}$/.test(scheduler || '')) {
    throw new Error('WASM scheduler must be a 43-character address');
  }
  return {
    device: 'process@1.0',
    type: 'Process',
    'scheduler-device': 'scheduler@1.0',
    'execution-device': 'stack@1.0',
    'scheduler-location': scheduler,
    scheduler,
    // Device names are matched BYTE-FOR-BYTE against the node's registry, and
    // every name in it is lowercase. `JSON-Iface@1.0` is therefore a different
    // string from `json-iface@1.0` and resolves to nothing: the process dies at
    // init with `{device_not_loadable,<<"JSON-Iface@1.0">>,
    // <<"device-name-not-resolvable">>}`, which reads as "this node has no JSON
    // interface" and is not that at all. `/~<name>@<ver>/keys` distinguishes the
    // two: a registered device answers 200, an unresolvable one answers that
    // same 500. Keep every device name here lowercase.
    //
    // The worker is a self-contained wasm32-unknown-unknown module with zero
    // imports, so it must not depend on WASI, and the stack omits it. (The node
    // does register `wasi@1.0`; the earlier reading that it did not was the
    // casing bug above.)
    // The signed process owner remains available through env.Process.
    authority: authority || scheduler,
    'device-stack': deviceStack || [
      'json-iface@1.0', 'wasm-64@1.0', 'multipass@1.0', 'patch@1.0',
    ],
    'stack-keys': ['init', 'compute', 'snapshot', 'normalize'],
    image: imageBytes ? { body: imageBytes } : image,
    'output-prefix': 'wasm',
    passes: 2,
    // `/results/outbox`, not `/results/patches`: `dev_json_iface` builds the
    // outbox as a numbered map and leaves `patches` a list, and `dev_patch`
    // folds its source with `maps:fold/3`. See ProcessResponse in
    // battle-fleet-rust/src/lib.rs.
    'patch-from': '/results/outbox',
    'patch-to': '/',
    'random-seed': randomSeed || String(Math.floor(Math.random() * 1e9)),
    ...fields,
  };
}

async function scheduleProcess(node, jwk, proc) {
  // Where a spawn is POSTed depends on the node's build, and the failure looks
  // nothing like the cause: `permaweb/edge` answers the bare `/schedule` with a
  // flat `404 not_found`, which reads as "this node is broken" rather than
  // "that route moved". Measured, on the same signed payload:
  //
  //   hyperbeam.tylerw.ai (edge)   /schedule 404,  ~scheduler@1.0/schedule 200
  //   schedule.forward.computer    /schedule 200
  //
  // So try the device-qualified path first — it is the more explicit form and
  // the one the newer build wants — and fall back to the bare route for nodes
  // that predate the change. Only a 404 is worth retrying elsewhere: any other
  // status is the node objecting to the message, and re-sending it to a
  // different path would just bury the real reason.
  const paths = ['/~scheduler@1.0/schedule', '/schedule'];
  const tried = [];
  for (const path of paths) {
    const res = await postSigned(node, path, proc, jwk);
    if (res.status === 200) {
      const id = res.headers['process'];
      if (!id) {
        throw new Error(`spawn via ${path} returned no process header: ${JSON.stringify(res.headers)}`);
      }
      return id;
    }
    tried.push(`${path} -> ${res.status} ${hbError(res)}`);
    if (res.status !== 404) break;
  }
  throw new Error(`spawn failed on ${node}:\n  ${tried.join('\n  ')}`);
}

/** The schedule route a node was last seen to accept. See `sendMessage`. */
const SCHEDULE_ROUTE = new Map();

/**
 * Where signed sends are reported. Null by default, so every script that does
 * not install one measures nothing.
 *
 * This client is how funding, unlocks and oaths are signed, and a harness that
 * cannot see them shows a launch as a quiet gap. The record uses the field
 * names of `TransportTiming` in `src/lib/hyperbeam.ts`.
 *
 * An accepted send is not reported at acceptance: POST acceptance is a one-way
 * number, and reporting it as `accepted-unread` made every launch write look
 * like an error. It is held until a caller's `awaitComputedSlot` on the same
 * process gets the head past its slot, then its reply is read by slot and it
 * is reported `ok` or `rejected` with `t1` at that read. A send nobody settles
 * is reported `accepted-unread` when the observer is replaced or removed.
 *
 * `roles` maps pid -> pidRole for non-admin sends; an `Admin.*` action is
 * `admin` whatever it targets.
 */
let sendObserver = null;
let sendRoles = {};
/** Accepted sends waiting for their reply: `{node, pid, slot, timing, observer}`. */
const unsettledSends = [];

export function setSendObserver(fn, roles = null) {
  for (const held of unsettledSends.splice(0)) observeSend(held.timing, held.observer);
  sendObserver = fn ?? null;
  sendRoles = roles ?? {};
}

function observeSend(timing, observer = sendObserver) {
  if (!observer) return;
  // Diagnostics must never fail a send the scheduler has already accepted.
  try { observer(timing); } catch { /* observers never throw */ }
}

/** Report every held send on `pid` at or below the computed `head`, from its reply. */
async function settleSends({ node, pid, head, fetchImpl }) {
  const base = transportNode(node);
  const due = [];
  for (let i = unsettledSends.length - 1; i >= 0; i -= 1) {
    const held = unsettledSends[i];
    if (held.node === base && held.pid === pid && held.slot <= head) due.push(...unsettledSends.splice(i, 1));
  }
  await Promise.all(due.map(async (held) => {
    let reply = null;
    try {
      const res = await fetchImpl(
        `${base}/${pid}~process@1.0/compute&slot=${held.slot}/results/output/data`,
        { headers: { accept: 'text/plain' }, signal: AbortSignal.timeout(30_000) },
      );
      const body = res.ok ? (await res.text()).trim() : '';
      if (body && !/^<!DOCTYPE html|^<html/i.test(body)) reply = JSON.parse(body);
    } catch { reply = null; }
    if (reply === null) {
      observeSend(held.timing, held.observer);
      return;
    }
    const outcome = typeof reply === 'object' && reply.error ? 'rejected' : 'ok';
    observeSend({ ...held.timing, t1: Date.now(), ok: true, outcome }, held.observer);
  }));
}

/** Schedule a signed message against an existing process. Returns its slot. */
export async function sendMessage({
  node, jwk, process: pid, action, tags = {}, data, body, path, push = true,
}) {
  const t0 = Date.now();
  const started = process.hrtime.bigint();
  // Fields become HTTP headers, and header names are case-insensitive. So
  // `action` and `Action` are distinct object keys but the SAME header, and
  // sending both produces a duplicate that the node rejects with a bare
  // `400 Message is not valid.` naming nothing. Fold to lowercase and dedupe;
  // later entries win, so callers can still override a default.
  const fields = new Map();
  const put = (k, v) => {
    if (v === undefined || v === null) return;
    fields.set(String(k).toLowerCase(), typeof v === 'string' ? v : String(v));
  };

  put('target', pid);
  put('type', 'Message');
  // Without `subject`, dev_scheduler tries to schedule the request body instead
  // of the message. Same bare 400.
  put('subject', 'self');
  if (action) put('action', action);
  for (const [k, v] of Object.entries(tags)) put(k, v);
  if (data !== undefined) put('data', data);
  put('random-seed', String(Math.floor(Math.random() * 1e9)));

  const msg = {
    ...Object.fromEntries(fields),
    ...(body === undefined ? {} : { body }),
  };
  const sentAction = fields.get('action')?.toLowerCase() ?? null;
  const timing = (outcome, { res = null, slot = null, error } = {}) => {
    const t = res?.timing;
    return {
      action: sentAction,
      slot: slot === null || slot === undefined ? null : Number(slot),
      node,
      pid,
      pidRole: sentAction?.startsWith('admin.') ? 'admin' : (sendRoles[pid] ?? null),
      t0,
      t1: Date.now(),
      buildMs: t ? t.encodeMs : 0,
      signMs: t ? t.signMs + t.sealMs : 0,
      postMs: t ? t.postMs : 0,
      sendMs: durMs(started, process.hrtime.bigint()),
      bytes: t ? t.bytes : 0,
      // As in `TransportTiming`: a reply was read, which a refusal also is.
      ok: outcome === 'ok' || outcome === 'rejected',
      outcome,
      ...(error === undefined ? {} : { error }),
    };
  };
  const report = (outcome, detail) => {
    if (sendObserver) observeSend(timing(outcome, detail));
  };

  // Same story as `spawnProcess`: the schedule route moved between node builds
  // and a miss is a flat `404 not_found` rather than anything about routing.
  // An explicit `path` is always honoured as given; otherwise try the known
  // spellings, newest first, and only move on for a 404.
  //
  // The winner is remembered per node, because this runs hundreds of times in a
  // deploy — 17 Admin.Load batches, then a message per paid-list chunk — and
  // paying a failed round trip before each of them would be slower than the
  // deploy itself.
  const candidates = path
    ? [path]
    : [`/${pid}~process@1.0/schedule`, `/${pid}~scheduler@1.0/schedule`, `/${pid}/schedule`];
  const known = SCHEDULE_ROUTE.get(node);
  const ordered = known && !path
    ? [known, ...candidates.filter((p) => p !== known)]
    : candidates;

  const tried = [];
  let lastResponse = null;
  for (const candidate of ordered) {
    let res;
    try {
      res = await postSigned(node, candidate, msg, jwk);
    } catch (error) {
      report('post-failed', { error: error instanceof Error ? `${error.name}: ${error.message}` : String(error) });
      throw error;
    }
    lastResponse = res;
    if (res.status === 200) {
      if (!path) SCHEDULE_ROUTE.set(node, candidate);
      const slot = res.headers['slot'];
      // Queued, not awaited, and not raced. The push is still best-effort from
      // the caller's point of view — the message is already accepted, and
      // AWAITING the delivery doubled the round trips of every backend write
      // for no benefit, since most messages emit no outbox at all.
      //
      // But firing them CONCURRENTLY was not free, it was just billed to
      // somebody else. `push&slot=N` for a slot above the computed head makes
      // the node replay every intermediate slot to reach it, and
      // `dev_process.erl` compute_to_slot recurses over those with no per-slot
      // cache read — so N racing pushes each replay from wherever the head was
      // when they started. Measured on the live node: every one of 75 racing
      // pushes targeted a slot above the head, each replayed 20.1 slots, and
      // that is what made the first 400 slots of a fresh process cost 6.38
      // executions each against 1.00 in steady state.
      //
      // One in flight per process, in slot order, so each push asks for head+1
      // and replays one slot. See `pendingPushes` for the other half: a queued
      // push that never runs is a destroyed Rune, so a script must drain before
      // it exits.
      if (push && slot !== undefined && slot !== null) {
        queuePush({ node, process: pid, slot });
      }
      if (sendObserver && slot !== undefined && slot !== null && Number.isSafeInteger(Number(slot))) {
        unsettledSends.push({ node: transportNode(node), pid, slot: Number(slot),
          timing: timing('accepted-unread', { res, slot }), observer: sendObserver });
      } else {
        report('accepted-unread', { res, slot });
      }
      return { slot, headers: res.headers };
    }
    tried.push(`${candidate} -> ${res.status} ${hbError(res)}`);
    if (res.status !== 404) break;
  }
  const error = new Error(`send failed on ${node}:\n  ${tried.join('\n  ')}`);
  error.status = lastResponse?.status ?? null;
  report(error.status === 429 ? 'rate-limited' : error.status === 408 ? 'timeout' : 'post-failed',
    { res: lastResponse, error: error.message });
  throw error;
}

/**
 * Deliver whatever a computed slot left in its outbox.
 *
 * A process cannot send anything by itself. A handler that wants to reach
 * another process writes the message into `results.outbox`, and it sits there
 * until somebody asks the node to push it — nothing does that automatically.
 *
 * `Rune.Withdraw` is the proof: the game deducted a player's runes and queued
 * the token's mint, and because nothing pushed, the token's slot count never
 * moved and the runes were destroyed. Every message that crosses a process
 * boundary needs this second half, so it runs for every write rather than only
 * where an outbox is expected — pushing an empty one costs nothing, and a
 * handler that starts emitting one later would otherwise silently stop working.
 *
 * Best-effort and never throws: the caller's own message has already been
 * accepted, and failing it because a downstream delivery was slow would report
 * completed work as an error.
 */
export async function pushSlot({ node, process: pid, slot }) {
  try {
    const res = await send(node, `/${pid}~process@1.0/push&slot=${slot}`, 'GET', {});
    return res.status === 200;
  } catch {
    return false;
  }
}

/**
 * One push in flight per process, in the order the slots were accepted.
 *
 * Keyed by `node|process` because the serialisation that matters is per
 * process: two different processes have separate heads and separate workers,
 * and holding one behind the other would just be a slower deploy. Two writes to
 * the SAME process are the ones that must not race, because the second push
 * asking for a slot the first has not reached yet is what makes the node replay
 * the gap.
 *
 * A rejection cannot escape here — `pushSlot` already swallows everything and
 * returns a boolean — but the `catch` stays so a future throw cannot turn one
 * failed delivery into an unhandled rejection that kills a seeding run.
 */
const PUSH_QUEUES = new Map();

export function queuePush({ node, process: pid, slot }) {
  const key = `${node}|${pid}`;
  const tail = (PUSH_QUEUES.get(key) ?? Promise.resolve())
    .then(() => pushSlot({ node, process: pid, slot }))
    .catch(() => false);
  PUSH_QUEUES.set(key, tail);
  return tail;
}

/**
 * Wait for queued pushes to drain. Await this before a script exits.
 *
 * This is not tidiness. A process cannot send anything by itself: a queued push
 * that never runs is an outbox that is never delivered, and the first time that
 * happened here the game had already deducted a player's Rune while the token's
 * mint sat undelivered — the runes were destroyed. Serialising the pushes makes
 * that window longer, so draining stops being optional.
 *
 * With no arguments, drains every process this client has pushed for.
 */
export async function pendingPushes({ node, process: pid } = {}) {
  const queues = node && pid
    ? [PUSH_QUEUES.get(`${node}|${pid}`)]
    : [...PUSH_QUEUES.values()];
  await Promise.all(queues.filter(Boolean));
}

// The safety net under the explicit drains. `beforeExit` fires when the loop
// runs dry with the process still alive, and awaiting here keeps it alive long
// enough for the tail to land — so a script that writes and returns without
// settling still delivers its outboxes. It does NOT fire on an explicit
// `process.exit()` or an uncaught throw, which is why `awaitComputedSlot`
// drains too rather than relying on this.
process.on('beforeExit', () => { void pendingPushes(); });


/** Plain unsigned GET of process state. `path` defaults to `now`. */
export async function readState({ node, process: pid, path = 'now' }) {
  const p = pid ? `/${pid}~process@1.0/${path.replace(/^\//, '')}` : '/' + path.replace(/^\//, '');
  const res = await send(node, p, 'GET', { accept: 'text/plain' });
  return {
    status: res.status,
    value: res.body.toString(),
    headers: res.headers
  };
}

/**
 * Wait until the process has actually COMPUTED up to `slot`, and only then let
 * the caller address that slot.
 *
 * ## Why a settle may not simply ask for the slot it wants
 *
 * A HyperBEAM slot carries two things forward and they travel separately: the
 * published map goes through the message cache, and the Luerl VM — every global
 * the contract keeps its world in — goes through the message's `priv`, which is
 * NOT cached. A `compute&slot=N` asked for before anything has driven the head
 * past N is served off a path with no live worker behind it: `dev_lua` re-runs
 * the module from the top, and the handler is called with a COMPLETE `base` and
 * an EMPTY set of globals.
 *
 * Nothing errors, and that is the whole problem. `users` still reads 50, every
 * `player-<address>` still holds the record it held, and `Players` is empty —
 * so the next wallet to act is minted from nothing, its funding is gone and its
 * `joinedAt` is rewritten to now. Measured on this node, on a throwaway process
 * per run, driving the same bootstrap eight ways:
 *
 *   settle by `compute&slot=N` immediately after the POST   5 runs, 5 wiped
 *   settle by `now/at-slot`, then address the slot          3 runs, 0 wiped
 *
 * — and the two contracts under test (the one before tonight's changes and the
 * one after) behaved identically in both columns, which is how we know this is
 * the read pattern and not the Lua.
 *
 * `now` is what makes the difference: it computes to the scheduler head through
 * the live worker, so by the time the slot is addressed it is already computed
 * and the read is a cache hit. One extra request per deploy message, against a
 * process that silently starts again from nothing.
 *
 * This is for DEPLOY and SEED paths — a single writer that can afford a `now`
 * read per message. The browser client deliberately does not do this (see
 * `computedSlot` in `src/lib/hyperbeam.ts`): it is one of many readers, `now`
 * is 18–46 s under concurrent writers, and the head is behind by construction
 * for a slot that client just scheduled.
 */
export async function awaitComputedSlot({
  node, process: pid, slot, attempts = 90, delayMs = 1000, maxDelayMs = 4_000,
  budgetMs = 180_000, fetchImpl = fetch,
}) {
  const target = Number(slot);
  if (!Number.isSafeInteger(target) || target < 0) {
    throw new Error(`awaitComputedSlot needs a slot number, got ${slot}`);
  }
  // Let this process's queued pushes land first. The node runs
  // `process-now-from-cache`, so `now/at-slot` READS the head rather than
  // driving it — during a cold burst the push is the only thing advancing it,
  // and settling before the pushes have run is waiting for something that only
  // the thing you are not waiting for can do. Draining here also means the six
  // callers of this function need no drain of their own.
  await pendingPushes({ node, process: pid });
  // The POLICY is `settleHead`, shared with the browser and swarm client in
  // `src/lib/hyperbeam.ts`. All this supplies is how a Node tool reads a head.
  const head = await settleHead({
    slot: target, attempts, delayMs, maxDelayMs, budgetMs,
    readHead: async () => {
      const res = await fetchImpl(
        `${transportNode(node)}/${pid}~process@1.0/now/at-slot`,
        { headers: { accept: 'text/plain' } },
      );
      if (!res.ok) return null;
      const body = (await res.text()).trim();
      // An HTML body at status 200 is "key absent", never a value.
      if (/^<!DOCTYPE html|^<html/i.test(body)) return null;
      const at = Number(body);
      return Number.isSafeInteger(at) ? at : null;
    },
  });
  // A computed head is when a held send's reply can be read by slot at all.
  if (head !== null && unsettledSends.length) await settleSends({ node, pid, head, fetchImpl });
  return head;
}

/** Drive one process through an already-scheduled final slot, once, in order. */
export async function driveComputedSlot(options) {
  queuePush({ node: options.node, process: options.process, slot: options.slot });
  return awaitComputedSlot(options);
}

export { toTabm, tabmToHttp, signatureBase, b64url, sha256, sfStr, sfInnerList, sfDict, hbError, send };
