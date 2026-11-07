# Native testnet operations

`native-testnet.json` is the canonical public process inventory of what is
live: token, threshold beacon, Any-Honest beacon (v2, `MZMoXv-2`), committees,
validators and DAO. `deploy.mjs` never writes it. v3 deploys record into
`v3-testnet.json` (`RNG_STATE`) until the cutover below merges them in.

The HyperBEAM node is recreated through `compose.hyperbeam-stage.yaml`. Its
process cache, node key, and node configuration are host-mounted, so changing
the runtime image does not discard proposals, stakes, votes, beacon state,
balances, or historical process implementation IDs.

Promote a tested runtime under the stable tag, then recreate it:

```bash
docker tag runerealm-hb:<candidate> runerealm-hb:rng-current
docker compose -f /opt/hyperbeam-rng-stage/compose.yaml up -d --force-recreate
curl -fsS -H 'Accept: application/json' \
  https://randao.net/hb-stage/~rng@1.0/generator
curl -fsS https://randao.net/api/anyhonest
curl -fsS https://randao.net/api/dao
```

Keep the previous container and image until the device, beacon, DAO, console,
validators, and authenticated subscription path have all been verified.

## Any-Honest cracker

Its own container, separate from HyperBEAM, pinned to one core the node does not use (on a shared host the node runs on cores 1-15, daemons on core 0).
It works on a late round until the beacon's published `abandonAt`: a round every validator committed to waits for its crack (up to 7 days) while the Treasury can pay the bounty.

```bash
docker build -t rng-cracker -f provider/Dockerfile.cracker .
mkdir -p /opt/rng-cracker && echo '{"beacon":"<anyHonest>","hbNode":"https://hyperbeam.tylerw.ai","dataDir":"/data","listen":7479}' > /opt/rng-cracker/config.json
docker run --rm -v /opt/rng-cracker:/data rng-cracker init /data/config.json   # prints its address
docker run -d --name rng-cracker --restart unless-stopped --cpuset-cpus=0 --network host   -v /opt/rng-cracker:/data rng-cracker run /data/config.json
docker run --rm -v /opt/rng-cracker:/data rng-cracker claim /data/config.json  # withdraw bounties
```

Before stopping a validator node, create `pause` in its `secrets-dir` and wait
for `ready: false` in `/~rng-validator@1.0/status`; a ready validator stopped
without pausing is slashed for every round it does not finish.

## deploy.mjs (v3)

The command list is the header of `deploy.mjs`. Config templates:

| File | What |
| --- | --- |
| `v3-genesis.json` | genesis allocations (whole RNG or atoms, `$DEPLOYER` allowed; must sum to exactly 10^15 atoms): all of it to RNG Labs, plus the `distribution` the runbook transfers on |
| `v3-params.json` | genesis `Gov.Configure` parameters and `predecessor`; checked against the beacon's hard bounds before sending |
| `anyhonest-h.json` | `h`, `hProof` for `T` |
| `anyhonest-validators.json` | validator wallets for `bond-for` |
| `../governance/proposals/*.json` | DAO proposal templates (`dao-propose`, placeholders `$BEACON`, `$SUCCESSOR`, ...) |

`--dry-run` prints every spawn and message as JSON and sends nothing.
`node deploy/deploy.mjs plan --dry-run` prints the whole sequence below.
Every spawn pins one scheduler (the node's), and `genesis-configure`,
`configure-fair` and `handover` refuse processes recorded on another one: the
beacon believes the DAO and the token only through its own scheduler's
`from-process`.

## Launch runbook (testnet cutover)

```bash
cd v2
export HB_NODE=https://hyperbeam.tylerw.ai HB_WALLET=<deployer.json> \
  RNG_STATE=deploy/v3-testnet.json PARALITH_MONO=/c/REPO/paralith-mono
node deploy/deploy.mjs plan --dry-run      # review every message first
```

1. **Token.** `spawn-token deploy/v3-genesis.json`: the whole supply,
   1,000,000,000 RNG, goes to RNG Labs (`$DEPLOYER` on testnet). Check:
   `status` shows sealed, supply 10^15, `sequenced-v1`.
2. **DAO.** `spawn-dao` (YapDAO `stake-dao/1` from paralith-mono, `Dao-Token` =
   RNG, rules from `daoRules()`, same scheduler). It refuses a token without
   `sequenced-v1` and checks `daoinfo` (configured, token, no admin).
3. **Beacon v3 genesis.** `spawn-beacon`, then
   `genesis-configure deploy/v3-params.json`. This locks token, unit, self and
   `predecessor = MZMoXv-2` and sends `Successor-Ack` to it (the v2 beacon has
   no handler for it; that refusal is expected).
4. **250 M under DAO control.** `fund-reserve` (200 M) and `fund-treasury`
   (50 M) from Labs into the beacon. This is the DAO's share: the DAO process
   itself must never receive RNG, because stake-dao/1 can never send an action
   to the token it stakes (paralith-mono `dao.lua:193`), so RNG sent there is
   unspendable. The DAO controls both through `Gov.*`: the reserve pays
   heartbeat rounds (and moves only to a successor), the treasury is
   spendable by proposal, at most 10 % per 30 days (5 M at launch), and can
   top up the reserve (`Gov.Fund-Reserve`). Every `fund-*` refuses until
   `beaconinfo.token` is set (step 3): before genesis the beacon can only
   refund the Credit-Notice through its sender, and past 16 senders or 256
   notices each the atoms strand.
   **Fair play** (open to any game): `spawn-fair`, `configure-fair` (beacon,
   token, `requestPrice` from `v3-params.json`), `fund-fair 40` (the fair
   process's beacon float, 10 requests; it is topped up from the games after
   every batch, never spent). Each game prepays its own draws:
   `fund-game <rng> <game>` (or any Transfer to the fair process with
   `X-Fair-Game = <game>`); an unfunded game gets `Game-Unfunded`, and a game
   takes back its free balance with `Fair.Withdraw { Nonce }`. Re-run
   `configure-fair` whenever governance changes the beacon's `requestPrice`.
5. **Validators bond and migrate.** Each launch validator receives 100,000 RNG
   and bonds all of it (4 x stake, the rank cap) in one transfer:
   `bond-for 100000 deploy/anyhonest-validators.json`. At the cap from day
   one, a newcomer must bond as much to outrank them (a quarter of the seats
   go by seniority whatever the bond). A launch validator outside that file
   gets `grant <address> 100000` and bonds at least 25,000 itself (100,000 to
   match the operators). Third parties run
   `node provider/anyhonest-validator.mjs init`, get RNG, then `bond` and
   `run`. The in-node devices need the v3-aware `rng-validator@1.0` (WP5)
   build first. Soak 72 h on deployer ownership: `status`, `test-subscription`.
   A later allocation for Paralith contracts' RNG is a plain `grant`, not
   part of launch.

   *Soak vs runway.* The 72 h soak is a pre-handover live test: the v3 beacon
   runs real rounds with real validators while the deployer can still pause
   or roll back, before anything is handed to the DAO. The runway is how long
   the reserve keeps paying heartbeat rounds: 200 M RNG at 2 rounds/s x
   1 RNG (172,800 RNG/day) is about 1,157 days (3.2 years), extendable by
   `Gov.Fund-Reserve` from the treasury; after it the beacon falls back to
   request-driven rounds. The soak spends about 0.5 M of it.
6. **Successor on the old beacon (legacy Admin path).** With the v2 owner wallet:
   `RNG_LEGACY_STATE=deploy/native-testnet.json node deploy/deploy.mjs legacy-set-successor MZMoXv-2aLD1MaR5tHEpXNrZgc6DoUpdw2q4DvlfxC0 <v3 beacon>`.
   Devices pause there, finish their reveals and move to v3. Each validator
   then exits the old beacon (`anyhonest-validator.mjs exit --beacon MZMoXv-2...`,
   twice) to get its old TEST-RNG bond back.
7. **Reserve move: skip.** The v2 reserve is in the old TEST-RNG token
   (`Tk0E1Vfr...`). The v3 beacon refuses a Credit-Notice from another token
   and the atoms would be stranded, so `legacy-move-reserve` refuses when the
   successor uses a different token. The v3 reserve is the genesis allocation
   (step 4). The old reserve stays on MZMoXv-2 and is retired with the old
   TEST-RNG; old TEST-RNG balances keep no role in v3 and are not converted.
8. **Console and crackers.** Record the v3 token, DAO, beacon and fair in
   `native-testnet.json` (MZMoXv-2 and the advisory DAO to `retired`) and the
   console env (`console/deploy/native-testnet.env`) together, so
   `test/deployment-config.test.mjs` stays green. Point each cracker's
   `config.json` `beacon` at v3 and restart it.
9. **Handover to the DAO.** `handover <guardian wallet> --confirm`
   (`Gov.Handover`, one way; the guardian may pause and cancel queued actions
   for 90 days). Name the guardian explicitly (an ops wallet, not the
   deployer; `plan` needs `RNG_GUARDIAN`). It refuses unless the beacon's
   `govQueue` is empty (`gov Gov.Cancel Gov-Id=<id>` first) and the DAO
   publishes a `stake-dao/1` `daoinfo` on our token, no admin, voting period
   under the beacon's 10-day delays. Prove it:
   `dao-stake 30000`, `dao-propose governance/proposals/001-handover-proof.json`,
   `dao-vote <id> Yes`. After the 7-day vote the DAO executes it; check the
   proposal is `executed` and `Reveal-Window-Ms` is still 30000 with no
   `Not authorised` refusal. Then `verify` (includes "governed by the DAO").

**Verify after every step:** `node deploy/deploy.mjs status` (or `verify`,
which exits 1 on any failed check: sealed token, DAO on RNG with no admin,
beacon token/self/predecessor, health `ok`, reserve funded, governor, fair
bound, one scheduler). Validators: `anyhonest-validator.mjs status`.

**Rollback**
- Before step 9: `gov Gov.Pause` (deployer) stops the v3 heartbeat and new
  requests. Clear the old beacon's successor
  (`legacy-set-successor MZMoXv-2... ""`), re-point console and crackers to
  MZMoXv-2, which keeps running until retired. Do not retire it before the
  soak ends.
- After step 9: the guardian pauses (`HB_WALLET=<guardian.json> ... gov Gov.Pause`).
  The fix is a new beacon voted in with `003-set-successor.json` (10 days).
  Validators can `Pause`/`Exit` at any time; governance can never take a bond.
