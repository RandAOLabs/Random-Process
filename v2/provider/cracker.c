/* cracker.c: solve a time-lock puzzle without the trapdoor, with GMP.
 *
 *   cracker y     <N hex> <x hex> <T>          prints x^(2^T) mod N
 *   cracker proof <N hex> <x hex> <T> <l hex>  prints x^floor(2^T / l) mod N
 *
 * Both are T sequential squarings inside mpz_powm. The Wesolowski challenge l
 * is computed by the caller (provider/timelock.mjs), so the hashing rules live
 * in one place.
 */
#include <stdio.h> /* before gmp.h, so it declares mpz_out_str */
#include <gmp.h>
#include <stdlib.h>
#include <string.h>

int main(int argc, char **argv) {
  if (argc < 5) {
    fprintf(stderr, "usage: cracker y N x T | cracker proof N x T l\n");
    return 2;
  }
  mpz_t n, x, e, out, l;
  mpz_inits(n, x, e, out, l, NULL);
  if (mpz_set_str(n, argv[2], 16) || mpz_set_str(x, argv[3], 16)) return 2;
  unsigned long t = strtoul(argv[4], NULL, 10);
  mpz_ui_pow_ui(e, 2, t); /* 2^T */
  if (strcmp(argv[1], "proof") == 0) {
    if (argc < 6 || mpz_set_str(l, argv[5], 16)) return 2;
    mpz_fdiv_q(e, e, l); /* floor(2^T / l) */
  } else if (strcmp(argv[1], "y") != 0) {
    return 2;
  }
  mpz_powm(out, x, e, n);
  mpz_out_str(stdout, 16, out);
  putchar('\n');
  return 0;
}
