// Threshold BLS for the beacon committee (BLS12-381, public keys in G1,
// signatures in G2: 48-byte keys, 96-byte signatures).
//
// Any t of n partial signatures combine into the same group signature, which
// verifies as an ordinary BLS signature under the group public key.
//
// Keys come from a joint-Feldman DKG (dkgDeal / dkgVerifyShare / dkgFinish):
// every member deals a random polynomial, so no one ever holds the group key.
// dealerKeygen remains for tests only.
import { bls12_381 as bls } from '@noble/curves/bls12-381.js';

const { Fr } = bls.fields;
const G1 = bls.G1.Point;
const G2 = bls.G2.Point;
const sigs = bls.longSignatures;
const enc = new TextEncoder();

const randomScalar = () => {
  const bytes = bls.utils.randomSecretKey();
  return Fr.create(BigInt('0x' + Buffer.from(bytes).toString('hex')));
};

const validateThreshold = (n, t) => {
  if (!Number.isSafeInteger(n) || !Number.isSafeInteger(t) || !(t >= 1 && t <= n)) {
    throw new Error('need integer 1 <= t <= n');
  }
};

/** Shares for an n-member committee where any t can sign. */
export function dealerKeygen(n, t) {
  validateThreshold(n, t);
  const coeffs = Array.from({ length: t }, randomScalar);
  const f = (x) => coeffs.reduceRight((acc, c) => Fr.add(Fr.mul(acc, x), c), Fr.ZERO);
  const shares = Array.from({ length: n }, (_, k) => {
    const index = k + 1;
    const secret = f(BigInt(index));
    return { index, secret: secret.toString(16), publicKey: G1.BASE.multiply(secret).toHex() };
  });
  return { n, t, groupKey: G1.BASE.multiply(coeffs[0]).toHex(), shares };
}

const hashMsg = (message) => sigs.hash(enc.encode(message));

/** One member's partial signature over message, as hex. */
export function partialSign(share, message) {
  return hashMsg(message).multiply(BigInt('0x' + share.secret)).toHex();
}

/** Check a partial against that member's public key share. */
export function verifyPartial(sharePublicKey, message, partialHex) {
  return sigs.verify(G2.fromHex(partialHex), hashMsg(message), G1.fromHex(sharePublicKey));
}

/** Combine t partials [{ index, signature }] into the group signature (hex). */
export function combine(partials) {
  if (!Array.isArray(partials) || partials.length === 0) throw new Error('need at least one partial');
  const unique = new Set(partials.map((p) => p.index));
  if (unique.size !== partials.length) throw new Error('duplicate partial index');
  if (partials.some((p) => !Number.isSafeInteger(p.index) || p.index < 1)) throw new Error('invalid partial index');
  const idx = partials.map((p) => BigInt(p.index));
  let sum = G2.ZERO;
  partials.forEach((p, i) => {
    // Lagrange coefficient at x = 0.
    let lambda = Fr.ONE;
    idx.forEach((j, k) => {
      if (k !== i) lambda = Fr.mul(lambda, Fr.div(j, Fr.sub(j, idx[i])));
    });
    sum = sum.add(G2.fromHex(p.signature).multiply(lambda));
  });
  return sum.toHex();
}

// --- Distributed key generation (joint Feldman VSS) -------------------------

const scalarHex = (s) => s.toString(16);
const hexScalar = (h) => Fr.create(BigInt('0x' + h));
const evalPoly = (coeffs, x) => coeffs.reduceRight((acc, c) => Fr.add(Fr.mul(acc, x), c), Fr.ZERO);
// Σ_k C_k · x^k: the public value of a committed polynomial at x.
const evalCommitments = (commitments, x) => {
  let acc = G1.ZERO, pow = Fr.ONE;
  for (const c of commitments) {
    acc = acc.add(G1.fromHex(c).multiply(pow));
    pow = Fr.mul(pow, x);
  }
  return acc;
};

/** Member `index` deals: public commitments, and one private share per member. */
export function dkgDeal(n, t) {
  validateThreshold(n, t);
  const coeffs = Array.from({ length: t }, randomScalar);
  const shares = {};
  for (let j = 1; j <= n; j++) shares[j] = scalarHex(evalPoly(coeffs, BigInt(j)));
  return { commitments: coeffs.map((c) => G1.BASE.multiply(c).toHex()), shares };
}

/** Does share (from a dealer) for member j match that dealer's commitments? */
export function dkgVerifyShare(j, shareHex, commitments) {
  return G1.BASE.multiply(hexScalar(shareHex)).equals(evalCommitments(commitments, BigInt(j)));
}

/**
 * Member `index` finishes once it holds a verified share from every qualified
 * dealer. received: { dealer: shareHex }; commitments: { dealer: [hex] }.
 * Returns this member's secret share plus the public keys everyone agrees on.
 */
export function dkgFinish(index, n, t, received, commitments) {
  validateThreshold(n, t);
  if (!Number.isSafeInteger(index) || index < 1 || index > n) throw new Error('invalid member index');
  const expected = Array.from({ length: n }, (_, i) => i + 1);
  const dealers = Object.keys(commitments).map(Number).sort((a, b) => a - b);
  const senders = Object.keys(received).map(Number).sort((a, b) => a - b);
  if (dealers.length !== n || !dealers.every((d, i) => d === expected[i])) throw new Error('incomplete dealer commitments');
  if (senders.length !== n || !senders.every((d, i) => d === expected[i])) throw new Error('incomplete dealer shares');
  for (const d of dealers) {
    if (!Array.isArray(commitments[d]) || commitments[d].length !== t) {
      throw new Error(`bad commitment count from dealer ${d}`);
    }
    if (typeof received[d] !== 'string' || received[d] === '') throw new Error(`missing share from dealer ${d}`);
    if (!dkgVerifyShare(index, received[d], commitments[d])) throw new Error(`bad share from dealer ${d}`);
  }
  const secret = dealers.reduce((acc, d) => Fr.add(acc, hexScalar(received[d])), Fr.ZERO);
  if (secret === Fr.ZERO) throw new Error('zero aggregate secret share');
  const groupPoint = dealers.reduce((acc, d) => acc.add(G1.fromHex(commitments[d][0])), G1.ZERO);
  if (groupPoint.equals(G1.ZERO)) throw new Error('zero aggregate group key');
  const groupKey = groupPoint.toHex();
  const sharePublicKeys = {};
  for (let j = 1; j <= n; j++) {
    const point = dealers.reduce((acc, d) => acc.add(evalCommitments(commitments[d], BigInt(j))), G1.ZERO);
    if (point.equals(G1.ZERO)) throw new Error(`zero public share for member ${j}`);
    sharePublicKeys[j] = point.toHex();
  }
  return { index, n, t, secret: scalarHex(secret), publicKey: sharePublicKeys[index], groupKey, sharePublicKeys };
}

/** Verify a group signature. */
export function verify(groupKey, message, signatureHex) {
  return sigs.verify(G2.fromHex(signatureHex), hashMsg(message), G1.fromHex(groupKey));
}
