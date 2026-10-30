// Runs v2 Lua tests.
//   node test/run-tests.mjs            local, AOS wasm via @permaweb/ao-loader
//   node test/run-tests.mjs --live URL  a HyperBEAM node's ~lua@5.3a (Luerl, the RC7 runtime)
// AO_LOADER / AOS_WASM override where the loader and module come from; they
// default to the copies in paralith-mono.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const V2 = path.resolve(HERE, '..');
const PARALITH = process.env.PARALITH_ROOT || 'C:/REPO/paralith-mono';
const AO_LOADER = process.env.AO_LOADER || path.join(PARALITH, 'node_modules/@permaweb/ao-loader/dist/index.cjs');
const AOS_WASM = process.env.AOS_WASM || path.join(PARALITH, 'backend/native/module/AOS.wasm');

const read = (p) => fs.readFileSync(path.join(V2, p), 'utf8');
const bundle = [
  'rng = (function()', read('lib/rng.lua'), 'end)()',
  read('test/rng_test.lua'),
].join('\n');

function verdict(text) {
  console.log(text);
  const m = /(\d+) passed, (\d+) failed\s*$/.exec(text);
  if (!m) { console.error('no verdict in output'); process.exit(1); }
  process.exit(m[2] === '0' ? 0 : 1);
}

const live = process.argv.indexOf('--live');
if (live !== -1) {
  const node = process.argv[live + 1] || 'https://hyperbeam.tylerw.ai';
  const res = await fetch(`${node}/~lua@5.3a/rngtest`, {
    method: 'POST', headers: { 'content-type': 'application/lua' }, body: bundle,
  });
  const body = await res.text();
  if (res.status !== 200) { console.error(`${node}: HTTP ${res.status}\n${body.slice(0, 2000)}`); process.exit(1); }
  verdict(body);
} else {
  const { default: AoLoader } = await import(pathToFileURL(AO_LOADER).href);
  const handle = await AoLoader(fs.readFileSync(AOS_WASM), {
    format: 'wasm32-unknown-emscripten', computeLimit: 9e12, memoryLimit: 512 * 1024 * 1024,
  });
  const pid = 'rng-tests'.padEnd(43, '_');
  const result = await handle(null, {
    Id: 'eval-rng-tests', Target: pid, Owner: pid, From: pid,
    Tags: [{ name: 'Action', value: 'Eval' }], Data: bundle + '\nreturn runRngTests()',
    'Block-Height': '1', Timestamp: '1700000000000', Module: 'aos', Cron: false,
  }, { Process: { Id: pid, Owner: pid, Tags: [] }, Module: { Id: 'aos', Tags: [] } });
  if (result.Error) { console.error(result.Error); process.exit(1); }
  const out = result.Output?.data;
  verdict(typeof out === 'string' ? out : out?.output ?? JSON.stringify(out));
}
