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

#pragma STDC FENV_ACCESS ON
#include <fenv.h>
#include <inttypes.h>
#include <stdint.h>
#include <stdio.h>

typedef union {
  double r;
  uint64_t hex;
  struct {
    uint64_t f : 52;  // fraction
    uint64_t e : 11;  // exponent
    uint64_t s : 1;   // sign
  } bits;
} double_u;

typedef union {
  float r;
  uint32_t hex;
  struct {
    uint32_t f : 23;
    uint32_t e : 8;
    uint32_t s : 1;
  } bits;
} float_u;

typedef struct {
  uint64_t pos_max;
  uint64_t neg_min;
  uint64_t pos_min;
  uint64_t neg_max;
  uint64_t pos_inf;
  uint64_t neg_inf;
  uint64_t pos_zero;
  uint64_t neg_zero;
  uint64_t pos_subn;
  uint64_t neg_subn;
  uint64_t snan;
  uint64_t qnan;
  uint64_t pos_1_0;
  uint64_t neg_1_0;
} speciald_t;

typedef struct {
  uint32_t pos_max;
  uint32_t neg_min;
  uint32_t pos_min;
  uint32_t neg_max;
  uint32_t pos_inf;
  uint32_t neg_inf;
  uint32_t pos_zero;
  uint32_t neg_zero;
  uint32_t pos_subn;
  uint32_t neg_subn;
  uint32_t snan;
  uint32_t qnan;
  uint32_t pos_1_0;
  uint32_t neg_1_0;
} specials_t;

speciald_t sd = {
  .pos_max  = 0x7fefffffffffffff,
  .neg_min  = 0xffefffffffffffff,
  .pos_min  = 0x0010000000000000,
  .neg_max  = 0x8010000000000000,
  .pos_inf  = 0x7ff0000000000000,
  .neg_inf  = 0xfff0000000000000,
  .pos_zero = 0x0000000000000000,
  .neg_zero = 0x8000000000000000,
  .pos_subn = 0x0000000000000001,
  .neg_subn = 0x8000000000000001,
  .snan     = 0x7ff0000000000001,
  .qnan     = 0x7ff8000000000000,
  .pos_1_0  = 0x3ff0000000000000,
  .neg_1_0  = 0xbff0000000000000,
};

specials_t ss = {
  .pos_max  = 0x7f7fffff,
  .neg_min  = 0xff7fffff,
  .pos_min  = 0x00800000,
  .neg_max  = 0x80800000,
  .pos_inf  = 0x7F800000,
  .neg_inf  = 0xFF800000,
  .pos_zero = 0x00000000,
  .neg_zero = 0x80000000,
  .pos_subn = 0x00000001,
  .neg_subn = 0x80000001,
  .snan     = 0x7F800001,
  .qnan     = 0x7FC00000,
  .pos_1_0  = 0x3F800000,
  .neg_1_0  = 0xBF800000,
};

void print_double(double_u d) {
  printf("(%.16f)s:%d e:%d f:0x%llx (0x%llx)\n", d.r, d.bits.s, d.bits.e, d.bits.f, d.hex);
}
void print_float(float_u f) {
  printf("(%.16f) s:%d e:%d f:0x%08x (0x%08x)\n", f.r, f.bits.s, f.bits.e, f.bits.f, f.hex);
}
void print_float32(uint32_t s) { printf("0x%08x\n", s); }
void print_float64(uint64_t v) { printf("0x%016llx\n", v); }

typedef enum { RNE = FE_TONEAREST, RTZ = FE_TOWARDZERO, RDN = FE_DOWNWARD, RUP = FE_UPWARD } RND;

void roundup(RND rnd) { fesetround(rnd); }

int main(int argc, char *argv[]) {
  roundup(RNE);

  return 0;
}

/******************************************************************************/
