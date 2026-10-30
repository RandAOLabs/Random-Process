// The daemon's view of AO: read the beacon's published info and partials,
// post this member's partial and its round attestation.
// Uses the vendored paralith-mono HyperBEAM client (HTTP signatures, push).
import fs from 'node:fs';
import path from 'node:path';
import { readState, sendMessage, jwkToAddress } from '../vendor/hbclient.mjs';

export function loadWallet(cfg) {
  return JSON.parse(fs.readFileSync(path.join(cfg.dataDir, 'provider-wallet.json'), 'utf8'));
}

export async function makeAo(cfg) {
  const jwk = loadWallet(cfg);
  const node = cfg.hbNode;
  return {
    address: jwkToAddress(jwk),
    async beaconInfo() {
      const res = await readState({ node, process: cfg.beacon, path: 'now/beaconinfo' });
      if (res.status !== 200) throw new Error(`beaconinfo: HTTP ${res.status}`);
      return JSON.parse(res.value);
    },
    async beaconPartials() {
      const res = await readState({ node, process: cfg.beacon, path: 'now/beaconpartials' });
      if (res.status !== 200) throw new Error(`beaconpartials: HTTP ${res.status}`);
      return JSON.parse(res.value);
    },
    async postPartial(round, signature) {
      return sendMessage({ node, jwk, process: cfg.beacon, action: 'Partial', data: JSON.stringify({ round, signature }) });
    },
    async postRound(round, signature) {
      return sendMessage({ node, jwk, process: cfg.beacon, action: 'Round', data: JSON.stringify({ round, signature }) });
    },
  };
}
