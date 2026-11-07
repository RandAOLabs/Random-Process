// Any-Honest validator in plain Node: everything the `rng-validator@1.0`
// device does, so a third party needs no custom HyperBEAM build. It commits
// c = g^alpha with a fresh secret when a round can take it, reveals alpha once
// the beacon shows the round revealing, says Ready / Pause, follows a
// successor beacon, and leaves with Exit / Finalize-Exit. Cracking is its own
// service (anyhonest-cracker.mjs), never run here.
//
//   node v2/provider/anyhonest-validator.mjs init --beacon <pid> --node <url> [--dir <dir>]
//   node v2/provider/anyhonest-validator.mjs bond [RNG]   [--dir <dir>]
//   node v2/provider/anyhonest-validator.mjs run          [--dir <dir>]
//   node v2/provider/anyhonest-validator.mjs status       [--dir <dir>]
//   node v2/provider/anyhonest-validator.mjs pause | resume | exit | claim [--dir <dir>]
//
// <dir> defaults to ./rng-validator and holds config.json, the wallet and the
// secrets. A config file path may be given instead of --dir (older deploys):
// { beacon, hbNode, dataDir, listen?, topUp?, interval? }.
//
// Clocks: the validator never compares its own clock with the beacon's
// timestamps directly. Beacon times (nextRoundAt, rejoinAt) are compared with
// localNow - offset, where offset = min over recent reads of
// (localReadAt - beaconinfo.at). Health is only measured from local round
// trips: a send, then the first read that shows the beacon computed it.
import fs from 'node:fs';
import path from 'node:path';
import http from 'node:http';
import crypto from 'node:crypto';
import { pathToFileURL } from 'node:url';
import * as tl from './anyhonest.mjs';

const isPid = (s) => typeof s === 'string' && /^[A-Za-z0-9_-]{43}$/.test(s);
const num = (v, d = 0) => (Number.isFinite(Number(v)) && v !== null && v !== '' ? Number(v) : d);
const truthy = (v) => !(v === undefined || v === null || v === false || v === 0 || v === '0' || v === '');
const list = (v) => (Array.isArray(v) ? v : []);
const obj = (v) => (v && typeof v === 'object' && !Array.isArray(v) ? v : {});

// --- Clock offset ------------------------------------------------------------

/** offset = min over the last five minutes of (localReadAt - info.at). The
 *  minimum is the read that was freshest, so beaconNow = localNow - offset is
 *  never ahead of the beacon by more than the clocks drift in five minutes. */
export class Clock {
  constructor({ bucketMs = 10_000, buckets = 30 } = {}) { this.bucketMs = bucketMs; this.keep = buckets; this.mins = new Map(); }
  observe(localReadAt, at) {
    if (!(num(at) > 0)) return;
    const b = Math.floor(localReadAt / this.bucketMs), d = localReadAt - num(at);
    this.mins.set(b, Math.min(this.mins.get(b) ?? Infinity, d));
    for (const k of this.mins.keys()) if (k <= b - this.keep) this.mins.delete(k);
  }
  /** null until the beacon has published `at` (older beacons: offset 0). */
  get offset() { return this.mins.size ? Math.min(...this.mins.values()) : null; }
  beaconNow(localNow) { return localNow - (this.offset ?? 0); }
}

// --- Health: local round trips only -----------------------------------------

/** Each send is timed from just before it to the first read that shows the
 *  beacon computed its slot (`at-slot` >= slot): both ends on the local clock.
 *  A send that fails, or never shows up, counts as an infinite round trip. */
export class Health {
  constructor({ need = 5, keep = 20, windowMs = 600_000, timeoutMs = 30_000 } = {}) {
    Object.assign(this, { need, keep, windowMs, timeoutMs });
    this.samples = []; this.pending = [];
  }
  sent(t0, slot) {
    if (Number.isFinite(slot) && slot >= 0) this.pending.push({ t0, slot });
    else this.add(t0, Infinity);
  }
  add(at, ms) { this.samples.push({ at, ms }); if (this.samples.length > this.keep) this.samples.shift(); }
  observe(atSlot, localNow) {
    this.pending = this.pending.filter((p) => {
      if (p.slot <= atSlot) { this.add(localNow, localNow - p.t0); return false; }
      if (localNow - p.t0 > this.timeoutMs) { this.add(localNow, Infinity); return false; }
      return true;
    });
  }
  recent(localNow) { return this.samples.filter((s) => localNow - s.at < this.windowMs); }
  roundTrip(localNow) {
    const r = this.recent(localNow);
    return r.length >= this.need ? Math.max(...r.map((s) => s.ms)) : Infinity;
  }
  healthy(localNow, commitWindowMs) { return this.roundTrip(localNow) < commitWindowMs / 2; }
  get probing() { return this.pending.length > 0; }
}

// --- Backoff after a fault (as the device) ----------------------------------

/** rejoinBaseMs doubled per incident, up to rejoinCapMs, on the local clock.
 *  A fault while ready starts an incident; ready for a cap or longer resets. */
export function backoff(mine, params, now, b) {
  if (!mine) return b;
  const faults = num(mine.faults);
  const base = num(params.rejoinBaseMs, 60_000), cap = num(params.rejoinCapMs, 3_600_000);
  let { n, until } = b;
  if (b.faults !== null && faults > b.faults && b.readySince > 0) {
    n = now - b.readySince < cap ? n + 1 : 1;
    until = now + Math.min(cap, base * 2 ** Math.min(n - 1, 32));
  }
  const readySince = !truthy(mine.ready) ? 0 : b.readySince || now;
  return { faults, n, until, readySince };
}

// --- Secrets -----------------------------------------------------------------

/** Every secret sent for a round, { c: alpha }, owner-only, on disk BEFORE its
 *  commit is sent, so a restart can still reveal. */
export function secretStore(dir) {
  fs.mkdirSync(dir, { recursive: true, mode: 0o700 });
  const file = (r) => path.join(dir, `${r}.json`);
  const read = (r) => { try { return JSON.parse(fs.readFileSync(file(r), 'utf8')); } catch { return {}; } };
  return {
    read,
    save(r, c, alpha) {
      const tmp = `${file(r)}.tmp`;
      fs.writeFileSync(tmp, JSON.stringify({ ...read(r), [c]: alpha }), { mode: 0o600 });
      fs.renameSync(tmp, file(r));
    },
    /** A commitment shown whole, or as the 16-hex prefix the beacon shows until a round is late. */
    secretFor(r, shown) {
      const s = read(r);
      if (s[shown]) return s[shown];
      const hit = Object.keys(s).find((c) => c.length > shown.length && c.startsWith(shown));
      return hit ? s[hit] : null;
    },
    prune(oldest) {
      for (const f of fs.readdirSync(dir)) {
        const m = /^(\d+)\.json$/.exec(f);
        if (m && Number(m[1]) < oldest) fs.rmSync(path.join(dir, f), { force: true });
      }
    },
  };
}

// --- Plan: what to send now --------------------------------------------------

export const findMine = (validators, me) => list(validators).find((v) => v?.address === me) ?? null;
const isActive = (v) => truthy(v.ready) && !truthy(v.exiting) && !truthy(v.overdue);

/** Rounds still owed: a reveal for a round committed to, or a commit to the
 *  open round whose set we are in. */
export function obligations(info, me) {
  const open = obj(info.open);
  const owed = [...list(info.revealing), open]
    .filter((x) => obj(x.committed)[me] && !list(x.revealed).includes(me)).map((x) => num(x.round));
  if (open.phase === 'commit' && list(open.active).includes(me) && !obj(open.committed)[me]) owed.push(num(open.round));
  return owed;
}

/** Not sent yet, or the beacon computed past its slot and `ms` passed with no
 *  effect. A scheduled message WILL be computed, so nothing is resent into a
 *  beacon that has not reached it yet (2026-11-04: resends flooded a beacon
 *  14,000 slots behind). */
export const due = (sent, key, atSlot, now, ms) => {
  const s = sent.get(key);
  return !s || (s.slot <= atSlot && now - s.at > ms);
};

/**
 * The actions for one pass, as [{ kind, round, data }], and the oldest round
 * still shown. ctx: { me, sent, atSlot, now (local), beaconNow, healthy,
 * backoffUntil, exit, pause, moving, mine, secrets, newAlpha?, commit? }.
 * Ready is said only by a member in good standing with a full stake (bond plus
 * the earnings the beacon refills it from), not before the beacon's cooldown,
 * nor our own backoff, nor while the local round trip is over half the commit
 * window. No waiver on quorum loss (2026-11-06: 108 slashes per validator).
 */
export function plan(info, ctx) {
  const { me, sent, atSlot, now, beaconNow, secrets } = ctx;
  if (!list(info.features).includes('ready')) throw new Error('beacon lacks the `ready` feature; this validator needs a v2+ beacon');
  const p = obj(info.params), open = obj(info.open);
  const mine = ctx.mine ?? findMine(info.validators, me);
  const member = !!mine;
  const D = (kind, round, ms) => due(sent, `${kind}:${round}`, atSlot, now, ms);
  const stopping = !!(ctx.exit || ctx.moving || ctx.pause);
  const exiting = member && truthy(mine.exiting), ready = member && truthy(mine.ready);
  const stake = num(p.stake, 25_000), unit = num(info.unit, 1_000_000) || 1;
  const earned = mine && mine.earnedAtoms !== undefined ? Math.floor(num(mine.earnedAtoms) / unit) : null;
  const bond = member ? num(mine.bond ?? mine.stake) : 0;
  // With earnings unpublished the beacon decides; with them published we do.
  const fullStake = earned === null || bond + earned >= stake;
  const actions = [];
  if (member && !ready && !exiting && !stopping && !truthy(mine.overdue)
      && beaconNow >= num(mine.rejoinAt) && now >= num(ctx.backoffUntil)
      && ctx.healthy && fullStake && D('Ready', 0, 30_000)) {
    actions.push({ kind: 'Ready', round: 0, data: {} });
  }
  if (member && ready && !exiting && stopping && !ctx.exit && D('Pause', 0, 3000)) actions.push({ kind: 'Pause', round: 0, data: {} });
  if (member && ctx.exit) {
    if (!exiting) { if (D('Exit', 0, 3000)) actions.push({ kind: 'Exit', round: 0, data: {} }); }
    else if (obligations(info, me).length === 0 && D('Finalize-Exit', 0, 30_000)) actions.push({ kind: 'Finalize-Exit', round: 0, data: {} });
  }
  // A round taking its first commit is opened only by an available validator
  // that is not stopping; a round already open is owed by its whole set.
  const active = list(info.validators).filter(isActive).length;
  const openRound = num(open.round);
  const wantsRound = num(open.pending) > 0 || (truthy(p.heartbeat) && info.mode !== 'request-driven');
  const mayCommit = open.phase === 'collecting'
    ? member && isActive(mine) && !stopping && active >= num(p.minCommits, 2) && wantsRound && beaconNow >= num(info.nextRoundAt)
    : open.phase === 'commit' && list(open.active).includes(me);
  if (mayCommit && !obj(open.committed)[me] && D('Commit', openRound, 1000)) {
    // A fresh secret on every send, a resend after a void included.
    const alpha = (ctx.newAlpha ?? tl.newAlpha)(), c = (ctx.commit ?? tl.commit)(alpha);
    secrets.save(openRound, c, alpha);
    actions.push({ kind: 'Commit', round: openRound, data: { round: openRound, c } });
  }
  // Rounds overlap: the open round takes commits while older ones reveal.
  const rounds = [...list(info.revealing), open];
  for (const x of rounds) {
    const shown = obj(x.committed)[me], r = num(x.round);
    if (x.phase !== 'reveal' || typeof shown !== 'string' || list(x.revealed).includes(me) || !D('Reveal', r, 3000)) continue;
    const alpha = secrets.secretFor(r, shown);
    if (alpha) actions.push({ kind: 'Reveal', round: r, data: { round: r, alpha } });
    else ctx.log?.(`round ${r}: no secret on disk for our commit; cannot reveal`);
  }
  return { actions, oldest: Math.min(...rounds.map((x) => num(x.round))) };
}

/** On a beacon with `act`, the commit and every reveal go as one Act message
 *  (at most 16 parts), halving what a round costs the beacon. */
export function batch(actions, info) {
  const one = (a) => ({ action: a.kind, keys: [`${a.kind}:${a.round}`], data: a.data });
  if (!list(info.features).includes('act')) return actions.map(one);
  const steps = actions.filter((a) => a.kind === 'Commit' || a.kind === 'Reveal').slice(0, 16);
  const rest = actions.filter((a) => !steps.includes(a));
  const out = rest.map(one);
  if (steps.length === 1) out.push(one(steps[0]));
  if (steps.length > 1) {
    const commit = steps.find((a) => a.kind === 'Commit');
    out.push({ action: 'Act', keys: steps.map((a) => `${a.kind}:${a.round}`),
      data: { ...(commit ? { commit: commit.data } : {}), reveals: steps.filter((a) => a.kind === 'Reveal').map((a) => a.data) } });
  }
  return out;
}

// --- Successor ----------------------------------------------------------------

/** Move only to a successor this beacon names, that names this beacon back as
 *  its predecessor, and (once the beacon publishes it) has acknowledged. */
export async function checkSuccessor(info, beacon, readInfo) {
  const next = info.successor;
  if (!isPid(next) || next === beacon) return null;
  if ('successorAck' in info && info.successorAck !== true) return null;
  try { return (await readInfo(next)).predecessor === beacon ? next : null; } catch { return null; }
}

/** The registry, in whichever shape `beaconvalidators` holds it. */
export function registryEntry(raw, me) {
  if (!raw) return null;
  const v = typeof raw === 'string' ? JSON.parse(raw) : raw;
  if (Array.isArray(v)) return findMine(v, me);
  if (Array.isArray(v.validators)) return findMine(v.validators, me);
  return v[me] ? { address: me, ...v[me] } : null;
}

// --- The validator loop --------------------------------------------------------

/**
 * io: { readInfo(pid), readAtSlot(pid), readKey(pid, key) -> string|null,
 *       post(pid, action, data) -> slot, transfer(token, tags) -> slot, now() }.
 * cfg: { beacon, dataDir, topUp? }.
 */
export function createValidator({ cfg, me, io, log = () => {} }) {
  const dir = cfg.dataDir;
  const secrets = secretStore(path.join(dir, 'secrets'));
  const followFile = path.join(dir, 'beacon.json');
  const flag = (f) => fs.existsSync(path.join(dir, f));
  let beacon = cfg.beacon;
  try {
    const f = JSON.parse(fs.readFileSync(followFile, 'utf8'));
    if (f.configured === cfg.beacon && isPid(f.beacon)) beacon = f.beacon;
  } catch { /* none yet */ }
  const st = {
    me, sent: new Map(), clock: new Clock(), health: new Health(),
    backoff: { faults: null, n: 0, until: 0, readySince: 0 },
    registry: { at: -Infinity, entry: null }, successor: { at: -Infinity, id: null },
    lastProbe: -Infinity, lastTopUp: -Infinity, wasExiting: false, done: false, status: { address: me },
    get beacon() { return beacon; },
  };

  async function send(action, data, keys, now) {
    const t0 = io.now();
    let slot = -1;
    try { slot = await io.post(beacon, action, data); } catch (e) { log(`${action}: ${e.message}`); }
    st.health.sent(t0, slot);
    for (const k of keys) st.sent.set(k, { at: now, slot: Number.isFinite(slot) ? slot : -1 });
    return slot;
  }

  async function pass() {
    // at-slot first, so the state read is at least that far along.
    const atSlot = num(await io.readAtSlot(beacon));
    const info = await io.readInfo(beacon);
    const now = io.now();
    st.clock.observe(now, info.at);
    st.health.observe(atSlot, now);
    const beaconNow = st.clock.beaconNow(now);
    const p = obj(info.params);
    const commitWindowMs = num(p.commitWindowMs, 5000);
    st.health.timeoutMs = Math.max(30_000, 4 * commitWindowMs);

    // beaconinfo lists at most 128 validators; the full registry has its own key.
    let mine = findMine(info.validators, me);
    if (!mine && now - st.registry.at > 30_000) {
      st.registry = { at: now, entry: registryEntry(await io.readKey(beacon, 'now/beaconvalidators').catch(() => null), me) };
    }
    if (!mine) mine = st.registry.entry;

    st.backoff = backoff(mine, p, now, st.backoff);
    if (now - st.successor.at > 10_000) st.successor = { at: now, id: await checkSuccessor(info, beacon, io.readInfo) };
    const exit = flag('exit'), pause = flag('pause'), moving = !!st.successor.id;
    const healthy = st.health.healthy(now, commitWindowMs);
    const ctx = { me, sent: st.sent, atSlot, now, beaconNow, healthy, backoffUntil: st.backoff.until,
      exit, pause, moving, mine, secrets, log };
    const { actions, oldest } = plan(info, ctx);
    for (const m of batch(actions, info)) {
      if (m.action !== 'Act' && m.action !== 'Commit' && m.action !== 'Reveal') log(`${m.action} -> ${beacon}`);
      await send(m.action, m.data, m.keys, now);
    }

    // Before Ready a validator sends nothing, so it probes: a no-op Get-Info
    // every 2 s, only once Ready is otherwise close to allowed.
    const stake = num(p.stake, 25_000), unit = num(info.unit, 1_000_000) || 1;
    const bond = mine ? num(mine.bond ?? mine.stake) : 0;
    const earned = mine?.earnedAtoms !== undefined ? Math.floor(num(mine?.earnedAtoms) / unit) : 0;
    const shortfall = mine ? Math.max(0, stake - bond - earned) : stake;
    const waiting = mine && !truthy(mine.ready) && !truthy(mine.exiting) && !exit && !pause && !moving && !truthy(mine.overdue);
    if (waiting && !healthy && !st.health.probing && now - st.lastProbe > 2000
        && beaconNow >= num(mine.rejoinAt) - 30_000 && now >= st.backoff.until - 30_000) {
      st.lastProbe = now;
      await send('Get-Info', {}, [], now);
    }
    // Ready needs the full stake back after every fault. Top up from the
    // validator wallet only when configured to; otherwise say what to run.
    if (waiting && shortfall > 0) {
      // Unpublished earnings: Ready may still be refilled by the beacon, so no top-up.
      if (cfg.topUp && mine.earnedAtoms !== undefined && isPid(info.token) && now - st.lastTopUp > 60_000) {
        st.lastTopUp = now;
        log(`topping up bond by ${shortfall} RNG`);
        try { await io.transfer(info.token, bondTags(beacon, shortfall, unit)); } catch (e) { log(`top-up: ${e.message}`); }
      } else if (!cfg.topUp && now - st.lastTopUp > 60_000) {
        st.lastTopUp = now;
        log(`bond ${bond} + earnings ${earned} < stake ${stake}: run \`bond ${shortfall}\` to rejoin`);
      }
    }

    secrets.prune(oldest);
    for (const [k, v] of st.sent) if (now - v.at > 600_000) st.sent.delete(k);

    // Follow the successor once nothing is owed here.
    if (moving && obligations(info, me).length === 0) {
      const next = st.successor.id;
      log(`following successor ${next}; bond again there (\`bond\`), and \`exit\` here with --beacon ${beacon}`);
      fs.writeFileSync(`${followFile}.tmp`, JSON.stringify({ configured: cfg.beacon, beacon: next }));
      fs.renameSync(`${followFile}.tmp`, followFile);
      beacon = next;
      st.sent.clear(); st.successor = { at: -Infinity, id: null }; st.registry = { at: -Infinity, entry: null };
    }

    if (mine && truthy(mine.exiting)) st.wasExiting = true;
    if (exit && st.wasExiting && !mine) { st.done = true; log('exit finalized; bond refunded'); }
    const rt = st.health.roundTrip(now);
    st.status = { address: me, beacon, round: info.round, open: open(info).round ?? null, phase: open(info).phase ?? null,
      registered: !!mine, ready: mine ? truthy(mine.ready) : null, paused: mine ? truthy(mine.paused) : null,
      exiting: mine ? truthy(mine.exiting) : null, bond: mine ? bond : 0, stake, shortfall,
      faults: mine ? num(mine.faults) : null, rejoinAt: mine ? num(mine.rejoinAt) || null : null,
      backoffUntil: st.backoff.until || null, clockOffsetMs: st.clock.offset, roundTripMs: Number.isFinite(rt) ? rt : null,
      healthy, flags: { exit, pause }, moving: st.successor.id, beaconHealth: info.health ?? null, at: now };
    return { actions, info };
  }
  const open = (info) => obj(info.open);
  return { pass, state: st };
}

/** Transfer tags that bond `amount` RNG to `beacon` (D7: X-Bond). */
export const bondTags = (beacon, amount, unit) => ({
  Recipient: beacon, Quantity: String(BigInt(Math.round(amount)) * BigInt(unit)), 'X-Bond': 'true',
});

// --- CLI -------------------------------------------------------------------------

function parseArgs(argv) {
  const [cmd, ...rest] = argv;
  const flags = {}, pos = [];
  for (let i = 0; i < rest.length; i++) {
    const a = rest[i];
    if (a.startsWith('--')) {
      const k = a.slice(2);
      if (rest[i + 1] === undefined || rest[i + 1].startsWith('--')) flags[k] = true; else flags[k] = rest[++i];
    } else pos.push(a);
  }
  return { cmd, flags, pos };
}

function loadConfig(flags, pos) {
  const cfgPath = pos.find((a) => a.endsWith('.json')) ?? path.join(path.resolve(flags.dir ?? 'rng-validator'), 'config.json');
  if (!fs.existsSync(cfgPath)) throw new Error(`no config at ${cfgPath}: run \`init --beacon <pid> --node <url>\` first`);
  const cfg = JSON.parse(fs.readFileSync(cfgPath, 'utf8'));
  cfg.hbNode = cfg.hbNode ?? cfg.node;
  cfg.dataDir = path.resolve(path.dirname(cfgPath), cfg.dataDir ?? '.');
  return { cfg, cfgPath };
}

async function nodeIo(cfg, jwk) {
  const { readState } = await import('../vendor/hbclient.mjs');
  const { message } = await import('./hb.mjs');
  const node = cfg.hbNode;
  const readKey = async (pid, key) => {
    const r = await readState({ node, process: pid, path: key });
    return r.status === 200 ? r.value : null;
  };
  return {
    readKey,
    readAtSlot: async (pid) => num(await readKey(pid, 'now/at-slot')),
    readInfo: async (pid) => {
      const v = await readKey(pid, 'now/beaconinfo');
      if (v === null) throw new Error(`beaconinfo of ${pid}: not readable on ${node}`);
      return JSON.parse(v);
    },
    post: (pid, action, data) => message({ node, jwk, process: pid, action, data: JSON.stringify(data) }),
    transfer: (token, tags) => message({ node, jwk, process: token, action: 'Transfer', tags }),
    now: () => Date.now(),
  };
}

const USAGE = `Any-Honest validator

  init --beacon <pid> --node <url> [--dir <dir>] [--listen <port>] [--top-up]
                    create the wallet and config; prints the address to fund
  bond [RNG]        bond RNG from the validator wallet (default: up to the full stake)
  run               validate: Ready, commit, reveal, follow a successor
  status            this validator on the beacon, and the running loop's health
  pause | resume    stop / restart taking new rounds (owed rounds are still done)
  exit              leave: Exit, finish owed rounds, Finalize-Exit refunds the bond
  claim             send earned RNG to the validator wallet

<dir> defaults to ./rng-validator. Add --beacon <pid> to bond/exit/claim/status
to act on another beacon (e.g. the one this validator moved from).`;

export async function main(argv = process.argv.slice(2)) {
  const { cmd, flags, pos } = parseArgs(argv);
  const out = (o) => console.log(typeof o === 'string' ? o : JSON.stringify(o, null, 2));
  const { jwkToAddress } = await import('../vendor/hbclient.mjs');

  if (cmd === 'init') {
    const legacy = pos.find((a) => a.endsWith('.json'));
    let cfgPath, cfg;
    if (legacy) {
      cfgPath = path.resolve(legacy);
      cfg = JSON.parse(fs.readFileSync(cfgPath, 'utf8'));
    } else {
      const dir = path.resolve(flags.dir ?? 'rng-validator');
      cfgPath = path.join(dir, 'config.json');
      cfg = fs.existsSync(cfgPath) ? JSON.parse(fs.readFileSync(cfgPath, 'utf8')) : { dataDir: '.' };
      if (flags.beacon) cfg.beacon = flags.beacon;
      if (flags.node) cfg.hbNode = String(flags.node).replace(/\/$/, '');
      if (flags.listen) cfg.listen = Number(flags.listen);
      if (flags['top-up']) cfg.topUp = true;
      if (!isPid(cfg.beacon) || !cfg.hbNode) throw new Error('init needs --beacon <43-char pid> and --node <url>');
      fs.mkdirSync(dir, { recursive: true, mode: 0o700 });
      fs.writeFileSync(cfgPath, JSON.stringify(cfg, null, 2));
    }
    const dataDir = path.resolve(path.dirname(cfgPath), cfg.dataDir ?? '.');
    fs.mkdirSync(dataDir, { recursive: true, mode: 0o700 });
    const wallet = path.join(dataDir, 'validator-wallet.json');
    if (!fs.existsSync(wallet)) {
      const jwk = crypto.generateKeyPairSync('rsa', { modulusLength: 4096, publicExponent: 65537 }).privateKey.export({ format: 'jwk' });
      fs.writeFileSync(wallet, JSON.stringify(jwk), { mode: 0o600 });
    }
    const address = jwkToAddress(JSON.parse(fs.readFileSync(wallet, 'utf8')));
    out({ address, config: cfgPath, wallet, next: 'send RNG to this address, then run `bond`, then `run`. Back up the wallet file.' });
    return 0;
  }
  if (!cmd || cmd === 'help' || flags.help) { out(USAGE); return cmd ? 0 : 1; }

  const { cfg } = loadConfig(flags, pos);
  const jwk = JSON.parse(fs.readFileSync(path.join(cfg.dataDir, 'validator-wallet.json'), 'utf8'));
  const me = jwkToAddress(jwk);
  const io = await nodeIo(cfg, jwk);
  const beaconOf = () => {
    if (isPid(flags.beacon)) return flags.beacon;
    try {
      const f = JSON.parse(fs.readFileSync(path.join(cfg.dataDir, 'beacon.json'), 'utf8'));
      if (f.configured === cfg.beacon && isPid(f.beacon)) return f.beacon;
    } catch { /* not moved */ }
    return cfg.beacon;
  };
  const setFlag = (f, on) => {
    const file = path.join(cfg.dataDir, f);
    if (on) fs.writeFileSync(file, new Date().toISOString()); else fs.rmSync(file, { force: true });
  };

  if (cmd === 'bond') return bondCommand({ io, me, beacon: beaconOf(), amount: pos.find((a) => !a.endsWith('.json')), out });
  if (cmd === 'status') {
    const beacon = beaconOf();
    const t0 = Date.now(), info = await io.readInfo(beacon), t1 = Date.now();
    const mine = findMine(info.validators, me) ?? registryEntry(await io.readKey(beacon, 'now/beaconvalidators').catch(() => null), me);
    const offset = num(info.at) > 0 ? t1 - num(info.at) : 0;
    const balance = isPid(info.token) ? await io.readKey(info.token, `now/balance-${me}`).catch(() => null) : null;
    let loop = null;
    try { loop = JSON.parse(fs.readFileSync(path.join(cfg.dataDir, 'status.json'), 'utf8')); } catch { /* not running */ }
    const p = obj(info.params), unit = num(info.unit, 1_000_000) || 1;
    out({ address: me, beacon, registered: !!mine, ready: mine?.ready ?? false, paused: mine?.paused ?? false,
      exiting: mine?.exiting ?? false, bond: mine ? num(mine.bond ?? mine.stake) : 0, stake: num(p.stake),
      walletRNG: balance === null ? null : Number(BigInt(balance) / BigInt(unit)),
      faults: mine?.faults ?? 0, lastFault: mine?.lastFault ?? null,
      rejoinInS: mine?.rejoinAt ? Math.max(0, Math.ceil((num(mine.rejoinAt) - (Date.now() - offset)) / 1000)) : 0,
      readMs: t1 - t0, beaconHealth: info.health ?? null, commitWindowMs: num(p.commitWindowMs),
      loop: loop && { ...loop, ageS: Math.round((Date.now() - loop.at) / 1000) } });
    return 0;
  }
  if (cmd === 'pause' || cmd === 'resume') { setFlag('pause', cmd === 'pause'); out(`${cmd}d: the running validator picks this up on its next pass`); return 0; }
  if (cmd === 'exit') {
    if (isPid(flags.beacon) && flags.beacon !== beaconOf()) {
      // An old beacon this loop no longer watches: one step per call.
      const info = await io.readInfo(flags.beacon), mine = findMine(info.validators, me);
      const action = mine?.exiting ? 'Finalize-Exit' : 'Exit';
      out({ action, slot: await io.post(flags.beacon, action, {}), next: action === 'Exit' ? 'run `exit` again once its rounds are done' : 'done' });
      return 0;
    }
    setFlag('exit', true);
    out('exit requested: `run` sends Exit, finishes owed rounds, then Finalize-Exit refunds the bond and stops');
    return 0;
  }
  if (cmd === 'claim') { out({ slot: await io.post(beaconOf(), 'Claim', {}) }); return 0; }
  if (cmd !== 'run') { out(USAGE); return 1; }

  const log = (...a) => console.log(new Date().toISOString(), ...a);
  const v = createValidator({ cfg, me, io, log });
  if (cfg.listen) {
    http.createServer((_, res) => { res.writeHead(200, { 'content-type': 'application/json' }); res.end(JSON.stringify(v.state.status)); })
      .listen(cfg.listen, '127.0.0.1');
  }
  log(`validator ${me} watching ${v.state.beacon} on ${cfg.hbNode}`);
  const interval = num(cfg.interval, 100);
  let wrote = 0;
  for (;;) {
    try {
      await v.pass();
      if (Date.now() - wrote > 2000) {
        wrote = Date.now();
        fs.writeFileSync(path.join(cfg.dataDir, 'status.json'), JSON.stringify(v.state.status));
      }
      if (v.state.done) { setFlag('exit', false); return 0; }
    } catch (e) { log('loop error:', e.message); }
    await new Promise((r) => setTimeout(r, interval));
  }
}

/** Bond `amount` RNG (default: what brings the bond to the full stake). A first
 *  bond below the stake is refunded by the beacon, so it is refused here. */
export async function bondCommand({ io, me, beacon, amount, out = () => {} }) {
  const info = await io.readInfo(beacon);
  if (!isPid(info.token)) throw new Error('beaconinfo names no token');
  const unit = num(info.unit, 1_000_000) || 1, stake = num(obj(info.params).stake, 25_000);
  const mine = findMine(info.validators, me) ?? registryEntry(await io.readKey(beacon, 'now/beaconvalidators').catch(() => null), me);
  const bond = mine ? num(mine.bond ?? mine.stake) : 0;
  const rng = amount !== undefined ? Number(amount) : Math.max(0, stake - bond);
  if (!Number.isInteger(rng) || rng < 0) throw new Error(`bad amount ${amount}: whole RNG only`);
  if (rng === 0) { out({ bond, stake, note: 'already at the full stake' }); return 0; }
  if (!mine && rng < stake) throw new Error(`a first bond must be at least the stake (${stake} RNG); smaller ones are refunded`);
  const balance = await io.readKey(info.token, `now/balance-${me}`).catch(() => null);
  if (balance !== null && BigInt(balance) < BigInt(rng) * BigInt(unit)) {
    throw new Error(`wallet holds ${BigInt(balance) / BigInt(unit)} RNG, needs ${rng}: send RNG to ${me}`);
  }
  const tags = bondTags(beacon, rng, unit);
  const slot = await io.transfer(info.token, tags);
  out({ bonded: rng, token: info.token, beacon, slot, next: '`run` says Ready once the bond lands and the round trip is healthy' });
  return 0;
}

if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  main().then((code) => process.exit(code ?? 0), (e) => { console.error(e.message); process.exit(1); });
}

