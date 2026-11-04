// Deploy and drive the HyperBEAM RNG test network.
//
//   node deploy/deploy.mjs spawn                     spawn TEST-RNG and the beacon
//   node deploy/deploy.mjs reset                     archive an unavailable test deployment
//   node deploy/deploy.mjs spawn-beacon              replace only the beacon (keeps the token)
//   node deploy/deploy.mjs configure <committee.json> set token, committee, group key
//   node deploy/deploy.mjs fund <rng> [for]           faucet, then fund a beacon balance
//   node deploy/deploy.mjs enqueue [id]                submit without waiting for finalization
//   node deploy/deploy.mjs request [id]               ask for one beacon value
//   node deploy/deploy.mjs verify [round]              verify a finalized round from state
//   node deploy/deploy.mjs info                       print the beacon's published info
//   node deploy/deploy.mjs spawn-anyhonest            spawn the Any-Honest beacon
//   node deploy/deploy.mjs configure-anyhonest <validators.json>
//   node deploy/deploy.mjs mint-creator               mint 1B TEST-RNG to owner
//   node deploy/deploy.mjs fund-anyhonest [foundation] [treasury]
//   node deploy/deploy.mjs spawn-dao                  spawn advisory governance
//   node deploy/deploy.mjs stake-dao [rng]
//   node deploy/deploy.mjs propose-dao <proposal.json>
//   node deploy/deploy.mjs vote-dao <id> <yes|no|abstain>
//   node deploy/deploy.mjs test-subscription         live authenticated-push acceptance test
//
// Env: HB_NODE (HyperBEAM endpoint), HB_WALLET (owner/deployer wallet),
//      RNG_STATE (optional deployment-state path; defaults to testnet.json).
import fs from 'node:fs';
import path from 'node:path';
import { createHash } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import {
  spawnProcess, sendMessage, readState, jwkToAddress, awaitComputedSlot, pendingPushes, nodeAddress,
} from '../vendor/hbclient.mjs';
import * as bls from '../provider/bls.mjs';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const V2 = path.resolve(HERE, '..');
const read = (p) => fs.readFileSync(path.join(V2, p), 'utf8');
const NODE = process.env.HB_NODE;
const VERIFICATION = process.env.RNG_VERIFICATION || 'attestations';
const WALLET = process.env.HB_WALLET;
if (!NODE) throw new Error('HB_NODE is required');
if (!WALLET) throw new Error('HB_WALLET is required');
const STATE = process.env.RNG_STATE
  ? path.resolve(process.env.RNG_STATE)
  : path.join(HERE, 'testnet.json');
const jwk = JSON.parse(fs.readFileSync(WALLET, 'utf8'));
const me = jwkToAddress(jwk);
const state = fs.existsSync(STATE) ? JSON.parse(fs.readFileSync(STATE, 'utf8')) : {};
const save = () => fs.writeFileSync(STATE, JSON.stringify(state, null, 2) + '\n');

const json = () => [
  read('vendor/json.lua'),
  'local jsonx = (function()', read('vendor/jsonenc.lua'), 'end)()',
  'local encode, jsonObject = jsonx.encode, jsonx.object',
];
const tokenSource = () => [...json(), read('token/rng-token.lua')].join('\n');
const beaconSource = () => [...json(), 'rng = (function()', read('lib/rng.lua'), 'end)()', read('beacon/beacon.lua')].join('\n');
const anyHonestSource = () => [...json(), 'rng = (function()', read('lib/rng.lua'), 'end)()', read('beacon/anyhonest.lua')].join('\n');
// The same beacon on lua-patch@1.0 (paralith-mono's lua53b.lua adapter): only
// changed keys are published, and the VM keeps the state between messages.
// The adapter's compute calls the beacon's, so the beacon's final full collect
// moves out to it; the bootstrap gives the owner and scheduler checks the
// facts they read from `base.process` on lua@5.3a.
const anyHonestPatchSource = (owner, scheduler) => {
  const src = anyHonestSource();
  const collect = 'collectgarbage("collect")';
  const at = src.lastIndexOf(collect);
  if (at === -1) throw new Error('beacon has no final full collect');
  const q = JSON.stringify;
  return [
    src.slice(0, at) + src.slice(at + collect.length),
    `Lua53bBootstrapBase = { process = { commitments = { owner = { committer = ${q(owner)}, type = "rsa-pss-sha512" } },`
      + ` ["scheduler-location"] = ${q(scheduler)} }, ["scheduler-location"] = ${q(scheduler)} }`,
    'Lua53bKeepaliveKey = "timelockrev"',
    'Lua53bGcStep = 5000',
    'Lua53bPatchMode = true',
    read('vendor/lua53b.lua'),
  ].join('\n');
};
const daoSource = () => [...json(), read('governance/dao.lua')].join('\n');
const subscriptionConsumerSource = (beacon, id) => [...json(), read('test/subscription-consumer.lua')]
  .join('\n').replaceAll('__BEACON__', beacon).replaceAll('__SUBSCRIPTION_ID__', id);

async function send(pid, action, { tags = {}, data } = {}) {
  const { slot } = await sendMessage({ node: NODE, jwk, process: pid, action, tags, data });
  await awaitComputedSlot({ node: NODE, process: pid, slot });
  const out = await readState({ node: NODE, process: pid, path: `compute&slot=${slot}/results/output/data` });
  await pendingPushes({ node: NODE, process: pid });
  return { slot, output: out.value };
}

async function beaconInfo() {
  const r = await readState({ node: NODE, process: state.beacon, path: 'now/beaconinfo' });
  if (r.status !== 200) throw new Error(`beaconinfo: HTTP ${r.status}`);
  return JSON.parse(r.value);
}

async function beaconState() {
  const r = await readState({ node: NODE, process: state.beacon, path: 'now/beaconstate' });
  if (r.status !== 200) throw new Error(`beaconstate: HTTP ${r.status}`);
  return JSON.parse(r.value);
}

async function anyHonestInfo() {
  const r = await readState({ node: NODE, process: state.anyHonest, path: 'now/beaconinfo' });
  if (r.status !== 200) throw new Error(`any-honest beaconinfo: HTTP ${r.status}`);
  return JSON.parse(r.value);
}

async function enqueueRequest(id) {
  const requested = await send(state.beacon, 'Request-Random', {
    tags: { Tier: 'beacon', 'Request-Id': id },
  });
  const accepted = JSON.parse(requested.output);
  if (!Number.isSafeInteger(accepted.round)) throw new Error(`request was not accepted: ${requested.output}`);
  return { accepted, output: requested.output };
}

async function verifyRound(round) {
  const record = (await beaconState()).rounds[String(round)];
  if (!record) throw new Error(`finalized round ${round} is missing from beacon state`);
  const message = `hyperbeam/rng/v1|${state.beacon}|${round}`;
  if (!bls.verify(state.groupKey, message, record.signature)) throw new Error(`round ${round} BLS signature failed verification`);
  const value = createHash('sha256').update(`hyperbeam/rng/v1/round|${message}|${record.signature}`, 'latin1').digest('hex');
  if (record.value !== value) throw new Error(`round ${round} value does not match its signature`);
  return record;
}

const [cmd, ...args] = process.argv.slice(2);

if (cmd === 'reset') {
  if (state.beacon) (state.retired ||= []).push(state.beacon);
  if (state.token) (state.retiredTokens ||= []).push(state.token);
  delete state.token;
  delete state.beacon;
  delete state.groupKey;
  delete state.committee;
  delete state.sharePublicKeys;
  delete state.verification;
  save();
  console.log('archived unavailable test deployment');
}

if (cmd === 'spawn') {
  if (state.beacon) throw new Error(`already deployed (${STATE}); move it aside to redeploy`);
  state.owner = me;
  state.token = await spawnProcess({ node: NODE, jwk, lua: tokenSource(), name: 'TEST-RNG' });
  console.log('token ', state.token);
  save();
  state.beacon = await spawnProcess({ node: NODE, jwk, lua: beaconSource(), name: 'HyperBEAM-RNG-Beacon' });
  console.log('beacon', state.beacon);
  save();
  // First messages initialise each process and publish its read keys.
  console.log('token info ', (await send(state.token, 'Info')).output);
  console.log('beacon info', (await send(state.beacon, 'Get-Info')).output);
}

if (cmd === 'spawn-beacon') {
  if (state.beacon) (state.retired ||= []).push(state.beacon);
  state.beacon = await spawnProcess({ node: NODE, jwk, lua: beaconSource(), name: 'HyperBEAM-RNG-Beacon' });
  console.log('beacon', state.beacon);
  save();
  console.log('beacon info', (await send(state.beacon, 'Get-Info')).output);
}

if (cmd === 'configure') {
  const committee = JSON.parse(fs.readFileSync(args[0], 'utf8'));
  state.groupKey = committee.groupKey;
  state.committee = committee.members;
  state.sharePublicKeys = committee.sharePublicKeys;
  state.verification = VERIFICATION;
  save();
  const r = await send(state.beacon, 'Configure', { data: JSON.stringify({
    self: state.beacon, token: state.token, unit: 1000000, threshold: committee.t, cadenceMs: 5000,
    groupKey: committee.groupKey, committee: committee.members,
    sharePublicKeys: committee.sharePublicKeys, verification: VERIFICATION,
  }) });
  console.log(r.output);
}

if (cmd === 'fund') {
  const rng = Number(args[0] || 10);
  const forWho = args[1] || me;
  console.log('faucet', (await send(state.token, 'Faucet')).output);
  console.log('transfer', (await send(state.token, 'Transfer', {
    tags: { Recipient: state.beacon, Quantity: String(rng * 1000000), 'X-For': forWho },
  })).output);
  console.log('balance', (await send(state.beacon, 'Balance', { tags: { Account: forWho } })).output);
}

if (cmd === 'enqueue') {
  const id = args[0] || `req-${Date.now()}`;
  const requested = await enqueueRequest(id);
  console.log(requested.output);
}

if (cmd === 'request') {
  const id = args[0] || `req-${Date.now()}`;
  const requested = await enqueueRequest(id);
  console.log('request', requested.output);
  const target = requested.accepted.round;
  let finalized = null;
  for (let i = 0; i < 60; i++) {
    const info = await beaconInfo();
    if (info.round >= target) {
      finalized = { info, seconds: i };
      break;
    }
    await new Promise((r) => setTimeout(r, 1000));
  }
  if (!finalized) throw new Error(`round ${target} did not finalize within 60 seconds`);
  await verifyRound(target);
  console.log(`round ${target} finalized and verified after ~${finalized.seconds}s`, JSON.stringify(finalized.info));
}

if (cmd === 'verify') {
  const round = Number(args[0] || (await beaconInfo()).round);
  if (!Number.isSafeInteger(round) || round < 1) throw new Error('verify needs a positive round');
  console.log(JSON.stringify(await verifyRound(round), null, 1));
}

if (cmd === 'spawn-anyhonest') {
  // `--replace <reason>` retires the recorded beacon first; its bonds and
  // reserve stay on it. Validators, funding and the console then move over.
  const replace = args.indexOf('--replace');
  if (state.anyHonest && replace >= 0) {
    (state.retired ||= []).push({ anyHonest: state.anyHonest, reason: args[replace + 1] || 'replaced',
      at: new Date().toISOString() });
    delete state.anyHonest;
    save();
  }
  if (state.anyHonest) throw new Error(`Any-Honest beacon already deployed (${state.anyHonest})`);
  // lua-patch@1.0 unless `--lua53a`; the scheduler is this node.
  const legacy = args.includes('--lua53a');
  const scheduler = await nodeAddress(NODE);
  state.anyHonest = await spawnProcess({ node: NODE, jwk, scheduler, name: 'RNG-Any-Honest-Beacon',
    executionDevice: legacy ? 'lua@5.3a' : 'lua-patch@1.0',
    lua: legacy ? anyHonestSource() : anyHonestPatchSource(me, scheduler) });
  state.anyHonestDevice = legacy ? 'lua@5.3a' : 'lua-patch@1.0';
  save();
  console.log('any-honest', state.anyHonest);
  console.log('info', (await send(state.anyHonest, 'Get-Info')).output);
}

if (cmd === 'configure-anyhonest') {
  if (!state.anyHonest || !state.token) throw new Error('spawn the token and Any-Honest beacon first');
  const validators = JSON.parse(fs.readFileSync(args[0], 'utf8'));
  if (!Array.isArray(validators) || validators.length < 2) throw new Error('validators.json must contain at least two addresses');
  const table = JSON.parse(read('deploy/anyhonest-h.json'));
  const T = 134217728;
  const puzzle = table[String(T)];
  const configured = await send(state.anyHonest, 'Configure', { data: JSON.stringify({
    self: state.anyHonest, token: state.token, unit: 1000000,
    T, h: puzzle.h, hProof: puzzle.hProof,
    // Validators run in-node (rng-validator@1.0) and push their slots: every
    // commit lands within ~0.7 s, so a 1 s window and 0.5 s cadence. Reveals
    // keep 30 s for a busy node.
    commitWindowMs: 1000, revealWindowMs: 30000,
    abandonAfterMs: 1800000, minCommits: 2, cadenceMs: 500,
    // The beacon this one replaces: validator devices follow its successor.
    ...(state.retired?.at(-1)?.anyHonest ? { predecessor: state.retired.at(-1).anyHonest } : {}),
    heartbeat: 1, roundPrice: 3, requestPrice: 4,
    subscriptionPrice: 1, subscriptionRounds: 1000, crackBounty: 10,
    suspendAfter: 3, slash: 1000, rejoinAfter: 0,
  }) });
  console.log('configure', configured.output);
  for (const address of validators) {
    console.log('validator', address, (await send(state.anyHonest, 'Admin.Add-Validator', {
      data: JSON.stringify({ address }),
    })).output);
  }
  state.anyHonestValidators = validators;
  save();
}

if (cmd === 'mint-creator') {
  if (!state.token || !state.owner) throw new Error('token and owner are required');
  const atoms = '1000000000000000';
  console.log((await send(state.token, 'Admin.Mint', {
    tags: { Recipient: state.owner, Quantity: atoms },
  })).output);
}

if (cmd === 'fund-anyhonest') {
  if (!state.anyHonest || !state.token) throw new Error('token and Any-Honest beacon are required');
  const foundation = Number(args[0] || 100000000);
  const treasury = Number(args[1] || 1000000);
  for (const [amount, tag] of [[foundation, 'X-Foundation'], [treasury, 'X-Treasury']]) {
    if (!Number.isSafeInteger(amount) || amount < 1) throw new Error(`invalid ${tag} amount`);
    console.log(tag, (await send(state.token, 'Transfer', {
      tags: { Recipient: state.anyHonest, Quantity: String(amount * 1000000),
        'X-For': state.owner, [tag]: 'true' },
    })).output);
  }
  for (const address of state.anyHonestValidators || []) {
    console.log('bond', address, (await send(state.token, 'Transfer', {
      tags: { Recipient: state.anyHonest, Quantity: String(25000 * 1000000),
        'X-For': address, 'X-Bond': 'true' },
    })).output);
  }
  console.log(JSON.stringify(await anyHonestInfo(), null, 1));
}

// Re-bond validators a slashing run emptied (bond below the slash, so they
// cannot rejoin): `bond-anyhonest [units] [address...]`, default every
// recorded validator whose bond is under one slash.
if (cmd === 'bond-anyhonest') {
  if (!state.anyHonest || !state.token) throw new Error('token and Any-Honest beacon are required');
  const units = Number(args[0] || 25000);
  if (!Number.isSafeInteger(units) || units < 1) throw new Error('invalid bond amount');
  const info = await anyHonestInfo();
  const targets = args.length > 1 ? args.slice(1)
    : (info.validators || []).filter((v) => Number(v.bond) < Number(info.params.slash)).map((v) => v.address);
  for (const address of targets) {
    console.log('bond', address, (await send(state.token, 'Transfer', {
      tags: { Recipient: state.anyHonest, Quantity: String(units * 1000000),
        'X-For': address, 'X-Bond': 'true' },
    })).output);
  }
  console.log(JSON.stringify((await anyHonestInfo()).validators, null, 1));
}

// Owner brings suspended validators back (strikes cleared, bond kept):
// `reinstate-anyhonest [address...]`, default every suspended one.
if (cmd === 'reinstate-anyhonest') {
  if (!state.anyHonest) throw new Error('Any-Honest beacon is required');
  const info = await anyHonestInfo();
  const targets = args.length ? args : (info.validators || []).filter((v) => v.suspended).map((v) => v.address);
  for (const address of targets) {
    console.log('reinstate', address, (await send(state.anyHonest, 'Admin.Reinstate', { data: JSON.stringify({ address }) })).output);
  }
  console.log(JSON.stringify((await anyHonestInfo()).validators, null, 1));
}

if (cmd === 'spawn-dao') {
  if (state.dao) throw new Error(`DAO already deployed (${state.dao})`);
  state.dao = await spawnProcess({ node: NODE, jwk, lua: daoSource(), name: 'RNG-DAO-Advisory' });
  save();
  console.log('dao', state.dao);
  console.log('configure', (await send(state.dao, 'Configure', { data: JSON.stringify({
    self: state.dao, token: state.token, unit: 1000000,
    votingPeriodMs: 604800000, quorumBps: 2000, minProposalStake: 1000,
  }) })).output);
  console.log('info', (await send(state.dao, 'Info')).output);
}

if (cmd === 'stake-dao') {
  if (!state.dao) throw new Error('spawn the DAO first');
  const amount = Number(args[0] || 10000);
  if (!Number.isSafeInteger(amount) || amount < 1) throw new Error('stake must be a positive whole RNG amount');
  console.log((await send(state.token, 'Transfer', { tags: {
    Recipient: state.dao, Quantity: String(amount * 1000000),
    'X-For': me, 'X-Governance': 'true',
  } })).output);
}

if (cmd === 'propose-dao') {
  if (!state.dao) throw new Error('spawn the DAO first');
  const proposal = JSON.parse(fs.readFileSync(args[0], 'utf8'));
  console.log((await send(state.dao, 'Propose', { data: JSON.stringify(proposal) })).output);
}

if (cmd === 'vote-dao') {
  if (!state.dao) throw new Error('spawn the DAO first');
  const id = Number(args[0]);
  const choice = args[1];
  if (!Number.isSafeInteger(id) || !['yes', 'no', 'abstain'].includes(choice)) throw new Error('vote-dao needs an id and yes, no, or abstain');
  console.log((await send(state.dao, 'Vote', { data: JSON.stringify({ id, choice }) })).output);
}

if (cmd === 'info-dao') {
  const r = await readState({ node: NODE, process: state.dao, path: 'now/daostate' });
  console.log(r.value);
}

if (cmd === 'test-subscription') {
  if (!state.anyHonest || !state.token) throw new Error('token and Any-Honest beacon are required');
  const id = `acceptance-${Date.now()}`;
  const consumer = await spawnProcess({ node: NODE, jwk,
    lua: subscriptionConsumerSource(state.anyHonest, id), name: 'RNG-Subscription-Acceptance' });
  state.subscriptionAcceptance = { consumer, id, testedAt: Date.now() };
  save();
  await send(state.token, 'Faucet');
  await send(state.token, 'Transfer', { tags: {
    Recipient: state.anyHonest, Quantity: '1000000', 'X-For': consumer,
  } });
  await send(consumer, 'Start');
  let receipt = null;
  for (let attempt = 0; attempt < 30; attempt++) {
    const r = await readState({ node: NODE, process: consumer, path: 'now/subscriptionstate' });
    if (r.status === 200) {
      const candidate = JSON.parse(r.value);
      if (Number(candidate.receipts) > 0) { receipt = candidate; break; }
    }
    await new Promise((resolve) => setTimeout(resolve, 1000));
  }
  if (!receipt) throw new Error('subscription did not deliver within 30 seconds');
  const published = await readState({ node: NODE, process: state.anyHonest, path: 'now/timelockstate' });
  const beaconState = JSON.parse(published.value);
  const round = beaconState.rounds[String(receipt.lastRound)];
  if (!round) throw new Error(`subscription round ${receipt.lastRound} is not retained`);
  const expected = createHash('sha256').update(
    `hyperbeam/rng/subscription/v1|${round.value}|${id}|${receipt.lastRound}`,
  ).digest('hex');
  if (receipt.lastValue !== expected) throw new Error('subscription value failed independent verification');
  console.log(JSON.stringify({ consumer, id, receipts: receipt.receipts,
    round: receipt.lastRound, value: receipt.lastValue, verified: true }, null, 2));
}

if (cmd === 'info') console.log(JSON.stringify(await beaconInfo(), null, 1));
if (cmd === 'info-anyhonest') console.log(JSON.stringify(await anyHonestInfo(), null, 1));
