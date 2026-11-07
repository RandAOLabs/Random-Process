# RNG Labs product model

RNG Labs presents one HyperBEAM-native cryptographic core, `~rng@1.0`, through
five product surfaces. A surface may be a randomness source, a delivery mode,
or an inspection tool; they are not five equivalent security tiers.

| Surface | Contract | Current status |
|---|---|---|
| **Local** | Deterministic, replay-safe bytes. Predictable to the sender. | Live |
| **Fast** | On-demand 2-of-3 threshold BLS: a paid request binds before the committee can reconstruct its result. About one message phase; safe unless 2 of 3 operators collude. Not a heartbeat: rounds open only for paid requests. | v2 process live on the old token; v3 (RNG token, DAO-governed) built, cutover pending |
| **Beacon** | A Foundation-funded continuous stream of shared Any-Honest rounds. | v2 live on the native testnet; v3 built, cutover pending |
| **Any-Honest** | Time-lock commit/reveal remains unpredictable while one validator is honest; withheld outputs can be cracked. | v2 live; v3 built, cutover pending |
| **Fair play** | The player's own committed secret makes each draw fair to them, even if every validator and the game collude. | v3 built, not deployed |
| **Proof Explorer** | Fetch and independently verify retained rounds and derived values. | Live |

The device namespace owns deterministic cryptographic operations: derivation,
BLS verification, time-lock generators, reveal checks, and crack checks. The
RNG library and beacon processes own messaging, request binding, subscriptions,
balances, and fees.

The randomness tiers, weakest to strongest:

| Tier | Safe unless | Speed |
|---|---|---|
| Local | always predictable to the sender | immediate, free |
| Fast | 2 of 3 committee operators collude | about one message phase |
| Any-Honest | every validator colludes (one honest one is enough) | slower (commit and reveal windows) |

The fast-tier implementation (`beacon/beacon.lua`) and `SPEC.md` use `beacon`
as a legacy technical id for it. Product-facing interfaces call that surface
**Fast**; it is not a beacon. **Beacon** is the continuously advancing
Any-Honest public feed.

Any-Honest v3 is permissionless and DAO-governed:

- anyone becomes a validator by bonding the stake; nobody admits or removes
  validators except the DAO, which always refunds the bond;
- the RNG DAO (YapDAO `stake-dao/1`, staking RNG) sets parameters inside hard
  bounds, with a 7-day delay on anything that moves the beacon or its reserve;
- RNG has a fixed supply of 1,000,000,000, minted once at genesis, with no
  faucet and no mint. Users get RNG from allocations or the market.

Do not describe v3 as live until the cutover in
[`deploy/README.md`](./deploy/README.md) has passed `deploy.mjs verify` and the
DAO handover proof. The protocol is [`ANY_HONEST.md`](./ANY_HONEST.md); the
threshold protocol remains in [`SPEC.md`](./SPEC.md).
