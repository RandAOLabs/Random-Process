// Reference implementation of rng.lua's stream, in JS with node:crypto.
// Prints the golden vectors that rng_test.lua checks against, so the Lua
// SHA-256 and stream are verified against an independent implementation.
import { createHash } from 'node:crypto';

const sha = (buf) => createHash('sha256').update(buf).digest();

export function stream(material) {
  const seed = sha(Buffer.from('rng/v1|' + material, 'latin1'));
  let block = 0;
  let words = [];
  const u32 = () => {
    if (words.length === 0) {
      const d = sha(Buffer.concat([seed, Buffer.from(String(block++), 'latin1')]));
      for (let i = 0; i < 8; i++) words.push(d.readUInt32BE(i * 4));
    }
    return words.shift();
  };
  const int = (lo, hi) => {
    const range = BigInt(hi - lo + 1);
    if (range === 1n) return lo;
    const limit = (2n ** 32n / range) * range;
    let x = BigInt(u32());
    while (x >= limit) x = BigInt(u32());
    return lo + Number(x % range);
  };
  return { u32, int };
}
export function vectors() {
  const shaCases = ['', 'abc', 'a'.repeat(55), 'a'.repeat(56), 'a'.repeat(64),
    'a'.repeat(119), 'a'.repeat(120), 'abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq'];
  const s1 = stream('vector');
  const s2 = stream('vector');
  return {
    sha: shaCases.map((c) => [c.length > 20 ? `${c[0]}x${c.length}` : c, sha(Buffer.from(c)).toString('hex')]),
    u32: Array.from({ length: 10 }, () => s1.u32()),
    int: Array.from({ length: 10 }, () => s2.int(1, 6)),
  };
}
