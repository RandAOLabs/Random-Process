// Beacon contract tests: real threshold-BLS fixtures from JS, the contract run
// in Lua through compute().
//   node test/run-beacon-tests.mjs              local (AOS wasm via ao-loader)
//   node test/run-beacon-tests.mjs --live URL   a HyperBEAM node's ~lua@5.3a (Luerl)
import fs from 'node:fs';
import path from 'node:path';
import { createHash } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import AoLoader from '@permaweb/ao-loader';
import * as bls from '../provider/bls.mjs';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const V2 = path.resolve(HERE, '..');
const AOS_WASM = process.env.AOS_WASM
  || path.join(process.env.PARALITH_ROOT || 'C:/REPO/paralith-mono', 'backend/native/module/AOS.wasm');
const read = (p) => fs.readFileSync(path.join(V2, p), 'utf8');
const sha = (s) => createHash('sha256').update(s, 'latin1').digest('hex');
const addr = (s) => s.padEnd(43, '_');

// Fixtures.
const F = {
  owner: addr('owner'), sched: addr('scheduler'), stranger: addr('stranger'),
  token: addr('rng-token'), game: addr('game'), beacon: addr('beacon'),
  members: [addr('node-1'), addr('node-2'), addr('node-3')],
  unit: 1000000, req1: 'r-one', req2: 'r-two', req3: 'r-three', req4: 'r-four',
};
const deals = [1, 2, 3].map(() => bls.dkgDeal(3, 2));
const commitments = Object.fromEntries(deals.map((d, i) => [i + 1, d.commitments]));
const shares = [1, 2, 3].map((j) => bls.dkgFinish(j, 3, 2, Object.fromEntries(deals.map((d, i) => [i + 1, d.shares[j]])), commitments));
F.sharePublicKeys = [1, 2, 3].map((i) => shares[0].sharePublicKeys[i]);
const roundMessage = (round) => `hyperbeam/rng/v1|${F.beacon}|${round}`;
const sign = (msg, idx) => bls.combine(idx.map((i) => ({ index: shares[i].index, signature: bls.partialSign(shares[i], msg) })));
F.sig1 = sign(roundMessage(1), [0, 2]);
F.sig2 = sign(roundMessage(2), [1, 2]);
F.sig3 = sign(roundMessage(3), [0, 1]);
F.partial31 = bls.partialSign(shares[0], roundMessage(3));
F.partial32 = bls.partialSign(shares[1], roundMessage(3));
if (!bls.verify(shares[0].groupKey, roundMessage(1), F.sig1)) throw new Error('fixture signature does not verify');
const forged = bls.dealerKeygen(3, 2);
F.fake1 = bls.combine([0, 1].map((i) => ({ index: forged.shares[i].index, signature: bls.partialSign(forged.shares[i], roundMessage(1)) })));
F.fake3 = bls.combine([0, 1].map((i) => ({ index: forged.shares[i].index, signature: bls.partialSign(forged.shares[i], roundMessage(3)) })));
F.value1 = sha(`hyperbeam/rng/v1/round|${roundMessage(1)}|${F.sig1}`);
F.value3 = sha(`hyperbeam/rng/v1/round|${roundMessage(3)}|${F.sig3}`);
F.out1 = sha(`hyperbeam/rng/v1/request|${F.value1}|${F.req1}`);
F.out2 = sha(`hyperbeam/rng/v1/request|${F.value1}|${F.req2}`);
F.config = JSON.stringify({ self: F.beacon, token: F.token, threshold: 2, cadenceMs: 5000,
  groupKey: shares[0].groupKey, committee: F.members, sharePublicKeys: F.sharePublicKeys, unit: F.unit });

const luaString = (s) => `"${String(s).replace(/\\/g, '\\\\').replace(/"/g, '\\"')}"`;
const luaValue = (v) => Array.isArray(v) ? `{ ${v.map(luaValue).join(', ')} }`
  : typeof v === 'number' ? String(v) : luaString(v);
const fixtures = `F = { ${Object.entries(F).map(([k, v]) => `${k} = ${luaValue(v)}`).join(',\n  ')} }`;

const bundle = [
  read('vendor/json.lua'),
  'local jsonx = (function()', read('vendor/jsonenc.lua'), 'end)()',
  'encode, jsonObject = jsonx.encode, jsonx.object',
  'json = require(".json")',
  'Owner = nil -- AOS presets Owner; on a node the contract resolves it from the spawn signer',
  'rng = (function()', read('lib/rng.lua'), 'end)()',
  read('beacon/beacon.lua'),
  fixtures,
  read('test/beacon_test.lua'),
].join('\n');

function verdict(text) {
  console.log(text);
  const m = /(\d+) passed, (\d+) failed\s*$/.exec(text);
  if (!m) { console.error('no verdict'); process.exit(1); }
  process.exit(m[2] === '0' ? 0 : 1);
}

const live = process.argv.indexOf('--live');
if (live !== -1) {
  const node = process.argv[live + 1] || 'https://hyperbeam.tylerw.ai';
  const res = await fetch(`${node}/~lua@5.3a/rngtest`, { method: 'POST', headers: { 'content-type': 'application/lua' }, body: bundle });
  const body = await res.text();
  if (res.status !== 200) { console.error(`${node}: HTTP ${res.status}\n${body.slice(0, 3000)}`); process.exit(1); }
  verdict(body);
} else {
  const handle = await AoLoader(fs.readFileSync(AOS_WASM), { format: 'wasm32-unknown-emscripten', computeLimit: 9e12, memoryLimit: 512 * 1024 * 1024 });
  const pid = addr('beacon-tests');
  const result = await handle(null, {
    Id: 'eval-beacon-tests', Target: pid, Owner: pid, From: pid, Tags: [{ name: 'Action', value: 'Eval' }],
    Data: bundle + '\nreturn runBeaconTests()', 'Block-Height': '1', Timestamp: '1700000000000', Module: 'aos', Cron: false,
  }, { Process: { Id: pid, Owner: pid, Tags: [] }, Module: { Id: 'aos', Tags: [] } });
  if (result.Error) { console.error(result.Error); process.exit(1); }
  const out = result.Output?.data;
  verdict(typeof out === 'string' ? out : out?.output ?? JSON.stringify(out));
}
