/**
 * ans104.mjs — build and sign ANS-104 data items, with no dependencies.
 *
 * This exists so the end-to-end harness can drive the SAME code path the
 * browser uses. A page cannot produce HyperBEAM's httpsig signature, so a write
 * from the app is always an ANS-104 data item signed by the wallet extension's
 * `signDataItem`. `hbclient.mjs` signs httpsig, which is a different scheme —
 * testing through it would exercise a path no player ever takes.
 *
 * So this implements the wallet side: given a JWK and the same
 * `{data, target, tags}` object the app passes to `signDataItem`, it returns
 * the signed binary the extension would have returned.
 *
 * Format (ANS-104, signature type 1 — Arweave RSA-4096):
 *
 *   u16le  signature type            = 1
 *   [512]  signature
 *   [512]  owner (the RSA modulus)
 *   u8     target present            + [32] target
 *   u8     anchor present            + [32] anchor
 *   u64le  tag count
 *   u64le  tag bytes length
 *   [...]  tags, Avro-encoded
 *   [...]  data
 *
 * The signature is RSA-PSS/SHA-256 (salt length 32) over the Arweave deep hash
 * of ["dataitem", "1", sigType, owner, target, anchor, tags, data].
 */
import crypto from 'node:crypto';

const enc = new TextEncoder();
const sha384 = (b) => crypto.createHash('sha384').update(b).digest();
const sha256 = (b) => crypto.createHash('sha256').update(b).digest();
const b64url = (b) => Buffer.from(b).toString('base64url');
const b64urlDec = (s) => Buffer.from(s, 'base64url');

// Deep hash ------------------------------------------------------------------

function deepHash(value) {
  if (Array.isArray(value)) {
    const tag = enc.encode(`list${value.length}`);
    return deepHashChunks(value, sha384(tag));
  }
  const data = Buffer.from(value);
  const tag = enc.encode(`blob${data.length}`);
  return sha384(Buffer.concat([sha384(tag), sha384(data)]));
}

function deepHashChunks(chunks, acc) {
  if (chunks.length === 0) return acc;
  const next = sha384(Buffer.concat([acc, deepHash(chunks[0])]));
  return deepHashChunks(chunks.slice(1), next);
}

// Avro tag encoding ----------------------------------------------------------

/** Avro writes integers as zigzag-encoded variable-length ints. */
function zigzag(n) {
  let value = (n << 1) ^ (n >> 31);
  if (n > 0x3fffffff || n < -0x3fffffff) {
    // Fall back to BigInt for anything that would overflow a 32-bit shift.
    const big = BigInt(n);
    value = Number((big << 1n) ^ (big >> 63n));
  }
  const bytes = [];
  let v = value >>> 0;
  while (v > 0x7f) {
    bytes.push((v & 0x7f) | 0x80);
    v >>>= 7;
  }
  bytes.push(v);
  return Buffer.from(bytes);
}

function avroString(s) {
  const body = Buffer.from(s, 'utf8');
  return Buffer.concat([zigzag(body.length), body]);
}

export function encodeTags(tags) {
  if (!tags || tags.length === 0) return Buffer.alloc(0);
  const parts = [zigzag(tags.length)];
  for (const { name, value } of tags) {
    parts.push(avroString(String(name)), avroString(String(value)));
  }
  parts.push(Buffer.from([0])); // block terminator
  return Buffer.concat(parts);
}

// Signing --------------------------------------------------------------------

function longTo8Bytes(n) {
  const buf = Buffer.alloc(8);
  buf.writeBigUInt64LE(BigInt(n));
  return buf;
}

/**
 * The wallet's `signDataItem`, implemented for Node.
 *
 * `item` is exactly what the app passes: `{ data, target, tags }`.
 * Returns the signed data item as a Buffer, which is what the app POSTs.
 */
export async function signDataItem(jwk, item) {
  const owner = b64urlDec(jwk.n);
  const target = item.target ? b64urlDec(item.target) : Buffer.alloc(0);
  const anchor = item.anchor ? Buffer.from(item.anchor) : Buffer.alloc(0);
  const tagBytes = encodeTags(item.tags ?? []);
  const data = Buffer.from(item.data ?? '', typeof item.data === 'string' ? 'utf8' : undefined);

  if (target.length && target.length !== 32) {
    throw new Error(`target must be a 32-byte address, got ${target.length}`);
  }

  const digest = deepHash([
    enc.encode('dataitem'),
    enc.encode('1'),
    enc.encode('1'),          // signature type 1, as a decimal string
    owner,
    target,
    anchor,
    tagBytes,
    data,
  ]);

  // WebCrypto's RSA-PSS (what the wallet extension uses) hashes what it is
  // given, so the deep hash is the *message*, not the digest — sign it with
  // SHA-256 and a salt length of 32 to match.
  const signature = crypto.sign('sha256', digest, {
    key: crypto.createPrivateKey({ key: { ...jwk, kty: 'RSA' }, format: 'jwk' }),
    padding: crypto.constants.RSA_PKCS1_PSS_PADDING,
    saltLength: 32,
  });

  return Buffer.concat([
    Buffer.from([1, 0]),                                    // sig type 1, u16le
    signature,                                              // 512
    owner,                                                  // 512
    target.length ? Buffer.concat([Buffer.from([1]), target]) : Buffer.from([0]),
    anchor.length ? Buffer.concat([Buffer.from([1]), anchor]) : Buffer.from([0]),
    longTo8Bytes(item.tags?.length ?? 0),
    longTo8Bytes(tagBytes.length),
    tagBytes,
    data,
  ]);
}

export const jwkToAddress = (jwk) => b64url(sha256(b64urlDec(jwk.n)));

/**
 * Generate a burner wallet.
 *
 * Arweave keys are RSA-4096 with e=65537. Generating one takes a few seconds;
 * that is the cost of the key size, not a bug.
 */
export function generateWallet() {
  const { privateKey } = crypto.generateKeyPairSync('rsa', {
    modulusLength: 4096,
    publicExponent: 0x10001,
  });
  const jwk = privateKey.export({ format: 'jwk' });
  return { ...jwk, kty: 'RSA' };
}

/**
 * Install a wallet shim at `globalThis.arweaveWallet`, so code written against
 * the browser extension runs unchanged in Node.
 */
export function installWalletShim(jwk) {
  globalThis.arweaveWallet = walletShim(jwk);
  return jwkToAddress(jwk);
}

/**
 * The same shim without installing it, for a thread that hosts several
 * wallets and so cannot hang any one of them on `globalThis`.
 */
export function walletShim(jwk) {
  const address = jwkToAddress(jwk);
  return {
    async connect() {},
    async disconnect() {},
    async getActiveAddress() { return address; },
    async getPermissions() {
      return ['ACCESS_ADDRESS', 'ACCESS_PUBLIC_KEY', 'SIGN_TRANSACTION'];
    },
    async signDataItem(item) {
      const buf = await signDataItem(jwk, item);
      // The extension hands back an ArrayBuffer; match that exactly, or the
      // app's `new Uint8Array(signed)` silently produces the wrong bytes.
      return buf.buffer.slice(buf.byteOffset, buf.byteOffset + buf.byteLength);
    },
  };
}
