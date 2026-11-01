# RNG console deployment

The public console is recreated through `compose.yaml`, not an ad hoc
`docker run`. `native-testnet.env` pins the token, threshold beacon,
Any-Honest beacon, and advisory DAO processes from
`v2/deploy/native-testnet.json`.

Build and validate a candidate image, then promote it under the stable tag:

```bash
docker tag rng-console:<candidate> rng-console:current
docker compose -f /opt/rng-console-deploy/compose.yaml up -d --force-recreate
curl -fsS https://randao.net/api/status
curl -fsS https://randao.net/api/anyhonest
curl -fsS https://randao.net/api/dao
```

Source-only deployments retain every process ID because Compose reloads the
tracked environment file. If a protocol migration intentionally changes a
process ID, update `native-testnet.json`, this environment file, and the Sites
runtime environment in the same change.

The DAO is an independent AO process. Rebuilding the console, HyperBEAM node,
or beacon provider containers does not reset DAO proposals, stakes, or votes.

