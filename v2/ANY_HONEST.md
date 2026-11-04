# HyperBEAM RNG Any-Honest v1

Status: implementation candidate for the native testnet.

## Purpose

The Any-Honest beacon publishes one shared round every 500 ms while validators
keep up. Every validator commits a fresh time-lock puzzle before reveals begin.
Once commits close, one honest hidden contribution is sufficient to keep the
round unpredictable. A withheld contribution can be recovered by sequential
work and a Wesolowski proof verified by HyperBEAM's `~rng@1.0` device.

## Who does what

- **The beacon** is an AO process (`beacon/anyhonest.lua`), run on
  `lua-patch@1.0`: it keeps its state in the node's VM and publishes only the
  keys that change. `deploy/deploy.mjs spawn-anyhonest` builds it with the
  `vendor/lua53b.lua` adapter (`--lua53a` for the old build).
- **Validators** run inside HyperBEAM as the `rng-validator@1.0` device. It
  makes each puzzle, keeps the secret on disk, commits, reveals, says Ready
  and Pause, and follows a successor beacon.
- **Crackers** are a separate service, `provider/anyhonest-cracker.mjs`
  (`provider/Dockerfile.cracker`), that anyone may run for the crack bounty.
  One crack is about 3 minutes of one CPU core, so a cracker works one puzzle
  at a time on its own CPU budget, never on a HyperBEAM node's cores.

## Round lifecycle

Rounds overlap. A new round can open every `cadenceMs` (500) while earlier
rounds reveal or wait for a crack.

1. **Open:** the first commit opens a round and fixes its set: every validator
   that is ready, not exiting and in good standing. Only a validator in that
   set opens it. A round opens only while at least `minCommits` (2; 3 once
   there are enough validators) are ready; with fewer it could only void.
2. **Commit:** every validator in the set posts `c = g^alpha mod N` for a fresh
   `alpha`. Commits close as soon as the whole set has committed, or after
   `commitWindowMs` (2,000).
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

- **Ready** (`Ready`): allowed in good standing (no output it owes is past its
  deadline unfilled) with a full stake. The device sends it by itself whenever
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

## Fixed economics

Prices are constants configured by an administrator after an advisory DAO
vote. Validator membership never appears in a price formula.

- Foundation heartbeat: 3 RNG per finalized round.
- One-shot Any-Honest request: 4 RNG.
- Secure subscription: 1 RNG per 1,000 pushed rounds by default.
- Verified crack: 10 RNG from the DAO Treasury.

The Foundation reserve and DAO Treasury are separate token balances. Foundation
funds pay only for shared heartbeat rounds. Subscription payments, slashes and
one RNG from each one-shot request fund the Treasury. The Treasury fronts crack
bounties; the withholder's stake reimburses it.

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

The owner names a successor with `Admin.Set-Successor`; the successor is
configured with `predecessor` set to the old beacon. A validator device stops
taking new rounds on the old beacon (Pause), reveals what it still owes, then
moves to the successor and records the move in `secrets-dir/beacon.json`.
`Admin.Move-Reserve` sends the unspent Foundation reserve to the successor as
its reserve. Stakes do not move: validators exit the old beacon to get theirs
back.

## Published keys

| Key | What | Changes |
| --- | --- | --- |
| `beaconinfo` | rounds open and revealing, validators, params, prices, `features` | every message |
| `beaconparams` | the group `g`, `n`, the puzzle `T` and `h` | on Configure |
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
signed messages cannot be replayed on another beacon.

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
It creates a disposable AO consumer, prepays five rounds, waits for an
authenticated push, and recomputes the subscriber-specific value from the
published round before reporting success.

## Governance

DAO votes are advisory. RNG Labs administrators manually execute passed votes
after checking the exact action. Governance may set price constants, fund the
Foundation reserve or Treasury, admit or remove validators, change stakes and
penalties, and approve software upgrades. No DAO vote directly upgrades a
contract or transfers protocol funds.

## Later: the validator marketplace

As in the original RandAO protocol, a requester will choose any subset of
validators (or a saved group) per request, from a public view of each
validator's status and record. That changes the round model from one shared
set to per-request sets and gets its own spec.
