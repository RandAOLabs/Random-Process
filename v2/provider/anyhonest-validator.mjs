// Any-Honest validator: commits c = g^alpha with a fresh secret
// when a round opens, reveals alpha once the beacon shows the round revealing.
// No shared secret with anyone. Superseded by the `rng-validator@1.0` device;
// cracking is its own service (anyhonest-cracker.mjs), never run here.
//
//   node provider/anyhonest-validator.mjs init <config>
//   node provider/anyhonest-validator.mjs run <config>
//   node provider/anyhonest-validator.mjs exit <config>
//   node provider/anyhonest-validator.mjs finalize-exit <config>
//
// Config: { beacon, hbNode, dataDir, listen? }.
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
// Round trips of recent reads and sends (ms), for the rejoin health probe.
const probe = { reads: [], posts: [], seen: new Set() };
const sample = (list, ms) => { list.push(ms); if (list.length > 20) list.shift(); };
const post = async (action, data) => {
  const t0 = Date.now();
  try { return await message({ node: cfg.hbNode, jwk, process: cfg.beacon, action, data: JSON.stringify(data) }); }
  finally { sample(probe.posts, Date.now() - t0); }
};

if (cmd === 'exit' || cmd === 'finalize-exit') {
  const action = cmd === 'exit' ? 'Exit' : 'Finalize-Exit';
  console.log(JSON.stringify(await post(action, {}), null, 2));
  process.exit(0);
}

/** Every secret sent for a round, { c: alpha }, is on disk before its commit
 *  is sent, so a restart can still reveal. Each send uses a fresh one. */
const secretFile = (round) => file('secrets', `${round}.json`);
const secrets = (round) => (fs.existsSync(secretFile(round)) ? JSON.parse(fs.readFileSync(secretFile(round), 'utf8')) : {});

let status = { address: me };
if (cfg.listen) {
  http.createServer((_, res) => { res.writeHead(200, { 'content-type': 'application/json' }); res.end(JSON.stringify(status)); })
    .listen(cfg.listen, '127.0.0.1');
}
log(`validator ${me} watching ${cfg.beacon}`);

// What we last sent per round, and the slot the node gave it. A scheduled
// message WILL be computed, so it is never resent while the beacon has not yet
// reached its slot: resending into a lagging beacon only lengthens its queue
// (2026-11-04: 14,000 slots behind, growing ~75 a minute). Once the beacon has
// computed past it and still shows nothing (a void, a refusal), resend.
let atSlot = 0;
const fresh = { round: 0, at: 0, slot: -1 };
const sent = { commit: { ...fresh }, close: { ...fresh }, rejoin: { ...fresh } };
const settled = (x, now, ms) => x.slot <= atSlot && now - x.at > ms;
const due = (kind, round, now, ms = 3000) => sent[kind].round !== round || settled(sent[kind], now, ms);
const mark = (kind, round, now, slot) => { sent[kind] = { round, at: now, slot: Number.isFinite(slot) ? slot : -1 }; };
// Several rounds can be revealing at once, so reveals are tracked per round.
const revealed = new Map();
const dueReveal = (round, now) => !revealed.has(round) || settled(revealed.get(round), now, 3000);
// Our own backoff after a fault, on top of the beacon's cooldown (rejoinAt):
// rejoinBaseMs doubling per incident, up to rejoinCapMs.
const backoff = { faults: null, n: 0, until: 0, readySince: 0 };
for (;;) {
  try {
    // Before the state read, so the state is at least this far along.
    const t0 = Date.now();
    atSlot = Number((await readState({ node: cfg.hbNode, process: cfg.beacon, path: 'now/at-slot' })).value) || 0;
    const i = await info();
    sample(probe.reads, Date.now() - t0);
    const o = i.open ?? {};
    const mine = i.validators.find((v) => v.address === me);
    status = { address: me, round: i.round, open: o.round, phase: o.phase,
      suspended: mine?.suspended ?? null, exiting: mine?.exiting ?? null,
      rejoinAt: Math.max(Number(mine?.rejoinAt ?? 0), backoff.until), reads: probe.reads.slice(-3), posts: probe.posts.slice(-3) };
    const committed = o.committed ?? {};
    const now = Date.now();

    // How late our commit would land: how long after a round's first commit
    // we first see it, plus a send. Sampled while others run rounds.
    if (o.phase === 'commit' && o.firstCommitAt > 0 && !probe.seen.has(o.round)) {
      probe.seen.add(o.round);
      if (probe.seen.size > 50) probe.seen.delete(probe.seen.values().next().value);
      sample(probe.reads, Math.max(0, now - o.firstCommitAt));
    }

    // Suspended: rejoin on our own while the bond still covers the next slash,
    // but never straight back into the rounds we just failed. After a fault
    // the beacon refuses Ready until `rejoinAt`, we back off on our own too,
    // and we rejoin only once our round trip is well inside the commit window.
    // No waiver when quorum is lost: rejoining at once on quorum loss turned
    // slow commits into 108 slashes per validator (2026-11-06).
    const p = i.params;
    const base = Number(p.rejoinBaseMs ?? 60000), cap = Number(p.rejoinCapMs ?? 3600000);
    // A fault while we were ready starts an incident; later faults of the same
    // incident (rounds we already held) do not escalate it.
    if (mine && backoff.faults !== null && mine.faults > backoff.faults && backoff.readySince) {
      backoff.n = now - backoff.readySince < cap ? backoff.n + 1 : 1;
      backoff.until = now + Math.min(cap, base * 2 ** (backoff.n - 1));
      log(`fault ${mine.faults} (${mine.lastFault?.kind} round ${mine.lastFault?.round}); backing off ${backoff.until - now} ms`);
    }
    if (mine) backoff.faults = mine.faults;
    if (mine?.ready && !backoff.readySince) backoff.readySince = now;
    if (!mine?.ready) backoff.readySince = 0;
    const max = (l) => (l.length ? Math.max(...l) : Infinity);
    const roundTrip = max(probe.reads) + (probe.posts.length ? max(probe.posts) : max(probe.reads));
    const healthy = probe.reads.length >= 20 && roundTrip < Number(p.commitWindowMs ?? 2000) / 2;
    if (mine?.suspended && !mine.exiting && !mine.overdue && mine.bond >= p.slash
      && now >= Number(mine.rejoinAt ?? 0) && now >= backoff.until && healthy && due('rejoin', i.round, now, 30000)) {
      log(`suspended since round ${mine.suspendedAt ?? '?'}; round trip ${roundTrip} ms; rejoining with bond ${mine.bond}`);
      mark('rejoin', i.round, now, await post('Ready', {}));
    }

    // Commit as soon as the cadence allows: every round with the heartbeat
    // on, else only rounds with requests waiting.
    // A round with fewer active validators than minCommits can only void, and
    // the beacon refuses to open one (Too-Few-Validators): wait instead.
    const activeCount = i.validators.filter((v) => !v.suspended && !v.exiting && !v.overdue).length;
    if (mine && !mine.suspended && !mine.exiting && activeCount >= Number(i.params.minCommits ?? 2)
        && (o.phase === 'collecting' || o.phase === 'commit') && (o.pending > 0 || i.params.heartbeat)
        && now >= i.nextRoundAt && !committed[me] && due('commit', o.round, now, 1000)) {
      // A fresh secret on every send, also a resend after a void: never reuse one.
      const alpha = tl.newAlpha(), c = tl.commit(alpha);
      fs.writeFileSync(secretFile(o.round), JSON.stringify({ ...secrets(o.round), [c]: alpha }), { mode: 0o600 });
      mark('commit', o.round, now, await post('Commit', { round: o.round, c }));
    }

    // Rounds overlap: the open round takes commits while older ones reveal.
    const rounds = [...(i.revealing ?? []), o];
    for (const x of rounds) {
      const committedX = x.committed ?? {};
      // Reveal only once the beacon shows the round revealing. If the window
      // has passed by our clock but it still shows commits, ask it to close.
      if (x.phase === 'commit' && x.commitDeadline > 0 && now >= x.commitDeadline && due('close', x.round, now, 2000)) {
        mark('close', x.round, now, await post('Close', { round: x.round }));
      }
      if (committedX[me] && !(x.revealed ?? []).includes(me) && x.phase === 'reveal' && dueReveal(x.round, now)) {
        const alpha = secrets(x.round)[committedX[me]];
        let slot;
        if (alpha) slot = await post('Reveal', { round: x.round, alpha });
        else log(`round ${x.round}: no secret on disk for our commit; cannot reveal`);
        revealed.set(x.round, { at: now, slot: Number.isFinite(slot) ? slot : -1 });
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
  // polling reacts promptly enough for a five-second cadence while the
  // dedicated node's configured service allowance keeps aggregate traffic
  // bounded.
  await sleep(50);
}
