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

