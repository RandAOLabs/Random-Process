// Any-Honest validator: commits c = g^alpha with a fresh secret
// when a round opens, reveals alpha once the beacon shows the round revealing,
// cracks reveals that are still missing after the deadline. No shared secret
// with anyone.
//
//   node provider/anyhonest-validator.mjs init <config>
//   node provider/anyhonest-validator.mjs run <config>
//   node provider/anyhonest-validator.mjs exit <config>
//   node provider/anyhonest-validator.mjs finalize-exit <config>
//
// Config: { beacon, hbNode, dataDir, listen? }. Uses RNG_CRACKER (native GMP)
// for cracks when set, else JavaScript.
import fs from 'node:fs';
import path from 'node:path';
import http from 'node:http';
import crypto from 'node:crypto';
import { readState, jwkToAddress } from '../vendor/hbclient.mjs';
import { message } from './hb.mjs';
import * as tl from './anyhonest.mjs';

const [cmd, configPath] = process.argv.slice(2);
const cfg = JSON.parse(fs.readFileSync(configPath, 'utf8'));
const file = (...p) => path.join(cfg.dataDir, ...p);
const log = (...a) => console.log(new Date().toISOString(), ...a);
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

if (cmd === 'init') {
  fs.mkdirSync(cfg.dataDir, { recursive: true });
  if (!fs.existsSync(file('validator-wallet.json'))) {
    const jwk = crypto.generateKeyPairSync('rsa', { modulusLength: 4096, publicExponent: 65537 }).privateKey.export({ format: 'jwk' });
    fs.writeFileSync(file('validator-wallet.json'), JSON.stringify(jwk), { mode: 0o600 });
  }
  console.log(JSON.stringify({ address: jwkToAddress(JSON.parse(fs.readFileSync(file('validator-wallet.json'), 'utf8'))) }));
  process.exit(0);
}

const jwk = JSON.parse(fs.readFileSync(file('validator-wallet.json'), 'utf8'));
const me = jwkToAddress(jwk);
fs.mkdirSync(file('secrets'), { recursive: true });

async function info() {
  const r = await readState({ node: cfg.hbNode, process: cfg.beacon, path: 'now/beaconinfo' });
  if (r.status !== 200) throw new Error(`beaconinfo: HTTP ${r.status}`);
  return JSON.parse(r.value);
}
const post = (action, data) => message({ node: cfg.hbNode, jwk, process: cfg.beacon, action, data: JSON.stringify(data) });

if (cmd === 'exit' || cmd === 'finalize-exit') {
  const action = cmd === 'exit' ? 'Exit' : 'Finalize-Exit';
  console.log(JSON.stringify(await post(action, {}), null, 2));
  process.exit(0);
}

/** Every secret sent for a round, { c: alpha }, is on disk before its commit
 *  is sent, so a restart can still reveal. Each send uses a fresh one. */
const secretFile = (round) => file('secrets', `${round}.json`);
const secrets = (round) => (fs.existsSync(secretFile(round)) ? JSON.parse(fs.readFileSync(secretFile(round), 'utf8')) : {});

const cracking = new Set();
async function crack(info, o, target) {
  const key = `${o.round}|${target}`;
  if (cracking.has(key)) return;
  cracking.add(key);
  const c = o.committed[target];
  const T = o.T ?? info.params.T;
  log(`cracking ${target.slice(0, 8)} for round ${o.round} (T=${T}, ${process.env.RNG_CRACKER ? 'native' : 'js'})`);
  const t0 = Date.now();
  try {
    const { y, proof } = process.env.RNG_CRACKER
      ? await tl.crackNative(process.env.RNG_CRACKER, c, T)
      : tl.crack(c, T);
    if (!tl.verifyCrack(c, T, y, proof).valid) throw new Error('own crack does not verify');
    await post('Crack', { round: o.round, validator: target, y, proof });
    log(`cracked ${target.slice(0, 8)} round ${o.round} in ${((Date.now() - t0) / 1000).toFixed(1)} s`);
  } catch (e) {
    log('crack failed:', e.message);
  } finally {
    cracking.delete(key);
  }
}

let status = { address: me };
if (cfg.listen) {
  http.createServer((_, res) => { res.writeHead(200, { 'content-type': 'application/json' }); res.end(JSON.stringify(status)); })
    .listen(cfg.listen, '127.0.0.1');
}
log(`validator ${me} watching ${cfg.beacon}`);

// What we last sent per round. The beacon's published state is the truth;
// this only stops resending more often than every 1-3 s while it catches up.
const sent = { commit: { round: 0, at: 0 }, close: { round: 0, at: 0 }, rejoin: { round: 0, at: 0 } };
const due = (kind, round, now, ms = 3000) => sent[kind].round !== round || now - sent[kind].at > ms;
const mark = (kind, round, now) => { sent[kind] = { round, at: now }; };
// Several rounds can be revealing at once, so reveals are tracked per round.
const revealed = new Map();
const dueReveal = (round, now) => !revealed.has(round) || now - revealed.get(round) > 3000;
for (;;) {
  try {
    const i = await info();
    const o = i.open ?? {};
    const mine = i.validators.find((v) => v.address === me);
    status = { address: me, round: i.round, open: o.round, phase: o.phase,
      suspended: mine?.suspended ?? null, exiting: mine?.exiting ?? null };
    const committed = o.committed ?? {};
    const now = Date.now();

    // Suspended: rejoin on our own (idle at once, slashed after the cooldown)
    // while the bond still covers the next slash (SPEC.md §2.2).
    if (mine?.suspended && !mine.exiting && mine.bond >= i.params.slash && (mine.idle || i.round >= mine.suspendedAt + i.params.rejoinAfter) && due('rejoin', i.round, now)) {
      log(`${mine.idle ? 'idle' : 'suspended'} since round ${mine.suspendedAt}; rejoining with bond ${mine.bond}`);
      await post('Rejoin', {});
      mark('rejoin', i.round, now);
    }

    // Commit as soon as the cadence allows: every round with the heartbeat
    // on, else only rounds with requests waiting.
    if (mine && !mine.suspended && !mine.exiting && (o.phase === 'collecting' || o.phase === 'commit') && (o.pending > 0 || i.params.heartbeat)
        && now >= i.nextRoundAt && !committed[me] && due('commit', o.round, now, 1000)) {
      // A fresh secret on every send, also a resend after a void: never reuse one.
      const alpha = tl.newAlpha(), c = tl.commit(alpha);
      fs.writeFileSync(secretFile(o.round), JSON.stringify({ ...secrets(o.round), [c]: alpha }), { mode: 0o600 });
      await post('Commit', { round: o.round, c });
      mark('commit', o.round, now);
    }

    // Rounds overlap: the open round takes commits while older ones reveal.
    const rounds = [...(i.revealing ?? []), o];
    for (const x of rounds) {
      const committedX = x.committed ?? {};
      // Reveal only once the beacon shows the round revealing. If the window
      // has passed by our clock but it still shows commits, ask it to close.
      if (x.phase === 'commit' && x.commitDeadline > 0 && now >= x.commitDeadline && due('close', x.round, now, 2000)) {
        await post('Close', { round: x.round });
        mark('close', x.round, now);
      }
      if (committedX[me] && !(x.revealed ?? []).includes(me) && x.phase === 'reveal' && dueReveal(x.round, now)) {
        const alpha = secrets(x.round)[committedX[me]];
        if (alpha) await post('Reveal', { round: x.round, alpha });
        else log(`round ${x.round}: no secret on disk for our commit; cannot reveal`);
        revealed.set(x.round, now);
      }

      // Crack reveals still missing after the deadline. Validators take turns
      // by address order, one reveal window apart, so one cracks and the rest wait.
      if (x.phase === 'reveal' && x.revealDeadline > 0) {
        const order = (x.active ?? []).filter((a) => committedX[a]).sort();
        for (const target of Object.keys(committedX)) {
          if ((x.revealed ?? []).includes(target) || target === me) continue;
          const turns = order.filter((a) => a !== target);
          const myTurn = turns.indexOf(me);
          if (myTurn >= 0 && now >= x.revealDeadline + myTurn * i.params.revealWindowMs) crack(i, x, target);
        }
      }
    }

    // A secret is only needed until its round is done.
    const oldest = Math.min(...rounds.map((x) => x.round));
    for (const f of fs.readdirSync(file('secrets'))) {
      if (Number(f.replace('.json', '')) < oldest) fs.rmSync(file('secrets', f));
    }
    for (const r of revealed.keys()) if (r < oldest) revealed.delete(r);
  } catch (e) {
    log('loop error:', e.message);
  }
  // All validators can reach a node through one reverse-proxy peer. Fast
  // polling reacts promptly enough for a one-second cadence while the
  // dedicated node's configured service allowance keeps aggregate traffic
  // bounded.
  await sleep(50);
}
