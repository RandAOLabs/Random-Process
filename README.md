# HyperBEAM RNG

Verifiable randomness for AO, created and operated by **RNG Labs**, a product
of **CipherPlay Inc.**

## Protocol

HyperBEAM RNG is a threshold-BLS randomness primitive for AO processes. A
distributed committee produces deterministic BLS12-381 signatures; HyperBEAM's
preloaded `~rng@1.0` device verifies those signatures and derives replay-stable
random bytes.

The canonical protocol, trust model, round-locking rules, and domain-separated
derivations are in [`v2/SPEC.md`](./v2/SPEC.md).

## Components

- `v2/lib/rng.lua`: deterministic local and beacon-backed Lua API;
- `v2/beacon/beacon.lua`: prepaid, round-locked threshold beacon process;
- `v2/provider/`: 2-of-3 BLS committee daemon and joint Feldman DKG;
- `v2/token/rng-token.lua`: replay-safe test payment token;
- `v2/deploy/`: HyperBEAM testnet and provider operations;
- `v2/console/`: live console, documentation, deterministic demo, and MCP
  server; and
- `v2/test/`: RNG, token, beacon, DKG, BLS, and interoperability coverage.

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
The testnet currently charges 3 TEST-RNG per request: one unit for each of two
serving committee members and one protocol unit. Test credits have no monetary
value and are available from the signed faucet. Applications should prepay
their process balance so end users do not need to manage RNG credits.

The live [RNG Labs Console](https://randao.net) shows the current committee,
price, verification mode, and an independently verified round. It also offers
a dedicated three-mode [`/try`](https://randao.net/try) console for local
derivation, live-round verification, and a guided Wander threshold request,
plus current Lua, JavaScript, and HTTP examples.

## Agent tools

The console exposes an MCP 2026-07-28 endpoint at
`https://randao.net/mcp` with these tools:

- `rng_status`
- `rng_verify_round`
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
