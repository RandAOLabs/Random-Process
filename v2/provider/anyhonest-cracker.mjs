// Any-Honest cracker: its own service, separate from any HyperBEAM node and
// from validators. It watches the beacon for reveals still missing after the
// reveal deadline, solves each puzzle without its secret (T squarings with
// native GMP), and posts `Crack`. A verified crack earns the beacon's crack
// bounty plus the withholder's share of that round; `claim` withdraws it.
// Anyone may run one: the beacon checks every crack, so it needs no trust.
//
//   node provider/anyhonest-cracker.mjs init  <config>   make the wallet, print its address
//   node provider/anyhonest-cracker.mjs run   <config>
//   node provider/anyhonest-cracker.mjs claim <config>   withdraw accrued rewards
//
// Config: { beacon, hbNode, dataDir, listen?, jitterMs? }. Before each crack it
// waits a random 0..jitterMs (default 60 s), so when several crackers race for
// the same puzzle the fastest machine does not win every time. RNG_CRACKER is the native GMP
// cracker (provider/cracker.c); without it the JavaScript one is ~10x slower.
//
// One crack at a time, always: a crack is minutes of one busy core, and
// running them in parallel took 13 of 16 cores of a HyperBEAM host
// (2026-11-04). Run it on its own CPU budget (e.g. `docker run --cpus=1`).
import fs from 'node:fs';
import path from 'node:path';
import http from 'node:http';
import crypto from 'node:crypto';
import { readState, jwkToAddress } from '../vendor/hbclient.mjs';
import { message } from './hb.mjs';
import * as tl from './anyhonest.mjs';

const [cmd, configPath] = process.argv.slice(2);
const cfg = JSON.parse(fs.readFileSync(configPath, 'utf8'));
const walletFile = path.join(cfg.dataDir, 'cracker-wallet.json');
const log = (...a) => console.log(new Date().toISOString(), ...a);
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

if (cmd === 'init') {
  fs.mkdirSync(cfg.dataDir, { recursive: true });
  if (!fs.existsSync(walletFile)) {
    const jwk = crypto.generateKeyPairSync('rsa', { modulusLength: 4096, publicExponent: 65537 }).privateKey.export({ format: 'jwk' });
    fs.writeFileSync(walletFile, JSON.stringify(jwk), { mode: 0o600 });
  }
  console.log(JSON.stringify({ address: jwkToAddress(JSON.parse(fs.readFileSync(walletFile, 'utf8'))) }));
  process.exit(0);
}

const jwk = JSON.parse(fs.readFileSync(walletFile, 'utf8'));
const me = jwkToAddress(jwk);
const post = (action, data) => message({ node: cfg.hbNode, jwk, process: cfg.beacon, action, data: JSON.stringify(data) });

if (cmd === 'claim') {
  console.log(JSON.stringify(await post('Claim', {})));
  process.exit(0);
}
if (cmd !== 'run') { console.error('usage: anyhonest-cracker.mjs init|run|claim <config>'); process.exit(2); }

async function info() {
  const r = await readState({ node: cfg.hbNode, process: cfg.beacon, path: 'now/beaconinfo' });
  if (r.status !== 200) throw new Error(`beaconinfo: HTTP ${r.status}`);
  return JSON.parse(r.value);
}

/** Every reveal still missing after its deadline: [{ round, target, c, T, giveUpAt }], oldest first. */
function missing(i, now) {
  const out = [];
  for (const x of i.revealing ?? []) {
    if (x.phase !== 'reveal' || !(x.revealDeadline > 0) || now < x.revealDeadline) continue;
    for (const [target, c] of Object.entries(x.committed ?? {})) {
      if ((x.revealed ?? []).includes(target)) continue;
      out.push({ round: x.round, target, c, T: x.T ?? i.params.T,
        giveUpAt: x.revealDeadline + Number(i.params.abandonAfterMs ?? 1_800_000) });
    }
  }
  return out.sort((a, b) => a.round - b.round);
}

// A crack the beacon will have abandoned before it finishes is not started.
let lastCrackMs = 5 * 60_000;
const done = new Set(); // `${round}|${target}` already posted
let status = { address: me, cracking: null, cracked: 0, failed: 0, lastCrackMs };
if (cfg.listen) {
  http.createServer((_, res) => { res.writeHead(200, { 'content-type': 'application/json' }); res.end(JSON.stringify(status)); })
    .listen(cfg.listen, '127.0.0.1');
}
log(`cracker ${me} watching ${cfg.beacon} (${process.env.RNG_CRACKER ? 'native' : 'js'})`);

for (;;) {
  try {
    const now = Date.now();
    const job = missing(await info(), now)
      .find((j) => !done.has(`${j.round}|${j.target}`) && j.giveUpAt - now > lastCrackMs * 1.5);
    if (job) {
      await sleep(Math.random() * Number(cfg.jitterMs ?? 60_000));
      if (!missing(await info(), Date.now()).some((j) => j.round === job.round && j.target === job.target)) {
        done.add(`${job.round}|${job.target}`);
        log(`already settled: ${job.target.slice(0, 8)} round ${job.round}`);
        continue;
      }
      status.cracking = `${job.round}|${job.target}`;
      log(`cracking ${job.target.slice(0, 8)} round ${job.round} (T=${job.T})`);
      const t0 = Date.now();
      const { y, proof } = process.env.RNG_CRACKER
        ? await tl.crackNative(process.env.RNG_CRACKER, job.c, job.T)
        : tl.crack(job.c, job.T);
      lastCrackMs = Date.now() - t0;
      if (!tl.verifyCrack(job.c, job.T, y, proof).valid) throw new Error('own crack does not verify');
      // Someone else may have cracked it meanwhile; a duplicate is only refused.
      const still = missing(await info(), Date.now()).some((j) => j.round === job.round && j.target === job.target);
      if (still) await post('Crack', { round: job.round, validator: job.target, y, proof });
      done.add(`${job.round}|${job.target}`);
      status = { ...status, cracking: null, cracked: status.cracked + (still ? 1 : 0), lastCrackMs };
      log(`${still ? 'cracked' : 'already settled:'} ${job.target.slice(0, 8)} round ${job.round} in ${(lastCrackMs / 1000).toFixed(1)} s`);
      continue;
    }
  } catch (e) {
    status = { ...status, cracking: null, failed: status.failed + 1 };
    log('error:', e.message);
  }
  if (done.size > 10_000) done.clear();
  await sleep(2000);
}
