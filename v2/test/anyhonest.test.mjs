// node --test test/anyhonest.test.mjs
import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import * as tl from '../provider/anyhonest.mjs';

const T = 4096; // small for tests; the protocol default is 2^27
const big = (h) => BigInt('0x' + h);
const hex = (n) => n.toString(16);
const bump = (h) => hex(big(h) + 1n);
const h = tl.crack(tl.G_HEX, T).y;

test('N is the RSA-2048 challenge and g is a fixed square mod N', () => {
  assert.equal(tl.N.toString(2).length, 2048);
  assert.ok(tl.G > 1n && tl.G < tl.N);
  const v = tl.expand('rng/timelock/g', 2112);
  assert.ok(v.toString(2).length <= 2112);
  assert.equal(tl.G, (v % tl.N) ** 2n % tl.N);
});

test('h^alpha equals T squarings of c, and reveal and crack agree', () => {
  const alpha = tl.newAlpha();
  const c = tl.commit(alpha);
  const r = tl.verifyReveal(c, alpha, h);
  assert.deepEqual(r, { valid: true, y: tl.output(alpha, h) });
  const k = tl.crack(c, T);
  const v = tl.verifyCrack(c, T, k.y, k.proof);
  assert.equal(v.valid, true);
  assert.equal(v.y, r.y);
  assert.equal(r.y, hex(tl.canonical(big(k.y))));
});

test('h and hProof verify as a crack of g', () => {
  const { y, proof } = tl.crack(tl.G_HEX, T);
  assert.equal(tl.verifyCrack(tl.G_HEX, String(T), y, proof).valid, true);
  assert.equal(tl.verifyCrack(tl.G_HEX, String(T + 1), y, proof).valid, false);
});

test('fresh secrets differ', () => {
  const a = tl.newAlpha(), b = tl.newAlpha();
  assert.notEqual(a, b);
  assert.ok(big(a) < 2n ** 256n);
  assert.notEqual(tl.commit(a), tl.commit(b));
});

test('bad reveals are refused with a reason', () => {
  const alpha = tl.newAlpha();
  const c = tl.commit(alpha);
  const no = (r) => { assert.equal(r.valid, false); assert.equal(typeof r.reason, 'string'); };
  no(tl.verifyReveal(c, bump(alpha), h));
  no(tl.verifyReveal(bump(c), alpha, h));
  no(tl.verifyReveal(tl.N_HEX, alpha, h));
  no(tl.verifyReveal(hex(big(c) + tl.N), alpha, h));
  no(tl.verifyReveal('0', alpha, h));
  no(tl.verifyReveal(c, alpha, '0'));
  no(tl.verifyReveal(c, alpha, tl.N_HEX));
  no(tl.verifyReveal(c, hex(1n << 512n), h));
  no(tl.verifyReveal(c.toUpperCase(), alpha, h));
  no(tl.verifyReveal('0' + c, alpha, h));
  no(tl.verifyReveal(c, 'zz', h));
  // A 512-bit alpha is allowed.
  const wide = hex((1n << 512n) - 1n);
  assert.equal(tl.verifyReveal(tl.commit(wide), wide, h).valid, true);
});

test('N - y cracks to the same canonical y; bad cracks are refused', () => {
  const c = tl.commit(tl.newAlpha());
  const k = tl.crack(c, T);
  const ok = tl.verifyCrack(c, T, k.y, k.proof);
  // N - y has its own challenge l; the proof is -(c^floor(2^T / l)), l odd.
  const ny = hex(tl.N - big(k.y));
  const l = tl.challengePrime(c, ny, T);
  const neg = tl.verifyCrack(c, T, ny, hex(tl.N - tl.modPow(big(c), 2n ** BigInt(T) / l, tl.N)));
  assert.equal(neg.valid, true);
  assert.equal(neg.y, ok.y);
  for (const [x, t, y, p] of [
    [c, T, k.y, bump(k.proof)], [c, T, bump(k.y), k.proof], [c, T + 1, k.y, k.proof],
    ['0', T, k.y, k.proof], [c, T, tl.N_HEX, k.proof], [c, T, k.y, '0'],
    [c, 2 ** 32 + 1, k.y, k.proof], [c, '-1', k.y, k.proof], [c, T, 'zz', k.proof],
  ]) assert.equal(tl.verifyCrack(x, t, y, p).valid, false);
  // t = 2^32 is in range (the proof is just wrong).
  assert.equal(tl.verifyCrack(c, 2 ** 32, k.y, k.proof).reason, 'bad proof');
});

test('challenge prime is a 128-bit prime', () => {
  const l = tl.challengePrime('cd', 'ef', 10);
  assert.equal(l.toString(2).length, 128);
  assert.ok(tl.isProbablePrime(l));
  assert.equal(tl.isProbablePrime(561n), false); // Carmichael
});

test('round value orders outputs by validator address', () => {
  const v1 = tl.roundValue('B'.repeat(43), 3, { b: '2', a: '1' });
  const v2 = tl.roundValue('B'.repeat(43), 3, { a: '1', b: '2' });
  assert.equal(v1, v2);
});

test('request value binds the requester', () => {
  const a = tl.requestValue('ab', 'P1', 'r1');
  assert.equal(a, createHash('sha256').update('hyperbeam/rng/any-honest/v1/request|ab|P1|r1').digest('hex'));
  assert.notEqual(a, tl.requestValue('ab', 'P2', 'r1'));
});
