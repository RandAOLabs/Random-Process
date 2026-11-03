#!/bin/sh
set -eu

: "${RNG_NODE_URL:?RNG_NODE_URL is required}"
: "${RNG_BEACON_ID:?RNG_BEACON_ID is required}"
: "${RNG_TOKEN_ID:?RNG_TOKEN_ID is required}"

npm run start:container -- \
  --port "${PORT:-4180}" \
  --var "RNG_NODE_URL:${RNG_NODE_URL}" \
  --var "RNG_BEACON_ID:${RNG_BEACON_ID}" \
  --var "RNG_TOKEN_ID:${RNG_TOKEN_ID}" \
  --var "RNG_ANYHONEST_ID:${RNG_ANYHONEST_ID:-}" \
  --var "RNG_DAO_ID:${RNG_DAO_ID:-}" \
  --var "RNG_NETWORK_LABEL:${RNG_NETWORK_LABEL:-Testnet}" &
SERVER=$!

# workerd can die (it ran out of heap after ~70 min on 2026-11-02) while the
# wrangler parent lives on, so the container stayed "Up" and served nothing for
# hours. Any HTTP answer counts as alive -- /api/status is legitimately 502
# while the beacon is unseeded -- but three missed answers in a row exit the
# container, and its restart policy brings it back.
(
  sleep 60
  misses=0
  while kill -0 "$SERVER" 2>/dev/null; do
    if node -e "fetch('http://127.0.0.1:'+(process.env.PORT||4180)+'/',{signal:AbortSignal.timeout(10000)}).then(()=>process.exit(0),()=>process.exit(1))"; then
      misses=0
    else
      misses=$((misses + 1))
      echo "watchdog: no answer ($misses/3)" >&2
      if [ "$misses" -ge 3 ]; then
        echo "watchdog: server is not answering; exiting so the container restarts" >&2
        kill "$SERVER" 2>/dev/null || true
        sleep 5
        kill -9 "$SERVER" 2>/dev/null || true
        exit 0
      fi
    fi
    sleep 30
  done
) &

trap 'kill "$SERVER" 2>/dev/null' TERM INT
wait "$SERVER"
exit 1
