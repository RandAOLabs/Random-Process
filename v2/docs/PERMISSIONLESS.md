# Any-Honest v3: permissionless, DAO-governed

Status: spec, feasibility and build plan. Nothing here is implemented yet.
Branch `permissionless`, based on v2 at `ff06740` (beacon `MZMoXv-2`).

## Summary

- An RNG-staked instance of YapDAO (`stake-dao/1`) governs the beacon. **YapDAO needs no
  code changes.** The beacon reads governance parameters from tags, keeps its own
  timelock, and accepts the DAO through the scheduler-attested `from-process` check it
  already uses for the token's `Credit-Notice`.
- The RNG token gets a fixed supply minted once at genesis. It has no faucet and no
  mint, and no admin power over balances. It adopts `sequenced-v1` (rune.lua) because
  the DAO deploy and the Paralith vault both require it.
- Validators join by bonding: a Transfer with `X-Bond` of at least `stake` creates the
  registry entry. There is no `Admin.Add-Validator` and no `Admin.Reinstate`. Each round
  takes at most `maxActive` validators, ranked by capped bond, then seniority.
- When the reserve runs out, the beacon switches to request-driven rounds instead of
  halting. A request that can never be served is refunded.
- A new "fair play" flow lets a player's browser commit a secret before the beacon value
  is bound. The result is final = H(beacon value, player secret), so an honest player
  knows the outcome is fair even if every validator and the game colluded. The flow
  runs as a separate process (or embedded library) and costs the beacon one request per
  batch.
- Third parties need only the JS validator, a wallet and RNG for the bond. The
  HyperBEAM fork with `rng-validator@1.0` + `rng@1.0` is optional.

## Decisions (changeable)

| # | Decision | Why |
|---|---|---|
| D1 | No YapDAO changes. Governance actions are one tags-only message per proposal, and the beacon parses its parameters from tags (`Gov-*` names below). | DAO caps fit: 16 tags, values ≤ 512 B, ≤ 2048 B total. An `h`/`hProof` (< N, ≤ 512 hex chars) fits one tag each. |
| D2 | The beacon keeps its own timelock: 10 days (longer than the DAO's 7-day vote) for `Gov.Set-Successor`, `Gov.Move-Reserve`, `Gov.Treasury-Spend`, `Gov.Fund-Reserve` and a `Gov.Configure` of `stake`, `slash`, `commitWindowMs`, `revealWindowMs`, `crackBounty`, `maxInFlight`, `cadenceMs` or `targetIntervalMs`; other Configure parameters apply at once (bounded). A queued action expires 14 days after it is due; the guardian may `Gov.Cancel` it until `guardianUntil`. | The DAO has no delay (DAO.md:121). A counter-proposal (Gov.Cancel) can pass inside the delay, and a validator can exit before a change to its bond's exposure lands. |
| D3 | The DAO process, the beacon and the RNG token run on **one scheduler** (`hyperbeam.tylerw.ai`, where Paralith also runs) | `from-process` is believed only when *our own* scheduler signed the delivery |
| D4 | Treasury and reserve stay inside the beacon and are never sent to the DAO | The DAO cannot target its staked token (dao.lua:192), so RNG it held would be stuck forever |
| D5 | Fixed supply of 1,000,000,000 RNG at 6 decimals (10^15 atoms < 2^53). Minted once at genesis to an allocation table, then sealed. | Enclosed economy. A sealed token has no owner to capture. |
| D6 | The token is a port of rune.lua's ledger (`sequenced-v1`, `t<n>` references). Every Transfer the beacon makes carries `X-Transfer-Sequence`. | `deploy-dao.mjs` L81-85 and vault.lua:407 refuse other tokens |
| D7 | Join = a single `X-Bond` credit that brings the bond to at least `stake`. A smaller first bond is refunded. The registry holds at most `maxValidators` = 256; when full, a join evicts (refunds) the lowest-ranked entry that never sent Ready and joined at least 1 h ago, and anyone may `Evict-Idle` an entry that has not sent Ready 7 days after joining. | Bounds `beaconinfo` (cost per published key) and spam; registering alone does not hold a seat |
| D8 | Each round takes `maxActive` = 64 validators. `maxActive // 4` seats go by seniority (earliest `readyAt`: ready without a break; a fault or Pause starts it over); the rest by rank: `min(bond, 4·stake)` descending, then `joinedAt` ascending, then address. Operator validators bond 4·stake from day one. | Fresh Sybils cannot push out incumbents at max bond, and bonding alone never buys every seat (see threat T3) |
| D9 | Ready (first time and every rejoin) needs bond + earnings refill ≥ `stake`. `rejoinBond` is removed. | Owner goal: rejoin = top back up to full stake |
| D10 | `Admin.Reinstate`, `Admin.Add-Validator` and `Claim-Protocol` are deleted. `Admin.Remove-Validator` becomes DAO-only `Gov.Remove-Validator`, which always refunds the full bond to the validator. | The DAO cannot take a bond |
| D11 | The deployer wallet is owner until `Gov.Handover`, a one-way switch to the DAO. A guardian wallet may `Gov.Pause` (heartbeat off, no new requests) until `guardianUntil` = handover + 90 d. The DAO can clear the guardian early. | Emergency brake during bootstrap. It can stop the beacon, never move funds. |
| D12 | Fair play is a separate process, `v2/fair/fair.lua`, built on an embeddable `v2/lib/fair.lua`. Each game chooses one of the two. | It must not slow the beacon. Embedding saves a ~160 ms hop. |
| D13 | Players sign fair-play messages with an ephemeral browser key by default; the wallet is optional | Avoids two wallet popups per game. Fairness needs knowledge of the secret, not identity. |
| D14 | Heartbeat `roundPrice` drops from 3 to 1 RNG. The reserve is 200 M, about 3.2 years at 2 rounds/s. | 3 RNG/round spends 19 % of supply a year |
| D15 | `v2/governance/dao.lua` (advisory) and its tests are deleted. Proposal templates move to `v2/governance/proposals/*.json` in Exec-Tags form. | Replaced by YapDAO |

## Feasibility verdicts

| Goal | Verdict | Evidence |
|---|---|---|
| 1. YapDAO controls the protocol | **Feasible, zero Yap changes.** One message per proposal, tags only (no Data), fired once in the slot that closes the proposal, with no timelock. None of the names the beacon needs are reserved. | dao.lua:72 caps 16/64/512/2048; reserved list dao.lua:160-174 (`data`, `body`, `x-transfer-sequence`, `x-reference`, `cast`, …); execute dao.lua:597-603. `Action`, `T`, `Successor`, `Quantity`, `Recipient`, `Reveal-Window-Ms` are all allowed. |
| 1a. Multiple messages per proposal | Not needed. A multi-step change is several proposals. `Gov.Configure` takes up to 14 parameters in one message. | — |
| 1b. A DAO cannot move a sequenced token it holds | Real limit (`X-Transfer-Sequence` is reserved), avoided by D4 | rune.lua:1092-1108 |
| 2. The DAO owns beacon and token | **Feasible.** The beacon's `actor()` already returns the attested `from-process` when our scheduler signed the delivery (anyhonest.lua:224-237), and `Credit-Notice` relies on it in production (:658). Paralith uses the same pattern everywhere (dao.lua:262 `sourceProcess`, rune.lua:431, custody.lua:138, hunt.lua:278). **Change needed:** `ownerOnly` uses `provenSigner` (wallet only, :921), so it must use `actor()` with `FromProcess` and `== Governor`. | The token needs no owner after genesis (D5) |
| 2a. Beacon identity weaknesses | Two fixes: (a) beacon `provenSigner` takes the *first* RSA commitment (:196-205). It must refuse mixed signers, like rng-token.lua:109-121. (b) `actor()` returns the scheduler's own address on a scheduler-signed message with no `from-process`. It must return nil, as dao.lua:285-291 does. | — |
| 3. Enclosed RNG economy | **Feasible.** Votes (DAO stake), fees (`requestPrice`, `subscriptionPrice`), slashing and pay are already in RNG. Remove `Faucet` and `Admin.Mint`. | rng-token.lua:370-404 |
| 3a. RNG on the Paralith orderbook | **Blocked in paralith-mono, not here.** The live vault is sealed (`Admin.ListAsset` is refused after `Admin.Seal`, vault.lua:1045; there is no unseal). Listing is owner-signed only, so a DAO cannot list (vault.lua:1029-1035). Route: the next Paralith fresh deploy lists `rng` before Seal, and `deploy-sharded-venue.mjs` spawns pair `RNG/GOLD`. | deploy-sharded-venue.mjs L237-267 |
| 4. Permissionless validators | **Feasible** with the beacon changes below. A non-HyperBEAM operator **can validate with the JS validator alone**: commit is `g^alpha mod N` (BigInt), and reveal verification runs on the beacon's node (`rng@1.0`), not the validator's. It needs a refresh first: it is marked superseded and lacks `Act`, `Pause` and successor-following (anyhonest-validator.mjs:3). Its default `commitWindowMs` of 2000 is stale. | Erlang device: dev_rng_validator.erl:132-293, 486-495 |
| 4a. Audit items | Reinstate bypass (:1058, Ready without stake or standing): delete it. Probe clock skew (validator.mjs:109 samples `localNow − firstCommitAt`, which mixes clocks): fix below. All-suspended alert: `health` field plus a console banner. | — |
| 4b. Reserve empty halts rounds | **Bug confirmed.** With heartbeat on, the first Commit fails `Foundation-Reserve-Empty` (:821), the round never opens, and its pending requests are never abandoned, because `abandon` only covers reveal-phase rounds (:513-527). The fix is below. | — |
| 5. "Become a validator" page | Feasible. A new route `/validators` reads `beaconinfo`. | console app has `/how`, `/try`, `/dao`, `/why` |
| 6. Player as honest actor | **Feasible.** Latency is about 5-15 s per draw, or about 3-8 s when the commit is made ahead of time. Beacon cost is ≤ 1 outstanding `Request-Random` per fair process. | See "Fair play" |
| 7. One-off requests | **Exists:** fund via Transfer → `Request-Random` (price 4) → push to a process, or recompute for a wallet. Gaps: two messages per request, wallet results are not published, requests can get stuck, and there is no faucet-free funding UI. | anyhonest.lua:705-744, 547-567 |
| 8. Economics | Specified below. At small validator counts the stake is small next to pay. That is acceptable because withholding cannot bias a value (time-lock). | — |

## Component specs

### Beacon `v2/beacon/anyhonest.lua`

**Identity**
- `provenSigner`: return nil when two RSA commitments name different committers.
- `actor`: a scheduler-signed message without `from-process` returns nil.
- New state: `governor` (DAO pid, "" before handover), `guardian`, `guardianUntil`, `gov = { queue = {}, nextId }`.
- `isGovernor(msg)`: `FromProcess and actor == Timelock.governor and governor ~= ""`.
- `isDeployer(msg)`: `governor == "" and provenSigner(msg) == Owner` (wallet, pre-handover only).
- `govOnly`: `isGovernor or isDeployer`.

**Governance handlers.** All read **tags**. Data is used as a fallback only when the deployer signs. Tag names are compared lowercased with `-` and `_` stripped.

| Action | Who | Tags | Effect |
|---|---|---|---|
| `Gov.Handover` | deployer | `Governor` (pid), `Guardian` (addr, optional) | refused while anything is queued, or if the governor is the deployer, the beacon or the token; sets governor; the deployer path is off forever; `guardianUntil = now + 90 d`. `deploy.mjs handover` also checks the governor publishes a `stake-dao/1` `daoinfo` on our token, and never defaults the guardian |
| `Gov.Configure` | gov | any of `T`, `H`, `H-Proof`, `Commit-Window-Ms`, `Reveal-Window-Ms`, `Abandon-After-Ms`, `Min-Commits`, `Max-Active`, `Max-Validators`, `Cadence-Ms`, `Target-Interval-Ms`, `Max-In-Flight`, `Catch-Up-Ms`, `Stake`, `Slash`, `Rejoin-Base-Ms`, `Rejoin-Cap-Ms`, `Heartbeat`, `Round-Price`, `Request-Price`, `Subscription-Price`, `Subscription-Rounds`, `Crack-Bounty`, `Fair-Window-Ms` (≤ 15 per message) | the whole message is checked against the bounds below; `Stake`, `Slash`, `Commit-Window-Ms`, `Reveal-Window-Ms`, `Crack-Bounty`, `Max-In-Flight`, `Cadence-Ms`, `Target-Interval-Ms` are queued 10 d (re-checked at apply), the rest applies immediately |
| `Gov.Set-Successor` | gov | `Successor` | queued 10 d, applied by anyone's `Gov.Apply`; supersedes any queued Set-Successor |
| `Successor-Ack` | the successor process, or one queued to become it (attested) | — | records the ack time; only an ack since the naming Set-Successor was queued counts; acks of a cancelled or replaced successor are deleted |
| `Gov.Move-Reserve` | gov | `Successor` (the successor or a queued one) | queued 10 d; pays only that successor, at apply the applied successor with a current ack; dropped if the successor changed; sends `X-Foundation` to it |
| `Gov.Treasury-Spend` | gov | `Recipient` (not the DAO, the beacon or the token), `Quantity` (atoms) | queued 10 d; spends + reserve funding ≤ 10 % of the treasury per 30-day window (`beaconinfo.treasuryWindow`) |
| `Gov.Fund-Reserve` | gov | `Quantity` | treasury → reserve, queued 10 d, under the same window cap |
| `Gov.Remove-Validator` | gov | `Validator` | as the old Remove: not while committed, full bond refunded |
| `Gov.Pause` / `Gov.Resume` | gov, or guardian before `guardianUntil` | — | `heartbeat = 0` and `paused = true` (new Request/Subscribe refused) / undo (Resume: gov only) |
| `Gov.Clear-Guardian` | gov | — | ends the guardian's powers early |
| `Gov.Cancel` | gov, or guardian before `guardianUntil` | `Gov-Id` | drops a queued action (a spend's share of the window comes back) |
| `Gov.Apply` | anyone | `Gov-Id` | runs a queued action whose `at` has passed, until `at + 14 d` (then `Expired`, dropped); an action that can never apply is dropped |

A `Gov.*` from the governor carrying an `X-Dao-Proposal` already seen runs once: a redelivery is a no-op.

On a new beacon, `Successor-Ack` comes from its `Configure`/genesis outbox:
`{ target = predecessor, Action = "Successor-Ack" }`.

**Hard bounds** (checked in `Gov.Configure` and at genesis; replaces :1091-1100)
- `2^27 ≤ T ≤ 2^32` (`minT()` raised from 2^20; the harness keeps 1)
- `10 000 ≤ revealWindowMs ≤ 600 000`; `500 ≤ commitWindowMs ≤ 10 000`
- `revealWindowMs ≤ abandonAfterMs ≤ 7 d`
- `1 ≤ slash ≤ stake / 10`; `stake ≤ 10^7`: a fault takes at most a tenth of the stake
- `1 ≤ crackBounty ≤ slash`: each crack also takes the bounty from the withholder's bond
- `1 ≤ maxInFlight ≤ 8`; `cadenceMs ≤ 60 s`; `targetIntervalMs ≤ 10 min`
- `2 × (1 + maxInFlight) × (slash + crackBounty) ≤ stake`. One incident (from the first fault, which
  suspends the validator, until it is in good standing) can fault only the rounds it already holds: the one
  committing plus at most `maxInFlight` revealing. Each costs a slash plus at most one crack bounty, so an
  incident costs at most half the stake (defaults: 4 × 1 010 = 4 040 of 25 000). No vote can turn
  slashing into confiscation.
- `rejoinBaseMs ≥ revealWindowMs`; `rejoinBaseMs ≤ rejoinCapMs ≤ 30 d`
- `2 ≤ minCommits ≤ maxActive ≤ 128`; `maxActive ≤ maxValidators ≤ 1024`
- every price and the bounty ≥ 1; `heartbeat ∈ {0,1}`
- `token`, `unit`, `self` and `predecessor` are fixed after genesis (`Token-Locked`)

**Validators**
- `Credit-Notice` with `X-Bond`: if `who` is not registered, refuse and refund unless the
  credit makes the bond ≥ `stake` and the registry has room (a full registry evicts its lowest-ranked
  never-ready entry that joined at least 1 h ago, refunded; with none, `Registry-Full`). Register `{ ready = false, joinedAt = now }`. Any remainder below one whole
  RNG in a Credit-Notice is refunded to the sender.
- `Ready`: requires `bond + refill ≥ stake` always (delete `rejoinBond`, :1022). Everything else is unchanged.
- `activeValidators()` → eligible (ready, not exiting, not overdue); `maxActive // 4` by seniority, the rest by D8 rank.
- Subscriptions are deleted once their last round has passed; at most 16 live per subscriber.
- Delete `Admin.Add-Validator`, `Admin.Reinstate`, `Claim-Protocol`, `Admin.Set-Successor`, `Admin.Move-Reserve`, `Configure` (genesis config becomes `Gov.Configure` under `isDeployer`).
- `beaconinfo.validators` lists only active + ready + suspended-with-bond, capped at 128. The full registry goes in one key, `beaconvalidators`, rewritten only when it changes.

**Reserve and stuck requests**
- Commit in `collecting` with heartbeat on and reserve < `roundPrice`: if the round has pending
  requests, open it unsponsored; otherwise fail `Nothing-Pending`. `beaconinfo.mode = "request-driven"`.
- `advance()`: a `collecting` round whose oldest pending request is older than `abandonAfterMs` is
  refunded and notified, the same as `abandon()`.
- A reveal-phase round is abandoned past `abandonAfterMs` (default 30 min) only if some validator in its
  set never committed, or the treasury cannot pay a crack bounty. A complete round waits for its crack, so
  a withholder who has seen the other outputs cannot void a value it dislikes (selective abort). Run at
  least two independent crackers; a crack of T = 2^27 takes minutes.
- Hard cap: 7 days after its reveal deadline any round is abandoned and its requests refunded, so nothing
  hangs forever (the withholder was already slashed at the deadline; a void then costs it a slash and a
  week). Each revealing round in `beaconinfo` carries `abandonable` and `abandonAt`; the cracker works on a
  round until `abandonAt`, not `abandonAfterMs`.
- A late round (past its reveal deadline) no longer counts toward `maxInFlight`: its withholder is
  suspended and in no newer round, so a stuck round does not throttle new ones.
- A handler that throws leaves no partial state on either device: the state is deep-copied before each
  handler (all but the `seen` guard, whose changes are journaled and undone) and put back on an error.
  Measured in the test harness at about 2 ms per message for a 35 KB state (≈ 7 % of a message there).
- Before genesis no token is known, so a `Credit-Notice` cannot be credited. It is refunded to `Sender`
  by a `Transfer` to the attested process that sent it (a fake token moves nothing), on a
  per-sender `X-Transfer-Sequence` stream; genesis continues the named token's stream and counts the
  refunded references as credited. At most 16 senders and 256 references each; past that the atoms
  strand, so the deploy script still never transfers before genesis.
- `health = { status = ok|degraded|halted, active, eligible, minCommits, since }`.
  It is `halted` when eligible < minCommits.
- `beaconinfo.at = now` (scheduler time of this slot), for clock offset estimates.

**One-off requests**
- `Credit-Notice` with `X-Request-Id` (and optional `X-Request-Time`): credit `Sender`, then run
  `Request-Random` for `Sender` in the same slot (one user message). On refusal the credit stays in the balance.
- The finalized round record `beaconround-<r%8>` gains `requests = [{ requester, requestId, value }]`
  (only for this round's requests), so wallets read their value directly.

**Token payouts:** `transferAtoms` adds `X-Transfer-Sequence = <Timelock.transferSeq + 1>`.
The counter only increases and never resets, as in dao.lua's payouts.

### Token `v2/token/rng-token.lua`

- Name `RNG`, ticker `RNG` (`TEST-RNG` on testnet), Denomination 6.
- Genesis: `GenesisAllocations = { [addr] = atoms, ... }` is injected by the deploy prelude, minted on the first slot
  only when `Minted == 0`, and must sum to exactly 10^15 or the process refuses every action. Then `Sealed = true`.
- Delete `Faucet`, `Admin.Mint`, `faucetView` and the faucet state. Keep `Admin.Checkpoint` (deployer, harmless).
- Port rune.lua's process-transfer streams: process senders must send `X-Transfer-Sequence`, which is deduped in a 256 window
  (rune.lua:1086-1161). Publish `tokeninfo.ProcessTransferProtocol = "sequenced-v1"`.
- `Credit-Notice` keeps `Sender`, `Quantity`, `Reference = t<n>`, and forwards `X-*` tags.

### YapDAO instance (no code change, deploy only)

- `deploy-dao.mjs` in the yap repo with `RUNE_TOKEN=<RNG pid>` (it is generic over `Dao-Token`, dao.lua:458-465). Rules:
  `Dao-Name = RNG DAO`, threshold 25 000 RNG, deposit 5 000, voting period 7 d,
  quorum 1 000 bps, pass 5 000, veto 3 334, unstake delay 14 d, 20 open proposals.
- Proposal templates (`v2/governance/proposals/*.json`) hold `{ title, body, execProcess, execTags }`,
  e.g. `{ "Action": "Gov.Configure", "Reveal-Window-Ms": "30000" }`.

### Fair play `v2/lib/fair.lua` + `v2/fair/fair.lua`

| Step | Message | Signed by | State |
|---|---|---|---|
| 1 | `Fair.Commit { Game, Session (≤64), Commit = hex sha256("rng/fair/v1/commit|"‖Game‖"|"‖Session‖"|"‖s) }` | player key P | session `committed`, joins `batch[next]` |
| 2 | fair → beacon `Request-Random { Request-Id = "fair-<b>" }` | fair (attested) | sent when no request is outstanding; otherwise waits for the current result |
| 3 | beacon → fair `RNG-Result` (value v_b) | beacon (attested, checked `== beacon`) | each session gets `v = H("rng/fair/v1/beacon|"‖v_b‖"|"‖Game‖"|"‖Session)`, status `reveal-due`, `revealBy = now + fairWindowMs` (60 s). The next batch's request goes out in the same slot. |
| 4 | `Fair.Reveal { Game, Session, Secret = s }` | anyone | checks the hash; `final = H("rng/fair/v1/final|"‖v‖"|"‖s)`; `Fair-Result` → Game |
| 5 | `Fair.Expire { Game, Session }` after `revealBy` | anyone | `final = H("rng/fair/v1/forfeit|"‖v)`, status `forfeit` → Game |

- Published: one key `fairsessions` holding the last N per game (bounded), plus `fairbatches`.
  The player checks its own `Commit`, bound round and inputs, then recomputes `final`.
- Every session is paid from the fair process's beacon balance. The process accepts `Fair.Open` only
  from games its deployer allowed (`Fair.Configure { allowGames = [...], removeGames = [...] }`, or
  `openToAll = true`); any other game gets `Game-Not-Allowed`. Default: no game. (A per-game prepaid
  balance was considered; it needs the fair process to hold and forward tokens, so it is not built.)
- At `maxGames`, a new game evicts the oldest idle one. The scan drops lapsed allowances first, so
  throwaway games that never open again do not hold the registry.
- Embedded mode: a game process calls `fair.commit/onResult/reveal/expire` on its own state and
  handles Fair.* in its own handler table. This saves the hop. No allowlist unless the game sets `allow`.
- Browser: `v2/console/lib/fair-client.ts` creates an RSA-PSS key with WebCrypto once (kept in IndexedDB),
  draws s with `crypto.getRandomValues(32)`, signs ANS-104 with the vendored client, and stores s
  until it reveals (it re-reveals after a reload).

### Validators (what a third party runs)

| Option | Run | Needs |
|---|---|---|
| A (simplest) | `node v2/provider/anyhonest-validator.mjs init && … run` (after WP4) | Node 22, a wallet created by `init`, the beacon pid, the scheduler URL, ≥ `stake` RNG; secrets dir on durable disk; RTT < `commitWindowMs/2` |
| B | HyperBEAM fork node with `rng-validator@1.0` (`on.start` hook) + `rng@1.0` (blst NIF) | the same, plus building the fork |
| optional | `anyhonest-cracker` | CPU; earns `crackBounty` per crack |

Steps: init the wallet → buy RNG → `Transfer { Recipient = beacon, Quantity = stake·10^6, X-Bond = "true" }`
→ the validator sends `Ready` itself (an entry that never does can be evicted) → it works every round in the active set → `Pause` / `Exit` → `Finalize-Exit` refunds the bond.

**Clock-skew fix (both clients):** measure health only from local round trips: post → the commit appears in
`beaconinfo` (local clock both ends). Estimate `offset = min over samples of (localReadAt − info.at)`,
and compare `nextRoundAt` and `rejoinAt` against `localNow − offset`.

### Console `v2/console`

- `/validators`: plain title and body copy (no kicker or hero typography). Sections: requirements,
  four steps with copyable commands, live table (`beaconvalidators`), earnings estimate from live params
  (`roundPrice·rate/active` + request share), risks (slash per missed duty, cooldown doubling, lost secrets
  = a slash per open round, lost wallet = lost bond, DAO parameter changes within the hard bounds).
- Health banner on every page when `health.status ≠ ok`.
- `/try`: remove Faucet. "Get RNG" links to the Paralith RNG/GOLD market. Add one-message pay-and-request.
- `/dao`: replace the advisory console with a link and read-only view of the RNG DAO in Yap (`?dao=<pid>`).

## Security analysis

| # | Threat | Mitigation | Residual |
|---|---|---|---|
| T1 | Forged DAO message (a tag claiming `from-process`) | believed only when our scheduler signed it; mixed signers refused | trust in the node operator (true for every AO process) |
| T2 | DAO capture (whale buys > 50 % of staked RNG) | 7-day vote, ⅓ veto; 10-day timelock (longer than the vote, so a Gov.Cancel can pass; the guardian can cancel for 90 d) on successor, reserve, treasury, reserve funding and bond-exposure parameters; treasury outflow ≤ 10 % per 30 days; handover refused over a non-empty queue. **Bonds and user balances are not reachable by governance**: removal refunds in full, a fault takes ≤ stake/10, and slash/stake/window changes land 10 d after the vote, so a validator exits first. | the reserve (via a malicious successor, T9) and ≤ 10 % of the treasury per 30 days, each ≥ 17 days after the proposal, visibly |
| T3 | Sybils fill the active set, then grind the last commit (all validators colluding sets the value) | D8: rank by capped bond, so incumbents at 4·stake cannot be displaced (operators bond 4·stake from day one); a quarter of the seats go by seniority, which bonding cannot buy; consumers needing per-draw guarantees use fair play | an attacker at 4·stake takes up to ¾ of the seats from incumbents below the cap; the whole set only if the senior seats are also its own |
| T4 | Withholding a reveal to bias, or to abort a round after seeing the other outputs | the time-lock makes the value fixed at commit close; crack + slash; a round whose commits are complete is not abandoned while a crack is paid for, until the 7-day cap | delay only; a round short of a commit can still be abandoned after `abandonAfterMs` (30 min, far above the crack time) if nobody cracks; any round after 7 d with no crack |
| T5 | Spam registrations, registry squatting | first bond ≥ stake; registry cap; refund otherwise; a full registry evicts its lowest-ranked never-ready entry, and anyone evicts one idle 7 d | a squatter that does send Ready must then do (or be slashed for) the work |
| T6 | Reserve drained → halt | request-driven fallback, refund of stuck requests | heartbeat consumers see gaps |
| T7 | All validators suspended | `health = halted`, banner, validator logs; requests refunded after `abandonAfterMs` | liveness depends on operators |
| T8 | Guardian abuse | can only pause, cannot move funds or resume; expires; DAO can clear | 90 days of censorship risk |
| T9 | Malicious successor drains the reserve | DAO vote + 10-day timelock; Move-Reserve names its successor at queue time and pays only it, with an ack received since it was named; acks of cancelled or replaced successors are deleted; validators' devices only follow a successor naming this beacon | same as T2 |
| T10 | Lost payout (a sequenced transfer never delivered) | the sequence never resets; a `Resend-Payout`-style handler is a follow-up (token window 256) | stalls if > 256 are lost |
| F1 | Player grinds the secret | commit fixed before its batch's request is sent; v_b unknown to anyone until reveals (any-honest) | — |
| F2 | Player withholds the reveal after seeing v (1-bit option) | forfeit is final and games MUST score it as the worst outcome; entry is charged before commit | a game that rewards forfeit is broken by design |
| F3 | Game + all validators collude against the player | they never learn s (256-bit, hashed) → final is uniform to them | none if the player is honest |
| F4 | Player + all validators collude against the game | they can grind v_b knowing s | the game relies on any-honest, as today |
| F5 | Game substitutes a commit | the commit is signed by P; the player checks it in `fairsessions` before revealing | — |
| F6 | Fair-process bloat slows the beacon | ≤ 1 outstanding request per fair process; batch size unbounded | — |
| F7 | Unknown games drain the fair process's beacon balance | only deployer-allowed games may `Fair.Open` | an allowed game can still spend it; the deployer removes it |

## Economics

| Item | Value | Notes |
|---|---|---|
| Supply | 1,000,000,000 RNG, fixed | D5 |
| Allocation | reserve 200 M (beacon), treasury 50 M (beacon), RNG/GOLD liquidity 100 M, community / players / validator grants 300 M, RNG Labs 350 M | open question 1 |
| Heartbeat | 2 rounds/s × `roundPrice` 1 = 63.1 M/yr → reserve ≈ 3.2 yr | was 3 → 189 M/yr (the prior audit's ~188.9 M/yr) |
| Request | 4 RNG: 1 treasury, 3 split among contributors | unchanged |
| Subscription | 1 RNG per 1000 rounds → treasury | unchanged |
| Stake | 25 000 | at n=3: ≈ 10.4 h of pay; n=64: ≈ 9.3 days of pay |
| Slash | 1 000 per failed duty → treasury; bound ≤ stake / 10 | n=3: ≈ 25 min of pay; n=64: ≈ 9 h |
| Cooldown | 60 s base, ×2 per incident, cap 1 h; bounds ≥ reveal window, ≤ 30 d | unchanged |
| Crack bounty | 10 from treasury, reimbursed from the withholder's bond | the treasury nets +1 000 per withheld reveal |
| Max-rank bond | 4 × stake = 100 000 | D8 |

Sanity check:
- Pay per validator is `roundPrice·2/n` RNG/s plus request share. Entry is profitable until
  the set fills, so the set self-sizes towards `maxActive`.
- A fault always costs more than the rounds skipped. At n = 64, a round pays 0.016, so a slash equals ~64 000 rounds.
- A validator that cannot hold `commitWindowMs/2` RTT loses ≈ 1 000 per incident. Its client refuses Ready
  until it is healthy.
- After the reserve is spent, validators live on requests: 3 RNG/request ÷ n. Beacons with few requests then shrink,
  which is the intended endgame. The DAO can re-fund via `Gov.Fund-Reserve` from slashes and fees.
- Atoms stay below 2^53 at full supply. `int()` narrowing is required on every tag.

## Build plan

Work packages with disjoint files. The interfaces they share are this document's
message formats. WP1, WP2, WP3 and WP4 run in parallel; WP5-WP8 follow.

| WP | Scope | Files (only these) | Tests to add |
|---|---|---|---|
| WP1 | Beacon v3: identity fixes, Gov.* + timelock + guardian, permissionless bond/Ready, active-set ranking, bounds, reserve fallback, stuck-request refund, health/at, pay-and-request, round `requests`, `X-Transfer-Sequence`, registry key | `v2/beacon/anyhonest.lua`, `v2/test/anyhonest_test.lua`, `v2/test/run-anyhonest-tests.mjs` | DAO-attested Configure accepted; wallet/forged `from-process`/mixed-signer refused; deployer locked out after Handover; each bound rejected; timelock not before `at`; Move-Reserve needs ack; treasury 10 % cap; guardian expiry; bond < stake refunded; registry full; Ready needs full stake; ranking + maxActive; reserve empty → request-driven; stuck collecting refund; pay-and-request one slot; `requests` in round record; sequence strictly increasing; Reinstate/Add/Claim gone |
| WP2 | Token: genesis + seal, no faucet/mint, sequenced-v1 | `v2/token/rng-token.lua`, `v2/test/token_test.lua`, `v2/test/run-token-tests.mjs` | genesis sum ≠ supply refuses everything; mint once only; Faucet/Mint unknown; process transfer without sequence refused; replay within/after window; `tokeninfo` publishes protocol; restore never lowers counters |
| WP3 | Fair play lib + process | `v2/lib/fair.lua`, `v2/fair/fair.lua`, `v2/test/fair_test.lua`, `v2/test/run-fair-tests.mjs` | commit before request; one outstanding request; batch carry-over; RNG-Result only from the beacon; reveal hash mismatch; expire before/after `revealBy`; forfeit value; domain separation; bounded `fairsessions` |
| WP4 | JS validator parity + skew fix | `v2/provider/anyhonest-validator.mjs`, `v2/provider/anyhonest.mjs`, `v2/test/validator.test.mjs` (new) | Act batching; Pause/Exit; successor follow (needs ack); bond command sends X-Bond; Ready gated by local-RTT health; skewed clock (±60 s) neither false-healthy nor stuck; defaults read from `beaconinfo.params` |
| WP5 | Erlang device parity (repo `hyperbeam-rng-validator`) | `src/preloaded/node/dev_rng_validator.erl`, its eunit file, `docs/devices/rng-validator-at-1-0.md` | skew-free health; full-stake Ready; `health` read; successor ack check |
| WP6 | Console: validator page + health banner | `v2/console/app/validators/page.tsx`, `v2/console/components/validator-guide.tsx`, `v2/console/components/health-banner.tsx`, `v2/console/components/site-header.tsx`, `v2/console/app/layout.tsx` | render with mocked `beaconinfo` (ok/halted); earnings math unit test |
| WP7 | Console: try/dao/fair client | `v2/console/components/try-console.tsx`, `v2/console/components/dao-console.tsx`, `v2/console/lib/rng.ts`, `v2/console/lib/fair-client.ts`, `v2/console/app/api/dao/**`, `v2/console/examples/fair-demo/**` | no faucet path; pay-and-request message shape; fair client commit/reveal hashes match `fair.lua` vectors; IndexedDB loss → forfeit shown |
| WP8 | Deploy + governance + docs | `v2/deploy/deploy.mjs`, `v2/deploy/README.md`, `v2/test/deployment-config.test.mjs`, `v2/governance/**` (delete `dao.lua`), `v2/test/dao_test.lua` + `run-dao-tests.mjs` (delete), `v2/ANY_HONEST.md`, `v2/SPEC.md`, `v2/PRODUCT.md` | genesis prelude sums; same-scheduler check for token/beacon/DAO; proposal templates valid against DAO caps + reserved names |
| WP9 | Paralith listing (paralith-mono, separate session, later) | `deploy-sharded-venue.mjs` asset list + pair config | RNG deposit/withdraw e2e on a fresh vault |

## Launch plan (testnet)

1. **Build and test**: WP1-WP8 green; `node backend/native/e2e.mjs`-style signed run against the real node for DAO→beacon.
2. **Deploy token** (genesis allocations) on the beacon's scheduler. Verify the supply and `sequenced-v1`.
3. **Deploy the RNG DAO** with `deploy-dao.mjs` (Dao-Token = RNG). Verify `daoinfo` and the same `scheduler-location`.
4. **Deploy beacon v3** with deployer `Gov.Configure` (token, unit, self, predecessor = MZMoXv-2, params, h). Fund the reserve and treasury from genesis (`X-Foundation`, `X-Treasury`).
5. **Validators bond themselves** (the three current ones first), then third parties. Soak for 72 h with deployer ownership.
6. **Old beacon**: `Admin.Set-Successor` (v2 wallet path). Devices follow once v3 acks. The old TEST-RNG reserve cannot move: it is a different token, so it stays and is retired.
7. **Handover**: deployer `Gov.Handover { Governor = DAO, Guardian = ops wallet }`. Prove it with a DAO proposal that re-sets one parameter to its current value and confirm `executed` plus the beacon's applied rev.
8. **Market**: Paralith fresh deploy lists RNG and seeds RNG/GOLD (WP9).

**Rollback**
- Before step 7: deployer `Gov.Pause` or reconfigure. Consumers re-point to MZMoXv-2 (it keeps running until retired).
- After step 7: the guardian pauses. The fix is a new beacon voted in via `Gov.Set-Successor` (10 d). Validators can `Pause`/`Exit` at any time, and bonds are never at governance risk.

## Open questions for Tyler

1. Supply 1 B and the split (RNG Labs 350 M would control the early DAO quorum). Change it, or should RNG Labs not vote?
2. Active-set cap 64 ranked by capped bond + seniority, or uncapped (stronger any-honest, but slower rounds as the set grows)?
3. Guardian pause for 90 days after handover: keep it, shorten it, or drop it?
4. Market: RNG/GOLD, RNG/RUNE or both. This needs a Paralith fresh deploy, since the live vault is sealed. Who seeds liquidity?
5. Heartbeat subsidy: `roundPrice` 1 (≈ 3.2-year reserve) or keep 3 (≈ 1 year)?
