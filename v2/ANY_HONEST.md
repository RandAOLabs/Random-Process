# HyperBEAM RNG Any-Honest v3

Status: v3 (permissionless, DAO-governed, fixed supply, fair play) is built on
branch `permissionless` and not yet deployed. The live testnet beacon is still
v2 (`MZMoXv-2`) until the cutover in [`deploy/README.md`](./deploy/README.md).
Design, threat model and economics: [`docs/PERMISSIONLESS.md`](./docs/PERMISSIONLESS.md).

## Purpose

The Any-Honest beacon publishes one shared round every 500 ms while validators
keep up. Every validator commits a fresh time-lock puzzle before reveals begin.
Once commits close, one honest hidden contribution is sufficient to keep the
round unpredictable. A withheld contribution can be recovered by sequential
work and a Wesolowski proof verified by HyperBEAM's `~rng@1.0` device.

## Who does what

- **The beacon** is an AO process (`beacon/anyhonest.lua`), run on
  `lua-patch@1.0`: it keeps its state in the node's VM and publishes only the
  keys that change. `deploy/deploy.mjs spawn-beacon` builds it with the
  `vendor/lua53b.lua` adapter (`--lua53a` for the old build).
- **Validators** are anyone who bonds the stake. They run either the JS
  validator (`provider/anyhonest-validator.mjs`, Node 22 only) or the
  `rng-validator@1.0` device inside a HyperBEAM node. Either one makes each
  puzzle, keeps the secret on disk, commits, reveals, says Ready and Pause,
  and follows a successor beacon. The console's `/validators` page has the steps.
- **The RNG DAO** (YapDAO `stake-dao/1`, staking RNG) governs the beacon. See
  [Governance](#governance).
- **Fair play** (`fair/fair.lua`, or `lib/fair.lua` embedded in a game) lets a
  player's own secret make each draw fair to them. See [Fair play](#fair-play).
- **Crackers** are a separate service, `provider/anyhonest-cracker.mjs`
  (`provider/Dockerfile.cracker`), that anyone may run for the crack bounty.
  One crack is about 3 minutes of one CPU core, so a cracker works one puzzle
  at a time on its own CPU budget, never on a HyperBEAM node's cores.

## Round lifecycle

Rounds overlap. Rounds are due every `targetIntervalMs` (500), at most
`maxInFlight` (3) at once, while earlier
rounds reveal or wait for a crack.

1. **Open:** the first commit opens a round and fixes its set: the first
   `maxActive` (64) validators that are ready, not exiting and in good
   standing, ranked by `min(bond, 4 * stake)`, then join time, then address.
   Only a validator in that set opens it. A round opens only while at least
   `minCommits` (2) are ready; with fewer it could only void.
2. **Commit:** every validator in the set posts `c = g^alpha mod N` for a fresh
   `alpha`. Commits close as soon as the whole set has committed, or after
   `commitWindowMs` (5,000).
3. **Reveal:** validators reveal `alpha` within `revealWindowMs` (30,000);
   `~rng@1.0/verify-reveal` returns the canonical output.
4. **Crack:** after the reveal deadline, anyone may submit the missing output
   and proof to `~rng@1.0/verify-crack`. Rounds after a late one go on without
   waiting; only the late round's value waits for its crack.
5. **Abandon:** a round still missing an output `abandonAfterMs` (360,000, about
   two crack times) after its reveal deadline gets no value. Its requests are
   refunded in full and requesting processes are told `Round-Abandoned`.
6. **Finalize:** canonical outputs ordered by validator address form one round
   value under `hyperbeam/rng/any-honest/v1/round`.

A void round (fewer than `minCommits` commits) keeps its number and the sha256
of every commitment it saw, so none can be reused under that number.

A validator sends its reveals and its next commit as one `Act` message
(`{ reveals: [{ round, alpha }], commit: { round, c } }`) when the beacon lists
`act` in `features`. Each part is checked exactly as its own `Reveal` or
`Commit` would be. This halves the messages a round costs.

## Validator duty and punishment

A validator is **ready** (it gets rounds) or **not ready**. Readiness is a
promise: a ready validator does every round it is given.

- **Join:** a token Transfer to the beacon with `X-Bond` that brings the bond
  to at least `stake` registers the validator (not ready). A smaller first bond,
  or a full registry (`maxValidators`, 256), is refunded. Nobody admits or
  reinstates validators.
- **Ready** (`Ready`): allowed in good standing (no output it owes is past its
  deadline unfilled) with bond plus earnings refill of at least `stake`, the
  first time and after every fault. The validator sends it by itself whenever
  it can work.
- **Pause** (`Pause`): no new rounds, no penalty. Rounds already given are still
  owed: commits to a round whose set it is in, and every reveal. To go offline,
  a validator pauses, finishes its rounds, then stops. On a node, the operator
  pauses by creating the file `pause` in the device's `secrets-dir`, and
  deletes it to come back.

Every failed duty is a full `slash` (1,000 RNG) of the stake, paid to the DAO
Treasury, and makes the validator not ready:

- **Missed commit:** in a round's set, no commit within the commit window.
- **Missed reveal:** an output missing at the reveal deadline, one slash for
  every such round. A crash with five rounds in flight costs five slashes.

There is no allowance and no window that forgives: a mistake must never be
cheaper than doing the work. A slashed validator gets no new rounds until it
is in good standing again (its late outputs cracked or abandoned) and sends
Ready.

One incident costs at most the rounds the validator already holds: the first
fault takes it out of every round opened after it. Ready is then refused
(`Cooling-Down`) until `rejoinAt`: `rejoinBaseMs` (60,000) after the fault,
doubling per incident up to `rejoinCapMs` (3,600,000); a validator ready for
`rejoinCapMs` starts over. Info shows `suspendedAt`, `suspendedAtMs`,
`rejoinAt` and `strikes`. A device rejoins only after that, and only once its
own round trip is well inside the commit window.

## Validator money

Each validator has two balances in the beacon:

- **Stake** (`stake`, 25,000 RNG): locked collateral, added with an `X-Bond`
  transfer. Slashes and the crack bounty for its withheld outputs come out of
  it.
- **Earnings:** its share of every round's pools and any crack bounties it
  won. `Claim` withdraws them at any time.

`Ready` refills a short stake from earnings, all or nothing, so a validator
pays for its own mistakes out of what it earned. Only one that has earned too
little needs new tokens. A validator that performs well is never slashed and
its earnings only grow.

## Economics

RNG has a fixed supply of 1,000,000,000 (6 decimals), minted once at genesis
and then sealed: no faucet, no mint, no admin over balances. The genesis
allocation funds the Foundation reserve (200 M, about 3.2 years of heartbeat)
and the Treasury (50 M). Prices are DAO-set parameters inside hard bounds.
Validator membership never appears in a price formula.

- Foundation heartbeat: 1 RNG per finalized round.
- One-shot Any-Honest request: 4 RNG.
- Secure subscription: 1 RNG per 1,000 pushed rounds by default.
- Verified crack: 10 RNG from the DAO Treasury.

The Foundation reserve and DAO Treasury are separate token balances. Foundation
funds pay only for shared heartbeat rounds. Subscription payments, slashes and
one RNG from each one-shot request fund the Treasury. The Treasury fronts crack
bounties; the withholder's stake reimburses it.

When the reserve cannot pay a round, the beacon goes **request-driven**
(`beaconinfo.mode`): rounds open only for pending requests. A request whose
round never opens is refunded after `abandonAfterMs`. The DAO can refill the
reserve from the Treasury (`Gov.Fund-Reserve`).

One-off requests take one message: a token Transfer with `X-Request-Id` pays
and requests. The finalized round record lists `requests`, so a wallet reads
its own value.

The fixed heartbeat pool is split equally among round contributors. Adding a
validator reduces each contributor's share and never changes customer prices.

## Validator exit

`Exit` immediately removes a validator from future assignment. Rounds already
in their commit phase remain obligations. After all assigned commitments are
revealed or cracked, `Finalize-Exit` removes the validator and returns its
remaining stake. Earnings stay claimable. A validator never waits for a
calendar epoch merely to stop receiving work.

Every round stores its own set, commitments, outputs, puzzle parameters, and
final value. Membership changes cannot mutate an existing round.

## Replacing a beacon

The new beacon's genesis `Gov.Configure` names the old one as `predecessor`
and sends it `Successor-Ack` (`Resend-Successor-Ack` sends it again). On the
old beacon, governance queues `Gov.Set-Successor` (7 days, then anyone's
`Gov.Apply`). A validator stops taking new rounds on the old beacon (Pause),
reveals what it still owes, then moves to a successor that names the old
beacon as predecessor, and records the move in `secrets-dir/beacon.json`.
`Gov.Move-Reserve` (7 days) sends the unspent reserve to an acked successor on
the same token. Stakes do not move: validators exit the old beacon to get
theirs back and bond on the new one.

## Published keys

| Key | What | Changes |
| --- | --- | --- |
| `beaconinfo` | rounds open and revealing, listed validators, params, prices, `mode`, `health`, `at`, governor, `govQueue`, `features` | every message |
| `beaconvalidators` | the full registry | when it changes |
| `beaconparams` | the group `g`, `n`, the puzzle `T` and `h` | on `Gov.Configure` |
| `beaconround-<round % 8>` | a finalized round: commits, outputs, value | when it finalizes |
| `beaconrecent` | the last 8 rounds' values and times | when a round finalizes |
| `timelockstate` | the whole state, a recovery checkpoint | every 1,000 messages on `lua-patch@1.0` |

Until a round is late, `beaconinfo` shows each commitment as its first 16 hex
digits (a validator finds its secret by prefix). A late round shows them
whole, which is what crackers work on.

## Identity

Every message must be signed for this beacon (the target door from
paralith-mono `game/kernel/door.lua`): a message signed for another beacon,
or a signature that does not commit `target`, is refused, so a validator's
signed messages cannot be replayed on another beacon. A message carrying two
signatures from different signers is refused. A process (the DAO, a token, a
consumer) is believed only through a `from-process` that this beacon's own
scheduler signed, so the token, the DAO, the beacon and fair play run on one
scheduler.

`health` is `ok`, `degraded` or `halted` (fewer eligible validators than
`minCommits`); the console shows a banner when it is not `ok`.

## Secure subscriptions

Only AO processes may create a push subscription. `Subscribe` binds the process
to the open round while its commit window is accepting requests. Once reveal
begins, the earliest future open round becomes `effectiveRound`.

Subscriptions are prepaid for a number of rounds. Every finalized covered round
sends the subscriber an authenticated `RNG-Subscription` message. Its
subscriber-specific result is:

```text
SHA-256(
  "hyperbeam/rng/subscription/v1|" || round_value || "|" ||
  subscription_id || "|" || round
)
```

Public reads remain available for observation and independent verification,
but secure push is the canonical delivery path because it binds before reveal
and avoids trusting a website or gateway for timing and completeness.

Operators can run `deploy/deploy.mjs test-subscription` against a deployment.
It creates a disposable AO consumer, prepays it, waits for an
authenticated push, and recomputes the subscriber-specific value from the
published round before reporting success.

## Governance

Before handover the deployer wallet governs; `Gov.Handover` hands the beacon to
the RNG DAO for good. After that only a passed DAO proposal (one tags-only
message, sent by the DAO process) can act:

| Action | Delay | Effect |
| --- | --- | --- |
| `Gov.Configure` | none | parameters, inside hard bounds; token, unit, self and predecessor never change after genesis |
| `Gov.Set-Successor`, `Gov.Move-Reserve` | 7 days | name a successor; move the reserve to an acked successor |
| `Gov.Treasury-Spend` | 48 hours | at most 10% of the Treasury per action |
| `Gov.Fund-Reserve`, `Gov.Remove-Validator` | none | Treasury to reserve; remove a validator, bond refunded in full |
| `Gov.Pause` / `Gov.Resume`, `Gov.Clear-Guardian`, `Gov.Cancel` | none | the brake; end the guardian; drop a queued action |

Anyone runs `Gov.Apply` once a queued action is due. A guardian wallet may
`Gov.Pause` for 90 days after handover; it cannot resume or move funds.
Governance can never take a bond or a user balance. Proposal templates are in
`governance/proposals/`.

## Fair play

A player who wants a draw that is fair even if every validator and the game
collude commits `sha256("rng/fair/v1/commit|" Game "|" Session "|" s)` with an
ephemeral key (`Fair.Commit`) before the fair process requests a beacon value
for its batch. After the beacon's `RNG-Result`, the player reveals `s`
(`Fair.Reveal`) and the final value is `H("rng/fair/v1/final|" v "|" s)`. A
reveal missing after `fairWindowMs` (60 s) is a forfeit (`Fair.Expire`), which
games must score as the worst outcome. The fair process pays its beacon
requests from its own beacon balance (a Transfer with `X-For` = the fair process).

## Later: the validator marketplace

As in the original RandAO protocol, a requester will choose any subset of
validators (or a saved group) per request, from a public view of each
validator's status and record. That changes the round model from one shared
set to per-request sets and gets its own spec.
