import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import {
  loadAllocations, genesisPrelude, badParams, genesisConfig, daoRules, sameScheduler,
  fillTemplate, proposalErrors, checkV3, SUPPLY_ATOMS, handoverErrors, fundError, BEACON_GOV_DELAY_MS,
  fastGenesisConfig,
} from '../deploy/deploy.mjs';

const V2 = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const readJson = (p) => JSON.parse(fs.readFileSync(path.join(V2, p), 'utf8'));
const pid = (s) => s.padEnd(43, '_');
const DEPLOYER = pid('deployer');
const state = readJson('deploy/native-testnet.json');
const env = Object.fromEntries(
  fs.readFileSync(path.join(V2, 'console/deploy/native-testnet.env'), 'utf8')
    .split(/\r?\n/)
    .filter(Boolean)
    .map((line) => line.split(/=(.*)/s).slice(0, 2)),
);

test('console deployment follows the canonical native-testnet processes', () => {
  assert.equal(env.RNG_TOKEN_ID, state.token);
  assert.equal(env.RNG_BEACON_ID, state.beacon);
  assert.equal(env.RNG_ANYHONEST_ID, state.anyHonest);
  assert.equal(env.RNG_DAO_ID, state.dao);
});

test('deployment manifests retain state and load the pinned console environment', () => {
  const consoleCompose = fs.readFileSync(path.join(V2, 'console/deploy/compose.yaml'), 'utf8');
  const hyperbeamCompose = fs.readFileSync(path.join(V2, 'deploy/compose.hyperbeam-stage.yaml'), 'utf8');
  assert.match(consoleCompose, /native-testnet\.env/);
  assert.match(hyperbeamCompose, /store-overlay5:\/app\/cache-mainnet/);
  assert.match(hyperbeamCompose, /node-config\.json:\/app\/node-config\.json:ro/);
});

test('genesis: RNG Labs holds 100 % in one allocation; 250 M goes under DAO control by transfer', () => {
  const spec = readJson('deploy/v3-genesis.json');
  assert.equal(spec.allocations.length, 1, 'one allocation');
  assert.equal(spec.allocations[0].role, 'labs');
  const a = loadAllocations(spec, { deployer: DEPLOYER });
  assert.deepEqual(Object.keys(a.table), [DEPLOYER]);
  assert.equal(a.table[DEPLOYER], SUPPLY_ATOMS);
  assert.equal(a.rows.length, 1);
  assert.equal(a.reserveRng, 200_000_000);
  assert.equal(a.treasuryRng, 50_000_000);
  assert.equal(a.reserveRng + a.treasuryRng, 250_000_000, 'DAO control: reserve + treasury');
  assert.equal(a.validatorRng, 100_000);
  assert.equal(a.ticker, 'TEST-RNG');
  const vals = readJson('deploy/anyhonest-validators.json').length;
  assert.ok(BigInt(a.reserveRng + a.treasuryRng + vals * a.validatorRng) * 1_000_000n <= SUPPLY_ATOMS);
  assert.throws(() => loadAllocations({ ...spec, distribution: { reserveRng: 0.5 } }, { deployer: DEPLOYER }), /whole/);
  assert.throws(() => loadAllocations({ ...spec, distribution: { reserveRng: 1_000_000_000, treasuryRng: 1 } },
    { deployer: DEPLOYER }), /exceeds/);
});

test('genesis allocations refuse a wrong sum, a bad address or a fraction', () => {
  const one = (rows) => ({ allocations: rows });
  assert.throws(() => loadAllocations(one([{ address: DEPLOYER, rng: 999_999_999 }])), /not exactly/);
  assert.throws(() => loadAllocations(one([{ address: DEPLOYER, rng: 1_000_000_001 }])), /not exactly/);
  assert.throws(() => loadAllocations(one([{ address: 'short', rng: 1_000_000_000 }])), /invalid address/);
  assert.throws(() => loadAllocations(one([{ address: DEPLOYER, rng: 0.5 }])), /whole/);
  assert.throws(() => loadAllocations(one([{ address: DEPLOYER, atoms: '1e15' }])), /positive integer/);
  assert.throws(() => loadAllocations(one([{ address: '$DEPLOYER', rng: 1_000_000_000 }])), /invalid address/);
  const split = loadAllocations(one([
    { address: pid('a'), atoms: '400000000000001' }, { address: pid('b'), atoms: '599999999999999' }]));
  assert.equal(split.table[pid('a')] + split.table[pid('b')], SUPPLY_ATOMS);
});

test('genesis prelude is Lua integers the token reads as GenesisAllocations', () => {
  const a = loadAllocations({ ticker: 'TEST-RNG', allocations: [
    { address: pid('b'), rng: 600_000_000 }, { address: pid('a'), rng: 400_000_000 }] });
  const prelude = genesisPrelude(a);
  assert.match(prelude, /^GenesisAllocations = \{\n/);
  assert.match(prelude, new RegExp(`\\["${pid('a')}"\\] = 400000000000000,`));
  assert.match(prelude, /TokenTicker = "TEST-RNG"$/);
  const sum = [...prelude.matchAll(/\] = (\d+),/g)].reduce((s, m) => s + BigInt(m[1]), 0n);
  assert.equal(sum, SUPPLY_ATOMS);
  assert.doesNotMatch(genesisPrelude({ ...a, ticker: 'RNG' }), /TokenTicker/);
});

test('genesis prelude evaluates in AOS Lua to integer atoms summing to 10^15', async (t) => {
  const wasm = process.env.AOS_WASM
    || path.join(process.env.PARALITH_ROOT || 'C:/REPO/paralith-mono', 'backend/native/module/AOS.wasm');
  if (!fs.existsSync(wasm)) return t.skip('AOS.wasm not available');
  const { default: AoLoader } = await import('@permaweb/ao-loader');
  const handle = await AoLoader(fs.readFileSync(wasm), { format: 'wasm32-unknown-emscripten', computeLimit: 9e12, memoryLimit: 256 * 1024 * 1024 });
  const prelude = genesisPrelude(loadAllocations(readJson('deploy/v3-genesis.json'), { deployer: DEPLOYER }));
  const id = pid('prelude');
  const r = await handle(null, {
    Id: 'eval-prelude', Target: id, Owner: id, From: id, Tags: [{ name: 'Action', value: 'Eval' }],
    Data: `${prelude}\nlocal s, n = 0, 0\nfor _, v in pairs(GenesisAllocations) do assert(math.type(v) == "integer"); s = s + v; n = n + 1 end\nreturn tostring(s) .. ":" .. n .. ":" .. TokenTicker`,
    'Block-Height': '1', Timestamp: '1700000000000', Module: 'aos', Cron: false,
  }, { Process: { Id: id, Owner: id, Tags: [] }, Module: { Id: 'aos', Tags: [] } });
  const out = r.Output?.data;
  assert.match(typeof out === 'string' ? out : out?.output ?? JSON.stringify(out), /1000000000000000:1:TEST-RNG/);
});

test('v3 params template is inside the beacon hard bounds, and each bound bites', () => {
  const { predecessor, ...p } = readJson('deploy/v3-params.json');
  assert.equal(predecessor, state.anyHonest, 'predecessor is the live v2 beacon');
  assert.deepEqual(badParams(p), []);
  for (const bad of [{ T: 2 ** 26 }, { revealWindowMs: 9999 }, { commitWindowMs: 10001 }, { abandonAfterMs: 1000 },
    { slash: 30000 }, { slash: 2501 }, { stake: 10 ** 7 + 1 }, { rejoinBaseMs: 1000 }, { rejoinCapMs: 31 * 86400000 },
    { minCommits: 1 }, { maxActive: 129 }, { maxValidators: 63 }, { heartbeat: 2 }, { roundPrice: 0 },
    { subscriptionRounds: 0 }, { maxInFlight: 0 }, { fairWindowMs: 0 }, { stake: 1.5 }]) {
    assert.notDeepEqual(badParams({ ...p, ...bad }), [], JSON.stringify(bad));
  }
});

test('genesis Gov.Configure names token, unit, self, predecessor and h', () => {
  const hTable = readJson('deploy/anyhonest-h.json');
  const params = readJson('deploy/v3-params.json');
  const d = genesisConfig({ beacon: pid('beacon'), token: pid('token'), params, hTable });
  assert.equal(d.self, pid('beacon'));
  assert.equal(d.token, pid('token'));
  assert.equal(d.unit, 1_000_000);
  assert.equal(d.predecessor, state.anyHonest);
  assert.equal(d.h, hTable['134217728'].h);
  assert.equal(d.hProof, hTable['134217728'].hProof);
  assert.equal(d.roundPrice, 1);
  assert.equal(d.rejoinBond, undefined);
  assert.throws(() => genesisConfig({ beacon: pid('beacon'), token: pid('token'), params: { ...params, T: 2 ** 28 }, hTable }), /no h/);
  assert.throws(() => genesisConfig({ beacon: pid('beacon'), token: pid('token'), params: { ...params, commitWindowMs: 1 }, hTable }), /hard bounds/);
});

test('RNG DAO rules follow the spec', () => {
  const r = daoRules({ token: pid('token'), ticker: 'TEST-RNG' });
  assert.equal(r['Dao-Token'], pid('token'));
  assert.equal(r['Dao-Name'], 'TEST-RNG DAO');
  assert.equal(r['Proposal-Threshold'], String(25_000e6));
  assert.equal(r['Proposal-Deposit'], String(5_000e6));
  assert.equal(r['Voting-Period'], String(7 * 86400000));
  assert.equal(r['Unstake-Delay'], String(14 * 86400000));
  assert.deepEqual([r['Quorum-Bps'], r['Pass-Bps'], r['Veto-Bps'], r['Max-Active-Proposals']], ['1000', '5000', '3334', '20']);
  assert.ok(Number(r['Max-Proposals-Per-Proposer']) <= Number(r['Max-Active-Proposals']));
  assert.equal(r['Dao-Admin'], undefined, 'stake-dao/1 refuses Dao-Admin');
  assert.equal(daoRules({ token: pid('token') })['Dao-Name'], 'RNG DAO');
});

test('token, DAO, beacon and fair must share one scheduler', () => {
  const S = pid('sched');
  const s = { scheduler: S, token: pid('t'), dao: pid('d'), beacon: pid('b'), processes: {
    [pid('t')]: { scheduler: S }, [pid('d')]: { scheduler: S }, [pid('b')]: { scheduler: S } } };
  assert.equal(sameScheduler(s, ['token', 'dao', 'beacon']), true);
  assert.throws(() => sameScheduler({ ...s, processes: { ...s.processes, [pid('d')]: { scheduler: pid('other') } } },
    ['token', 'dao', 'beacon']), /from-process would not be believed/);
  assert.throws(() => sameScheduler(s, ['fair']), /not deployed/);
  assert.throws(() => sameScheduler({ ...s, processes: {} }, ['token']), /no spawn record/);
  assert.throws(() => sameScheduler({ ...s, scheduler: undefined }, ['token']), /no scheduler/);
});

test('proposal templates are valid against the DAO caps, reserved names and beacon tags', () => {
  const dir = path.join(V2, 'governance/proposals');
  const files = fs.readdirSync(dir).filter((f) => f.endsWith('.json'));
  assert.ok(files.length >= 8);
  const committee = readJson('deploy/committee.json');
  const vars = { BEACON: pid('beacon'), FAST: pid('fast'), DAO: pid('dao'), TOKEN: pid('token'), SUCCESSOR: pid('next'),
    RECIPIENT: pid('who'), VALIDATOR: pid('val'), QUANTITY: '1000000', GOV_ID: '1',
    COMMITTEE: JSON.stringify(committee.members.slice(0, 2)), SHARE_KEYS: JSON.stringify(committee.sharePublicKeys.slice(0, 2)),
    GROUP_KEY: committee.groupKey };
  assert.ok(!files.some((f) => /guardian/i.test(f)), 'no guardian template');
  for (const f of files) {
    const p = fillTemplate(JSON.parse(fs.readFileSync(path.join(dir, f), 'utf8')), vars);
    assert.deepEqual(proposalErrors(p, { token: vars.TOKEN, fast: vars.FAST }), [], f);
    assert.doesNotMatch(JSON.stringify(p), /guardian/i, `${f} mentions a guardian`);
    assert.doesNotMatch(JSON.stringify(p), /\$[A-Z]/, `${f} has an unfilled placeholder`);
  }
  const ok = { title: 't', body: '', execProcess: pid('beacon'), execTags: { Action: 'Gov.Pause' } };
  assert.deepEqual(proposalErrors(ok), []);
  const bad = (execTags, extra = {}) => proposalErrors({ ...ok, ...extra, execTags }, { token: pid('token') });
  assert.match(bad({ Action: 'Gov.Pause', Data: 'x' }).join(), /reserved/);
  assert.match(bad({ Action: 'Gov.Pause', 'X-Transfer-Sequence': '1' }).join(), /reserved/);
  assert.match(bad({ Action: 'Gov.Pause', 'X-Dao-Id': '1' }).join(), /reserved/);
  assert.match(bad({ Action: 'Gov.Configure', 'Reveal-Window-Ms': '' }).join(), /non-empty/);
  assert.match(bad({ Action: 'Gov.Configure', 'Reveal-Window-Ms': 'a'.repeat(513) }).join(), /<= 512/);
  assert.match(bad({ Action: 'Gov.Configure', Bogus: '1' }).join(), /does not read/);
  assert.match(bad({ Action: 'Admin.Add-Validator' }).join(), /not a beacon Gov/);
  assert.match(bad({ Action: 'Gov.Handover', Governor: pid('x') }).join(), /not a beacon Gov/);
  assert.match(bad({ Action: 'Gov.Pause' }, { execProcess: pid('token') }).join(), /staked token/);
  assert.match(bad({ Action: 'Gov.Clear-Guardian' }).join(), /not a beacon Gov/);
  // The fast tier has its own Gov.* table.
  const fast = (execTags) => proposalErrors({ ...ok, execProcess: pid('fast'), execTags }, { token: pid('token'), fast: pid('fast') });
  assert.deepEqual(fast({ Action: 'Gov.Configure', 'Signer-Fee': '2' }), []);
  assert.deepEqual(fast({ Action: 'Gov.Claim-Protocol', Recipient: pid('who') }), []);
  assert.match(fast({ Action: 'Gov.Configure', 'Reveal-Window-Ms': '1' }).join(), /does not read/);
  assert.match(fast({ Action: 'Gov.Treasury-Spend', Recipient: pid('who'), Quantity: '1' }).join(), /not a fast-tier Gov/);
  assert.match(bad({ Action: 'Gov.Claim-Protocol', Recipient: pid('who') }).join(), /not a beacon Gov/);
  const many = Object.fromEntries(Array.from({ length: 16 }, (_, i) => [`T${i}`, '1']));
  assert.match(bad({ Action: 'Gov.Configure', ...many }).join(), /more than 16/);
});

test('checkV3 passes on a healthy deployment and flags each problem', () => {
  const S = pid('sched');
  const s = { scheduler: S, token: pid('t'), dao: pid('d'), beacon: pid('b'), fair: pid('f'), predecessor: pid('old'),
    governor: pid('d'), processes: Object.fromEntries([pid('t'), pid('d'), pid('b'), pid('f')].map((p) => [p, { scheduler: S }])) };
  const good = {
    tokeninfo: { Sealed: 'true', TotalSupply: '1000000000000000', ProcessTransferProtocol: 'sequenced-v1' },
    daoinfo: { Configured: true, Token: pid('t'), Admin: '' },
    beaconinfo: { token: pid('t'), self: pid('b'), predecessor: pid('old'), health: { status: 'ok' },
      foundationReserveAtoms: '200000000000000', governor: pid('d') },
    fairinfo: { beacon: pid('b'), token: pid('t'), requestPriceAtoms: 4000000 },
  };
  assert.deepEqual(checkV3({ state: s, ...good }).filter((c) => !c.ok), []);
  const failing = (patch) => checkV3({ state: s, ...good, ...patch }).filter((c) => !c.ok).map((c) => c.check);
  assert.deepEqual(failing({ tokeninfo: { ...good.tokeninfo, Sealed: 'false' } }), ['token sealed']);
  assert.deepEqual(failing({ beaconinfo: { ...good.beaconinfo, governor: '' } }), ['beacon governed by the DAO']);
  assert.deepEqual(failing({ beaconinfo: { ...good.beaconinfo, foundationReserveAtoms: '0' } }), ['beacon reserve funded']);
  assert.deepEqual(failing({ daoinfo: { ...good.daoinfo, Token: pid('x') } }), ['dao configured on RNG']);
  assert.deepEqual(failing({ fairinfo: { ...good.fairinfo, token: '' } }), ['fair paid in RNG']);
});

test('dry-run plan prints the whole v3 sequence and sends nothing', () => {
  const out = execFileSync(process.execPath, [path.join(V2, 'deploy/deploy.mjs'), 'plan', '--dry-run'], {
    // An unreachable node: a dry run must not touch the network.
    env: { ...process.env, HB_NODE: 'http://127.0.0.1:9', HB_WALLET: '', RNG_DEPLOYER: DEPLOYER,
      RNG_SCHEDULER: pid('sched'), RNG_STATE: path.join(V2, 'deploy/does-not-exist.json') },
    encoding: 'utf8',
  });
  const lines = out.trim().split('\n').map((l) => JSON.parse(l));
  assert.ok(lines.every((l) => l.dryRun === true));
  const spawns = lines.filter((l) => l.op === 'spawn');
  assert.deepEqual(spawns.map((l) => l.role), ['token', 'dao', 'beacon', 'fair', 'fast']);
  assert.ok(spawns.every((l) => l.scheduler === pid('sched')), 'one scheduler');
  const [token, dao, beacon, fair, fast] = spawns.map((l) => l.pid);
  assert.equal(spawns[4].executionDevice, 'lua@5.3a');
  assert.match(spawns[0].prelude, new RegExp(`\\["${DEPLOYER}"\\] = 1000000000000000,`));
  assert.equal(spawns[1].definition['dao-token'], token);
  assert.equal(spawns[2].executionDevice, 'lua-patch@1.0');
  const sends = lines.filter((l) => l.op === 'send');
  const at = (action) => sends.findIndex((l) => l.action === action);
  const cfg = sends[at('Gov.Configure')];
  assert.equal(cfg.target, beacon);
  assert.deepEqual([cfg.data.token, cfg.data.self, cfg.data.predecessor], [token, beacon, state.anyHonest]);
  const transfers = sends.filter((l) => l.action === 'Transfer');
  assert.ok(transfers.every((l) => l.target === token));
  assert.deepEqual(transfers.find((l) => l.tags['X-Foundation']).tags.Quantity, '200000000000000');
  assert.deepEqual(transfers.find((l) => l.tags['X-Treasury']).tags.Quantity, '50000000000000');
  const float = transfers.find((l) => l.tags['X-For'] === fair);
  assert.equal(float.tags.Recipient, beacon);
  assert.equal(float.tags.Quantity, '40000000', 'fair float: 10 requests');
  // Fair play is open to any game: no allowlist step.
  assert.ok(sends.every((l) => l.action !== 'Fair.Configure' || !('allowGames' in (l.data || {}))));
  // The whole supply starts with Labs; reserve + treasury (250 M) are the DAO's, in the beacon.
  const daoControl = transfers.filter((l) => l.tags['X-Foundation'] || l.tags['X-Treasury'])
    .reduce((n, l) => n + BigInt(l.tags.Quantity), 0n);
  assert.equal(daoControl, 250_000_000_000_000n);
  assert.ok(transfers.every((l) => l.tags.Recipient !== dao), 'no RNG to the DAO process: it can never spend its staked token');
  const bonds = transfers.filter((l) => l.tags['X-Bond']);
  assert.deepEqual(bonds.map((l) => l.tags['X-For']), readJson('deploy/anyhonest-validators.json'));
  assert.ok(bonds.every((l) => l.tags.Quantity === '100000000000'), 'operators bond 4 x stake');
  assert.deepEqual(sends[at('Fair.Configure')].data.beacon, beacon);
  assert.equal(sends[at('Fair.Configure')].data.token, token);
  assert.equal(sends[at('Fair.Configure')].data.requestPrice, readJson('deploy/v3-params.json').requestPrice);
  const handover = sends[at('Gov.Handover')];
  assert.deepEqual(handover.tags, { Governor: dao }, 'no guardian');
  assert.equal(handover.target, beacon);
  assert.ok(at('Gov.Configure') < at('Gov.Handover'));
  // The fast tier: genesis on the existing committee and the v3 token, then handed to the DAO.
  const fastCfg = sends.find((l) => l.target === fast && l.action === 'Gov.Configure');
  const committee = readJson('deploy/committee.json');
  assert.deepEqual([fastCfg.data.self, fastCfg.data.token, fastCfg.data.threshold, fastCfg.data.groupKey],
    [fast, token, committee.t, committee.groupKey]);
  assert.deepEqual(fastCfg.data.committee, committee.members);
  assert.deepEqual(fastCfg.data.sharePublicKeys, committee.sharePublicKeys);
  assert.ok(!('cadenceMs' in fastCfg.data), 'no cadence: on demand');
  const fastHandover = sends.find((l) => l.target === fast && l.action === 'Gov.Handover');
  assert.deepEqual(fastHandover.tags, { Governor: dao });
  assert.ok(sends.indexOf(fastCfg) < sends.indexOf(fastHandover));
  const propose = sends[at('Propose')];
  assert.ok(at('Gov.Handover') < at('Propose'), 'the proof proposal follows the handover');
  assert.equal(propose.target, dao);
  assert.equal(propose.tags['Exec-Process'], beacon);
  for (const gone of ['Configure', 'Admin.Add-Validator', 'Admin.Reinstate', 'Admin.Mint', 'Faucet', 'Claim-Protocol']) {
    assert.equal(at(gone), -1, `${gone} is not part of v3`);
  }
  assert.equal(fs.existsSync(path.join(V2, 'deploy/does-not-exist.json')), false, 'dry run writes no state');
});

test('legacy commands target the live v2 beacon from the read-only inventory', () => {
  const run = (...args) => execFileSync(process.execPath, [path.join(V2, 'deploy/deploy.mjs'), ...args, '--dry-run'], {
    env: { ...process.env, HB_NODE: 'http://127.0.0.1:9', HB_WALLET: '', RNG_DEPLOYER: DEPLOYER }, encoding: 'utf8' });
  const before = fs.readFileSync(path.join(V2, 'deploy/native-testnet.json'), 'utf8');
  const succ = JSON.parse(run('legacy-set-successor', state.anyHonest, pid('v3')));
  assert.deepEqual([succ.target, succ.action, succ.data], [state.anyHonest, 'Admin.Set-Successor', { successor: pid('v3') }]);
  const tune = JSON.parse(run('legacy-tune', 'commitWindowMs=5000'));
  assert.deepEqual([tune.target, tune.action, tune.data], [state.anyHonest, 'Configure', { commitWindowMs: 5000 }]);
  assert.equal(fs.readFileSync(path.join(V2, 'deploy/native-testnet.json'), 'utf8'), before);
});

test('no guardian anywhere: beacon, deploy script, templates', () => {
  for (const f of ['beacon/anyhonest.lua', 'beacon/beacon.lua', 'deploy/deploy.mjs']) {
    const src = fs.readFileSync(path.join(V2, f), 'utf8');
    assert.doesNotMatch(src, /guardianUntil|isGuardian|Clear-Guardian|RNG_GUARDIAN|--no-guardian|GUARDIAN_MS/, f);
  }
});

test('fast genesis takes the existing committee and refuses a bad one', () => {
  const committee = readJson('deploy/committee.json');
  const d = fastGenesisConfig({ fast: pid('fast'), token: pid('token'), committee });
  assert.deepEqual([d.unit, d.verification, d.signerFee, d.protocolFee], [1_000_000, 'attestations', 1, 1]);
  const bad = (patch) => () => fastGenesisConfig({ fast: pid('fast'), token: pid('token'), committee: { ...committee, ...patch } });
  assert.throws(bad({ t: 1 }), /t must be/);
  assert.throws(bad({ t: 4 }), /t must be/);
  assert.throws(bad({ members: [committee.members[0], committee.members[0], committee.members[1]] }), /distinct/);
  assert.throws(bad({ sharePublicKeys: committee.sharePublicKeys.slice(0, 2) }), /one 96-hex key per member/);
  assert.throws(bad({ groupKey: 'ab' }), /groupKey/);
  assert.throws(() => fastGenesisConfig({ fast: 'x', token: pid('token'), committee }), /ids/);
});

test('fund-fast and gov-fast dry-run against the fast tier', () => {
  const tmp = path.join(V2, 'deploy', `.fast-test-${process.pid}.json`);
  const S = pid('sched');
  fs.writeFileSync(tmp, JSON.stringify({ scheduler: S, token: pid('token'), dao: pid('dao'), fast: pid('fast'),
    processes: { [pid('token')]: { scheduler: S }, [pid('dao')]: { scheduler: S }, [pid('fast')]: { scheduler: S } } }));
  try {
    const run = (...args) => execFileSync(process.execPath, [path.join(V2, 'deploy/deploy.mjs'), ...args, '--dry-run'], {
      env: { ...process.env, HB_NODE: 'http://127.0.0.1:9', HB_WALLET: '', RNG_DEPLOYER: DEPLOYER, RNG_SCHEDULER: S,
        RNG_STATE: tmp }, encoding: 'utf8' }).trim().split('\n').map((l) => JSON.parse(l));
    const [fund] = run('fund-fast', '9');
    assert.deepEqual([fund.target, fund.action, fund.tags.Recipient, fund.tags.Quantity, fund.tags['X-For']],
      [pid('token'), 'Transfer', pid('fast'), '9000000', DEPLOYER]);
    const [gov] = run('gov-fast', 'Gov.Configure', 'Signer-Fee=2');
    assert.deepEqual([gov.target, gov.action, gov.tags], [pid('fast'), 'Gov.Configure', { 'Signer-Fee': '2' }]);
    const [h] = run('handover-fast');
    assert.deepEqual([h.target, h.action, h.tags], [pid('fast'), 'Gov.Handover', { Governor: pid('dao') }]);
  } finally { fs.rmSync(tmp, { force: true }); }
});

test('fund-fast refuses a fast tier that has not run genesis-configure-fast', () => {
  const s = { token: pid('t'), fast: pid('f') };
  assert.equal(fundError({ state: s, beaconinfo: { token: pid('t') }, role: 'fast' }), null);
  assert.match(fundError({ state: s, beaconinfo: { token: '' }, role: 'fast' }), /genesis-configure-fast/);
});

test('handover is refused onto a wallet, a foreign DAO or over a queued action', () => {
  const s = { token: pid('t'), dao: pid('d'), beacon: pid('b') };
  const beaconinfo = { token: pid('t'), governor: '', govQueue: [] };
  const daoinfo = { Standard: 'stake-dao/1', Configured: true, Token: pid('t'), Admin: '', VotingPeriod: 7 * 86400000 };
  assert.deepEqual(handoverErrors({ state: s, beaconinfo, daoinfo, me: DEPLOYER }), []);
  const why = (patch) => handoverErrors({ state: s, beaconinfo, daoinfo, me: DEPLOYER, ...patch }).join('; ');
  assert.match(why({ daoinfo: null }), /no daoinfo: not a live DAO process/);
  assert.match(why({ state: { ...s, dao: DEPLOYER } }), /deployer wallet/);
  assert.match(why({ beaconinfo: { ...beaconinfo, govQueue: [{ id: 1, kind: 'Treasury-Spend' }] } }), /1 queued governance/);
  assert.match(why({ beaconinfo: { ...beaconinfo, governor: pid('x') } }), /already governed/);
  assert.match(why({ daoinfo: { ...daoinfo, Standard: 'other/1' } }), /not stake-dao\/1/);
  assert.match(why({ daoinfo: { ...daoinfo, Token: pid('x') } }), /not a DAO configured on our token/);
  assert.match(why({ daoinfo: { ...daoinfo, Admin: pid('a') } }), /has an admin/);
  assert.match(why({ daoinfo: { ...daoinfo, VotingPeriod: BEACON_GOV_DELAY_MS } }), /voting period/);
});

test('fund-* refuses a beacon that has not run genesis-configure', () => {
  const s = { token: pid('t'), beacon: pid('b') };
  assert.equal(fundError({ state: s, beaconinfo: { token: pid('t') } }), null);
  assert.match(fundError({ state: s, beaconinfo: { token: '' } }), /strand/);
  assert.match(fundError({ state: s, beaconinfo: null }), /strand/);
});

test('every beacon governance delay outlasts the DAO vote', () => {
  const lua = fs.readFileSync(path.join(V2, 'beacon/anyhonest.lua'), 'utf8');
  const block = /local GOV_DELAY_MS = \{([\s\S]*?)\}/.exec(lua)[1];
  const delays = [...block.matchAll(/\["([A-Za-z-]+)"\] = (\d+) \* DAY_MS/g)].map((m) => [m[1], Number(m[2]) * 86400000]);
  assert.deepEqual(delays.map(([k]) => k).sort(), ['Configure', 'Fund-Reserve', 'Move-Reserve', 'Set-Successor', 'Treasury-Spend']);
  const vote = Number(daoRules({ token: pid('t') })['Voting-Period']);
  for (const [kind, ms] of delays) {
    assert.ok(ms > vote, `${kind} delay ${ms} must exceed the voting period ${vote}`);
    assert.ok(ms >= BEACON_GOV_DELAY_MS, kind);
  }
  const fast = fs.readFileSync(path.join(V2, 'beacon/beacon.lua'), 'utf8');
  const fastBlock = /local GOV_DELAY_MS = \{([\s\S]*?)\}/.exec(fast)[1];
  const fastDelays = [...fastBlock.matchAll(/\["([A-Za-z-]+)"\] = (\d+) \* DAY_MS/g)].map((m) => [m[1], Number(m[2]) * 86400000]);
  assert.deepEqual(fastDelays.map(([k]) => k).sort(), ['Claim-Protocol', 'Configure']);
  for (const [kind, ms] of fastDelays) assert.ok(ms > vote, `fast ${kind} delay must exceed the voting period`);
  const move = readJson('governance/proposals/004-move-reserve.json');
  assert.equal(move.execTags.Successor, '$SUCCESSOR', 'Move-Reserve names its successor');
});
