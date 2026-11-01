// Writes to HyperBEAM as ANS-104 data items: the path browsers use, accepted
// by both the old fork and v0.11-RC7 (RC7 rejects the old httpsig keyids).
// Reads and pushes still go through the vendored client.
import { signDataItem } from '../vendor/ans104.mjs';
import { nodeAddress, queuePush } from '../vendor/hbclient.mjs';

const tagList = (o) => Object.entries(o).filter(([, v]) => v !== undefined && v !== null)
  .map(([name, value]) => ({ name, value: String(value) }));

async function post(node, path, jwk, item) {
  const body = await signDataItem(jwk, item);
  const res = await fetch(`${node}${path}?codec-device=ans104@1.0`, {
    method: 'POST', headers: { 'content-type': 'application/ans104', 'accept-bundle': 'true' }, body,
  });
  if (!res.ok) {
    const detail = (res.headers.get('details') || await res.text()).slice(0, 400);
    throw new Error(`${path}: HTTP ${res.status} ${detail}`);
  }
  await res.arrayBuffer().catch(() => {});
  return res.headers;
}

/** Spawn a lua@5.3a process scheduled on `node`. Returns its id. */
export async function spawnLua({ node, jwk, lua, tags = {} }) {
  const h = await post(node, '/~scheduler@1.0/schedule', jwk, {
    data: lua,
    tags: tagList({
      device: 'process@1.0', type: 'Process', 'scheduler-device': 'scheduler@1.0',
      'execution-device': 'lua@5.3a', 'scheduler-location': await nodeAddress(node),
      'content-type': 'application/lua', 'random-seed': String(Math.random()), ...tags,
    }),
  });
  const id = h.get('process');
  if (!id) throw new Error('spawn returned no process id');
  return id;
}

/** Schedule a message; its outbox is pushed in the background. Returns the slot. */
export async function message({ node, jwk, process: pid, action, tags = {}, data = '' }) {
  const h = await post(node, `/${pid}~process@1.0/schedule`, jwk, {
    target: pid, data,
    tags: tagList({ type: 'Message', action, ...tags, 'random-seed': String(Math.random()) }),
  });
  const slot = Number(h.get('slot'));
  if (Number.isFinite(slot)) queuePush({ node, process: pid, slot });
  return slot;
}
