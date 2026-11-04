// Time-lock beacon contract tests: the contract run in Lua through compute(),
// rng@1.0 time-lock operations mocked by a table of answers computed with real
// BigInt math mod the RSA-2048 challenge number (SPEC.md §2.3, §2.5, §3).
//   node test/run-anyhonest-tests.mjs            local (AOS wasm)
//   node test/run-anyhonest-tests.mjs --live URL a node's ~lua@5.3a (Luerl)
import fs from 'node:fs';
import path from 'node:path';
import { createHash } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import AoLoader from '@permaweb/ao-loader';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const V2 = path.resolve(HERE, '..');
const AOS_WASM = process.env.AOS_WASM
  || path.join(process.env.PARALITH_ROOT || 'C:/REPO/paralith-mono', 'backend/native/module/AOS.wasm');
const read = (p) => fs.readFileSync(path.join(V2, p), 'utf8');
const shaBuf = (s) => createHash('sha256').update(s, 'latin1').digest();
const sha = (s) => shaBuf(s).toString('hex');
const addr = (s) => s.padEnd(43, '_');

// --- rng@1.0 time-lock operations, in BigInt ---------------------------------

const N = BigInt('0xc7970ceedcc3b0754490201a7aa613cd73911081c790f5f1a8726f463550bb5b'
  + '7ff0db8e1ea1189ec72f93d1650011bd721aeeacc2acde32a04107f0648c2813'
  + 'a31f5b0b7765ff8b44b4b6ffc93384b646eb09c7cf5e8592d40ea33c80039f35'
  + 'b4f14a04b51f7bfd781be4d1673164ba8eb991c2c4d730bbbe35f592bdef524a'
  + 'f7e8daefd26c66fc02c479af89d64d373f442709439de66ceb955f3ea37d5159'
  + 'f6135809f85334b5cb1813addc80cd05609f10ac6a95ad65872c909525bdad32'
  + 'bc729592642920f24c61dc5b3c3b7923e56b16a4d9d373d8721f24a3fc0f1b31'
  + '31f55615172866bccc30f95054c824e733a5eb6817f7bc16399d48c6361cc7e5');
const hex = (n) => n.toString(16);
const big = (h) => BigInt('0x' + h);
const canon = (y) => (y < N - y ? y : N - y);
function modPow(b, e, m = N) {
  let r = 1n;
  b %= m;
  for (; e > 0n; e >>= 1n) { if (e & 1n) r = (r * b) % m; b = (b * b) % m; }
  return r;
}
function expand(s, bits) {
  const parts = [];
  for (let k = 0; parts.length * 256 < bits; k++) parts.push(shaBuf(`${s}|${k}`));
  return big(Buffer.concat(parts).toString('hex')) >> BigInt(parts.length * 256 - bits);
}
const G = modPow(expand('rng/timelock/g', 2112) % N, 2n);
const SMALL = [];
for (let n = 2; n < 1000; n++) if (SMALL.every((p) => n % p)) SMALL.push(n);
function isPrime(n) {
  for (const p of SMALL) if (n % BigInt(p) === 0n) return n === BigInt(p);
  let d = n - 1n, s = 0;
  while (!(d & 1n)) { d >>= 1n; s++; }
  next: for (const a of SMALL.slice(0, 20).map(BigInt)) {
    let x = modPow(a, d, n);
    if (x === 1n || x === n - 1n) continue;
    for (let i = 1; i < s; i++) { x = (x * x) % n; if (x === n - 1n) continue next; }
    return false;
  }
  return true;
}
function challenge(xHex, yHex, t) {
  let l = big(shaBuf(`rng/wesolowski|${xHex}|${yHex}|${t}`).subarray(0, 16).toString('hex')) | (1n << 127n) | 1n;
  while (!isPrime(l)) l += 2n;
  return l;
}
const okHex = (s) => typeof s === 'string' && /^[1-9a-f][0-9a-f]*$/.test(s) && big(s) < N;
const device = {
  'verify-reveal': ({ c, alpha, h }) => {
    if (!okHex(c) || !okHex(h) || !/^[1-9a-f][0-9a-f]{0,127}$/.test(alpha)) return { valid: false, reason: 'bad input' };
    if (modPow(G, big(alpha)) !== big(c)) return { valid: false, reason: 'g^alpha != c' };
    return { valid: true, y: hex(canon(modPow(big(h), big(alpha)))) };
  },
  'verify-crack': ({ x, t, y, proof }) => {
    if (![x, y, proof].every(okHex) || !(Number(t) <= 2 ** 32)) return { valid: false, reason: 'bad input' };
    const T = BigInt(t), l = challenge(x, y, t);
    const ok = (modPow(big(proof), l) * modPow(big(x), modPow(2n, T, l))) % N === big(y);
    return ok ? { valid: true, y: hex(canon(big(y))) } : { valid: false, reason: 'bad proof' };
  },
  generator: () => ({ g: hex(G), n: hex(N) }),
};
// Every call the contract makes is looked up here; the Lua mock counts misses.
const FIELDS = { 'verify-reveal': ['c', 'alpha', 'h'], 'verify-crack': ['x', 't', 'y', 'proof'], generator: [] };
const dev = {};
function answer(key, inputs) {
  const res = device[key](inputs);
  dev[[key, ...FIELDS[key].map((f) => inputs[f])].join('|')] = res;
  return res;
}
/** y = x^(2^t) (or N - y) with its Wesolowski proof, answered by the device. */
function crack(xHex, t, negate = false) {
  const x = big(xHex), y = modPow(x, 1n << BigInt(t));
  const yHex = hex(negate ? N - y : y), l = challenge(xHex, yHex, t);
  let proof = modPow(x, (1n << BigInt(t)) / l);
  if (negate) proof = N - proof; // (-p)^l = -(p^l), l odd
  const res = answer('verify-crack', { x: xHex, t: String(t), y: yHex, proof: hex(proof) });
  if (!res.valid) throw new Error('fixture crack does not verify');
  return { y: yHex, proof: hex(proof) };
}

// --- fixtures -----------------------------------------------------------------

const T = 1024, T2 = 2048;
const F = {
  owner: addr('owner'), sched: addr('scheduler'), stranger: addr('stranger'), token: addr('rng-token'),
  game: addr('game'), beacon: addr('timelock-beacon'), unit: 1000000, T, T2, N: hex(N), g: hex(G),
  v: [addr('val-a'), addr('val-b'), addr('val-c')],
};
const H1 = crack(hex(G), T), H2 = crack(hex(G), T2);
Object.assign(F, { h: H1.y, hProof: H1.proof, h2: H2.y, hProof2: H2.proof, badHProof: hex(big(H2.proof) + 1n) });
answer('verify-crack', { x: hex(G), t: String(T2), y: F.h2, proof: F.badHProof });
answer('verify-crack', { x: hex(G), t: String(T), y: F.h2, proof: F.hProof2 }); // h for another T
answer('generator', {});
if (!read('beacon/anyhonest.lua').replace(/"\s*\.\.\s*"/g, '').includes(hex(G))) throw new Error('anyhonest.lua g differs from the reference');

// P[name] = { c, alpha, y* }, every reveal of it answered; names are round + validator.
const P = {};
const puzzle = (name, h = F.h) => {
  const alpha = hex(big(sha(`alpha|${name}`)) | 1n);
  const c = hex(modPow(G, big(alpha)));
  P[name] = { c, alpha, y: answer('verify-reveal', { c, alpha, h }).y };
};
for (const n of ['r1a', 'r1b', 'r1c', 'r2a', 'r2b', 'r2c', 'r3a', 'r3b', 'r3c', 'r4a', 'r4b', 'r4c',
  'r5a', 'r5b', 'r5c', 'r6a', 'r6b', 'r7a', 'r7b', 'r8a', 'r8a2', 'r8b', 'r8c']) puzzle(n);
for (const n of ['r9a', 'r9b', 'r9c']) puzzle(n, F.h2);
answer('verify-reveal', { c: P.r1a.c, alpha: P.r1b.alpha, h: F.h }); // wrong secret
// Round 2: c withholds, a stranger cracks it with N - y; round 3: a cracks c.
F.crack2 = crack(P.r2c.c, T, big(P.r2c.y) === modPow(big(P.r2c.c), 1n << BigInt(T)));
F.crack3 = crack(P.r3c.c, T);
F.badCrack = hex(big(F.crack3.proof) + 1n);
answer('verify-crack', { x: P.r3c.c, t: String(T), y: F.crack3.y, proof: F.badCrack });
if (big(F.crack2.y) === big(P.r2c.y)) throw new Error('crack2 should submit the non-canonical y');

const value = (r, names) => sha(`hyperbeam/rng/any-honest/v1/round|${F.beacon}|${r}|${names.map((n) => P[n].y).join('|')}`);
F.value1 = value(1, ['r1a', 'r1b', 'r1c']);
F.value2 = value(2, ['r2a', 'r2b', 'r2c']);
F.value3 = value(3, ['r3a', 'r3b', 'r3c']);
F.out1 = sha(`hyperbeam/rng/any-honest/v1/request|${F.value1}|${F.game}|req-1`);
F.config = JSON.stringify({ self: F.beacon, token: F.token, unit: F.unit, T, h: F.h, hProof: F.hProof,
  commitWindowMs: 3000, revealWindowMs: 10000, abandonAfterMs: 60000, minCommits: 2, cadenceMs: 0, targetIntervalMs: 0, stake: 25000, slash: 1000,
  heartbeat: 1, roundPrice: 3, requestPrice: 4, subscriptionPrice: 1, subscriptionRounds: 1000, crackBounty: 10 });
F.dev = dev;

const luaString = (s) => `"${String(s).replace(/\\/g, '\\\\').replace(/"/g, '\\"')}"`;
const lua = (v) => Array.isArray(v) ? `{ ${v.map(lua).join(', ')} }`
  : typeof v === 'object' ? `{ ${Object.entries(v).map(([k, x]) => `[${luaString(k)}] = ${lua(x)}`).join(', ')} }`
  : typeof v === 'number' ? String(v) : typeof v === 'boolean' ? String(v) : luaString(v);
const fixtures = `F = ${lua(F)}\nP = ${lua(P)}\nDEVICE_FIELDS = ${lua(FIELDS)}`;

const bundle = [
  read('vendor/json.lua'),
  'local jsonx = (function()', read('vendor/jsonenc.lua'), 'end)()',
  'encode, jsonObject = jsonx.encode, jsonx.object',
  'json = require(".json")',
  'Owner = nil',
  'TestHarness = true',
  'rng = (function()', read('lib/rng.lua'), 'end)()',
  read('beacon/anyhonest.lua'),
  fixtures,
  read('test/anyhonest_test.lua'),
].join('\n');

function verdict(text) {
  console.log(text);
  const m = /(\d+) passed, (\d+) failed\s*$/.exec(text);
  if (!m) { console.error('no verdict'); process.exit(1); }
  process.exit(m[2] === '0' ? 0 : 1);
}

const live = process.argv.indexOf('--live');
if (live !== -1) {
  const node = process.argv[live + 1] || 'https://randao.net/hb-stage';
  const res = await fetch(`${node}/~lua@5.3a/rngtest`, { method: 'POST', headers: { 'content-type': 'application/lua' }, body: bundle });
  const body = await res.text();
  if (res.status !== 200) { console.error(`${node}: HTTP ${res.status}\n${body.slice(0, 3000)}`); process.exit(1); }
  verdict(body);
} else {
  const handle = await AoLoader(fs.readFileSync(AOS_WASM), { format: 'wasm32-unknown-emscripten', computeLimit: 9e12, memoryLimit: 512 * 1024 * 1024 });
  const pid = addr('timelock-tests');
  const result = await handle(null, {
    Id: 'eval-timelock-tests', Target: pid, Owner: pid, From: pid, Tags: [{ name: 'Action', value: 'Eval' }],
    Data: bundle + '\nreturn rngtest()', 'Block-Height': '1', Timestamp: '1700000000000', Module: 'aos', Cron: false,
  }, { Process: { Id: pid, Owner: pid, Tags: [] }, Module: { Id: 'aos', Tags: [] } });
  if (result.Error) { console.error(result.Error); process.exit(1); }
  const out = result.Output?.data;
  verdict(typeof out === 'string' ? out : out?.output ?? JSON.stringify(out));
}
