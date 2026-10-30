#!/usr/bin/env bash
# Install and operate the HyperBEAM RNG provider daemon on the committee nodes.
#
#   deploy/nodes.sh install  <tgz>   copy an archive containing app/ to every node
#   deploy/nodes.sh init             create each node's provider wallet + DKG key
#   deploy/nodes.sh beacon <id>      point existing committee keys at a new beacon
#   deploy/nodes.sh dkg-unsafe-http  development only; unauthenticated peer transport
#   deploy/nodes.sh dkg-offline      same ceremony, deals relayed through this machine over SSH
#   deploy/nodes.sh start            start the daemon (docker, restart unless-stopped)
#   deploy/nodes.sh status | logs    health and recent logs
#
# The daemon runs in node:22-slim with host networking, so each host's own
# firewall decides who can reach port $PORT. Files live in /opt/rng-provider.
set -euo pipefail

KEY="${SSH_KEY:?set SSH_KEY to the committee SSH private key}"
PORT=7477
BASE=/opt/rng-provider
IMAGE=node:22-slim
# index name ip
NODES=("1 main 176.9.219.106" "2 paralith 49.12.125.122" "3 rng 138.201.220.159")

ssh_() { ssh -i "$KEY" -o BatchMode=yes -o IdentitiesOnly=yes -o ConnectTimeout=15 "root@$1" "${@:2}"; }
run_() { # ip, daemon command
  ssh_ "$1" "docker run --rm --network host -v $BASE:/srv $IMAGE node /srv/app/provider/daemon.mjs $2 /srv/config.json"
}

case "${1:-}" in
  install)
    for n in "${NODES[@]}"; do read -r i name ip <<<"$n"
      scp -i "$KEY" -o BatchMode=yes -o IdentitiesOnly=yes "$2" "root@$ip:/tmp/rng-provider.tgz"
      ssh_ "$ip" "mkdir -p $BASE/data && chmod 700 $BASE/data && rm -rf $BASE/app && tar -C $BASE -xzf /tmp/rng-provider.tgz && docker pull -q $IMAGE >/dev/null && echo $name installed"
    done ;;
  config) # config <beacon> <hbNode> <peers.json>: write each node's config.json
    for n in "${NODES[@]}"; do read -r i name ip <<<"$n"
      node -e '
        const [i, beacon, hbNode, peersFile, port] = process.argv.slice(1);
        const peers = JSON.parse(require("fs").readFileSync(peersFile, "utf8")).filter((p) => p.index !== +i);
        console.log(JSON.stringify({ index: +i, n: 3, t: 2, beacon, hbNode, listen: +port, dataDir: "/srv/data", peers }));
      ' "$i" "$2" "$3" "$4" "$PORT" | ssh_ "$ip" "cat > $BASE/config.json"
      echo "$name configured"
    done ;;
  init)
    for n in "${NODES[@]}"; do read -r i name ip <<<"$n"
      ssh_ "$ip" "test -f $BASE/config.json || echo '{\"index\":$i,\"dataDir\":\"/srv/data\"}' > $BASE/config.json"
      echo "$(run_ "$ip" init) $ip"
    done ;;
  beacon)
    for n in "${NODES[@]}"; do read -r i name ip <<<"$n"
      ssh_ "$ip" "docker run --rm -v $BASE:/srv $IMAGE node -e '
        const fs = require(\"fs\");
        const cfg = JSON.parse(fs.readFileSync(\"/srv/config.json\", \"utf8\"));
        cfg.beacon = process.argv[1];
        fs.writeFileSync(\"/srv/config.json\", JSON.stringify(cfg));
      ' '$2'"
      echo "$name beacon updated"
    done ;;
  dkg-unsafe-http)
    for n in "${NODES[@]}"; do read -r i name ip <<<"$n"
      run_ "$ip" dkg-unsafe-http > "/tmp/rng-dkg-$name.log" 2>&1 &
    done
    wait
    for n in "${NODES[@]}"; do read -r i name ip <<<"$n"
      echo "== $name"; tail -n 3 "/tmp/rng-dkg-$name.log"
      ssh_ "$ip" "cat $BASE/data/transcript.json" > "/tmp/rng-transcript-$name.json"
    done ;;
  dkg-offline)
    tmp="$(mktemp -d)"
    for n in "${NODES[@]}"; do read -r i name ip <<<"$n"
      run_ "$ip" dkg-deal >/dev/null
      ssh_ "$ip" "cat $BASE/data/deal-$i.json" > "$tmp/deal-$i.json"
    done
    for n in "${NODES[@]}"; do read -r i name ip <<<"$n"
      for f in "$tmp"/deal-*.json; do
        [ "$(basename "$f")" = "deal-$i.json" ] || ssh_ "$ip" "cat > $BASE/data/$(basename "$f")" < "$f"
      done
      echo "$name $(run_ "$ip" dkg-finish)"
    done
    rm -rf "$tmp" ;;
  start)
    for n in "${NODES[@]}"; do read -r i name ip <<<"$n"
      ssh_ "$ip" "docker rm -f rng-provider >/dev/null 2>&1; docker run -d --name rng-provider --restart unless-stopped --network host -v $BASE:/srv $IMAGE node /srv/app/provider/daemon.mjs run /srv/config.json >/dev/null && echo $name started"
    done ;;
  status)
    failed=0
    for n in "${NODES[@]}"; do read -r i name ip <<<"$n"
      result="$(ssh_ "$ip" "docker ps --filter name=rng-provider --format '{{.Status}}'; curl -fsS -m 3 http://127.0.0.1:$PORT/health")"
      echo "$name: $result"
      [[ "$result" == *'"healthy":true'* ]] || failed=1
    done
    exit "$failed" ;;
  logs)
    for n in "${NODES[@]}"; do read -r i name ip <<<"$n"
      echo "== $name"; ssh_ "$ip" "docker logs --tail ${2:-15} rng-provider 2>&1"
    done ;;
  *) sed -n '2,10p' "$0"; exit 1 ;;
esac
