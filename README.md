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
- `v2/deploy/`: HyperBEAM testnet and provider operations; and
- `v2/test/`: RNG, token, beacon, DKG, BLS, and interoperability coverage.

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
