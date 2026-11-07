// node --test test/validator.test.mjs
// The JS validator against a mocked node: no network, a fake clock on each side.
import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import * as tl from '../provider/anyhonest.mjs';
import {
  plan, batch, Clock, Health, backoff, secretStore, createValidator, bondCommand, checkSuccessor, bondTags,
} from '../provider/anyhonest-validator.mjs';

const ME = 'me'.padEnd(43, '0');
const OTHER = 'ot'.padEnd(43, '0');
const BEACON = 'be'.padEnd(43, '0');
const NEXT = 'nx'.padEnd(43, '0');
const TOKEN = 'tk'.padEnd(43, '0');
const UNIT = 1_000_000;
const tmp = () => fs.mkdtempSync(path.join(os.tmpdir(), 'rng-validator-'));

function baseInfo(over = {}) {
  return {
    round: 7, nextRoundAt: 0, at: 0, token: TOKEN, unit: UNIT, features: ['act', 'ready'],
    params: { minCommits: 2, heartbeat: 1, slash: 1000, stake: 25000, commitWindowMs: 5000,
      rejoinBaseMs: 60000, rejoinCapMs: 3600000 },
    validators: [{ address: ME, ready: true, bond: 25000, faults: 0 }, { address: OTHER, ready: true, bond: 25000 }],
    open: { round: 7, phase: 'collecting', pending: 0, committed: {}, active: [] }, revealing: [],
    successor: '', predecessor: '', ...over,
  };
}
const ctx = (dir, over = {}) => ({ me: ME, sent: new Map(), atSlot: 10, now: 100000, beaconNow: 100000, healthy: true,
  backoffUntil: 0, secrets: secretStore(dir), ...over });
const kinds = (r) => r.actions.map((a) => a.kind);

// --- A mocked node: one beacon (and maybe a successor), its own clock ---------

function mockNode({ skew = 0, delay = 100 } = {}) {
  // skew: how far the validator's clock is AHEAD of the beacon's.
  const clock = { t: 1_000_000 };
  const node = {
    clock, skew, delay, slot: 0, computed: {}, posts: [], transfers: [], infos: {}, balances: {},
    beaconTime: () => clock.t - node.skew,
    info(pid = BEACON) { return node.infos[pid]; },
    effect(pid, action, data) {
      const i = node.infos[pid], v = i.validators.find((x) => x.address === ME);
      if (action === 'Ready' && v && node.readyOk !== false) Object.assign(v, { ready: true, paused: false, rejoinAt: undefined });
      if (action === 'Pause' && v) Object.assign(v, { ready: false, paused: true });
      if (action === 'Exit' && v) v.exiting = true;
      if (action === 'Finalize-Exit' && v) i.validators = i.validators.filter((x) => x !== v);
      const c = action === 'Commit' ? data.c : action === 'Act' ? data.commit?.c : null;
      if (c && i.open.round === (data.round ?? data.commit.round)) i.open.committed[ME] = c.slice(0, 16);
      for (const r of action === 'Act' ? data.reveals : action === 'Reveal' ? [data] : []) {
        const x = [...i.revealing, i.open].find((o) => o.round === r.round);
        if (x) x.revealed = [...(x.revealed ?? []), ME];
      }
    },
    /** Compute every message posted at least `delay` ms ago (local clock). */
    tick() {
      for (const p of node.posts) {
        if (!p.done && clock.t - p.t >= node.delay) {
          p.done = true; node.computed[p.pid] = Math.max(node.computed[p.pid] ?? 0, p.slot);
          node.effect(p.pid, p.action, p.data);
        }
      }
      for (const pid of Object.keys(node.infos)) node.infos[pid].at = node.beaconTime() - 20;
    },
    io: {
      now: () => clock.t,
      readAtSlot: async (pid) => node.computed[pid] ?? 0,
      readInfo: async (pid) => {
        if (!node.infos[pid]) throw new Error('unknown process');
        return structuredClone(node.infos[pid]);
      },
      readKey: async (pid, key) => (key.startsWith('now/balance-') ? node.balances[key.slice(12)] ?? null : null),
      post: async (pid, action, data) => { const slot = ++node.slot; node.posts.push({ pid, action, data, slot, t: clock.t }); return slot; },
      transfer: async (token, tags) => { node.transfers.push({ token, tags }); return ++node.slot; },
    },
    sentActions: (pid = BEACON) => node.posts.filter((p) => p.pid === pid).map((p) => p.action),
  };
  node.infos[BEACON] = baseInfo();
  return node;
}
async function run(v, node, steps, dt = 100) {
  for (let k = 0; k < steps; k++) { node.clock.t += dt; node.tick(); await v.pass(); }
}
const make = (node, cfg = {}) => {
  const dir = tmp();
  return { dir, v: createValidator({ cfg: { beacon: BEACON, dataDir: dir, ...cfg }, me: ME, io: node.io }) };
};

// --- Crypto parity -------------------------------------------------------------

test('commit is g^alpha mod N, as rng@1.0 checks it', () => {
  assert.equal(tl.commit('1'), tl.G_HEX);
  const a = tl.newAlpha();
  assert.equal(tl.verifyReveal(tl.commit(a), a, tl.G_HEX).valid, true);
  assert.match(a, /^[1-9a-f][0-9a-f]*$/);
});

// --- plan ------------------------------------------------------------------------

test('a commit is on disk before it is returned, owner-only', () => {
  const dir = tmp();
  const r = plan(baseInfo(), ctx(dir));
  assert.deepEqual(kinds(r), ['Commit']);
  const c = r.actions[0].data.c;
  assert.ok(secretStore(dir).read(7)[c]);
  if (process.platform !== 'win32') assert.equal(fs.statSync(path.join(dir, '7.json')).mode & 0o777, 0o600);
});

test('defaults come from beaconinfo.params: no commit below minCommits, none before nextRoundAt', () => {
  const two = baseInfo({ params: { ...baseInfo().params, minCommits: 3 } });
  assert.deepEqual(kinds(plan(two, ctx(tmp()))), []);
  assert.deepEqual(kinds(plan(baseInfo({ nextRoundAt: 100001 }), ctx(tmp()))), []);
  assert.deepEqual(kinds(plan(baseInfo({ mode: 'request-driven' }), ctx(tmp()))), []);
  const pending = baseInfo({ mode: 'request-driven', open: { ...baseInfo().open, pending: 1 } });
  assert.deepEqual(kinds(plan(pending, ctx(tmp()))), ['Commit']);
});

test('never resend before the beacon computed the slot', () => {
  const sent = new Map([['Commit:7', { at: 0, slot: 11 }]]);
  assert.deepEqual(kinds(plan(baseInfo(), ctx(tmp(), { sent }))), []);
  sent.set('Commit:7', { at: 0, slot: 9 });
  assert.deepEqual(kinds(plan(baseInfo(), ctx(tmp(), { sent }))), ['Commit']);
});

test('reveals from the stored secret when the beacon shows only a 16-hex prefix', () => {
  const dir = tmp(), s = secretStore(dir), a = tl.newAlpha(), c = tl.commit(a);
  s.save(3, c, a);
  const info = baseInfo({ revealing: [{ round: 3, phase: 'reveal', committed: { [ME]: c.slice(0, 16) }, revealed: [] }],
    open: { round: 4, phase: 'commit', committed: { [ME]: 'x' }, active: [ME] } });
  assert.deepEqual(plan(info, ctx(dir)).actions, [{ kind: 'Reveal', round: 3, data: { round: 3, alpha: a } }]);
  info.revealing[0].revealed = [ME];
  assert.deepEqual(plan(info, ctx(dir)).actions, []);
});

test('Act batches the commit and every reveal into one message', () => {
  const dir = tmp(), s = secretStore(dir);
  const secrets = [5, 6].map((r) => { const a = tl.newAlpha(), c = tl.commit(a); s.save(r, c, a); return { r, a, c }; });
  const info = baseInfo({ revealing: secrets.map(({ r, c }) => ({ round: r, phase: 'reveal', committed: { [ME]: c.slice(0, 16) }, revealed: [] })) });
  const r = plan(info, ctx(dir));
  assert.deepEqual(kinds(r), ['Commit', 'Reveal', 'Reveal']);
  const [m] = batch(r.actions, info);
  assert.equal(m.action, 'Act');
  assert.deepEqual(m.keys, ['Commit:7', 'Reveal:5', 'Reveal:6']);
  assert.deepEqual(m.data.commit, { round: 7, c: r.actions[0].data.c });
  assert.deepEqual(m.data.reveals, secrets.map(({ r: round, a: alpha }) => ({ round, alpha })));
  assert.deepEqual(batch(r.actions, { features: ['ready'] }).map((x) => x.action), ['Commit', 'Reveal', 'Reveal']);
  assert.deepEqual(batch(r.actions.slice(0, 1), info).map((x) => x.action), ['Commit']);
});

test('a commit-phase round is owed only by its set', () => {
  const info = baseInfo({ open: { round: 7, phase: 'commit', committed: {}, active: [OTHER] } });
  assert.deepEqual(kinds(plan(info, ctx(tmp()))), []);
  info.open.active = [ME, OTHER];
  assert.deepEqual(kinds(plan(info, ctx(tmp(), { pause: true }))), ['Pause', 'Commit']);
});

test('Ready needs good standing, the cooldown, our backoff, health and the full stake', () => {
  const v = (o) => baseInfo({ validators: [{ address: ME, ready: false, bond: 25000, ...o }, { address: OTHER, ready: true }] });
  assert.deepEqual(kinds(plan(v({}), ctx(tmp()))), ['Ready']);
  assert.deepEqual(kinds(plan(v({ overdue: true }), ctx(tmp()))), []);
  assert.deepEqual(kinds(plan(v({ rejoinAt: 100001 }), ctx(tmp()))), []);
  assert.deepEqual(kinds(plan(v({}), ctx(tmp(), { backoffUntil: 100001 }))), []);
  assert.deepEqual(kinds(plan(v({}), ctx(tmp(), { healthy: false }))), []);
  assert.deepEqual(kinds(plan(v({ bond: 24000, earnedAtoms: '0' }), ctx(tmp()))), []);
  assert.deepEqual(kinds(plan(v({ bond: 24000, earnedAtoms: String(1000 * UNIT) }), ctx(tmp()))), ['Ready']);
  assert.deepEqual(kinds(plan(v({}), ctx(tmp(), { pause: true }))), []);
  assert.throws(() => plan(baseInfo({ features: ['act'] }), ctx(tmp())), /ready/);
});

test('Pause, then Exit, then Finalize-Exit only once nothing is owed', () => {
  assert.deepEqual(kinds(plan(baseInfo(), ctx(tmp(), { pause: true }))), ['Pause']);
  assert.deepEqual(kinds(plan(baseInfo(), ctx(tmp(), { exit: true }))), ['Exit']);
  const exiting = baseInfo({ validators: [{ address: ME, ready: false, exiting: true, bond: 25000 }, { address: OTHER, ready: true }],
    revealing: [{ round: 6, phase: 'reveal', committed: { [ME]: 'abcd' }, revealed: [] }] });
  assert.deepEqual(kinds(plan(exiting, ctx(tmp(), { exit: true }))), []);
  exiting.revealing[0].revealed = [ME];
  assert.deepEqual(kinds(plan(exiting, ctx(tmp(), { exit: true }))), ['Finalize-Exit']);
});

// --- Clock and health ---------------------------------------------------------

test('offset is the minimum of localReadAt - at over recent reads', () => {
  const c = new Clock();
  assert.equal(c.offset, null);
  c.observe(1_000_000, 940_000 - 300);
  c.observe(1_000_500, 940_000 + 450);
  assert.equal(c.offset, 60_050);
  assert.equal(c.beaconNow(1_001_000), 1_001_000 - 60_050);
  c.observe(1_400_000, 1_340_000); // five minutes on, the old buckets are gone
  assert.equal(c.offset, 60_000);
});

test('health counts only local round trips, and a lost send as infinite', () => {
  const h = new Health();
  for (let k = 0; k < 4; k++) { h.sent(k * 1000, k + 1); h.observe(k + 1, k * 1000 + 200); }
  assert.equal(h.roundTrip(5000), Infinity); // 4 samples: not enough yet
  h.sent(5000, 5); h.observe(5, 5300);
  assert.equal(h.roundTrip(6000), 300);
  assert.equal(h.healthy(6000, 5000), true);
  h.sent(7000, -1);
  assert.equal(h.healthy(7000, 5000), false);
});

test('backoff doubles per incident from rejoinBaseMs', () => {
  const p = { rejoinBaseMs: 1000, rejoinCapMs: 8000 };
  let b = { faults: null, n: 0, until: 0, readySince: 0 };
  b = backoff({ ready: true, faults: 0 }, p, 100, b);
  b = backoff({ ready: false, faults: 1 }, p, 110, b);
  assert.equal(b.until, 1110);
  b = backoff({ ready: true, faults: 1 }, p, 2000, b);
  b = backoff({ ready: false, faults: 2 }, p, 2100, b);
  assert.equal(b.until, 4100);
});

// --- The loop against a mocked node ---------------------------------------------

function notReady(node, o = {}) {
  Object.assign(node.infos[BEACON].validators[0], { ready: false, ...o });
  node.infos[BEACON].open = { round: 7, phase: 'commit', committed: {}, active: [OTHER] };
}

test('before Ready it probes with Get-Info, and says Ready once 5 local round trips are fast', async () => {
  const node = mockNode({ delay: 300 });
  notReady(node);
  const { v } = make(node);
  await run(v, node, 30, 500);
  const sent = node.sentActions();
  assert.equal(sent.filter((a) => a === 'Get-Info').length, 5);
  assert.ok(sent.indexOf('Ready') > sent.lastIndexOf('Get-Info'));
  assert.equal(v.state.status.ready, true);
  assert.equal(v.state.status.roundTripMs >= 300 && v.state.status.roundTripMs < 2500, true);
});

test('a slow node never looks healthy: no Ready, whatever the clocks say', async () => {
  for (const skew of [0, 60_000, -60_000]) {
    const node = mockNode({ delay: 3000, skew });
    notReady(node);
    const { v } = make(node);
    await run(v, node, 60, 500);
    assert.ok(node.sentActions().includes('Get-Info'));
    assert.ok(!node.sentActions().includes('Ready'), `skew ${skew}`);
    assert.equal(v.state.status.healthy, false);
  }
});

test('commitWindowMs comes from params: the same 3 s round trip is healthy under a 20 s window', async () => {
  const node = mockNode({ delay: 3000 });
  notReady(node);
  node.infos[BEACON].params.commitWindowMs = 20_000;
  const { v } = make(node);
  await run(v, node, 80, 500);
  assert.ok(node.sentActions().includes('Ready'));
});

test('a skewed clock (+-60 s) waits for rejoinAt and nextRoundAt by the beacon clock, then acts', async () => {
  for (const skew of [60_000, -60_000]) {
    const node = mockNode({ skew });
    const rejoinAt = node.beaconTime() + 20_000;
    notReady(node, { rejoinAt });
    const { v } = make(node);
    await run(v, node, 30, 500); // 15 s: healthy, still cooling down
    assert.ok(!node.sentActions().includes('Ready'), `early Ready at skew ${skew}`);
    assert.ok(Math.abs(v.state.clock.offset - skew) < 1000);
    await run(v, node, 20, 500); // past rejoinAt on the beacon clock
    assert.ok(node.sentActions().includes('Ready'), `stuck at skew ${skew}`);

    // A round opens at nextRoundAt by the beacon clock.
    node.infos[BEACON].open = { round: 8, phase: 'collecting', pending: 0, committed: {}, active: [] };
    node.infos[BEACON].nextRoundAt = node.beaconTime() + 5000;
    await run(v, node, 8, 500);
    assert.ok(!node.sentActions().includes('Commit'), `early commit at skew ${skew}`);
    await run(v, node, 6, 500);
    assert.ok(node.sentActions().includes('Commit'), `no commit at skew ${skew}`);
  }
});

test('rejoin after a fault needs the full stake back: hint, or top up when configured', async () => {
  const node = mockNode();
  notReady(node, { bond: 24000, earnedAtoms: '0', faults: 1 });
  const lines = [];
  const dir = tmp();
  const v = createValidator({ cfg: { beacon: BEACON, dataDir: dir }, me: ME, io: node.io, log: (l) => lines.push(l) });
  await run(v, node, 20, 500);
  assert.ok(!node.sentActions().includes('Ready'));
  assert.ok(lines.some((l) => /bond 1000/.test(l)));
  assert.equal(node.transfers.length, 0);

  const { v: v2 } = make(node, { topUp: true });
  await run(v2, node, 3, 500);
  assert.deepEqual(node.transfers, [{ token: TOKEN, tags: { Recipient: BEACON, Quantity: String(1000 * UNIT), 'X-Bond': 'true' } }]);
});

test('exit: Exit, finish owed reveals, Finalize-Exit, then done', async () => {
  const node = mockNode();
  const dir = tmp(), s = secretStore(path.join(dir, 'secrets')), a = tl.newAlpha(), c = tl.commit(a);
  s.save(6, c, a);
  node.infos[BEACON].revealing = [{ round: 6, phase: 'reveal', committed: { [ME]: c.slice(0, 16) }, revealed: [] }];
  node.infos[BEACON].open = { round: 7, phase: 'commit', committed: {}, active: [OTHER] };
  fs.writeFileSync(path.join(dir, 'exit'), '1');
  const v = createValidator({ cfg: { beacon: BEACON, dataDir: dir }, me: ME, io: node.io });
  await run(v, node, 10, 500);
  const sent = node.sentActions();
  assert.ok(sent.includes('Exit') && sent.includes('Reveal'));
  assert.ok(sent.indexOf('Finalize-Exit') > sent.indexOf('Reveal'));
  assert.equal(v.state.done, true);
});

test('follows a successor only when it names this beacon back and the ack is in', async () => {
  const node = mockNode();
  node.infos[NEXT] = baseInfo({ predecessor: 'someone-else'.padEnd(43, '0') });
  node.infos[BEACON].successor = NEXT;
  node.infos[BEACON].params.heartbeat = 0; // no new rounds: nothing owed here
  const { v, dir } = make(node);
  const step = async (n) => { for (let k = 0; k < n; k++) { node.clock.t += 11_000; node.tick(); await v.pass(); } };
  await step(2);
  assert.equal(v.state.beacon, BEACON);

  node.infos[NEXT].predecessor = BEACON;
  node.infos[BEACON].successorAck = false;
  await step(2);
  assert.equal(v.state.beacon, BEACON);

  node.infos[BEACON].successorAck = true;
  await step(3);
  assert.ok(node.sentActions(BEACON).includes('Pause'));
  assert.equal(v.state.beacon, NEXT);
  assert.deepEqual(JSON.parse(fs.readFileSync(path.join(dir, 'beacon.json'), 'utf8')), { configured: BEACON, beacon: NEXT });
  // A restart stays on the successor.
  assert.equal(createValidator({ cfg: { beacon: BEACON, dataDir: dir }, me: ME, io: node.io }).state.beacon, NEXT);
});

test('a successor is not followed while this beacon is still owed a reveal', async () => {
  const info = baseInfo({ successor: NEXT,
    revealing: [{ round: 6, phase: 'reveal', committed: { [ME]: 'ab' }, revealed: [] }] });
  assert.equal(await checkSuccessor(info, BEACON, async () => ({ predecessor: BEACON })), NEXT);
  const node = mockNode();
  node.infos[BEACON] = info;
  node.infos[NEXT] = baseInfo({ predecessor: BEACON });
  const { v } = make(node);
  await run(v, node, 3, 500);
  assert.equal(v.state.beacon, BEACON);
});

// --- bond -------------------------------------------------------------------------

test('bond sends a Transfer with X-Bond for the full stake, refusing what would be refunded', async () => {
  const node = mockNode();
  node.infos[BEACON].validators = [{ address: OTHER, ready: true }];
  node.balances[ME] = String(30000 * UNIT);
  await bondCommand({ io: node.io, me: ME, beacon: BEACON });
  assert.deepEqual(node.transfers.at(-1), { token: TOKEN, tags: bondTags(BEACON, 25000, UNIT) });
  assert.equal(node.transfers.at(-1).tags.Quantity, '25000000000');
  await assert.rejects(bondCommand({ io: node.io, me: ME, beacon: BEACON, amount: '1000' }), /at least the stake/);
  node.balances[ME] = String(10 * UNIT);
  await assert.rejects(bondCommand({ io: node.io, me: ME, beacon: BEACON }), /holds 10 RNG/);
});

test('bond tops a registered validator up to the stake, or by a given amount', async () => {
  const node = mockNode();
  node.infos[BEACON].validators[0].bond = 22000;
  await bondCommand({ io: node.io, me: ME, beacon: BEACON });
  assert.equal(node.transfers.at(-1).tags.Quantity, String(3000 * UNIT));
  await bondCommand({ io: node.io, me: ME, beacon: BEACON, amount: '75000' });
  assert.equal(node.transfers.at(-1).tags.Quantity, String(75000 * UNIT));
  node.infos[BEACON].validators[0].bond = 25000;
  const n = node.transfers.length;
  await bondCommand({ io: node.io, me: ME, beacon: BEACON });
  assert.equal(node.transfers.length, n);
});
