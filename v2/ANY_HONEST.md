# HyperBEAM RNG Any-Honest v1

Status: implementation candidate for the native testnet.

## Purpose

The Any-Honest beacon publishes one shared round per second. Every validator
commits a fresh time-lock puzzle before reveals begin. Once commits close, one
honest hidden contribution is sufficient to keep the round unpredictable. A
withheld contribution can be recovered by sequential work and a Wesolowski
proof verified by HyperBEAM's `~rng@1.0` device.

## Round lifecycle

Rounds overlap. A new round begins every 1,000 ms while earlier rounds reveal
or wait for a crack.

1. **Commit:** active validators post `c = g^alpha mod N` for fresh `alpha`.
2. **Close:** the commit set and validator assignment become immutable.
3. **Reveal:** validators reveal `alpha`; `~rng@1.0/verify-reveal` returns the
   canonical output.
4. **Crack:** after the reveal deadline, anyone may submit the missing output
   and proof to `~rng@1.0/verify-crack`.
5. **Finalize:** canonical outputs ordered by validator address form one round
   value under `hyperbeam/rng/any-honest/v1/round`.

## Fixed economics

Prices are constants configured by an administrator after an advisory DAO
vote. Validator membership never appears in a price formula.

- Foundation heartbeat: 3 RNG per finalized round.
- One-shot Any-Honest request: 4 RNG.
- Secure subscription: 1 RNG per 1,000 pushed rounds by default.
- Verified crack: 10 RNG from the DAO Treasury.

The Foundation reserve and DAO Treasury are separate token balances. Foundation
funds pay only for shared heartbeat rounds. Subscription payments and one RNG
from each one-shot request fund the Treasury. The Treasury fronts crack
bounties; the withholder's bond reimburses it when possible.

The fixed heartbeat pool is split equally among round contributors. Adding a
validator reduces each contributor's share and never changes customer prices.

## Validator exit

`Exit` immediately removes a validator from future assignment. Rounds already
in their commit phase remain obligations. After all assigned commitments are
revealed or cracked, `Finalize-Exit` removes the validator and returns its
remaining bond. A validator never waits for a calendar epoch merely to stop
receiving work.

Every round stores its own active set, commitments, outputs, puzzle parameters,
and final value. Membership changes cannot mutate an existing round.

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

## Governance

DAO votes are advisory. RNG Labs administrators manually execute passed votes
after checking the exact action. Governance may set price constants, fund the
Foundation reserve or Treasury, admit or remove validators, change bonds and
penalties, and approve software upgrades. No DAO vote directly upgrades a
contract or transfers protocol funds.
