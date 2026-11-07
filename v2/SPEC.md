# HyperBEAM RNG v1 Protocol Specification

Status: testnet candidate. The canonical specification and reference
implementation are maintained by RNG Labs, a product of CipherPlay Inc., in
this repository. CipherPlay Inc. owns the project IP.

Scope: this document is the threshold-BLS surface only (`beacon/beacon.lua`).
It is unchanged by Any-Honest v3, which is in [`ANY_HONEST.md`](./ANY_HONEST.md).
The live threshold beacon keeps the old TEST-RNG token; the fixed-supply v3 RNG
token (no faucet, no mint) pays only the v3 Any-Honest beacon and fair play.

## Purpose

HyperBEAM RNG provides deterministic, publicly verifiable randomness to AO processes.
A threshold committee produces one BLS12-381 signature per round. Requests are
bound to a round before its signature can be reconstructed, and each request
receives a value derived from that round and its unique request identifier.

The protocol has two implemented security tiers:

- `local`: deterministic process-local pseudorandomness with no unpredictability
  against a party that knows the message inputs; and
- `beacon`: threshold-BLS randomness with the trust and liveness assumptions
  below.

No `fast` or `max` tier is defined by this version.

## Roles

- **Beacon process:** accepts funded requests, fixes their round, publishes
  partials, finalizes signatures, and accounts for fees.
- **Committee member:** holds one DKG secret share and an AO wallet used to
  authenticate partial and round submissions.
- **Requester:** prepays a beacon balance and submits a unique `Request-Id`.
- **Token process:** sends replay-identifiable `Credit-Notice` messages when a
  requester funds the beacon.

## Cryptography

The beacon uses BLS12-381 in the IETF minimal-public-key-size variant:

- public keys are compressed G1 points (48 bytes);
- signatures are compressed G2 points (96 bytes); and
- messages hash to G2 with
  `BLS_SIG_BLS12381G2_XMD:SHA-256_SSWU_RO_NUL_`.

Committee keys are created by an `n`-dealer joint Feldman DKG. Every dealer
commits to a degree `t - 1` polynomial and sends one encrypted scalar share to
each member. A member accepts a share only when it matches the dealer's public
commitments. The group public key is the sum of every dealer's constant
commitment. Any `t` distinct valid partial signatures interpolate to the same
group signature.

The final transcript publishes one G1 public share key per committee member.
Production beacon configuration binds each committee wallet to its public
share key, and `rng@1.0` verifies every partial before the beacon publishes or
rewards it.

The current ceremony is run offline through authenticated SSH transport.
X25519 + HKDF-SHA-256 + AES-256-GCM protects each share in transit. Feldman DKG
is verifiable but not robust: a malicious dealer can halt a ceremony by
withholding or sending an invalid share. Operators must restart the ceremony
after excluding a faulty dealer.

## Domain Separation

For beacon process id `B` and positive round `R`, committee members sign the
UTF-8 bytes:

```text
hyperbeam/rng/v1|B|R
```

For lowercase group signature hex `S`, the round value is:

```text
SHA-256("hyperbeam/rng/v1/round|" || signed_message || "|" || S)
```

For round value hex `V` and request id `Q`, the request value is:

```text
SHA-256("hyperbeam/rng/v1/request|" || V || "|" || Q)
```

The `rng@1.0/derive` primitive expands an arbitrary byte seed using blocks:

```text
SHA-256(
  "hyperbeam/rng/v1/derive|" || decimal(byte_length(seed)) || "|" ||
  seed || "|" || decimal(counter)
)
```

The output is the requested prefix of consecutive counter blocks. The seed
length makes the encoding injective across `(seed, counter)` pairs.

## Round State Machine

Each round is in one of three states:

1. **Open:** requests may be assigned to the round.
2. **Locked:** acceptance of the first committee `Partial` or `Round` closes the
   request set. Later requests are assigned to the following round.
3. **Finalized:** a valid group signature is recorded, results are emitted, and
   the next round becomes open.

Locking before partial publication is a security boundary. Once `t` partials
are public, anyone can reconstruct the round value. Allowing another request
into that round would let its sender grind `Request-Id` after learning the
round value.

## Authentication and Replay Rules

- An actor is a unique accepted signature committer.
- A process delivery is attributed to `from-process` only when this beacon's
  scheduler signed the delivery.
- Unsigned `from-process` values and messages with multiple distinct accepted
  signers identify nobody.
- A funding notice must come from the configured token, carry a non-empty
  replay reference, and transfer a whole number of RNG units.
- Funding references and requester/request-id pairs are accepted once.
- Round submissions are accepted only from configured committee wallets and
  only for the current round.

## Finalization Modes

The production mode verifies each partial under its configured DKG public share
key and verifies one submitted group signature under the group key through the
preloaded HyperBEAM `rng@1.0` device. A group signature finalizes only after at
least `t` valid partials are published; those partial providers receive the
committee fees.

The testnet fallback requires `t` distinct committee wallets to attest the
same group signature. Each provider verifies the combined signature off-chain
before attesting. In fallback mode, compromise of `t` provider wallet keys can
finalize an arbitrary value even without the BLS shares; this mode is not the
target production security model.

## Fees

A beacon request costs `t + 1` RNG units:

- one unit for each of `t` serving committee members; and
- one protocol unit.

Fees are debited when a request is accepted. Committee or network failure can
delay a result indefinitely; this version does not implement automatic refunds.

## Security Properties

Assuming fewer than `t` committee shares are compromised and SHA-256, BLS12-381,
and the authenticated scheduling layer remain secure:

- no party below threshold can predict a locked round's value;
- no party below threshold can forge a valid production round;
- the finalized signature and all derived values are publicly verifiable;
- replayed funding notices and request identifiers do not credit or charge
  twice; and
- process replay produces the same outputs.

The protocol does not prevent:

- threshold committee collusion or early reconstruction;
- committee censorship or liveness failure;
- a funded requester from buying many independent requests and selecting a
  favorable result;
- denial of service against the network or committee; or
- compromise of provider hosts, wallets, transport keys, or secret shares.

## Persistence and History

The beacon publishes its complete JSON state with a monotonically increasing
revision. A Lua VM that loses private globals restores from a newer published
revision. Finalized round records retain the latest 256 rounds. Replay guards,
balances, accruals, and pending requests remain in the published state.

## Interoperability

HyperBEAM's preloaded `rng@1.0` device is the consensus verifier for group
signatures and deterministic derivation. SDK methods are transport adapters;
they do not reimplement or weaken verification.

Protocol-incompatible changes require a new domain and version. `hyperbeam/rng/v1`
must never be reused for different signature messages or derivation formulas.
