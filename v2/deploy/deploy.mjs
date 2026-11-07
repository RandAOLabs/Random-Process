// Deploy and drive Any-Honest v3: fixed-supply RNG, the RNG DAO (YapDAO
// stake-dao/1), the permissionless beacon and fair play. docs/PERMISSIONLESS.md.
//
// v3 (state: RNG_STATE, default deploy/v3-testnet.json):
//   spawn-token <allocations.json>          RNG with GenesisAllocations (sealed after slot 1)
//   spawn-dao [--lua53b]                    the RNG DAO, stake-dao/1 staking RNG (needs PARALITH_MONO)
//   spawn-beacon [--lua53a]                 the v3 beacon (lua-patch@1.0 by default)
//   genesis-configure [params.json]         deployer Gov.Configure naming the token (locks token/unit/self/predecessor)
//   fund-reserve <rng> | fund-treasury <rng>  deployer Transfer with X-Foundation / X-Treasury
//   fund <rng> [for]                        a beacon balance (X-For)
//   spawn-fair | configure-fair [windowMs]  fair play (token, beacon requestPrice from v3-params.json)
//   fund-fair <rng>                         the fair process's beacon float (X-For = fair; not spent:
//                                           every bound batch is topped up from the games' balances)
//   fund-game <rng> <game>                  prepay a game's fair-play balance (X-Fair-Game); any game
//   grant <address> <rng>                   plain RNG transfer from the deployer
//   bond-for <rng> <address...|validators.json>  Transfer X-Bond X-For each validator
//   gov <Gov.Action> [Tag=Value ...]        any deployer-path Gov.* (Pause, Resume, Apply, Set-Successor, ...)
//   resend-ack                              Resend-Successor-Ack to the predecessor
//   handover --confirm                      Gov.Handover to the recorded DAO (one way; refused unless the
//                                           beacon's queue is empty and the DAO is a live stake-dao/1).
//                                           There is no guardian: after it only DAO proposals act.
// Fast tier (on-demand 2-of-3 threshold BLS, beacon/beacon.lua; not a heartbeat):
//   spawn-fast                              the fast-tier process (lua@5.3a)
//   genesis-configure-fast [committee.json] deployer Gov.Configure: v3 token, the existing committee
//                                           (deploy/committee.json), fees; locks token/unit/self
//   fund-fast <rng> [for]                   a fast-tier balance (X-For)
//   gov-fast <Gov.Action> [Tag=Value ...]   any deployer-path Gov.* on the fast tier
//   handover-fast --confirm                 Gov.Handover of the fast tier to the recorded DAO (one way)
//   dao-stake <rng> | dao-propose <template.json> [KEY=VALUE ...] | dao-vote <id> <Yes|No|NoWithVeto|Abstain>
//   status | verify                         read and check token, DAO, beacon, fair (verify exits 1 on a failure)
//   test-subscription                       authenticated-push acceptance test against the v3 beacon
//   plan <allocations.json> [params.json]   the whole v3 sequence, dry-run only
//
// Legacy, against the LIVE v2 beacon until cutover (state: RNG_LEGACY_STATE,
// default deploy/native-testnet.json, never written):
//   legacy-info | legacy-tune key=int ... | legacy-reinstate [address ...]
//   legacy-bond [units] [address ...]       old TEST-RNG X-Bond on the v2 beacon
//   legacy-set-successor <old> <new>        Admin.Set-Successor (v2 wallet path)
//   legacy-move-reserve <old>               Admin.Move-Reserve; refused across tokens
//   legacy-request [id] | legacy-verify [round] | legacy-beacon-info   the OLD threshold process (state.beacon
//                                           in native-testnet.json, on the old TEST-RNG); retired at launch
//
// --dry-run (or RNG_DRY_RUN=1) prints every spawn and message as one JSON line
// and sends nothing; it never writes state. RNG_DEPLOYER stands in for the
// wallet's address, RNG_SCHEDULER for the node's.
//
// Env: HB_NODE, HB_WALLET (deployer), RNG_STATE, RNG_LEGACY_STATE, RNG_SCHEDULER
//      (pin; must equal the node's), PARALITH_MONO (for spawn-dao).
import fs from 'node:fs';
import path from 'node:path';
import { createHash } from 'node:crypto';
import { fileURLToPath, pathToFileURL } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const V2 = path.resolve(HERE, '..');
const read = (p) => fs.readFileSync(path.join(V2, p), 'utf8');
const sha256 = (s) => createHash('sha256').update(s).digest('hex');

export const UNIT = 1_000_000;
export const SUPPLY_ATOMS = 1_000_000_000_000_000n; // 10^15: 1,000,000,000 RNG at 6 decimals
const DAY = 86_400_000;
const isPid = (v) => typeof v === 'string' && /^[A-Za-z0-9_-]{43}$/.test(v);
const atomsOf = (rng) => {
  if (!Number.isSafeInteger(Number(rng)) || Number(rng) < 1) throw new Error(`bad RNG amount ${rng}: whole RNG only`);
  return String(BigInt(rng) * BigInt(UNIT));
};

// ---------------------------------------------------------------------------
// Pure builders (tested in test/deployment-config.test.mjs)
// ---------------------------------------------------------------------------

/** Allocations file -> { table: { addr: atoms(BigInt) }, rows, ticker, reserveRng, treasuryRng, validatorRng }.
 * `$DEPLOYER` is the deployer's address; repeated addresses are summed.
 * `distribution` is what the runbook transfers on from the genesis holder
 * (reserve and treasury go under DAO control in the beacon; validatorRng is
 * each launch validator's grant, bonded whole). */
export function loadAllocations(spec, { deployer } = {}) {
  if (!spec || !Array.isArray(spec.allocations) || !spec.allocations.length) throw new Error('allocations[] is required');
  const table = {};
  const rows = [];
  let sum = 0n;
  const byRole = {};
  for (const row of spec.allocations) {
    const address = row.address === '$DEPLOYER' ? deployer : row.address;
    if (!isPid(address)) throw new Error(`allocation ${row.role || '?'}: invalid address ${address}`);
    let atoms;
    if (row.atoms !== undefined) {
      if (!/^[1-9][0-9]*$/.test(String(row.atoms))) throw new Error(`allocation ${row.role}: atoms must be a positive integer`);
      atoms = BigInt(row.atoms);
    } else {
      if (!Number.isSafeInteger(row.rng) || row.rng < 1) throw new Error(`allocation ${row.role}: rng must be a positive whole number`);
      atoms = BigInt(row.rng) * BigInt(UNIT);
    }
    sum += atoms;
    table[address] = (table[address] || 0n) + atoms;
    rows.push({ role: row.role, address, atoms: String(atoms), forward: row.forward });
    if (row.role) byRole[row.role] = (byRole[row.role] || 0n) + atoms;
  }
  if (sum !== SUPPLY_ATOMS) throw new Error(`allocations sum to ${sum} atoms, not exactly ${SUPPLY_ATOMS}`);
  const rngOf = (role) => (byRole[role] ? Number(byRole[role] / BigInt(UNIT)) : 0);
  const dist = spec.distribution || {};
  const whole = (name) => {
    const v = dist[name];
    if (v === undefined) return 0;
    if (!Number.isSafeInteger(v) || v < 0) throw new Error(`distribution.${name} must be a whole RNG amount`);
    return v;
  };
  const reserveRng = rngOf('reserve') || whole('reserveRng');
  const treasuryRng = rngOf('treasury') || whole('treasuryRng');
  const validatorRng = whole('validatorRng');
  if (BigInt(reserveRng + treasuryRng) * BigInt(UNIT) > SUPPLY_ATOMS) throw new Error('distribution exceeds the supply');
  return { table, rows, ticker: spec.ticker || 'RNG', reserveRng, treasuryRng, validatorRng };
}

/** The Lua prelude rng-token.lua reads on its first slot. */
export function genesisPrelude({ table, ticker }) {
  const entries = Object.keys(table).sort().map((a) => `  [${JSON.stringify(a)}] = ${table[a]},`);
  return [
    `GenesisAllocations = {`, ...entries, `}`,
    ...(ticker && ticker !== 'RNG' ? [`TokenTicker = ${JSON.stringify(ticker)}`] : []),
  ].join('\n');
}

/** The beacon's hard bounds (anyhonest.lua badParams), checked before sending. */
export function badParams(p) {
  const bad = [];
  const need = (ok, why) => { if (!ok) bad.push(why); };
  for (const [k, v] of Object.entries(p)) need(Number.isSafeInteger(v), `${k} must be an integer`);
  need(p.T >= 134217728 && p.T <= 4294967296, 'T in [2^27, 2^32]');
  need(p.revealWindowMs >= 10000 && p.revealWindowMs <= 600000, 'revealWindowMs in [10s, 600s]');
  need(p.commitWindowMs >= 500 && p.commitWindowMs <= 10000, 'commitWindowMs in [500, 10000]');
  need(p.abandonAfterMs >= p.revealWindowMs && p.abandonAfterMs <= 7 * DAY, 'revealWindowMs <= abandonAfterMs <= 7 d');
  need(p.slash >= 1 && p.slash * 10 <= p.stake && p.stake <= 10000000, '1 <= slash <= stake / 10, stake <= 10^7');
  need(p.rejoinBaseMs >= p.revealWindowMs && p.rejoinCapMs >= p.rejoinBaseMs && p.rejoinCapMs <= 30 * DAY,
    'revealWindowMs <= rejoinBaseMs <= rejoinCapMs <= 30 d');
  need(p.minCommits >= 2 && p.minCommits <= p.maxActive && p.maxActive <= 128, '2 <= minCommits <= maxActive <= 128');
  need(p.maxValidators >= p.maxActive && p.maxValidators <= 1024, 'maxActive <= maxValidators <= 1024');
  need(p.heartbeat === 0 || p.heartbeat === 1, 'heartbeat 0 or 1');
  need(p.roundPrice >= 1 && p.requestPrice >= 1 && p.subscriptionPrice >= 1 && p.crackBounty >= 1, 'prices and bounty >= 1');
  need(p.subscriptionRounds >= 1 && p.subscriptionRounds <= 31536000, 'subscriptionRounds in [1, 31536000]');
  need(p.cadenceMs >= 0 && p.cadenceMs <= 60000 && p.targetIntervalMs >= 0 && p.targetIntervalMs <= 600000
    && p.maxInFlight >= 1 && p.maxInFlight <= 8 && p.catchUpMs >= 0, 'rhythm parameters (cadence <= 60 s, interval <= 10 min, maxInFlight <= 8)');
  need(p.crackBounty <= p.slash, 'crackBounty <= slash');
  need(2 * (1 + p.maxInFlight) * (p.slash + p.crackBounty) <= p.stake, 'one incident ((1 + maxInFlight) x (slash + crackBounty)) <= stake / 2');
  need(p.fairWindowMs >= 1, 'fairWindowMs >= 1');
  return bad;
}

/** Data of the deployer's genesis Gov.Configure. */
export function genesisConfig({ beacon, token, params, hTable }) {
  const { predecessor = '', T, ...rest } = params;
  const puzzle = hTable[String(T)];
  if (!puzzle) throw new Error(`deploy/anyhonest-h.json has no h for T=${T}`);
  if (!isPid(beacon) || !isPid(token)) throw new Error('genesis needs the beacon and token ids');
  if (predecessor !== '' && !isPid(predecessor)) throw new Error('predecessor must be a process id or ""');
  const p = { T, ...rest };
  const bad = badParams(p);
  if (bad.length) throw new Error(`params outside the beacon's hard bounds: ${bad.join('; ')}`);
  return { self: beacon, token, unit: UNIT, predecessor, ...p, h: puzzle.h, hProof: puzzle.hProof };
}

/** The RNG DAO's definition (DAO.md rules; PERMISSIONLESS.md "YapDAO instance"). */
export function daoRules({ token, ticker = 'RNG' }) {
  return {
    'Dao-Name': ticker.startsWith('TEST-') ? 'TEST-RNG DAO' : 'RNG DAO',
    'Dao-Token': token,
    'Dao-Ticker': ticker,
    'Dao-Denomination': '6',
    'Proposal-Threshold': String(25_000 * UNIT),
    'Proposal-Deposit': String(5_000 * UNIT),
    'Voting-Period': String(7 * DAY),
    'Quorum-Bps': '1000',
    'Pass-Bps': '5000',
    'Veto-Bps': '3334',
    'Unstake-Delay': String(14 * DAY),
    'Max-Active-Proposals': '20',
    'Max-Proposals-Per-Proposer': '1',
  };
}

/** Recorded processes that must share the deployment's one scheduler (D3). */
export function sameScheduler(state, roles) {
  if (!isPid(state.scheduler) && !String(state.scheduler || '').startsWith('DRY')) throw new Error('no scheduler pinned');
  for (const role of roles) {
    const pid = state[role];
    if (!pid) throw new Error(`${role} is not deployed`);
    const rec = state.processes?.[pid];
    if (!rec) throw new Error(`${role} ${pid} has no spawn record`);
    if (rec.scheduler !== state.scheduler) {
      throw new Error(`${role} ${pid} is on scheduler ${rec.scheduler}, not ${state.scheduler}: from-process would not be believed`);
    }
  }
  return true;
}

// YapDAO dao.lua Exec-Tags rules (readAction, EXEC_* caps, EXEC_RESERVED).
const word = (s) => String(s).toLowerCase().replace(/[-_\s]/g, '');
const EXEC_RESERVED = new Set(['target', 'fromprocess', 'from', 'owner', 'signature', 'signatures', 'commitments',
  'committer', 'id', 'anchor', 'data', 'body', 'device', 'path', 'method', 'status', 'scheduler', 'schedulerlocation',
  'process', 'priv', 'type', 'variant', 'dataprotocol', 'pushedfor', 'fromscheduler', 'hashpath', 'slot', 'timestamp',
  'blockheight', 'contenttype', 'contentdigest', 'aotypes', 'aoresult', 'codecdevice', 'bundle',
  'xtransfersequence', 'xreference', 'cast']);
const GOV_TAGS = {
  'Gov.Configure': null, // checked against CONFIGURE_TAGS
  'Gov.Set-Successor': ['Successor'], 'Gov.Move-Reserve': ['Successor'], 'Gov.Treasury-Spend': ['Recipient', 'Quantity'],
  'Gov.Fund-Reserve': ['Quantity'], 'Gov.Remove-Validator': ['Validator'], 'Gov.Pause': [], 'Gov.Resume': [],
  'Gov.Cancel': ['Gov-Id'], 'Gov.Apply': ['Gov-Id'],
};
// The fast tier's Gov.* (beacon/beacon.lua): fees at once, committee timelocked.
const FAST_GOV_TAGS = {
  'Gov.Configure': ['Signer-Fee', 'Protocol-Fee', 'Committee', 'Share-Public-Keys', 'Group-Key', 'Threshold', 'Verification'],
  'Gov.Claim-Protocol': ['Recipient'], 'Gov.Pause': [], 'Gov.Resume': [], 'Gov.Cancel': ['Gov-Id'], 'Gov.Apply': ['Gov-Id'],
};
const CONFIGURE_TAGS = ['T', 'H', 'H-Proof', 'Commit-Window-Ms', 'Reveal-Window-Ms', 'Abandon-After-Ms', 'Min-Commits',
  'Max-Active', 'Max-Validators', 'Cadence-Ms', 'Target-Interval-Ms', 'Max-In-Flight', 'Catch-Up-Ms', 'Stake', 'Slash',
  'Rejoin-Base-Ms', 'Rejoin-Cap-Ms', 'Heartbeat', 'Round-Price', 'Request-Price', 'Subscription-Price',
  'Subscription-Rounds', 'Crack-Bounty', 'Fair-Window-Ms'].map(word);

/** Fill a proposal template's $BEACON/$FAST/$DAO/$TOKEN/$FAIR/$KEY placeholders. */
export function fillTemplate(template, vars) {
  const sub = (v) => String(v).replace(/\$([A-Z_]+)/g, (m, k) => (vars[k] !== undefined ? String(vars[k]) : m));
  return {
    ...template,
    execProcess: sub(template.execProcess),
    execTags: Object.fromEntries(Object.entries(template.execTags || {}).map(([k, v]) => [k, sub(v)])),
  };
}

/** Errors a (filled) proposal would hit at the DAO's Propose, or at the beacon
 * (or the fast tier, when `fast` names it and the proposal targets it). */
export function proposalErrors(p, { token, fast } = {}) {
  const errs = [];
  if (typeof p.title !== 'string' || !p.title || p.title.length > 120) errs.push('title must be 1-120 characters');
  if (typeof p.body !== 'string' || p.body.length > 4000) errs.push('body must be at most 4000 characters');
  if (!isPid(p.execProcess)) errs.push('execProcess must be a 43-character process id');
  if (token && p.execProcess === token) errs.push('execProcess cannot be the staked token');
  const tags = p.execTags || {};
  const names = Object.keys(tags);
  if (!names.length) errs.push('execTags names no tags');
  if (names.length > 16) errs.push('execTags has more than 16 tags');
  if (JSON.stringify(tags).length > 2048) errs.push('execTags is longer than 2048 bytes');
  const seen = new Set();
  for (const name of names) {
    const v = tags[name];
    if (!/^[A-Za-z0-9_-]{1,64}$/.test(name)) errs.push(`tag ${name}: letters, digits, - or _ (<= 64)`);
    if (EXEC_RESERVED.has(word(name)) || word(name).startsWith('commitment') || word(name).startsWith('xdao')) errs.push(`tag ${name} is reserved by the DAO`);
    if (seen.has(word(name))) errs.push(`tag ${name} twice`);
    seen.add(word(name));
    if (typeof v !== 'string' || !v || v.length > 512 || /[\x00-\x1f\x7f]/.test(v)) errs.push(`tag ${name}: non-empty string <= 512, no control characters`);
  }
  const action = tags.Action;
  const toFast = Boolean(fast) && p.execProcess === fast;
  const table = toFast ? FAST_GOV_TAGS : GOV_TAGS;
  if (!(action in table)) errs.push(`Action ${action} is not a ${toFast ? 'fast-tier' : 'beacon'} Gov.* action the DAO may send`);
  else {
    const allowed = new Set(['action', ...(table[action] || CONFIGURE_TAGS).map(word)]);
    for (const name of names) if (!allowed.has(word(name))) errs.push(`${action} does not read tag ${name}`);
    if (action === 'Gov.Configure' && names.length > 15) errs.push('Gov.Configure takes at most 14 parameters');
  }
  return errs;
}

/** The beacon's shortest governance delay (anyhonest.lua GOV_DELAY_MS): the DAO's
 * voting period must be shorter, so a Gov.Cancel can pass before an action lands. */
export const BEACON_GOV_DELAY_MS = 10 * DAY;

/** Why Gov.Handover must not be sent yet (empty: go). The governor must be a
 * live stake-dao/1 process on our token (a wallet publishes no daoinfo), and
 * the beacon must have nothing queued: the deployer's queue would land under
 * the DAO's name. */
export function handoverErrors({ state, beaconinfo, daoinfo, me }) {
  const errs = [];
  if (!isPid(state.dao)) errs.push('no DAO recorded: spawn-dao first');
  if (state.dao && state.dao === me) errs.push('the governor is the deployer wallet');
  if (!beaconinfo) errs.push(`beacon ${state.beacon} publishes no beaconinfo`);
  else {
    if (beaconinfo.token !== state.token) errs.push('beacon has not run genesis-configure');
    if (beaconinfo.governor) errs.push(`beacon is already governed by ${beaconinfo.governor}`);
    const queued = Array.isArray(beaconinfo.govQueue) ? beaconinfo.govQueue.length : 0;
    if (queued) errs.push(`beacon has ${queued} queued governance action(s): Gov.Cancel them first`);
  }
  if (!daoinfo) errs.push(`governor ${state.dao} publishes no daoinfo: not a live DAO process (a wallet?)`);
  else {
    if (daoinfo.Standard !== 'stake-dao/1') errs.push(`governor is ${daoinfo.Standard}, not stake-dao/1`);
    if (daoinfo.Configured !== true || daoinfo.Token !== state.token) errs.push('governor is not a DAO configured on our token');
    if (daoinfo.Admin !== '') errs.push('governor DAO has an admin');
    if (!(Number(daoinfo.VotingPeriod) < BEACON_GOV_DELAY_MS)) errs.push('DAO voting period is not shorter than the beacon governance delay');
  }
  return errs;
}

/** Why a transfer to the beacon (or the fast tier: role 'fast') would strand
 * (null: go): before genesis it refuses every Credit-Notice. */
export function fundError({ state, beaconinfo, role = 'beacon' }) {
  if (!beaconinfo || !state.token || beaconinfo.token !== state.token) {
    const step = role === 'fast' ? 'genesis-configure-fast' : 'genesis-configure';
    return `${role} ${state[role]} has not run ${step} (beaconinfo.token unset): a transfer now would strand`;
  }
  return null;
}

/** Data of the deployer's genesis Gov.Configure for the fast tier: the
 * existing DKG committee (deploy/committee.json), the v3 token, fees. */
export function fastGenesisConfig({ fast, token, committee, signerFee = 1, protocolFee = 1 }) {
  if (!isPid(fast) || !isPid(token)) throw new Error('fast genesis needs the fast-tier and token ids');
  const { t, groupKey, members, sharePublicKeys } = committee || {};
  const hex96 = (k) => typeof k === 'string' && /^[0-9a-fA-F]{96}$/.test(k);
  if (!Array.isArray(members) || !members.length || !members.every(isPid) || new Set(members).size !== members.length) {
    throw new Error('committee.members must be distinct addresses');
  }
  if (!Number.isSafeInteger(t) || t < 2 || t > members.length) throw new Error('committee.t must be in [2, members]');
  if (!hex96(groupKey)) throw new Error('committee.groupKey must be 96 hex characters');
  if (!Array.isArray(sharePublicKeys) || sharePublicKeys.length !== members.length || !sharePublicKeys.every(hex96)) {
    throw new Error('committee.sharePublicKeys must give one 96-hex key per member');
  }
  return { self: fast, token, unit: UNIT, committee: members, sharePublicKeys, groupKey, threshold: t,
    verification: 'attestations', signerFee, protocolFee };
}

/** Live checks over the published keys; each { check, ok, detail }. */
export function checkV3({ state, tokeninfo, daoinfo, beaconinfo, fairinfo, fastinfo }) {
  const out = [];
  const c = (check, ok, detail = '') => out.push({ check, ok: !!ok, detail });
  if (state.token) {
    c('token sealed', tokeninfo?.Sealed === 'true' || tokeninfo?.Sealed === true, tokeninfo?.Sealed);
    c('token supply 10^15', String(tokeninfo?.TotalSupply) === String(SUPPLY_ATOMS), tokeninfo?.TotalSupply);
    c('token sequenced-v1', tokeninfo?.ProcessTransferProtocol === 'sequenced-v1', tokeninfo?.ProcessTransferProtocol);
  }
  if (state.dao) {
    c('dao configured on RNG', daoinfo?.Configured === true && daoinfo?.Token === state.token, daoinfo?.Token);
    c('dao has no admin', daoinfo?.Admin === '', daoinfo?.Admin);
  }
  if (state.beacon) {
    c('beacon token', beaconinfo?.token === state.token, beaconinfo?.token);
    c('beacon self', beaconinfo?.self === state.beacon, beaconinfo?.self);
    if (state.predecessor !== undefined) c('beacon predecessor', (beaconinfo?.predecessor || '') === state.predecessor, beaconinfo?.predecessor);
    c('beacon health ok', beaconinfo?.health?.status === 'ok', JSON.stringify(beaconinfo?.health));
    c('beacon reserve funded', BigInt(beaconinfo?.foundationReserveAtoms || 0) > 0n, beaconinfo?.foundationReserveAtoms);
    if (state.governor) c('beacon governed by the DAO', beaconinfo?.governor === state.dao, beaconinfo?.governor);
  }
  if (state.fast) {
    c('fast token', fastinfo?.token === state.token, fastinfo?.token);
    c('fast self', fastinfo?.self === state.fast, fastinfo?.self);
    c('fast on demand', fastinfo?.tier === 'fast' && fastinfo?.nextRoundAt === 0, fastinfo?.mode);
    c('fast committee', Array.isArray(fastinfo?.committee) && fastinfo.committee.length >= fastinfo.threshold
      && fastinfo.threshold >= 2, `${fastinfo?.threshold}/${fastinfo?.committee?.length}`);
    if (state.fastGovernor) c('fast governed by the DAO', fastinfo?.governor === state.dao, fastinfo?.governor);
  }
  if (state.fair) {
    c('fair bound to beacon', fairinfo?.beacon === state.beacon, fairinfo?.beacon);
    c('fair paid in RNG', fairinfo?.token === state.token && Number(fairinfo?.requestPriceAtoms) > 0, fairinfo?.token);
  }
  try { sameScheduler(state, ['token', 'dao', 'beacon', 'fair', 'fast'].filter((r) => state[r])); c('one scheduler', true, state.scheduler); }
  catch (e) { c('one scheduler', false, e.message); }
  return out;
}

// ---------------------------------------------------------------------------
// Sources
// ---------------------------------------------------------------------------

const json = () => [
  read('vendor/json.lua'),
  'local jsonx = (function()', read('vendor/jsonenc.lua'), 'end)()',
  'local encode, jsonObject = jsonx.encode, jsonx.object',
];
export const tokenSource = (prelude) => [prelude, ...json(), read('token/rng-token.lua')].join('\n');
const anyHonestSource = () => [...json(), 'rng = (function()', read('lib/rng.lua'), 'end)()', read('beacon/anyhonest.lua')].join('\n');
// lua-patch@1.0 (paralith-mono's lua53b.lua adapter): only changed keys are
// published and the VM keeps state between messages. The adapter's compute
// calls the beacon's, so the beacon's final full collect moves out to it; the
// bootstrap gives the owner and scheduler facts lua@5.3a reads from `base.process`.
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
const fairSource = () => [
  read('vendor/json.lua'),
  'local jsonx = (function()', read('vendor/jsonenc.lua'), 'end)()',
  'encode, jsonObject = jsonx.encode, jsonx.object',
  'json = require(".json")',
  'rng = (function()', read('lib/rng.lua'), 'end)()',
  'fair = (function()', read('lib/fair.lua'), 'end)()',
  read('fair/fair.lua'),
].join('\n');
// The fast tier: on-demand threshold BLS (lua@5.3a, whole state per message).
const fastSource = () => [...json(), 'rng = (function()', read('lib/rng.lua'), 'end)()', read('beacon/beacon.lua')].join('\n');
const subscriptionConsumerSource = (beacon, id) => [...json(), read('test/subscription-consumer.lua')]
  .join('\n').replaceAll('__BEACON__', beacon).replaceAll('__SUBSCRIPTION_ID__', id);

// ---------------------------------------------------------------------------
// CLI
// ---------------------------------------------------------------------------

async function main(argv) {
  const DRY = argv.includes('--dry-run') || process.env.RNG_DRY_RUN === '1';
  const args = argv.filter((a) => a !== '--dry-run');
  const [cmd, ...rest] = args;
  const flag = (name) => rest.includes(name);
  const pos = rest.filter((a) => !a.startsWith('--'));
  const legacy = cmd?.startsWith('legacy-');
  const hb = DRY ? null : await import('../vendor/hbclient.mjs');

  const NODE = process.env.HB_NODE;
  if (!NODE && !DRY) throw new Error('HB_NODE is required');
  let jwk = null;
  if (process.env.HB_WALLET) jwk = JSON.parse(fs.readFileSync(process.env.HB_WALLET, 'utf8'));
  else if (!DRY) throw new Error('HB_WALLET is required');
  const me = jwk ? (hb || await import('../vendor/hbclient.mjs')).jwkToAddress(jwk) : process.env.RNG_DEPLOYER;
  if (!isPid(me)) throw new Error('set HB_WALLET (or RNG_DEPLOYER in --dry-run)');

  const STATE = legacy
    ? path.resolve(process.env.RNG_LEGACY_STATE || path.join(HERE, 'native-testnet.json'))
    : path.resolve(process.env.RNG_STATE || path.join(HERE, 'v3-testnet.json'));
  const state = cmd === 'plan' || !fs.existsSync(STATE) ? {} : JSON.parse(fs.readFileSync(STATE, 'utf8'));
  state.processes ||= {};
  const save = () => {
    if (DRY || legacy) return;
    fs.writeFileSync(STATE, JSON.stringify(state, null, 2) + '\n');
  };
  const log = (o) => console.log(JSON.stringify(DRY ? { dryRun: true, ...o } : o));
  const placeholder = (role) => `DRY${role}`.replace(/[^A-Za-z0-9]/g, '').padEnd(43, '_').slice(0, 43);

  async function pinScheduler() {
    const env = process.env.RNG_SCHEDULER;
    const actual = DRY ? (env || placeholder('scheduler')) : await hb.nodeAddress(NODE);
    if (env && env !== actual) throw new Error(`RNG_SCHEDULER ${env} is not this node's address ${actual}`);
    if (state.scheduler && state.scheduler !== actual) throw new Error(`this deployment is pinned to scheduler ${state.scheduler}, the node is ${actual}`);
    state.scheduler = actual;
    return actual;
  }

  async function spawn(role, { name, lua, executionDevice = 'lua@5.3a', extra = {} }) {
    const scheduler = await pinScheduler();
    const rec = { role, name, executionDevice, scheduler, sourceBytes: Buffer.byteLength(lua), sourceSha256: sha256(lua) };
    let pid;
    if (DRY) {
      pid = placeholder(role);
      log({ op: 'spawn', pid, ...rec, ...extra });
    } else {
      pid = await hb.spawnProcess({ node: NODE, jwk, lua, scheduler, executionDevice, name });
      log({ op: 'spawn', pid, ...rec });
    }
    state.processes[pid] = { role, scheduler, executionDevice, sourceSha256: rec.sourceSha256, at: new Date().toISOString() };
    state[role] = pid;
    save();
    return pid;
  }

  async function send(pid, action, { tags = {}, data } = {}) {
    if (!isPid(pid)) throw new Error(`${action}: no target process`);
    if (DRY) {
      log({ op: 'send', target: pid, action, tags, ...(data !== undefined ? { data: JSON.parse(data) } : {}) });
      return { slot: null, output: '{"dryRun":true}' };
    }
    const { slot } = await hb.sendMessage({ node: NODE, jwk, process: pid, action, tags, data });
    await hb.awaitComputedSlot({ node: NODE, process: pid, slot });
    const out = await hb.readState({ node: NODE, process: pid, path: `compute&slot=${slot}/results/output/data` });
    await hb.pendingPushes({ node: NODE, process: pid });
    log({ op: 'send', target: pid, action, tags, slot, output: out.value });
    return { slot, output: out.value };
  }

  async function key(pid, k) {
    if (DRY || !isPid(pid)) return null;
    const r = await hb.readState({ node: NODE, process: pid, path: `now/${k}` });
    if (r.status !== 200 || /^\s*</.test(r.value || '')) return null;
    try { return JSON.parse(r.value); } catch { return null; }
  }

  const transfer = (recipient, rng, extraTags = {}) => {
    if (!state.token) throw new Error('spawn-token first');
    return send(state.token, 'Transfer', { tags: { Recipient: recipient, Quantity: atomsOf(rng), ...extraTags } });
  };
  // Every fund-* is refused until the beacon has its token (genesis-configure).
  const fundBeacon = async (rng, tags, role = 'beacon') => {
    if (!DRY) {
      const err = fundError({ state, beaconinfo: await key(state[role], 'beaconinfo'), role });
      if (err) throw new Error(err);
    }
    return transfer(state[role], rng, tags);
  };
  const readJson = (file) => JSON.parse(fs.readFileSync(path.resolve(file), 'utf8'));
  const loadParams = (file) => readJson(file || path.join(HERE, 'v3-params.json'));

  const v3 = {
    async 'spawn-token'(file) {
      if (state.token && !flag('--replace')) throw new Error(`token already deployed (${state.token})`);
      const alloc = loadAllocations(readJson(file || path.join(HERE, 'v3-genesis.json')), { deployer: me });
      const prelude = genesisPrelude(alloc);
      state.deployer = me;
      state.tokenTicker = alloc.ticker;
      state.genesis = { rows: alloc.rows, reserveRng: alloc.reserveRng, treasuryRng: alloc.treasuryRng,
        validatorRng: alloc.validatorRng };
      const pid = await spawn('token', { name: alloc.ticker, lua: tokenSource(prelude), extra: { prelude } });
      await send(pid, 'Info');
      return alloc;
    },

    async 'spawn-dao'() {
      if (state.dao && !flag('--replace')) throw new Error(`DAO already deployed (${state.dao})`);
      sameScheduler(state, ['token']);
      const rules = daoRules({ token: state.token, ticker: state.tokenTicker || 'RNG' });
      const definition = Object.fromEntries(Object.entries(rules).map(([k, v]) => [k.toLowerCase(), v]));
      const device = flag('--lua53b') ? 'lua-patch@1.0' : 'lua@5.3a';
      if (DRY) {
        const pid = placeholder('dao');
        log({ op: 'spawn', pid, role: 'dao', standard: 'stake-dao/1', executionDevice: device, scheduler: state.scheduler,
          vanityPrefix: 'yap', definition });
        state.processes[pid] = { role: 'dao', scheduler: state.scheduler, executionDevice: device };
        state.dao = pid;
        return pid;
      }
      // deploy-dao.mjs semantics, our rules: the module comes from paralith-mono.
      const PM = path.resolve(process.env.PARALITH_MONO || path.join(V2, '..', '..', 'paralith-mono'));
      const imp = (p) => import(pathToFileURL(path.join(PM, p)).href);
      const { daoModuleSources, dao53bModuleSources } = await imp('backend/native/contracts-53b-bundle.mjs');
      const { spawnVanity, throwawayKey } = await imp('packages/rune-ao/src/spawn/node.mjs');
      const ti = await key(state.token, 'tokeninfo');
      if (ti?.ProcessTransferProtocol !== 'sequenced-v1') throw new Error(`token ${state.token} does not publish sequenced-v1`);
      const scheduler = await pinScheduler();
      const spawner = throwawayKey(); // signs the definition and confers nothing
      const lua = device === 'lua-patch@1.0'
        ? dao53bModuleSources({ owner: hb.jwkToAddress(spawner), scheduler, definition })
        : daoModuleSources();
      const { id } = await spawnVanity({ node: hb.transportNode(NODE), jwk: spawner, lua, prefix: 'yap', ignoreCase: true,
        executionDevice: device, scheduler, tags: { name: rules['Dao-Name'], ...definition } });
      state.processes[id] = { role: 'dao', scheduler, executionDevice: device, sourceSha256: sha256(lua), at: new Date().toISOString() };
      state.dao = id;
      state.daoRules = rules;
      save();
      let info = null;
      for (let i = 0; i < 60 && !info; i++) {
        info = await key(id, 'daoinfo');
        if (!info) await new Promise((r) => setTimeout(r, 1000));
      }
      if (!info || info.Configured !== true || info.Token !== state.token || info.Admin !== ''
          || info.ProposalThreshold !== rules['Proposal-Threshold']) {
        throw new Error(`DAO ${id} is not configured for RNG: ${JSON.stringify(info)}`);
      }
      log({ op: 'dao', dao: id, standard: info.Standard, name: info.Name });
      return id;
    },

    async 'spawn-beacon'() {
      if (state.beacon && !flag('--replace')) throw new Error(`beacon already deployed (${state.beacon})`);
      const lua53a = flag('--lua53a');
      const scheduler = await pinScheduler();
      const pid = await spawn('beacon', { name: 'RNG-Any-Honest-Beacon-v3',
        executionDevice: lua53a ? 'lua@5.3a' : 'lua-patch@1.0',
        lua: lua53a ? anyHonestSource() : anyHonestPatchSource(me, scheduler) });
      await send(pid, 'Get-Info');
      return pid;
    },

    async 'genesis-configure'(file) {
      sameScheduler(state, ['token', 'beacon']);
      const params = loadParams(file);
      const data = genesisConfig({ beacon: state.beacon, token: state.token, params,
        hTable: JSON.parse(read('deploy/anyhonest-h.json')) });
      state.predecessor = data.predecessor;
      save();
      return send(state.beacon, 'Gov.Configure', { data: JSON.stringify(data) });
    },

    'fund-reserve': async (rng) => fundBeacon(rng ?? state.genesis?.reserveRng, { 'X-Foundation': 'true' }),
    'fund-treasury': async (rng) => fundBeacon(rng ?? state.genesis?.treasuryRng, { 'X-Treasury': 'true' }),
    fund: async (rng, forWho) => fundBeacon(rng, { 'X-For': forWho || me }),
    grant: (address, rng) => {
      if (!isPid(address)) throw new Error('grant <address> <rng>');
      return transfer(address, rng);
    },

    async 'bond-for'(rng, ...targets) {
      const list = targets.length === 1 && targets[0].endsWith('.json') ? readJson(targets[0]) : targets;
      if (!list.length || !list.every(isPid)) throw new Error('bond-for <rng> <address...|validators.json>');
      for (const address of list) await transfer(state.beacon, rng, { 'X-For': address, 'X-Bond': 'true' });
    },

    async 'spawn-fair'() {
      if (state.fair && !flag('--replace')) throw new Error(`fair already deployed (${state.fair})`);
      const pid = await spawn('fair', { name: 'RNG-Fair-Play', lua: fairSource() });
      await send(pid, 'Get-Info');
      return pid;
    },
    async 'configure-fair'(windowMs) {
      sameScheduler(state, ['beacon', 'fair']);
      // requestPrice must equal the beacon's: a governance change of it is
      // followed by configure-fair again.
      const d = { beacon: state.beacon, token: state.token, requestPrice: loadParams().requestPrice,
        fairWindowMs: Number(windowMs || 60000), keep: 64, maxOpen: 10000 };
      return send(state.fair, 'Fair.Configure', { data: JSON.stringify(d) });
    },
    // The float the fair process requests from; >= 2 requests, since the next
    // batch may go out before the last top-up lands.
    'fund-fair': async (rng) => fundBeacon(rng, { 'X-For': state.fair }),
    // Any game may play: it prepays its own draws here (and Fair.Withdraws the rest).
    async 'fund-game'(rng, game) {
      if (!isPid(game) || !isPid(state.fair)) throw new Error('fund-game <rng> <game> (after spawn-fair)');
      if (!DRY) {
        const info = await key(state.fair, 'fairinfo');
        if (info?.token !== state.token) throw new Error('configure-fair first: the fair process refuses credits until its token is set');
      }
      return transfer(state.fair, rng, { 'X-Fair-Game': game });
    },

    async gov(action, ...kv) {
      if (!/^Gov\.[A-Za-z-]+$/.test(action || '')) throw new Error('gov <Gov.Action> [Tag=Value ...]');
      if (action === 'Gov.Handover') throw new Error('use `handover`');
      const tags = Object.fromEntries(kv.map((a) => a.split(/=(.*)/s).slice(0, 2)));
      return send(state.beacon, action, { tags });
    },
    'resend-ack': () => send(state.beacon, 'Resend-Successor-Ack'),

    // One way, and there is no guardian: after it the DAO acts only through
    // proposals, and every timelock (10 d) outlasts its 7-day vote.
    async handover() {
      if (!flag('--confirm') && !DRY) throw new Error('Gov.Handover is one way: add --confirm');
      sameScheduler(state, ['token', 'dao', 'beacon']);
      if (!DRY) {
        const [beaconinfo, daoinfo] = await Promise.all([key(state.beacon, 'beaconinfo'), key(state.dao, 'daoinfo')]);
        const errs = handoverErrors({ state, beaconinfo, daoinfo, me });
        if (errs.length) throw new Error(`handover refused: ${errs.join('; ')}`);
      }
      const r = await send(state.beacon, 'Gov.Handover', { tags: { Governor: state.dao } });
      state.governor = state.dao;
      save();
      return r;
    },

    // Fast tier: on-demand threshold BLS, paid per request; no heartbeat.
    async 'spawn-fast'() {
      if (state.fast && !flag('--replace')) throw new Error(`fast tier already deployed (${state.fast})`);
      const pid = await spawn('fast', { name: 'RNG-Fast-Threshold', lua: fastSource() });
      await send(pid, 'Get-Info');
      return pid;
    },
    async 'genesis-configure-fast'(file) {
      sameScheduler(state, ['token', 'fast']);
      const committee = readJson(file || path.join(HERE, 'committee.json'));
      const data = fastGenesisConfig({ fast: state.fast, token: state.token, committee });
      return send(state.fast, 'Gov.Configure', { data: JSON.stringify(data) });
    },
    'fund-fast': async (rng, forWho) => fundBeacon(rng, { 'X-For': forWho || me }, 'fast'),
    async 'gov-fast'(action, ...kv) {
      if (!/^Gov\.[A-Za-z-]+$/.test(action || '')) throw new Error('gov-fast <Gov.Action> [Tag=Value ...]');
      if (action === 'Gov.Handover') throw new Error('use `handover-fast`');
      const tags = Object.fromEntries(kv.map((a) => a.split(/=(.*)/s).slice(0, 2)));
      return send(state.fast, action, { tags });
    },
    async 'handover-fast'() {
      if (!flag('--confirm') && !DRY) throw new Error('Gov.Handover is one way: add --confirm');
      sameScheduler(state, ['token', 'dao', 'fast']);
      if (!DRY) {
        const [fastinfo, daoinfo] = await Promise.all([key(state.fast, 'beaconinfo'), key(state.dao, 'daoinfo')]);
        const errs = handoverErrors({ state: { ...state, beacon: state.fast }, beaconinfo: fastinfo, daoinfo, me });
        if (errs.length) throw new Error(`fast handover refused: ${errs.join('; ')}`);
      }
      const r = await send(state.fast, 'Gov.Handover', { tags: { Governor: state.dao } });
      state.fastGovernor = state.dao;
      save();
      return r;
    },

    'dao-stake': (rng) => transfer(state.dao, rng),
    async 'dao-propose'(file, ...kv) {
      const vars = { BEACON: state.beacon, FAST: state.fast, DAO: state.dao, TOKEN: state.token, FAIR: state.fair,
        ...Object.fromEntries(kv.map((a) => a.split(/=(.*)/s).slice(0, 2))) };
      const p = fillTemplate(readJson(file), vars);
      const errs = proposalErrors(p, { token: state.token, fast: state.fast });
      if (errs.length) throw new Error(`proposal refused: ${errs.join('; ')}`);
      return send(state.dao, 'Propose', { tags: { Title: p.title, Body: p.body,
        'Exec-Process': p.execProcess, 'Exec-Tags': JSON.stringify(p.execTags) } });
    },
    'dao-vote': (id, side) => {
      if (!id || !['Yes', 'No', 'NoWithVeto', 'Abstain'].includes(side)) throw new Error('dao-vote <id> <Yes|No|NoWithVeto|Abstain>');
      return send(state.dao, 'Vote', { tags: { Proposal: String(id), Side: side } });
    },

    async status() {
      const [tokeninfo, daoinfo, beaconinfo, fairinfo, fastinfo] = await Promise.all([
        key(state.token, 'tokeninfo'), key(state.dao, 'daoinfo'), key(state.beacon, 'beaconinfo'), key(state.fair, 'fairinfo'),
        key(state.fast, 'beaconinfo')]);
      const checks = checkV3({ state, tokeninfo, daoinfo, beaconinfo, fairinfo, fastinfo });
      console.log(JSON.stringify({ token: state.token, dao: state.dao, beacon: state.beacon, fair: state.fair, fast: state.fast,
        scheduler: state.scheduler, mode: beaconinfo?.mode, round: beaconinfo?.round, health: beaconinfo?.health,
        registered: beaconinfo?.registered, governor: beaconinfo?.governor, govQueue: beaconinfo?.govQueue,
        fastRound: fastinfo?.round, fastGovernor: fastinfo?.governor, fastGovQueue: fastinfo?.govQueue, checks }, null, 1));
      return checks;
    },
    async verify() {
      const checks = await v3.status();
      const failed = checks.filter((c) => !c.ok);
      if (failed.length && !DRY) { process.exitCode = 1; console.error(`FAILED: ${failed.map((c) => c.check).join(', ')}`); }
    },

    async 'test-subscription'() {
      if (DRY) throw new Error('test-subscription is live only');
      const id = `acceptance-${Date.now()}`;
      const consumer = await spawn('subscriptionConsumer', { name: 'RNG-Subscription-Acceptance',
        lua: subscriptionConsumerSource(state.beacon, id) });
      await transfer(state.beacon, 1, { 'X-For': consumer });
      await send(consumer, 'Start');
      let receipt = null;
      for (let i = 0; i < 30 && !receipt; i++) {
        const r = await key(consumer, 'subscriptionstate');
        if (Number(r?.receipts) > 0) receipt = r;
        else await new Promise((res) => setTimeout(res, 1000));
      }
      if (!receipt) throw new Error('subscription did not deliver within 30 seconds');
      const round = await key(state.beacon, `beaconround-${receipt.lastRound % 8}`);
      if (!round || round.round !== receipt.lastRound) throw new Error(`round ${receipt.lastRound} is not retained`);
      const expected = sha256(`hyperbeam/rng/subscription/v1|${round.value}|${id}|${receipt.lastRound}`);
      if (receipt.lastValue !== expected) throw new Error('subscription value failed independent verification');
      log({ op: 'subscription', consumer, id, round: receipt.lastRound, verified: true });
    },

    async plan(allocFile, paramsFile) {
      if (!DRY) throw new Error('plan is --dry-run only');
      await v3['spawn-token'](allocFile);
      await v3['spawn-dao']();
      await v3['spawn-beacon']();
      await v3['genesis-configure'](paramsFile);
      await v3['fund-reserve']();
      await v3['fund-treasury']();
      await v3['spawn-fair']();
      await v3['configure-fair']();
      await v3['fund-fair'](40); // a float of 10 requests at requestPrice 4
      // Each launch validator gets validatorRng (100,000) and bonds all of it,
      // 4 x stake, from day one: rank is capped bond, so a newcomer must bond
      // as much to outrank them (PERMISSIONLESS.md P2). One transfer does both.
      await v3['bond-for'](state.genesis.validatorRng, path.join(HERE, 'anyhonest-validators.json'));
      // The fast tier on the existing committee; the three rng-provider
      // daemons are repointed at it live (deploy/nodes.sh beacon <fast>).
      await v3['spawn-fast']();
      await v3['genesis-configure-fast']();
      // The old beacon's Admin.Set-Successor (legacy-set-successor) goes here, live.
      await v3.handover();
      await v3['handover-fast']();
      await v3['dao-propose'](path.join(V2, 'governance', 'proposals', '001-handover-proof.json'));
      log({ op: 'check', sameScheduler: sameScheduler(state, ['token', 'dao', 'beacon', 'fair', 'fast']), scheduler: state.scheduler });
    },
  };

  // Legacy: the live v2 beacon (MZMoXv-2, old TEST-RNG) until cutover.
  const old = () => { if (!isPid(state.anyHonest)) throw new Error(`no anyHonest in ${STATE}`); return state.anyHonest; };
  const legacyCmds = {
    'legacy-info': async () => console.log(JSON.stringify(await key(old(), 'beaconinfo'), null, 1)),
    'legacy-tune': (...kv) => {
      const params = Object.fromEntries(kv.map((a) => a.split('=')).map(([k, v]) => [k, Number(v)]));
      if (!Object.keys(params).length || Object.values(params).some((v) => !Number.isSafeInteger(v))) throw new Error('legacy-tune key=integer ...');
      return send(old(), 'Configure', { data: JSON.stringify(params) });
    },
    'legacy-reinstate': async (...targets) => {
      const info = targets.length ? null : await key(old(), 'beaconinfo');
      for (const address of targets.length ? targets : (info?.validators || []).filter((v) => v.suspended).map((v) => v.address)) {
        await send(old(), 'Admin.Reinstate', { data: JSON.stringify({ address }) });
      }
    },
    'legacy-bond': async (units = '25000', ...targets) => {
      const list = targets.length ? targets : state.anyHonestValidators || [];
      for (const address of list) {
        await send(state.token, 'Transfer', { tags: { Recipient: old(), Quantity: atomsOf(units), 'X-For': address, 'X-Bond': 'true' } });
      }
    },
    'legacy-set-successor': (from, to) => {
      if (!isPid(from) || (to !== '' && !isPid(to))) throw new Error('legacy-set-successor <old> <new|"">');
      return send(from, 'Admin.Set-Successor', { data: JSON.stringify({ successor: to }) });
    },
    'legacy-move-reserve': async (from) => {
      if (!isPid(from)) throw new Error('legacy-move-reserve <old>');
      const info = await key(from, 'beaconinfo');
      const next = info && await key(info.successor, 'beaconinfo');
      // A reserve in one token cannot fund a beacon on another: the successor
      // would refuse the Credit-Notice and the atoms would be stranded.
      if (!DRY && (!info || !next || next.token !== info.token)) {
        throw new Error(`refused: successor ${info?.successor} uses token ${next?.token}, the reserve is in ${info?.token}`);
      }
      return send(from, 'Admin.Move-Reserve');
    },
    'legacy-beacon-info': async () => console.log(JSON.stringify(await key(state.beacon, 'beaconinfo'), null, 1)),
    'legacy-request': async (id = `req-${Date.now()}`) => {
      const r = await send(state.beacon, 'Request-Random', { tags: { Tier: 'beacon', 'Request-Id': id } });
      console.log(r.output);
    },
    'legacy-verify': async (roundArg) => {
      const bls = await import('../provider/bls.mjs');
      const round = Number(roundArg || (await key(state.beacon, 'beaconinfo'))?.round);
      const record = (await key(state.beacon, 'beaconstate'))?.rounds?.[String(round)];
      if (!record) throw new Error(`finalized round ${round} is missing from beacon state`);
      const message = `hyperbeam/rng/v1|${state.beacon}|${round}`;
      if (!bls.verify(state.groupKey, message, record.signature)) throw new Error(`round ${round} BLS signature failed verification`);
      if (record.value !== sha256(Buffer.from(`hyperbeam/rng/v1/round|${message}|${record.signature}`, 'latin1'))) throw new Error('value mismatch');
      console.log(JSON.stringify(record, null, 1));
    },
  };

  const fn = v3[cmd] || legacyCmds[cmd];
  if (!fn) throw new Error(`unknown command ${cmd}; see the header of deploy/deploy.mjs`);
  await fn(...pos);
}

if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  main(process.argv.slice(2)).catch((e) => { console.error(e.message || e); process.exit(1); });
}
