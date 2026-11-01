# RNG Labs product model

RNG Labs presents one HyperBEAM-native cryptographic core, `~rng@1.0`, through
five product surfaces. A surface may be a randomness source, a delivery mode,
or an inspection tool; they are not five equivalent security tiers.

| Surface | Contract | Current status |
|---|---|---|
| **Local** | Deterministic, replay-safe bytes. Predictable to the sender. | Live |
| **Threshold** | A request is bound before a 2-of-3 BLS committee can reconstruct its result. | Live |
| **Beacon** | A continuous stream of shared public rounds that are free to read and verify. | Not deployed; the current Threshold service is on demand |
| **Any-Honest** | Time-lock commit/reveal remains unpredictable while one validator is honest; withheld outputs can be cracked. | Restoring from the earlier implementation |
| **Proof Explorer** | Fetch and independently verify retained rounds and derived values. | Live |

The device namespace owns deterministic cryptographic operations: derivation,
BLS verification, time-lock generators, reveal checks, and crack checks. The
RNG library and beacon processes own messaging, request binding, subscriptions,
balances, and fees.

The current implementation and `SPEC.md` still use `beacon` as a technical
alias for the on-demand Threshold process. Product-facing interfaces call that
surface **Threshold**. **Beacon** is reserved for the continuously advancing
public feed and must not be labeled live while it is static.

Any-Honest must not be described as live until its earlier implementation is
re-audited against the current protocol, merged under `~rng@1.0`, deployed to
the native testnet, and exercised through the console. The current implemented
protocol remains defined by [`SPEC.md`](./SPEC.md).
