import assert from 'node:assert/strict';
import fs from 'node:fs';
import test from 'node:test';

const state = JSON.parse(fs.readFileSync(new URL('../deploy/native-testnet.json', import.meta.url)));
const env = Object.fromEntries(
  fs.readFileSync(new URL('../console/deploy/native-testnet.env', import.meta.url), 'utf8')
    .split(/\r?\n/)
    .filter(Boolean)
    .map((line) => line.split(/=(.*)/s).slice(0, 2)),
);

test('console deployment follows the canonical native-testnet processes', () => {
  assert.equal(env.RNG_TOKEN_ID, state.token);
  assert.equal(env.RNG_BEACON_ID, state.beacon);
  assert.equal(env.RNG_ANYHONEST_ID, state.anyHonest);
  assert.equal(env.RNG_DAO_ID, state.dao);
});

test('deployment manifests retain state and load the pinned console environment', () => {
  const consoleCompose = fs.readFileSync(new URL('../console/deploy/compose.yaml', import.meta.url), 'utf8');
  const hyperbeamCompose = fs.readFileSync(new URL('../deploy/compose.hyperbeam-stage.yaml', import.meta.url), 'utf8');
  assert.match(consoleCompose, /native-testnet\.env/);
  assert.match(hyperbeamCompose, /store-overlay5:\/app\/cache-mainnet/);
  assert.match(hyperbeamCompose, /node-config\.json:\/app\/node-config\.json:ro/);
});
