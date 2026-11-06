# Native testnet operations

`native-testnet.json` is the canonical public process inventory: token,
threshold beacon, Any-Honest beacon, committees, validators, DAO, and live
subscription acceptance process.

The HyperBEAM node is recreated through `compose.hyperbeam-stage.yaml`. Its
process cache, node key, and node configuration are host-mounted, so changing
the runtime image does not discard DAO proposals, stakes, votes, beacon state,
balances, or historical process implementation IDs.

Promote a tested runtime under the stable tag, then recreate it:

```bash
docker tag runerealm-hb:<candidate> runerealm-hb:rng-current
docker compose -f /opt/hyperbeam-rng-stage/compose.yaml up -d --force-recreate
curl -fsS -H 'Accept: application/json' \
  https://randao.net/hb-stage/~rng@1.0/generator
curl -fsS https://randao.net/api/anyhonest
curl -fsS https://randao.net/api/dao
```

Keep the previous container and image until the device, beacon, DAO, console,
validators, and authenticated subscription path have all been verified.

Ordinary runtime and console deployments reuse the existing DAO. A deliberate
new-network migration must update `native-testnet.json`, the console deployment
environment, and the Sites runtime environment together.


## Any-Honest cracker

Its own container, separate from HyperBEAM, pinned to one core the node does not use (on a shared host the node runs on cores 1-15, daemons on core 0):

```bash
docker build -t rng-cracker -f provider/Dockerfile.cracker .
mkdir -p /opt/rng-cracker && echo '{"beacon":"<anyHonest>","hbNode":"https://hyperbeam.tylerw.ai","dataDir":"/data","listen":7479}' > /opt/rng-cracker/config.json
docker run --rm -v /opt/rng-cracker:/data rng-cracker init /data/config.json   # prints its address
docker run -d --name rng-cracker --restart unless-stopped --cpuset-cpus=0 --network host   -v /opt/rng-cracker:/data rng-cracker run /data/config.json
docker run --rm -v /opt/rng-cracker:/data rng-cracker claim /data/config.json  # withdraw bounties
```

## Any-Honest beacon cutover

The beacon is a process: replacing it needs no node rebuild. `kqzobErk` (the
lua@5.3a beacon) has no successor support, so this first cutover changes the
validators' node config; later ones use `Admin.Set-Successor` and need none.

1. `spawn-anyhonest --replace <reason>` (lua-patch@1.0), then
   `configure-anyhonest deploy/anyhonest-validators.json` (records the old
   beacon as `predecessor`).
2. Fund it: `fund-anyhonest <foundation> <treasury>` from the owner (the
   reserve of a lua@5.3a beacon cannot move; later beacons use
   `Admin.Move-Reserve`). It bonds 25,000 per validator.
3. Roll a node build with the current `rng-validator@1.0`, with
   `rng-validator.beacon` set to the new id. The devices say Ready on their own.
4. Point the crackers (`/opt/rng-cracker/data/config.json` on the side nodes)
   at the new id and restart them; update `native-testnet.json` and the
   console's `RNG_ANYHONEST_ID`.

Before stopping a validator node, create `pause` in its `secrets-dir` and wait
for `ready: false` in `/~rng-validator@1.0/status`; a ready validator stopped
without pausing is slashed for every round it does not finish.
