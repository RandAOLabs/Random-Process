# RNG Labs product model

RNG Labs presents one HyperBEAM-native cryptographic core, `~rng@1.0`, through
five product surfaces. A surface may be a randomness source, a delivery mode,
or an inspection tool; they are not five equivalent security tiers.

| Surface | Contract | Current status |
|---|---|---|
| **Local** | Deterministic, replay-safe bytes. Predictable to the sender. | Live |
| **Threshold** | A request is bound before a 2-of-3 BLS committee can reconstruct its result. | Live |
| **Beacon** | A Foundation-funded continuous stream of shared Any-Honest rounds. | Live on the native testnet |
| **Any-Honest** | Time-lock commit/reveal remains unpredictable while one validator is honest; withheld outputs can be cracked. | Live on the native testnet |
| **Proof Explorer** | Fetch and independently verify retained rounds and derived values. | Live |

The device namespace owns deterministic cryptographic operations: derivation,
BLS verification, time-lock generators, reveal checks, and crack checks. The
RNG library and beacon processes own messaging, request binding, subscriptions,
balances, and fees.

The threshold implementation and `SPEC.md` use `beacon` as a legacy technical
alias for the on-demand Threshold process. Product-facing interfaces call that
surface **Threshold**. **Beacon** is the continuously advancing Any-Honest
public feed.

Any-Honest must not be described as live until the unified device is deployed
to the native testnet and the heartbeat, reserve, subscription, exit, and crack
flows pass live verification. Its protocol is defined by
[`ANY_HONEST.md`](./ANY_HONEST.md); the threshold protocol remains in
[`SPEC.md`](./SPEC.md).
