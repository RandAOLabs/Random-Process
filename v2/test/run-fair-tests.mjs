// Fair-play tests (docs/PERMISSIONLESS.md, WP3): lib/fair.lua and fair/fair.lua
// run in Lua through compute(); expected hashes computed here with node:crypto
// (these are the vectors the browser client must match).
//   node test/run-fair-tests.mjs            local (AOS wasm)
//   node test/run-fair-tests.mjs --live URL a node's ~lua@5.3a (Luerl)
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
const sha = (s) => createHash('sha256').update(s, 'latin1').digest('hex');
const addr = (s) => s.padEnd(43, '_');

// The hashes of the fair-play flow, as fair-client.ts must compute them.
const commitHash = (game, session, s) => sha(`rng/fair/v1/commit|${game}|${session}|${s}`);
const sessionValue = (vb, game, session) => sha(`rng/fair/v1/beacon|${vb}|${game}|${session}`);
const finalValue = (v, s) => sha(`rng/fair/v1/final|${v}|${s}`);
const forfeitValue = (v) => sha(`rng/fair/v1/forfeit|${v}`);
// The beacon's per-request value (beacon/anyhonest.lua settle).
const requestValue = (round, requester, requestId) => sha(`hyperbeam/rng/any-honest/v1/request|${round}|${requester}|${requestId}`);

const F = {
  owner: addr('fair-owner'), sched: addr('scheduler'), stranger: addr('stranger'),
  beacon: addr('timelock-beacon'), other: addr('other-process'), game: addr('game'), game2: addr('game-two'),
  token: addr('rng-token'), payer: addr('payer'),
  self: 'f'.repeat(43), p1: addr('player-1'), p2: addr('player-2'), p3: addr('player-3'),
  s1: sha('secret-1'), s2: sha('secret-2'), s3: sha('secret-3'), s4: sha('secret-4'),
  round1: sha('round value 1'), round2: sha('round value 2'), round3: sha('round value 3'),
};
F.c1 = commitHash(F.game, 'sess-1', F.s1);
F.c2 = commitHash(F.game, 'sess-2', F.s2);
F.c3 = commitHash(F.game, 'sess-3', F.s3);
F.c4 = commitHash(F.game, 'sess-4', F.s4);
F.vb1 = requestValue(F.round1, F.self, 'fair-1');
F.vb2 = requestValue(F.round2, F.self, 'fair-2');
F.v1 = sessionValue(F.vb1, F.game, 'sess-1');
F.final1 = finalValue(F.v1, F.s1);
F.v2 = sessionValue(F.vb2, F.game, 'sess-2');
F.v3 = sessionValue(F.vb2, F.game, 'sess-3');
F.final3 = finalValue(F.v3, F.s3);
F.forfeit2 = forfeitValue(F.v2);
// A fixed vector, independent of the test flow, for fair-client.ts.
F.vector = { game: F.game, session: 'demo', secret: '00'.repeat(32), vb: '11'.repeat(32) };
F.vector.commit = commitHash(F.vector.game, F.vector.session, F.vector.secret);
F.vector.v = sessionValue(F.vector.vb, F.vector.game, F.vector.session);
F.vector.final = finalValue(F.vector.v, F.vector.secret);
F.vector.forfeit = forfeitValue(F.vector.v);

const luaString = (s) => `"${String(s).replace(/\\/g, '\\\\').replace(/"/g, '\\"')}"`;
const lua = (v) => Array.isArray(v) ? `{ ${v.map(lua).join(', ')} }`
  : typeof v === 'object' ? `{ ${Object.entries(v).map(([k, x]) => `[${luaString(k)}] = ${lua(x)}`).join(', ')} }`
  : typeof v === 'number' || typeof v === 'boolean' ? String(v) : luaString(v);

const bundle = [
  read('vendor/json.lua'),
  'local jsonx = (function()', read('vendor/jsonenc.lua'), 'end)()',
  'encode, jsonObject = jsonx.encode, jsonx.object',
  'json = require(".json")',
  'rng = (function()', read('lib/rng.lua'), 'end)()',
  'fair = (function()', read('lib/fair.lua'), 'end)()',
  read('fair/fair.lua'),
  `F = ${lua(F)}`,
  read('test/fair_test.lua'),
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
  const res = await fetch(`${node}/~lua@5.3a/fairtest`, { method: 'POST', headers: { 'content-type': 'application/lua' }, body: bundle });
  const body = await res.text();
  if (res.status !== 200) { console.error(`${node}: HTTP ${res.status}\n${body.slice(0, 3000)}`); process.exit(1); }
  verdict(body);
} else {
  const handle = await AoLoader(fs.readFileSync(AOS_WASM), { format: 'wasm32-unknown-emscripten', computeLimit: 9e12, memoryLimit: 512 * 1024 * 1024 });
  const pid = addr('fair-tests');
  const result = await handle(null, {
    Id: 'eval-fair-tests', Target: pid, Owner: pid, From: pid, Tags: [{ name: 'Action', value: 'Eval' }],
    Data: bundle + '\nreturn fairtest()', 'Block-Height': '1', Timestamp: '1700000000000', Module: 'aos', Cron: false,
  }, { Process: { Id: pid, Owner: pid, Tags: [] }, Module: { Id: 'aos', Tags: [] } });
  if (result.Error) { console.error(result.Error); process.exit(1); }
  const out = result.Output?.data;
  verdict(typeof out === 'string' ? out : out?.output ?? JSON.stringify(out));
}
