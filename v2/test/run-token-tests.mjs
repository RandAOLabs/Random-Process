import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import AoLoader from '@permaweb/ao-loader';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const V2 = path.resolve(HERE, '..');
const AOS_WASM = process.env.AOS_WASM
  || path.join(process.env.PARALITH_ROOT || 'C:/REPO/paralith-mono', 'backend/native/module/AOS.wasm');
const read = (p) => fs.readFileSync(path.join(V2, p), 'utf8');
const addr = (s) => s.padEnd(43, '_');
const F = {
  owner: addr('owner'), sched: addr('scheduler'), user: addr('user'),
  stranger: addr('stranger'), process: addr('process'), recipient: addr('recipient'),
};
const luaString = (s) => `"${String(s).replace(/\\/g, '\\\\').replace(/"/g, '\\"')}"`;
const fixtures = `F = { ${Object.entries(F).map(([k, v]) => `${k} = ${luaString(v)}`).join(', ')} }`;
const bundle = [
  read('vendor/json.lua'),
  'local jsonx = (function()', read('vendor/jsonenc.lua'), 'end)()',
  'encode, jsonObject = jsonx.encode, jsonx.object',
  'json = require(".json")',
  'Owner = nil',
  read('token/rng-token.lua'),
  fixtures,
  read('test/token_test.lua'),
].join('\n');

const handle = await AoLoader(fs.readFileSync(AOS_WASM), {
  format: 'wasm32-unknown-emscripten', computeLimit: 9e12, memoryLimit: 512 * 1024 * 1024,
});
const pid = addr('token-tests');
const result = await handle(null, {
  Id: 'eval-token-tests', Target: pid, Owner: pid, From: pid,
  Tags: [{ name: 'Action', value: 'Eval' }], Data: bundle + '\nreturn runTokenTests()',
  'Block-Height': '1', Timestamp: '1700000000000', Module: 'aos', Cron: false,
}, { Process: { Id: pid, Owner: pid, Tags: [] }, Module: { Id: 'aos', Tags: [] } });
if (result.Error) throw new Error(result.Error);
const out = result.Output?.data;
const text = typeof out === 'string' ? out : out?.output ?? JSON.stringify(out);
console.log(text);
const verdict = /(\d+) passed, (\d+) failed\s*$/.exec(text);
if (!verdict || verdict[2] !== '0') process.exit(1);
