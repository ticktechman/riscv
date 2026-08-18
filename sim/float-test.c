// build: gcc -O2 -frounding-math -std=c11 -Wall float-test.c -o float-test -lm

#if defined(__clang__)
#pragma STDC FENV_ACCESS ON
#endif
#include <fenv.h>
#include <inttypes.h>
#include <math.h>
#include <stdint.h>
#include <stdio.h>

#ifndef FE_ALL_EXCEPT
#define FE_ALL_EXCEPT (FE_INVALID | FE_OVERFLOW | FE_UNDERFLOW | FE_INEXACT | FE_DIVBYZERO)
#endif

typedef union {
  double r;
  uint64_t hex;
  struct {
    uint64_t f : 52;
    uint64_t e : 11;
    uint64_t s : 1;
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
  .pos_inf  = 0x7f800000,
  .neg_inf  = 0xff800000,
  .pos_zero = 0x00000000,
  .neg_zero = 0x80000000,
  .pos_subn = 0x00000001,
  .neg_subn = 0x80000001,
  .snan     = 0x7f800001,
  .qnan     = 0x7fc00000,
  .pos_1_0  = 0x3f800000,
  .neg_1_0  = 0xbf800000,
};

void print_double(double_u d) {
  printf("(%.16e) s:%d e:0x%03x f:0x%013llx hex:0x%016llx", d.r, (int)d.bits.s, (unsigned)d.bits.e,
         (unsigned long long)d.bits.f, (unsigned long long)d.hex);
}

void print_float(float_u f) {
  printf("(%.8e) s:%d e:0x%02x f:0x%06x hex:0x%08x", f.r, (int)f.bits.s, (unsigned)f.bits.e, (unsigned)f.bits.f,
         (unsigned)f.hex);
}

void print_exceptions(const char *label) {
  int raised = fetestexcept(FE_ALL_EXCEPT);
  printf("  [%s] exc:", label);
  if (raised & FE_INVALID) printf(" INVALID");
  if (raised & FE_OVERFLOW) printf(" OVERFLOW");
  if (raised & FE_UNDERFLOW) printf(" UNDERFLOW");
  if (raised & FE_INEXACT) printf(" INEXACT");
  if (raised & FE_DIVBYZERO) printf(" DIVBYZERO");
  if (raised == 0) printf(" (none)");
  printf("\n");
  feclearexcept(FE_ALL_EXCEPT);
}

const char *rnd_name(int rnd) {
  switch (rnd) {
    case FE_TONEAREST:
      return "RNE";
    case FE_TOWARDZERO:
      return "RTZ";
    case FE_DOWNWARD:
      return "RDN";
    case FE_UPWARD:
      return "RUP";
    default:
      return "???";
  }
}

/* ==================== Double 测试 ==================== */

void test_double_add(int rnd) {
  printf("\n--- Double 加法 [%s] ---\n", rnd_name(rnd));
#define TA_D(a, b)                       \
  do {                                   \
    feclearexcept(FE_ALL_EXCEPT);        \
    double_u _a          = {.hex = (a)}; \
    double_u _b          = {.hex = (b)}; \
    volatile double _res = _a.r + _b.r;  \
    double_u _r          = {.r = _res};  \
    printf("  + ");                      \
    print_double(_a);                    \
    printf("\n    ");                    \
    print_double(_b);                    \
    printf("\n  = ");                    \
    print_double(_r);                    \
    print_exceptions("add");             \
  } while (0)

  TA_D(sd.pos_inf, sd.pos_1_0);    // inf + 1 = inf
  TA_D(sd.pos_inf, sd.neg_inf);    // inf + (-inf) = NaN, INVALID
  TA_D(sd.pos_max, sd.pos_max);    // 溢出 -> inf, OVERFLOW
  TA_D(sd.pos_min, sd.pos_min);    // 次正规 + 次正规, UNDERFLOW
  TA_D(sd.pos_zero, sd.neg_zero);  // +0 + -0 = +0(RNE)
  TA_D(sd.pos_subn, sd.pos_min);   // 次正规 + 正规
  TA_D(sd.qnan, sd.pos_1_0);       // NaN + 1 = NaN, INVALID
#undef TA_D
}

void test_double_sub(int rnd) {
  printf("\n--- Double 减法 [%s] ---\n", rnd_name(rnd));
#define TS_D(a, b)                       \
  do {                                   \
    feclearexcept(FE_ALL_EXCEPT);        \
    double_u _a          = {.hex = (a)}; \
    double_u _b          = {.hex = (b)}; \
    volatile double _res = _a.r - _b.r;  \
    double_u _r          = {.r = _res};  \
    printf("  - ");                      \
    print_double(_a);                    \
    printf("\n    ");                    \
    print_double(_b);                    \
    printf("\n  = ");                    \
    print_double(_r);                    \
    print_exceptions("sub");             \
  } while (0)

  TS_D(sd.pos_zero, sd.pos_zero);  // 0 - 0 = +0
  TS_D(sd.pos_inf, sd.pos_inf);    // inf - inf = NaN, INVALID
  TS_D(sd.pos_1_0, sd.pos_1_0);    // 1 - 1 = +0
  TS_D(sd.neg_min, sd.pos_max);    // -max - max -> -inf, OVERFLOW
  TS_D(sd.pos_min, sd.pos_subn);   // 正规 - 次正规
#undef TS_D
}

void test_double_mul(int rnd) {
  printf("\n--- Double 乘法 [%s] ---\n", rnd_name(rnd));
#define TM_D(a, b)                       \
  do {                                   \
    feclearexcept(FE_ALL_EXCEPT);        \
    double_u _a          = {.hex = (a)}; \
    double_u _b          = {.hex = (b)}; \
    volatile double _res = _a.r * _b.r;  \
    double_u _r          = {.r = _res};  \
    printf("  * ");                      \
    print_double(_a);                    \
    printf("\n    ");                    \
    print_double(_b);                    \
    printf("\n  = ");                    \
    print_double(_r);                    \
    print_exceptions("mul");             \
  } while (0)

  TM_D(sd.pos_inf, sd.pos_zero);   // inf * 0 = NaN, INVALID
  TM_D(sd.pos_max, sd.pos_1_0);    // max * 1 = max
  TM_D(sd.pos_max, sd.pos_max);    // 溢出 -> inf, OVERFLOW
  TM_D(sd.pos_min, sd.pos_min);    // 下溢, UNDERFLOW
  TM_D(sd.pos_subn, sd.pos_subn);  // 次正规 * 次正规
  TM_D(sd.neg_1_0, sd.pos_inf);    // -1 * inf = -inf
  TM_D(sd.qnan, sd.pos_1_0);       // NaN * 1 = NaN, INVALID
#undef TM_D
}

void test_double_div(int rnd) {
  printf("\n--- Double 除法 [%s] ---\n", rnd_name(rnd));
#define TD_D(a, b)                       \
  do {                                   \
    feclearexcept(FE_ALL_EXCEPT);        \
    double_u _a          = {.hex = (a)}; \
    double_u _b          = {.hex = (b)}; \
    volatile double _res = _a.r / _b.r;  \
    double_u _r          = {.r = _res};  \
    printf("  / ");                      \
    print_double(_a);                    \
    printf("\n    ");                    \
    print_double(_b);                    \
    printf("\n  = ");                    \
    print_double(_r);                    \
    print_exceptions("div");             \
  } while (0)

  TD_D(sd.pos_inf, sd.pos_inf);    // inf/inf = NaN, INVALID
  TD_D(sd.pos_zero, sd.pos_zero);  // 0/0 = NaN, INVALID
  TD_D(sd.pos_1_0, sd.pos_zero);   // 1/0 = inf, OVERFLOW/DIVBYZERO
  TD_D(sd.pos_min, sd.pos_max);    // 下溢, UNDERFLOW
  TD_D(sd.pos_subn, sd.pos_1_0);   // 次正规 / 1 = 次正规
  TD_D(sd.pos_1_0, sd.pos_subn);   // 1 / 次正规 -> 大数
#undef TD_D
}

void test_double_sqrt(int rnd) {
  printf("\n--- Double sqrt [%s] ---\n", rnd_name(rnd));
#define TSQ_D(a)                         \
  do {                                   \
    feclearexcept(FE_ALL_EXCEPT);        \
    double_u _a          = {.hex = (a)}; \
    volatile double _res = sqrt(_a.r);   \
    double_u _r          = {.r = _res};  \
    printf("  sqrt(");                   \
    print_double(_a);                    \
    printf(")\n  = ");                   \
    print_double(_r);                    \
    print_exceptions("sqrt");            \
  } while (0)

  TSQ_D(sd.pos_inf);   // sqrt(inf) = inf
  TSQ_D(sd.pos_zero);  // sqrt(+0) = +0
  TSQ_D(sd.neg_zero);  // sqrt(-0) = -0
  TSQ_D(sd.pos_1_0);   // sqrt(1) = 1
  TSQ_D(sd.pos_max);   // sqrt(max)
  TSQ_D(sd.pos_min);   // sqrt(min normal)
  TSQ_D(sd.pos_subn);  // sqrt(subnormal)
  TSQ_D(sd.qnan);      // sqrt(NaN) = NaN, INVALID
  TSQ_D(sd.neg_min);   // sqrt(-max) = NaN, INVALID
#undef TSQ_D
}

void test_double_fma(int rnd) {
  printf("\n--- Double FMA [%s] ---\n", rnd_name(rnd));
#define TF_D(a, b, c)                             \
  do {                                            \
    feclearexcept(FE_ALL_EXCEPT);                 \
    double_u _a          = {.hex = (a)};          \
    double_u _b          = {.hex = (b)};          \
    double_u _c          = {.hex = (c)};          \
    volatile double _res = fma(_a.r, _b.r, _c.r); \
    double_u _r          = {.r = _res};           \
    printf("  fma(");                             \
    print_double(_a);                             \
    printf("\n      ");                           \
    print_double(_b);                             \
    printf("\n      ");                           \
    print_double(_c);                             \
    printf("\n  = ");                             \
    print_double(_r);                             \
    print_exceptions("fma");                      \
  } while (0)

  TF_D(sd.pos_inf, sd.pos_1_0, sd.pos_1_0);   // inf*1+1 = inf
  TF_D(sd.pos_max, sd.pos_max, sd.neg_max);   // 溢出 -> OVERFLOW
  TF_D(sd.pos_min, sd.pos_min, sd.pos_zero);  // 次正规, UNDERFLOW
  TF_D(sd.pos_1_0, sd.pos_1_0, sd.neg_1_0);   // 1*1-1 = +0
  TF_D(sd.snan, sd.pos_1_0, sd.pos_1_0);      // NaN 输入, INVALID
  // 关键对照：fma 一次舍入 vs 两次舍入
  // (max+1) 刚好超 max -> inf (fma 一次舍入)
  TF_D(sd.pos_max, sd.pos_1_0, sd.pos_1_0);
#undef TF_D
}

/* ==================== Float 测试 ==================== */

void test_float_add(int rnd) {
  printf("\n--- Float 加法 [%s] ---\n", rnd_name(rnd));
#define TA_F(a, b)                      \
  do {                                  \
    feclearexcept(FE_ALL_EXCEPT);       \
    float_u _a          = {.hex = (a)}; \
    float_u _b          = {.hex = (b)}; \
    volatile float _res = _a.r + _b.r;  \
    float_u _r          = {.r = _res};  \
    printf("  + ");                     \
    print_float(_a);                    \
    printf("\n    ");                   \
    print_float(_b);                    \
    printf("\n  = ");                   \
    print_float(_r);                    \
    print_exceptions("add");            \
  } while (0)

  TA_F(ss.pos_inf, ss.pos_1_0);
  TA_F(ss.pos_inf, ss.neg_inf);  // NaN, INVALID
  TA_F(ss.pos_max, ss.pos_max);  // 溢出
  TA_F(ss.pos_zero, ss.neg_zero);
  TA_F(ss.pos_subn, ss.pos_subn);
  TA_F(ss.qnan, ss.pos_1_0);  // INVALID
#undef TA_F
}

void test_float_sub(int rnd) {
  printf("\n--- Float 减法 [%s] ---\n", rnd_name(rnd));
#define TS_F(a, b)                      \
  do {                                  \
    feclearexcept(FE_ALL_EXCEPT);       \
    float_u _a          = {.hex = (a)}; \
    float_u _b          = {.hex = (b)}; \
    volatile float _res = _a.r - _b.r;  \
    float_u _r          = {.r = _res};  \
    printf("  - ");                     \
    print_float(_a);                    \
    printf("\n    ");                   \
    print_float(_b);                    \
    printf("\n  = ");                   \
    print_float(_r);                    \
    print_exceptions("sub");            \
  } while (0)

  TS_F(ss.pos_zero, ss.pos_zero);
  TS_F(ss.pos_inf, ss.pos_inf);  // NaN, INVALID
  TS_F(ss.pos_1_0, ss.pos_1_0);
#undef TS_F
}

void test_float_mul(int rnd) {
  printf("\n--- Float 乘法 [%s] ---\n", rnd_name(rnd));
#define TM_F(a, b)                      \
  do {                                  \
    feclearexcept(FE_ALL_EXCEPT);       \
    float_u _a          = {.hex = (a)}; \
    float_u _b          = {.hex = (b)}; \
    volatile float _res = _a.r * _b.r;  \
    float_u _r          = {.r = _res};  \
    printf("  * ");                     \
    print_float(_a);                    \
    printf("\n    ");                   \
    print_float(_b);                    \
    printf("\n  = ");                   \
    print_float(_r);                    \
    print_exceptions("mul");            \
  } while (0)

  TM_F(ss.pos_inf, ss.pos_zero);   // NaN, INVALID
  TM_F(ss.pos_max, ss.pos_max);    // 溢出
  TM_F(ss.pos_subn, ss.pos_subn);  // 下溢
  TM_F(ss.neg_1_0, ss.pos_inf);    // -inf
#undef TM_F
}

void test_float_div(int rnd) {
  printf("\n--- Float 除法 [%s] ---\n", rnd_name(rnd));
#define TD_F(a, b)                      \
  do {                                  \
    feclearexcept(FE_ALL_EXCEPT);       \
    float_u _a          = {.hex = (a)}; \
    float_u _b          = {.hex = (b)}; \
    volatile float _res = _a.r / _b.r;  \
    float_u _r          = {.r = _res};  \
    printf("  / ");                     \
    print_float(_a);                    \
    printf("\n    ");                   \
    print_float(_b);                    \
    printf("\n  = ");                   \
    print_float(_r);                    \
    print_exceptions("div");            \
  } while (0)

  TD_F(ss.pos_zero, ss.pos_zero);  // NaN, INVALID
  TD_F(ss.pos_1_0, ss.pos_zero);   // inf, DIVBYZERO
  TD_F(ss.pos_min, ss.pos_max);    // 下溢
  TD_F(ss.pos_1_0, ss.pos_subn);   // 大数
#undef TD_F
}

void test_float_sqrt(int rnd) {
  printf("\n--- Float sqrt [%s] ---\n", rnd_name(rnd));
#define TSQ_F(a)                        \
  do {                                  \
    feclearexcept(FE_ALL_EXCEPT);       \
    float_u _a          = {.hex = (a)}; \
    volatile float _res = sqrtf(_a.r);  \
    float_u _r          = {.r = _res};  \
    printf("  sqrt(");                  \
    print_float(_a);                    \
    printf(")\n  = ");                  \
    print_float(_r);                    \
    print_exceptions("sqrtf");          \
  } while (0)

  TSQ_F(ss.pos_inf);
  TSQ_F(ss.pos_zero);
  TSQ_F(ss.neg_zero);
  TSQ_F(ss.pos_1_0);
  TSQ_F(ss.pos_max);
  TSQ_F(ss.pos_min);
  TSQ_F(ss.pos_subn);
  TSQ_F(ss.qnan);     // INVALID
  TSQ_F(ss.neg_min);  // INVALID
#undef TSQ_F
}

void test_float_fma(int rnd) {
  printf("\n--- Float FMA [%s] ---\n", rnd_name(rnd));
#define TF_F(a, b, c)                             \
  do {                                            \
    feclearexcept(FE_ALL_EXCEPT);                 \
    float_u _a          = {.hex = (a)};           \
    float_u _b          = {.hex = (b)};           \
    float_u _c          = {.hex = (c)};           \
    volatile float _res = fmaf(_a.r, _b.r, _c.r); \
    float_u _r          = {.r = _res};            \
    printf("  fmaf(");                            \
    print_float(_a);                              \
    printf("\n       ");                          \
    print_float(_b);                              \
    printf("\n       ");                          \
    print_float(_c);                              \
    printf("\n  = ");                             \
    print_float(_r);                              \
    print_exceptions("fmaf");                     \
  } while (0)

  TF_F(ss.pos_inf, ss.pos_1_0, ss.pos_1_0);
  TF_F(ss.pos_max, ss.pos_max, ss.neg_max);  // 溢出
  TF_F(ss.pos_1_0, ss.pos_1_0, ss.neg_1_0);  // 0
  TF_F(ss.snan, ss.pos_1_0, ss.pos_1_0);     // INVALID
#undef TF_F
}

/* ==================== FMA vs x*y+z 对照 ==================== */

void test_fma_vs_plain(int rnd) {
  printf("\n--- FMA vs x*y+z 对照 [%s] ---\n", rnd_name(rnd));

// Double
#define CMP_D(a, b, c)                              \
  do {                                              \
    feclearexcept(FE_ALL_EXCEPT);                   \
    double_u _a            = {.hex = (a)};          \
    double_u _b            = {.hex = (b)};          \
    double_u _c            = {.hex = (c)};          \
    volatile double _plain = _a.r * _b.r + _c.r;    \
    volatile double _fma_v = fma(_a.r, _b.r, _c.r); \
    double_u _p            = {.r = _plain};         \
    double_u _q            = {.r = _fma_v};         \
    printf("  case: ");                             \
    print_double(_a);                               \
    printf("\n        ");                           \
    print_double(_b);                               \
    printf("\n        ");                           \
    print_double(_c);                               \
    printf("\n    x*y+z = ");                       \
    print_double(_p);                               \
    printf("\n    fma   = ");                       \
    print_double(_q);                               \
    if (_p.hex == _q.hex)                           \
      printf("  SAME");                             \
    else                                            \
      printf("  DIFFERENT");                        \
    print_exceptions("cmp");                        \
  } while (0)

  // 正常情况：结果可能相同
  CMP_D(sd.pos_1_0, sd.pos_1_0, sd.pos_1_0);  // 1*1+1 = 2
  // 边界：次正规精度暴露差异
  CMP_D(sd.pos_min, sd.pos_min, sd.pos_1_0);  // 极小*极小+1
  // 溢出边界
  CMP_D(sd.pos_max, sd.pos_1_0, sd.pos_max);  // max*1+max -> 可能 inf
#undef CMP_D

// Float
#define CMP_F(a, b, c)                              \
  do {                                              \
    feclearexcept(FE_ALL_EXCEPT);                   \
    float_u _a            = {.hex = (a)};           \
    float_u _b            = {.hex = (b)};           \
    float_u _c            = {.hex = (c)};           \
    volatile float _plain = _a.r * _b.r + _c.r;     \
    volatile float _fma_v = fmaf(_a.r, _b.r, _c.r); \
    float_u _p            = {.r = _plain};          \
    float_u _q            = {.r = _fma_v};          \
    printf("  case: ");                             \
    print_float(_a);                                \
    printf("\n        ");                           \
    print_float(_b);                                \
    printf("\n        ");                           \
    print_float(_c);                                \
    printf("\n    x*y+z = ");                       \
    print_float(_p);                                \
    printf("\n    fmaf  = ");                       \
    print_float(_q);                                \
    if (_p.hex == _q.hex)                           \
      printf("  SAME");                             \
    else                                            \
      printf("  DIFFERENT");                        \
    print_exceptions("cmp");                        \
  } while (0)

  CMP_F(ss.pos_1_0, ss.pos_1_0, ss.pos_1_0);
  CMP_F(ss.pos_min, ss.pos_min, ss.pos_1_0);
  CMP_F(ss.pos_max, ss.pos_1_0, ss.pos_max);
#undef CMP_F
}

/* ==================== main ==================== */

int main(int argc, char *argv[]) {
  (void)argc;
  (void)argv;

  int modes[] = {FE_TONEAREST, FE_TOWARDZERO, FE_DOWNWARD, FE_UPWARD};

  for (int i = 0; i < 4; i++) {
    fesetround(modes[i]);
    printf("\n########################################\n");
    printf("### 舍入模式: %s\n", rnd_name(modes[i]));
    printf("########################################\n");

    test_double_add(modes[i]);
    test_double_sub(modes[i]);
    test_double_mul(modes[i]);
    test_double_div(modes[i]);
    test_double_sqrt(modes[i]);
    test_double_fma(modes[i]);

    test_float_add(modes[i]);
    test_float_sub(modes[i]);
    test_float_mul(modes[i]);
    test_float_div(modes[i]);
    test_float_sqrt(modes[i]);
    test_float_fma(modes[i]);

    test_fma_vs_plain(modes[i]);
  }

  return 0;
}
