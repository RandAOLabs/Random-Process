#!/bin/sh
set -eu

: "${RNG_NODE_URL:?RNG_NODE_URL is required}"
: "${RNG_BEACON_ID:?RNG_BEACON_ID is required}"
: "${RNG_TOKEN_ID:?RNG_TOKEN_ID is required}"

exec npm run start:container -- \
  --port "${PORT:-4180}" \
  --var "RNG_NODE_URL:${RNG_NODE_URL}" \
  --var "RNG_BEACON_ID:${RNG_BEACON_ID}" \
  --var "RNG_TOKEN_ID:${RNG_TOKEN_ID}" \
  --var "RNG_NETWORK_LABEL:${RNG_NETWORK_LABEL:-Testnet}"
