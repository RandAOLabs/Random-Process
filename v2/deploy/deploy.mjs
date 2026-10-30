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
//
// Env: HB_NODE (HyperBEAM endpoint), HB_WALLET (owner/deployer wallet).
// State: deploy/testnet.json.
import fs from 'node:fs';
import path from 'node:path';
import { createHash } from 'node:crypto';
import { fileURLToPath } from 'node:url';
import {
  spawnProcess, sendMessage, readState, jwkToAddress, awaitComputedSlot, pendingPushes,
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
const STATE = path.join(HERE, 'testnet.json');
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

if (cmd === 'info') console.log(JSON.stringify(await beaconInfo(), null, 1));
