# HyperBEAM RNG

Verifiable randomness for AO, created and operated by **RNG Labs**, a product
of **CipherPlay Inc.**

## Protocol

HyperBEAM RNG is a multi-surface randomness primitive for AO processes. It
provides deterministic local streams, request-bound threshold BLS, and a
continuous Any-Honest time-lock beacon. HyperBEAM's preloaded `~rng@1.0`
device verifies BLS signatures, time-lock reveals and cracks, and deterministic
byte derivation.

The threshold protocol is in [`v2/SPEC.md`](./v2/SPEC.md); the time-lock beacon,
economics, subscriptions, validators, governance and fair play are in
[`v2/ANY_HONEST.md`](./v2/ANY_HONEST.md).

Any-Honest v3 (branch `permissionless`, not yet deployed) is permissionless
(anyone bonds and validates), governed by the RNG DAO, paid in a fixed-supply
RNG token, and offers fair play. Design: [`v2/docs/PERMISSIONLESS.md`](./v2/docs/PERMISSIONLESS.md);
launch runbook: [`v2/deploy/README.md`](./v2/deploy/README.md).

## Components

- `v2/lib/rng.lua`: deterministic local and beacon-backed Lua API;
- `v2/beacon/beacon.lua`: prepaid, round-locked threshold beacon process;
- `v2/beacon/anyhonest.lua`: Any-Honest beacon v3, permissionless and DAO-governed (2 rounds/s target);
- `v2/fair/fair.lua`, `v2/lib/fair.lua`: fair play (player commit/reveal over a beacon value);
- `v2/provider/`: 2-of-3 BLS committee daemon, joint Feldman DKG, the JS
  Any-Honest validator and the cracker;
- `v2/governance/proposals/`: RNG DAO proposal templates (Exec-Tags for `Gov.*`);
- `v2/token/rng-token.lua`: fixed-supply RNG token (genesis allocation, sealed, `sequenced-v1`);
- `v2/deploy/`: HyperBEAM testnet and provider operations;
- `v2/console/`: live console, documentation, deterministic demo, and MCP
  server; and
- `v2/test/`: RNG, token, beacon, fair play, validator, DKG, BLS, and deploy coverage.

## Use it

Local deterministic randomness is free and needs no wallet or token:

```lua
local rng = require("rng")

rng.on("Loot-Roll", function(stream, ctx)
  grantLoot(ctx.player, stream:int(1, 6))
end)

rng.request(msg, { on = "Loot-Roll", ctx = { player = msg.From } })
```

For value-bearing actions, configure the beacon and request the `beacon` tier.
The threshold testnet charges 3 TEST-RNG per request: one unit for each of two
serving committee members and one protocol unit. An Any-Honest v3 request costs
4 RNG and takes one message (a Transfer with `X-Request-Id`). v3 RNG has no
faucet. Applications should prepay their process balance so end users do not
need to manage RNG.

The live [RNG Labs Console](https://randao.net) shows the current committee,
price, verification mode, and an independently verified round. It also offers
a five-surface [`/try`](https://randao.net/try) console for local derivation,
threshold requests, the continuous Any-Honest beacon, one-shot Any-Honest
requests, and proof exploration. Live proofs and funding state are shown
directly from the native testnet.

## Agent tools

The console exposes an MCP 2026-07-28 endpoint at
`https://randao.net/mcp` with these tools:

- `rng_status`
- `rng_verify_round`
- `rng_anyhonest_status`
- `rng_governance_status`
- `rng_derive`
- `rng_integration_guide`
- `rng_request_plan`

The initial agent surface is read-only except for pure deterministic
derivation. It never accepts or stores wallet keys.

## Development

```bash
cd v2
npm ci
npm test
```

Live deployment commands require `HB_NODE`, `HB_WALLET`, and `SSH_KEY`; no
production endpoint or credential is embedded in the source.

## Security model

- A request set locks before its first partial signature is published.
- Any threshold of valid BLS shares produces the unique round signature.
- Production mode verifies partials and the group signature through
  HyperBEAM's `~rng@1.0` device.
- The current testnet can use a weaker threshold wallet-attestation fallback.
- Committee censorship and threshold compromise remain explicit trust risks.

See [`v2/SPEC.md`](./v2/SPEC.md) for the complete guarantees and non-guarantees.

## Ownership and licensing

Copyright © 2026 **CipherPlay Inc.** and contributors. RNG Labs is a CipherPlay
Inc. product and the protocol steward.

All rights are reserved unless an explicit license says otherwise. This
repository does not currently grant an open-source or commercial license to
the protocol implementation, provider software, beacon service, or SDK.
Contact CipherPlay Inc. for licensing.
