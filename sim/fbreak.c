/*
 *******************************************************************************
 *
 *        filename: fbreak.c
 *     description: floating point number break down
 *         created: 2026/08/15
 *          author: ticktechman
 *
 *******************************************************************************
 */

// build: gcc fbreak.c -o fbreak

#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>

typedef union {
  double r;
  struct {
    uint64_t f : 52; // fraction
    uint64_t e : 11; // exponent
    uint64_t s : 1;  // sign
  } bits;
  uint64_t hex;
} double_u;

typedef union {
  float r;
  struct {
    uint32_t f : 23;
    uint32_t e : 8;
    uint32_t s : 1;
  } bits;
  uint32_t hex;
} float_u;

int main(int argc, char *argv[]) {
  double_u d;
  d.hex = 0x37b4c8f800000000;
  printf("%.16f=s:%d e:%d f:0x%016llx\n", d.r, d.bits.s, d.bits.e, d.bits.f);

  float_u f;
  f.r = (float)d.r;
  printf("%.16f=s:%d e:%d f:0x08%x\n", f.r, f.bits.s, f.bits.e, f.bits.f);

  float_u f1, f2, f3;
  f1.hex = 0x4498a000;
  f2.hex = 0x0002991f;
  f3.r = f1.r * f2.r;

  printf("f1.hex:0x%08x\n", f1.hex);
  printf("f2.hex:0x%08x\n", f2.hex);
  printf("f3.hex:0x%08x\n", f3.hex);

  return 0;
}

/******************************************************************************/
