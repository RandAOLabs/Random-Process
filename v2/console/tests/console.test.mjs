// Console pure functions (WP6 /validators + health banner, WP7 fair client,
// pay-and-request, DAO view). Run: npm test (node --test with tests/register-ts.mjs).
import test from 'node:test';
import assert from 'node:assert/strict';
import crypto, { createHash } from 'node:crypto';
import * as fair from '../lib/fair-client.ts';
import { beaconHealth } from '../components/health-banner.tsx';
import { estimateEarnings } from '../components/validator-guide.tsx';
import { describeAction, queueView, tally, tokens } from '../app/api/dao/model.ts';
import { signDataItem as vendorSign } from '../../vendor/ans104.mjs';

// The runner's hashes (test/run-fair-tests.mjs), computed with node:crypto.
const sha = (s) => createHash('sha256').update(s, 'latin1').digest('hex');
const addr = (s) => s.padEnd(43, '_');
const ref = {
  commit: (g, s, x) => sha(`rng/fair/v1/commit|${g}|${s}|${x}`),
  session: (vb, g, s) => sha(`rng/fair/v1/beacon|${vb}|${g}|${s}`),
  final: (v, x) => sha(`rng/fair/v1/final|${v}|${x}`),
  forfeit: (v) => sha(`rng/fair/v1/forfeit|${v}`),
  request: (rv, who, id) => sha(`hyperbeam/rng/any-honest/v1/request|${rv}|${who}|${id}`),
};

test('fair hashes match the runner vectors', async () => {
  const game = addr('game');
  const v = { session: 'demo', secret: '00'.repeat(32), vb: '11'.repeat(32) };
  assert.equal(await fair.commitHash(game, v.session, v.secret), ref.commit(game, v.session, v.secret));
  const sv = ref.session(v.vb, game, v.session);
  assert.equal(await fair.sessionValue(v.vb, game, v.session), sv);
  assert.equal(await fair.finalValue(sv, v.secret), ref.final(sv, v.secret));
  assert.equal(await fair.forfeitValue(sv), ref.forfeit(sv));
  // The flow vectors: s1 = sha('secret-1'), vb1 = request(round1, self, 'fair-1').
  const self = 'f'.repeat(43), s1 = sha('secret-1'), round1 = sha('round value 1');
  const vb1 = ref.request(round1, self, 'fair-1');
  assert.equal(await fair.requestValue(round1, self, 'fair-1'), vb1);
  assert.equal(await fair.commitHash(game, 'sess-1', s1), ref.commit(game, 'sess-1', s1));
  assert.equal(await fair.finalValue(ref.session(vb1, game, 'sess-1'), s1), ref.final(ref.session(vb1, game, 'sess-1'), s1));
});

test('newSecret is 64 lowercase hex characters', () => {
  const s = fair.newSecret();
  assert.ok(fair.isSecret(s));
  assert.notEqual(s, fair.newSecret());
});

test('nextStep never reveals before reveal-due', () => {
  const s = 'ab'.repeat(32);
  const base = { game: addr('g'), session: 'x', player: addr('p'), commit: '0'.repeat(64) };
  assert.equal(fair.nextStep(null, s, 0), 'wait');
  assert.equal(fair.nextStep({ ...base, status: 'committed' }, s, 0), 'wait');
  assert.equal(fair.nextStep({ ...base, status: 'reveal-due', revealBy: 100 }, s, 50), 'reveal');
  assert.equal(fair.nextStep({ ...base, status: 'reveal-due', revealBy: 100 }, null, 50), 'forfeit-expected');
  assert.equal(fair.nextStep({ ...base, status: 'reveal-due', revealBy: 100 }, s, 101), 'expire');
  assert.equal(fair.nextStep({ ...base, status: 'forfeit' }, null, 0), 'done');
});

test('verifySession checks revealed and forfeit sessions', async () => {
  const game = addr('game'), session = 'sess', secret = sha('secret'), vb = sha('beacon');
  const v = ref.session(vb, game, session);
  const revealed = { game, session, player: addr('p'), commit: ref.commit(game, session, secret), status: 'revealed',
    beaconValue: vb, v, secret, final: ref.final(v, secret) };
  assert.deepEqual((await fair.verifySession(revealed)).problems, []);
  assert.equal((await fair.verifySession({ ...revealed, final: '0'.repeat(64) })).ok, false);
  const forfeit = { ...revealed, status: 'forfeit', secret: undefined, final: ref.forfeit(v) };
  assert.equal((await fair.verifySession(forfeit)).ok, true);
});

test('pay-and-request is one Transfer with X-Request-Id', async () => {
  const beacon = addr('beacon');
  assert.deepEqual(fair.payAndRequestTags(beacon, 4_000_000n, 'req-1', 1700000000000.7), {
    Action: 'Transfer', Recipient: beacon, Quantity: '4000000', 'X-Request-Id': 'req-1', 'X-Request-Time': '1700000000000' });
  assert.throws(() => fair.payAndRequestTags(beacon, 1, '', 0));
  const who = addr('wallet'), rv = sha('round');
  const records = [{ round: 7, value: sha('other'), requests: {} },
    { round: 8, value: rv, requests: [{ requester: who, requestId: 'req-1', value: ref.request(rv, who, 'req-1') }] }];
  assert.deepEqual(await fair.findRequest(records, who, 'req-1'),
    { round: 8, roundValue: rv, value: ref.request(rv, who, 'req-1'), valid: true });
  assert.equal(await fair.findRequest(records, who, 'req-2'), null);
});

test('signDataItem matches the vendored ANS-104 layout and verifies', async () => {
  const { privateKey } = crypto.generateKeyPairSync('rsa', { modulusLength: 4096, publicExponent: 0x10001 });
  const jwk = { ...privateKey.export({ format: 'jwk' }), kty: 'RSA' };
  const webKey = await crypto.subtle.importKey('jwk', { ...jwk, alg: 'PS256' }, { name: 'RSA-PSS', hash: 'SHA-256' }, false, ['sign']);
  const key = { privateKey: webKey, owner: jwk.n, address: await fair.addressOf(jwk.n) };
  const target = addr('fair-process').replace(/_/g, 'A');
  const tags = fair.fairCommitTags(addr('game'), 'demo', '0'.repeat(64), 1700000000000);
  const ours = Buffer.from(await fair.signDataItem(key, { target, tags }));
  const theirs = await vendorSign(jwk, { target, tags: Object.entries(tags).map(([name, value]) => ({ name, value })), data: '' });
  // Signature is randomized (PSS); everything after it must be identical.
  assert.equal(ours.length, theirs.length);
  assert.deepEqual(ours.subarray(514), theirs.subarray(514));
  const { digest } = await fair.dataItemDigest(jwk.n, { target, tags });
  const pss = { key: crypto.createPublicKey({ key: jwk, format: 'jwk' }), padding: crypto.constants.RSA_PKCS1_PSS_PADDING, saltLength: 32 };
  assert.ok(crypto.verify('sha256', digest, pss, ours.subarray(2, 514)));
  assert.ok(crypto.verify('sha256', digest, pss, theirs.subarray(2, 514)));
  assert.equal(key.address, createHash('sha256').update(Buffer.from(jwk.n, 'base64url')).digest('base64url'));
});

test('FairClient commits, waits for reveal-due, then reveals (memory store)', async () => {
  const game = addr('game'), fairPid = 'F'.repeat(43);
  let view = null, info = {};
  const sent = [];
  const fetchStub = async (url, init) => {
    if (url.endsWith('/now/fairsessions')) return new Response(JSON.stringify(view ? { [game]: [view] } : {}));
    if (url.endsWith('/now/fairinfo')) return new Response(JSON.stringify(info));
    if (url.includes('/schedule')) { sent.push(init.body); return new Response('', { headers: { slot: String(sent.length) } }); }
    if (url.includes('/push&')) return new Response('{}');
    return new Response('{"ok":true}');
  };
  const store = fair.memoryStore();
  const key = await fair.createKey();
  await store.putKey(key);
  const client = new fair.FairClient({ fair: fairPid, node: 'http://node', store, fetch: fetchStub });
  const saved = await client.commit(game, 'sess-1');
  assert.equal(saved.commit, ref.commit(game, 'sess-1', saved.secret));
  assert.equal(sent.length, 1);
  view = { game, session: 'sess-1', player: key.address, commit: saved.commit, status: 'committed' };
  info = { outstanding: { batch: 1, requestId: 'fair-1', sentAt: 0 }, requestAfter: 0 };
  assert.equal((await client.step(saved)).step, 'wait');
  assert.equal(sent.length, 1, 'no reveal while committed');
  // No request out and the interval passed: the client pokes the process (Get-Info).
  info = { outstanding: null, requestAfter: Date.now() + 60_000 };
  await client.step(saved);
  assert.equal(sent.length, 1, 'no poke before requestAfter');
  info = { outstanding: null, requestAfter: 0 };
  await client.step(saved);
  assert.equal(sent.length, 2, 'poke once the interval passed');
  assert.ok(Buffer.from(sent[1]).includes(Buffer.from('Get-Info')));
  sent.pop();
  view = { ...view, status: 'reveal-due', revealBy: Date.now() + 60_000 };
  assert.equal((await client.step(saved)).step, 'reveal');
  assert.equal(sent.length, 2);
  assert.ok(Buffer.from(sent[1]).includes(Buffer.from(saved.secret)), 'the reveal carries the secret');
  // A browser that lost IndexedDB sees the forfeit coming.
  assert.equal(fair.nextStep(view, null, Date.now()), 'forfeit-expected');
});

test('fairOpenTags is the game-side authorization', () => {
  assert.deepEqual(fair.fairOpenTags('sess-1', addr('player')), { Action: 'Fair.Open', Session: 'sess-1', Player: addr('player') });
});

test('FairClient.commit keeps the secret once the commit was scheduled (C9), retries Not-Opened', async () => {
  const game = addr('game'), fairPid = 'F'.repeat(43);
  const store = fair.memoryStore();
  await store.putKey(await fair.createKey());
  const make = (handler) => new fair.FairClient({ fair: fairPid, node: 'http://node', store, fetch: handler });
  // Scheduled, then the result read fails: the commit may be in; keep the secret.
  let client = make(async (url) => url.includes('/schedule') ? new Response('', { headers: { slot: '1' } })
    : url.includes('/push&') ? new Response('{}') : new Response('', { status: 502 }));
  await assert.rejects(client.commit(game, 'kept', { retries: 0 }));
  assert.equal((await store.list()).filter((s) => s.session === 'kept').length, 1, 'scheduled commit keeps its secret');
  // Never scheduled (node refused, or network down): drop it.
  client = make(async () => new Response('', { status: 500 }));
  await assert.rejects(client.commit(game, 'refused', { retries: 0 }), fair.NotScheduledError);
  client = make(async () => { throw new TypeError('network down'); });
  await assert.rejects(client.commit(game, 'offline', { retries: 0 }), fair.NotScheduledError);
  assert.deepEqual((await store.list()).map((s) => s.session), ['kept']);
  // Not-Opened is retried until the game's Fair.Open lands.
  let tries = 0;
  client = make(async (url) => url.includes('/schedule') ? new Response('', { headers: { slot: String(++tries) } })
    : url.includes('/push&') ? new Response('{}')
    : new Response(tries < 3 ? '{"error":"Not-Opened"}' : '{"committed":true}'));
  const saved = await client.commit(game, 'retried', { retries: 5, sleep: async () => {} });
  assert.equal(tries, 3);
  assert.equal(saved.session, 'retried');
  // A definite refusal (retries exhausted) drops the secret.
  client = make(async (url) => url.includes('/schedule') ? new Response('', { headers: { slot: '9' } })
    : url.includes('/push&') ? new Response('{}') : new Response('{"error":"Not-Opened"}'));
  await assert.rejects(client.commit(game, 'never', { retries: 1, sleep: async () => {} }), (e) => e.code === 'Not-Opened');
  assert.equal((await store.list()).some((s) => s.session === 'never'), false);
});

test('WP6 beaconHealth: v3 health wins, v2 is derived', () => {
  assert.equal(beaconHealth({ health: { status: 'halted', eligible: 1, minCommits: 2 } }).status, 'halted');
  assert.equal(beaconHealth({ validators: [{ ready: true }, { ready: true }, { ready: true }] }).status, 'ok');
  assert.equal(beaconHealth({ validators: [{ ready: true }, { suspended: true }, { suspended: true }], params: { minCommits: 2 } }).status, 'halted');
  assert.equal(beaconHealth({ validators: [{}, {}, {}, { suspended: true }, { suspended: true }, { suspended: true }, { suspended: true }] }).status, 'degraded');
  assert.equal(beaconHealth({ validators: [{}, {}] }, 120_000).status, 'degraded');
  assert.equal(beaconHealth({ validators: [{}, {}], mode: 'request-driven' }, 120_000).status, 'ok');
});

test('WP6 estimateEarnings splits round pay across the active set', () => {
  assert.deepEqual(estimateEarnings(1, 2, 4), { perSecond: 0.5, perDay: 43_200, perRound: 0.25 });
  assert.equal(estimateEarnings(1, 2, 0).perRound, 1);
});

test('DAO tally, actions and the beacon queue', () => {
  const p = { yes: '600', no: '300', abstain: '0', veto: '100', quorum: '500', passBps: 5000, vetoBps: 3334 };
  assert.equal(tally(p).outcome, 'passed');
  assert.equal(tally({ ...p, quorum: '2000' }).outcome, 'failed-quorum');
  assert.equal(tally({ ...p, veto: '500' }).outcome, 'vetoed');
  assert.equal(tokens('25000000000'), '25,000');
  const beacon = addr('beacon');
  assert.deepEqual(describeAction({ process: beacon, tags: { Action: 'Gov.Configure', 'Reveal-Window-Ms': '30000' }, executed: false }, beacon),
    { name: 'Gov.Configure', args: 'Reveal-Window-Ms=30000', toBeacon: true, executed: false });
  const q = queueView([{ id: 2, kind: 'Treasury-Spend', at: 300, queuedAt: 0, recipient: 'x' }, { id: 1, kind: 'Set-Successor', at: 100, queuedAt: 0 }], 200);
  assert.deepEqual(q.map((e) => [e.id, e.due, e.remainingMs, e.detail]), [[1, true, 0, ''], [2, false, 100, 'recipient=x']]);
});
