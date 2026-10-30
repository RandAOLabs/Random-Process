// HyperBEAM RNG provider daemon by RNG Labs, a CipherPlay Inc. product.
//
//   node provider/daemon.mjs init <config>   create this node's provider wallet and DKG transport key;
//                                            print the wallet address and transport public key
//   node provider/daemon.mjs dkg-unsafe-http <config>  development-only ceremony over unauthenticated HTTP
//   node provider/daemon.mjs run  <config>   post partials and attest rounds through the beacon
//
// Config (JSON): { index, n, t, beacon, listen, dataDir, wallet, hbNode,
//                  peers: [{ index, url, dkgPub }] }   (peers excludes self)
import fs from 'node:fs';
import path from 'node:path';
import http from 'node:http';
import crypto from 'node:crypto';
import * as bls from './bls.mjs';
import { makeAo } from './ao.mjs';
import { jwkToAddress } from '../vendor/hbclient.mjs';

const [cmd, configPath] = process.argv.slice(2);
const cfg = JSON.parse(fs.readFileSync(configPath, 'utf8'));
const file = (name) => path.join(cfg.dataDir, name);
const log = (...a) => console.log(new Date().toISOString(), ...a);
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// --- share encryption: x25519 + HKDF + AES-256-GCM --------------------------

function loadTransportKey() {
  return crypto.createPrivateKey(fs.readFileSync(file('dkg-transport.pem')));
}

function seal(recipientPubB64, plaintext) {
  const eph = crypto.generateKeyPairSync('x25519');
  const peer = crypto.createPublicKey({ key: Buffer.from(recipientPubB64, 'base64'), format: 'der', type: 'spki' });
  const key = Buffer.from(crypto.hkdfSync('sha256', crypto.diffieHellman({ privateKey: eph.privateKey, publicKey: peer }), Buffer.alloc(0), 'hyperbeam-rng/dkg/v1', 32));
  const iv = crypto.randomBytes(12);
  const c = crypto.createCipheriv('aes-256-gcm', key, iv);
  const ct = Buffer.concat([c.update(plaintext, 'utf8'), c.final()]);
  return {
    eph: eph.publicKey.export({ format: 'der', type: 'spki' }).toString('base64'),
    iv: iv.toString('base64'), ct: ct.toString('base64'), tag: c.getAuthTag().toString('base64'),
  };
}

function open(box, privateKey) {
  const eph = crypto.createPublicKey({ key: Buffer.from(box.eph, 'base64'), format: 'der', type: 'spki' });
  const key = Buffer.from(crypto.hkdfSync('sha256', crypto.diffieHellman({ privateKey, publicKey: eph }), Buffer.alloc(0), 'hyperbeam-rng/dkg/v1', 32));
  const d = crypto.createDecipheriv('aes-256-gcm', key, Buffer.from(box.iv, 'base64'));
  d.setAuthTag(Buffer.from(box.tag, 'base64'));
  return Buffer.concat([d.update(Buffer.from(box.ct, 'base64')), d.final()]).toString('utf8');
}

// --- HTTP helpers -------------------------------------------------------------

function serve(routes, host) {
  const server = http.createServer(async (req, res) => {
    const url = new URL(req.url, 'http://x');
    const route = routes[url.pathname];
    try {
      const body = route ? await route(url.searchParams) : null;
      res.writeHead(body ? 200 : 404, { 'content-type': 'application/json' });
      res.end(JSON.stringify(body ?? { error: 'not found' }));
    } catch (e) {
      res.writeHead(500, { 'content-type': 'application/json' });
      res.end(JSON.stringify({ error: e.message }));
    }
  });
  server.listen(cfg.listen, host);
  return server;
}

async function getJson(url) {
  const r = await fetch(url, { signal: AbortSignal.timeout(3000) });
  if (!r.ok) throw new Error(`${url}: HTTP ${r.status}`);
  return r.json();
}

// --- commands -----------------------------------------------------------------

if (cmd === 'init') {
  fs.mkdirSync(cfg.dataDir, { recursive: true });
  if (fs.existsSync(file('dkg-transport.pem'))) throw new Error('transport key already exists');
  const { privateKey, publicKey } = crypto.generateKeyPairSync('x25519');
  fs.writeFileSync(file('dkg-transport.pem'), privateKey.export({ format: 'pem', type: 'pkcs8' }), { mode: 0o600 });
  // The wallet this member signs Round posts with. Its own key, not the node's.
  const wallet = crypto.generateKeyPairSync('rsa', { modulusLength: 4096, publicExponent: 65537 })
    .privateKey.export({ format: 'jwk' });
  fs.writeFileSync(file('provider-wallet.json'), JSON.stringify({ kty: 'RSA', ...wallet }), { mode: 0o600 });
  console.log(JSON.stringify({
    index: cfg.index, address: jwkToAddress(wallet),
    dkgPub: publicKey.export({ format: 'der', type: 'spki' }).toString('base64'),
  }));
}

if (cmd === 'dkg-unsafe-http') {
  if (cfg.allowInsecureHttpDkg !== true) {
    throw new Error('unauthenticated HTTP DKG is disabled; use the offline SSH ceremony');
  }
  if (fs.existsSync(file('share.json'))) throw new Error('share.json already exists; move it aside to re-run the ceremony');
  const deal = bls.dkgDeal(cfg.n, cfg.t);
  const sealed = {};
  for (const p of cfg.peers) sealed[p.index] = seal(p.dkgPub, deal.shares[p.index]);
  const server = serve({ '/dkg/deal': async () => ({ index: cfg.index, commitments: deal.commitments, shares: sealed }) });
  log(`dealt; serving on :${cfg.listen}, waiting for ${cfg.peers.length} peers`);

  const priv = loadTransportKey();
  const received = { [cfg.index]: deal.shares[cfg.index] };
  const commitments = { [cfg.index]: deal.commitments };
  while (Object.keys(commitments).length < cfg.n) {
    for (const p of cfg.peers) {
      if (commitments[p.index]) continue;
      try {
        const d = await getJson(`${p.url}/dkg/deal`);
        const share = open(d.shares[cfg.index], priv);
        if (!bls.dkgVerifyShare(cfg.index, share, d.commitments)) throw new Error(`share from ${p.index} fails its commitments`);
        received[p.index] = share;
        commitments[p.index] = d.commitments;
        log(`verified deal from member ${p.index}`);
      } catch (e) { if (/fails/.test(e.message)) throw e; }
    }
    await sleep(1000);
  }
  const result = bls.dkgFinish(cfg.index, cfg.n, cfg.t, received, commitments);
  fs.writeFileSync(file('share.json'), JSON.stringify(result), { mode: 0o600 });
  fs.writeFileSync(file('transcript.json'), JSON.stringify({ commitments, groupKey: result.groupKey, sharePublicKeys: result.sharePublicKeys }, null, 1));
  log('ceremony done; groupKey', result.groupKey);
  // Keep serving briefly so slower peers can still fetch our deal.
  await sleep(30_000);
  server.close();
}

// Offline ceremony, for nodes that cannot reach each other: each node deals to
// a file, the operator copies every deal to every node (shares are sealed to
// their recipients), then each node finishes from those files.
if (cmd === 'dkg-deal') {
  if (fs.existsSync(file('share.json'))) throw new Error('share.json already exists');
  const deal = bls.dkgDeal(cfg.n, cfg.t);
  const sealed = {};
  for (const p of cfg.peers) sealed[p.index] = seal(p.dkgPub, deal.shares[p.index]);
  fs.writeFileSync(file('dkg-own.json'), JSON.stringify({ share: deal.shares[cfg.index], commitments: deal.commitments }), { mode: 0o600 });
  fs.writeFileSync(file(`deal-${cfg.index}.json`), JSON.stringify({ index: cfg.index, commitments: deal.commitments, shares: sealed }));
  console.log(`deal-${cfg.index}.json written`);
}

if (cmd === 'dkg-finish') {
  if (fs.existsSync(file('share.json'))) throw new Error('share.json already exists');
  const own = JSON.parse(fs.readFileSync(file('dkg-own.json'), 'utf8'));
  const priv = loadTransportKey();
  const received = { [cfg.index]: own.share };
  const commitments = { [cfg.index]: own.commitments };
  for (const p of cfg.peers) {
    const d = JSON.parse(fs.readFileSync(file(`deal-${p.index}.json`), 'utf8'));
    received[p.index] = open(d.shares[cfg.index], priv);
    commitments[p.index] = d.commitments;
  }
  const result = bls.dkgFinish(cfg.index, cfg.n, cfg.t, received, commitments);
  fs.writeFileSync(file('share.json'), JSON.stringify(result), { mode: 0o600 });
  fs.writeFileSync(file('transcript.json'), JSON.stringify({ commitments, groupKey: result.groupKey, sharePublicKeys: result.sharePublicKeys }, null, 1));
  fs.rmSync(file('dkg-own.json'));
  console.log(JSON.stringify({ index: cfg.index, groupKey: result.groupKey }));
}

if (cmd === 'run') {
  // Everything goes through the beacon on HyperBEAM: post our partial, read
  // the others' from the published `beaconpartials`, combine t, attest. The
  // nodes never connect to each other, so no port has to be opened.
  const share = JSON.parse(fs.readFileSync(file('share.json'), 'utf8'));
  if (share.index !== cfg.index
      || (share.n !== undefined && share.n !== cfg.n)
      || (share.t !== undefined && share.t !== cfg.t)) {
    throw new Error('share.json committee parameters do not match config');
  }
  const ao = await makeAo(cfg);
  let info = null;
  let partialFor = 0;
  let attested = 0;
  let partialAttempt = { round: 0, at: 0 };
  let roundAttempt = { round: 0, at: 0 };
  let validated = false;
  let lastSuccessAt = 0;
  let lastError = null;

  serve({ '/health': async () => ({
    healthy: lastSuccessAt > 0 && Date.now() - lastSuccessAt < 10_000,
    index: share.index, address: ao.address, round: info?.round, attested,
    lastSuccessAt, lastError,
  }) }, '127.0.0.1');
  log(`member ${share.index} (${ao.address}) running; health on 127.0.0.1:${cfg.listen}`);

  for (;;) {
    try {
      info = await ao.beaconInfo();
      if (!validated) {
        const member = info.committee.find((m) => m.address === ao.address);
        if (info.groupKey.toLowerCase() !== share.groupKey.toLowerCase()
            || info.threshold !== cfg.t || member?.index !== share.index
            || (member?.['public-key']
              && member['public-key'].toLowerCase() !== share.publicKey.toLowerCase())) {
          const error = new Error('beacon committee configuration does not match share.json');
          error.fatal = true;
          throw error;
        }
        validated = true;
      }
      lastSuccessAt = Date.now();
      lastError = null;
      attested = Math.max(attested, info.round);
      const r = info.nextRound;
      const message = `hyperbeam/rng/v1|${cfg.beacon}|${r}`;
      if (info.roundPendingCount > 0 && Date.now() >= info.nextRoundAt) {
        const mine = bls.partialSign(share, message);
        if (partialFor < r && (partialAttempt.round !== r || Date.now() - partialAttempt.at >= 10_000)) {
          await ao.postPartial(r, mine);
          partialAttempt = { round: r, at: Date.now() };
        }
        if (attested < r) {
          const posted = await ao.beaconPartials();
          if (posted.round === r && posted.by?.[ao.address] === mine) partialFor = r;
          const partials = [{ index: share.index, signature: mine }];
          if (posted.round === r) {
            for (const m of info.committee) {
              const sig = posted.by?.[m.address];
              if (m.index === share.index || !sig || partials.length >= cfg.t) continue;
              if (bls.verifyPartial(share.sharePublicKeys[m.index], message, sig)) partials.push({ index: m.index, signature: sig });
              else log(`member ${m.index} posted an invalid partial for round ${r}`);
            }
          }
          if (partials.length >= cfg.t) {
            const signature = bls.combine(partials.slice(0, cfg.t));
            if (!bls.verify(share.groupKey, message, signature)) throw new Error(`combined signature for round ${r} does not verify`);
            if (roundAttempt.round !== r || Date.now() - roundAttempt.at >= 10_000) {
              await ao.postRound(r, signature);
              roundAttempt = { round: r, at: Date.now() };
              log(`submitted round ${r} (${info.roundPendingCount} pending)`);
            }
          }
        }
      }
    } catch (e) {
      if (e.fatal) throw e;
      lastError = e.message;
      log('loop error:', e.message);
    }
    await sleep(1000);
  }
}
