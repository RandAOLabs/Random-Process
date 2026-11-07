// Time-lock puzzles for the `any-honest` surface: the reference
// implementation the validator daemon uses and the ~rng@1.0 device's test
// vectors are generated from.
import crypto from 'node:crypto';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';

const sha256 = (s) => crypto.createHash('sha256').update(s).digest();
const hex = (n) => n.toString(16);
const run = promisify(execFile);

export function modPow(b, e, m) {
  let r = 1n;
  b %= m;
  while (e > 0n) {
    if (e & 1n) r = (r * b) % m;
    b = (b * b) % m;
    e >>= 1n;
  }
  return r;
}

/** First `bits` bits of SHA-256(s|0) || SHA-256(s|1) || ... as a BigInt. */
export function expand(seed, bits) {
  const parts = [];
  for (let k = 0; parts.length * 256 < bits; k++) parts.push(sha256(`${seed}|${k}`));
  const all = BigInt('0x' + Buffer.concat(parts).toString('hex'));
  return all >> BigInt(parts.length * 256 - bits);
}

// The RSA-2048 challenge number: nobody knows its factors, so nobody knows
// the group order (SPEC 2.3).
export const N_HEX =
  'c7970ceedcc3b0754490201a7aa613cd73911081c790f5f1a8726f463550bb5b' +
  '7ff0db8e1ea1189ec72f93d1650011bd721aeeacc2acde32a04107f0648c2813' +
  'a31f5b0b7765ff8b44b4b6ffc93384b646eb09c7cf5e8592d40ea33c80039f35' +
  'b4f14a04b51f7bfd781be4d1673164ba8eb991c2c4d730bbbe35f592bdef524a' +
  'f7e8daefd26c66fc02c479af89d64d373f442709439de66ceb955f3ea37d5159' +
  'f6135809f85334b5cb1813addc80cd05609f10ac6a95ad65872c909525bdad32' +
  'bc729592642920f24c61dc5b3c3b7923e56b16a4d9d373d8721f24a3fc0f1b31' +
  '31f55615172866bccc30f95054c824e733a5eb6817f7bc16399d48c6361cc7e5';
export const N = BigInt('0x' + N_HEX);
export const G = (() => { const v = expand('rng/timelock/g', 2112) % N; return (v * v) % N; })();
export const G_HEX = hex(G);

/** Lowercase hex without leading zeros, else null: one spelling per number. */
export function parseHex(h) {
  return typeof h === 'string' && /^(0|[1-9a-f][0-9a-f]*)$/.test(h) ? BigInt('0x' + h) : null;
}
const parseT = (t) => (/^(0|[1-9][0-9]*)$/.test(String(t)) ? BigInt(t) : null);

/** y* = min(y, N - y): y and N - y pass the same checks, so they count as one. */
export const canonical = (y) => (y <= N - y ? y : N - y);

/** A fresh 256-bit secret, as hex. Never reuse one. */
export const newAlpha = () => hex(BigInt('0x' + crypto.randomBytes(32).toString('hex')));

/** The commit c = g^alpha mod N (hex in, hex out). */
export const commit = (alphaHex) => hex(modPow(G, parseHex(alphaHex), N));

/** The committer's own output y* = canonical(h^alpha), instantly. */
export const output = (alphaHex, hHex) => hex(canonical(modPow(parseHex(hHex), parseHex(alphaHex), N)));

/** SPEC 2.4 step 2, as the device: { valid, y } or { valid: false, reason }. */
export function verifyReveal(cHex, alphaHex, hHex) {
  const c = parseHex(cHex), alpha = parseHex(alphaHex), h = parseHex(hHex);
  if (c === null || c <= 0n || c >= N) return { valid: false, reason: 'c out of range' };
  if (h === null || h <= 0n || h >= N) return { valid: false, reason: 'h out of range' };
  if (alpha === null || alpha.toString(2).length > 512) return { valid: false, reason: 'bad alpha' };
  if (modPow(G, alpha, N) !== c) return { valid: false, reason: 'g^alpha is not c' };
  return { valid: true, y: hex(canonical(modPow(h, alpha, N))) };
}

// --- Wesolowski (SPEC 2.5) -------------------------------------------------

const SMALL_PRIMES = (() => {
  const out = [];
  for (let n = 2; n < 1000; n++) if (out.every((p) => n % p !== 0)) out.push(n);
  return out;
})();
const MR_BASES = SMALL_PRIMES.slice(0, 20).map(BigInt);

export function isProbablePrime(n) {
  if (n < 2n) return false;
  for (const p of SMALL_PRIMES) {
    const P = BigInt(p);
    if (n === P) return true;
    if (n % P === 0n) return false;
  }
  let d = n - 1n, s = 0;
  while ((d & 1n) === 0n) { d >>= 1n; s++; }
  outer: for (const a of MR_BASES) {
    let x = modPow(a, d, n);
    if (x === 1n || x === n - 1n) continue;
    for (let i = 1; i < s; i++) {
      x = (x * x) % n;
      if (x === n - 1n) continue outer;
    }
    return false;
  }
  return true;
}

export function challengePrime(xHex, yHex, T) {
  const h = sha256(`rng/wesolowski|${xHex}|${yHex}|${T}`);
  let c = BigInt('0x' + h.subarray(0, 16).toString('hex')) | (1n << 127n) | 1n;
  while (!isProbablePrime(c)) c += 2n;
  return c;
}

/**
 * Crack a puzzle: T sequential squarings of x, then the Wesolowski proof
 * (long division of 2^T by l, bit by bit). With x = g this makes h and hProof.
 * `onProgress(done, total)` is called every 2^16 of the 2T steps.
 */
export function crack(xHex, T, onProgress) {
  const x = parseHex(xHex);
  let y = x;
  for (let i = 0; i < T; i++) {
    y = (y * y) % N;
    if (onProgress && (i & 0xffff) === 0) onProgress(i, 2 * T);
  }
  const yHex = hex(y);
  const l = challengePrime(xHex, yHex, T);
  // proof = x^floor(2^T / l): walk the bits of the quotient from the top.
  let proof = 1n, r = 1n;
  for (let i = 0; i < T; i++) {
    const b = (2n * r) / l;
    r = (2n * r) % l;
    proof = (proof * proof) % N;
    if (b) proof = (proof * x) % N;
    if (onProgress && (i & 0xffff) === 0) onProgress(T + i, 2 * T);
  }
  return { y: yHex, proof: hex(proof) };
}

/** The same with the native GMP cracker (provider/cracker.c) at `bin`. */
export async function crackNative(bin, xHex, T) {
  const opts = { maxBuffer: 1 << 20 };
  const y = (await run(bin, ['y', N_HEX, xHex, String(T)], opts)).stdout.trim();
  const l = challengePrime(xHex, y, T);
  const proof = (await run(bin, ['proof', N_HEX, xHex, String(T), hex(l)], opts)).stdout.trim();
  return { y, proof };
}

/** SPEC 2.4 step 3, as the device: { valid, y } or { valid: false, reason }. */
export function verifyCrack(xHex, t, yHex, proofHex) {
  const x = parseHex(xHex), y = parseHex(yHex), proof = parseHex(proofHex), T = parseT(t);
  for (const [k, v] of [['x', x], ['y', y], ['proof', proof]]) {
    if (v === null || v <= 0n || v >= N) return { valid: false, reason: `${k} out of range` };
  }
  if (T === null || T > 2n ** 32n) return { valid: false, reason: 'bad t' };
  const l = challengePrime(xHex, yHex, T);
  if ((modPow(proof, l, N) * modPow(x, modPow(2n, T, l), N)) % N !== y) return { valid: false, reason: 'bad proof' };
  return { valid: true, y: hex(canonical(y)) };
}

/**
 * Re-check one output of a published round (SPEC 2.6): { y, via: 'reveal', alpha }
 * or { y, via: 'crack', proof } against the commit c. Returns y* or null. A crack
 * may have been made for N - y (same y*), so both are tried.
 */
export function checkOutput(cHex, out, T, hHex) {
  const y = parseHex(out.y);
  if (y === null || y <= 0n || y >= N) return null;
  const want = hex(canonical(y));
  if (out.via === 'reveal') return verifyReveal(cHex, out.alpha, hHex).y === want ? want : null;
  if (out.via !== 'crack') return null;
  for (const ys of [out.y, hex(N - y)]) if (verifyCrack(cHex, T, ys, out.proof).y === want) return want;
  return null;
}

/** The round value (SPEC 2.4 step 4); outputs: { address: y* hex }. */
export function roundValue(beacon, round, outputs) {
  const ys = Object.keys(outputs).sort().map((a) => outputs[a]);
  return crypto.createHash('sha256').update(`hyperbeam/rng/any-honest/v1/round|${beacon}|${round}|${ys.join('|')}`).digest('hex');
}

/** A request-specific value derived from one Any-Honest round. */
export const requestValue = (value, requester, requestId) =>
  crypto.createHash('sha256').update(`hyperbeam/rng/any-honest/v1/request|${value}|${requester}|${requestId}`, 'latin1').digest('hex');

/** Every reveal still missing after its deadline in a beaconinfo:
 *  [{ round, target, c, T, giveUpAt }]. giveUpAt is when the beacon abandons
 *  the round: its published `abandonAt` (a round that is not abandonable waits
 *  for its crack up to 7 days), else, from an older beacon, abandonAfterMs. */
export function crackJobs(i, now) {
  const out = [];
  for (const x of i.revealing ?? []) {
    if (x.phase !== 'reveal' || !(x.revealDeadline > 0) || now < x.revealDeadline) continue;
    const giveUpAt = Number.isFinite(x.abandonAt) ? x.abandonAt
      : x.revealDeadline + Number(i.params?.abandonAfterMs ?? 1_800_000);
    for (const [target, c] of Object.entries(x.committed ?? {})) {
      // A beacon shows a commitment whole only once its round is late; before
      // that it is a 16-digit prefix, nothing to crack.
      if ((x.revealed ?? []).includes(target) || typeof c !== 'string' || c.length <= 16) continue;
      out.push({ round: x.round, target, c, T: x.T ?? i.params.T, giveUpAt });
    }
  }
  return out.sort((a, b) => a.round - b.round);
}
