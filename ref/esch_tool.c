/*
 * esch_tool.c - Esch384 golden reference tool for the FPGA project.
 *
 * Uses the official SPARKLE C code (ref/official/esch384v2_ref, unmodified)
 * for all hashing. Adds:
 *   - a debug trace that prints the 512-bit state after every step,
 *   - test-vector generators for the hardware unit tests,
 *   - a small custom KAT file.
 *
 * Usage:
 *   esch_tool hash    <hexmsg>              digest (official code)
 *   esch_tool debug   <hexmsg>              per-step state trace + digest
 *   esch_tool alzette <count> <seed>        lines: c x y u v
 *   esch_tool linear  <count> <seed>        lines: 16 in words | 16 out words
 *   esch_tool sparkle <steps> <count> <seed> lines: 16 in words | 16 out words
 *   esch_tool kat                           custom KAT file (NIST format)
 *
 * Use "" for an empty message. All values are printed as 32-bit words in hex.
 * State word order is x0 y0 x1 y1 ... x7 y7 (spec p.6, "state[]" array).
 * Message bytes go into words little-endian (byte 0 = bits 7:0 of word 0).
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include "esch_cfg.h"
#include "sparkle_ref.h"

int crypto_hash(unsigned char *out, const unsigned char *in,
                unsigned long long inlen);
/* Defined (non-static) in official sparkle_ref.c, not in its header. */
void linear_layer(SparkleState *state, int brans);

#define NB      8    /* branches in SPARKLE512 */
#define RATE_B  16   /* rate in bytes          */
#define DIG_B   48   /* digest in bytes        */
#define MAXMSG  4096

/* Copied from official sparkle_ref.c (needed for the step-by-step trace). */
#define ROT(x, n) (((x) >> (n)) | ((x) << (32-(n))))
#define ELL(x) (ROT(((x) ^ ((x) << 16)), 16))
#define ARXBOX(x, y, c)                     \
  (x) += ROT((y), 31), (y) ^= ROT((x), 24), \
  (x) ^= (c),                               \
  (x) += ROT((y), 17), (y) ^= ROT((x), 17), \
  (x) ^= (c),                               \
  (x) += (y),          (y) ^= ROT((x), 31), \
  (x) ^= (c),                               \
  (x) += ROT((y), 24), (y) ^= ROT((x), 16), \
  (x) ^= (c)

static const uint32_t RCON[8] = {
  0xB7E15162, 0xBF715880, 0x38B4DA56, 0x324E7738,
  0xBB1185EB, 0x4F7C7B57, 0xCFBFA1C8, 0xC2B3293D
};

/* ---------- small helpers ---------- */

static uint64_t rng_state;
static uint32_t rnd32(void)   /* xorshift64*, reproducible from seed */
{
  rng_state ^= rng_state >> 12;
  rng_state ^= rng_state << 25;
  rng_state ^= rng_state >> 27;
  return (uint32_t)((rng_state * 0x2545F4914F6CDD1DULL) >> 32);
}

static size_t parse_hex(const char *s, uint8_t *out)
{
  size_t n = strlen(s), i;
  if (n % 2 || n / 2 > MAXMSG) { fprintf(stderr, "bad hex message\n"); exit(2); }
  for (i = 0; i < n / 2; i++) {
    unsigned v;
    if (sscanf(s + 2 * i, "%2x", &v) != 1) { fprintf(stderr, "bad hex\n"); exit(2); }
    out[i] = (uint8_t)v;
  }
  return n / 2;
}

static void print_bytes(const uint8_t *b, size_t n)
{
  size_t i;
  for (i = 0; i < n; i++) printf("%02X", b[i]);
}

static void print_state(const char *tag, const SparkleState *s)
{
  int i;
  printf("TRACE %-12s", tag);
  for (i = 0; i < NB; i++) printf(" %08x %08x", s->x[i], s->y[i]);
  printf("\n");
}

/* ---------- traced version of the hash (checked against official) ---------- */

static void sparkle_traced(SparkleState *s, int steps, const char *prefix)
{
  char tag[32];
  int i, j;
  for (i = 0; i < steps; i++) {
    s->y[0] ^= RCON[i % 8];
    s->y[1] ^= (uint32_t)i;
    for (j = 0; j < NB; j++) ARXBOX(s->x[j], s->y[j], RCON[j]);
    linear_layer(s, NB);
    snprintf(tag, sizeof tag, "%s.s%d", prefix, i);
    print_state(tag, s);
  }
}

/* Same as official add_msg_blk (hash.c, static there). */
static void inject(SparkleState *s, const uint8_t *in, size_t inlen,
                   uint32_t m[4])
{
  uint32_t buf[4] = {0, 0, 0, 0}, tx, ty;
  uint8_t bytes[16] = {0};
  int i;
  memcpy(bytes, in, inlen);
  if (inlen < RATE_B) bytes[inlen] = 0x80;          /* pad 10* */
  for (i = 0; i < 4; i++)                           /* little-endian words */
    buf[i] = (uint32_t)bytes[4*i] | ((uint32_t)bytes[4*i+1] << 8) |
             ((uint32_t)bytes[4*i+2] << 16) | ((uint32_t)bytes[4*i+3] << 24);
  tx = ELL(buf[0] ^ buf[2]);
  ty = ELL(buf[1] ^ buf[3]);
  for (i = 0; i < 2; i++) {          /* branches 2,3 get only tx/ty */
    s->x[i] ^= buf[2*i]   ^ ty;
    s->y[i] ^= buf[2*i+1] ^ tx;
  }
  for (i = 2; i < 4; i++) {
    s->x[i] ^= ty;
    s->y[i] ^= tx;
  }
  memcpy(m, buf, sizeof buf);
}

static int cmd_debug(const char *hex)
{
  static uint8_t msg[MAXMSG];
  uint8_t dig[DIG_B], dig_ref[DIG_B];
  SparkleState s;
  uint32_t m[4];
  char tag[32];
  size_t len = parse_hex(hex, msg), off = 0;
  int blk = 0, i, sq, w = 0;

  memset(&s, 0, sizeof s);
  printf("# Esch384 debug trace, message length %zu bytes\n", len);
  print_state("init", &s);

  while (len - off > RATE_B) {                       /* non-final blocks */
    inject(&s, msg + off, RATE_B, m);
    printf("# block %d: msg words %08x %08x %08x %08x (slim, %d steps)\n",
           blk, m[0], m[1], m[2], m[3], SPARKLE_STEPS_SLIM);
    snprintf(tag, sizeof tag, "b%d.inj", blk); print_state(tag, &s);
    snprintf(tag, sizeof tag, "b%d", blk);
    sparkle_traced(&s, SPARKLE_STEPS_SLIM, tag);
    off += RATE_B; blk++;
  }
  {                                                  /* final block */
    size_t last = len - off;
    int padded = last < RATE_B;
    s.y[3] ^= padded ? (1u << 24) : (2u << 24);      /* ConstM, see hash.c */
    inject(&s, msg + off, last, m);
    printf("# block %d (final, %zu bytes, %s, ConstM=%s): msg words "
           "%08x %08x %08x %08x (big, %d steps)\n", blk, last,
           padded ? "padded" : "full", padded ? "M1" : "M2",
           m[0], m[1], m[2], m[3], SPARKLE_STEPS_BIG);
    snprintf(tag, sizeof tag, "b%d.inj", blk); print_state(tag, &s);
    snprintf(tag, sizeof tag, "b%d", blk);
    sparkle_traced(&s, SPARKLE_STEPS_BIG, tag);
  }
  for (sq = 0; sq < 3; sq++) {                       /* squeeze 3 x 128 bits */
    if (sq > 0) {
      printf("# squeeze %d (slim, %d steps)\n", sq, SPARKLE_STEPS_SLIM);
      snprintf(tag, sizeof tag, "sq%d", sq);
      sparkle_traced(&s, SPARKLE_STEPS_SLIM, tag);
    }
    for (i = 0; i < 2; i++) {
      uint32_t v[2]; int k, b;
      v[0] = s.x[i]; v[1] = s.y[i];
      for (k = 0; k < 2; k++, w++)
        for (b = 0; b < 4; b++) dig[4*w + b] = (uint8_t)(v[k] >> (8*b));
    }
  }
  printf("DIGEST ");
  print_bytes(dig, DIG_B);
  printf("\n");

  crypto_hash(dig_ref, msg, len);
  if (memcmp(dig, dig_ref, DIG_B) != 0) {
    printf("ERROR: trace digest does not match official code: ");
    print_bytes(dig_ref, DIG_B);
    printf("\n");
    return 1;
  }
  printf("# OK: matches official crypto_hash\n");
  return 0;
}

/* ---------- other commands ---------- */

static int cmd_hash(const char *hex)
{
  static uint8_t msg[MAXMSG];
  uint8_t dig[DIG_B];
  size_t len = parse_hex(hex, msg);
  crypto_hash(dig, msg, len);
  print_bytes(dig, DIG_B);
  printf("\n");
  return 0;
}

static void rand_state(SparkleState *s)
{
  int i;
  for (i = 0; i < NB; i++) { s->x[i] = rnd32(); s->y[i] = rnd32(); }
}

static void print_words(const SparkleState *s)
{
  int i;
  for (i = 0; i < NB; i++) printf("%08x %08x ", s->x[i], s->y[i]);
}

static int cmd_alzette(int count)
{
  int n;
  for (n = 0; n < count; n++) {
    /* first 8 vectors use the 8 real branch constants, rest are random */
    uint32_t c = n < 8 ? RCON[n] : rnd32();
    uint32_t x = rnd32(), y = rnd32(), u = x, v = y;
    if (n == 0) { x = y = u = v = 0; }
    ARXBOX(u, v, c);
    printf("%08x %08x %08x %08x %08x\n", c, x, y, u, v);
  }
  return 0;
}

static int cmd_linear(int count)
{
  int n;
  for (n = 0; n < count; n++) {
    SparkleState s;
    rand_state(&s);
    if (n == 0) memset(&s, 0, sizeof s);
    print_words(&s); printf("| ");
    linear_layer(&s, NB);
    print_words(&s); printf("\n");
  }
  return 0;
}

static int cmd_sparkle(int steps, int count)
{
  int n;
  for (n = 0; n < count; n++) {
    SparkleState s;
    rand_state(&s);
    if (n == 0) memset(&s, 0, sizeof s);
    print_words(&s); printf("| ");
    sparkle_ref(&s, NB, steps);                     /* official */
    print_words(&s); printf("\n");
  }
  return 0;
}

/* Custom KATs: edge cases around the 16-byte block boundary, plus
   non-sequential data (official KATs only use 00 01 02 ...). */
static int cmd_kat(void)
{
  static const int lens[] = {0, 1, 15, 16, 17, 31, 32, 33, 48, 64, 100, 255};
  static uint8_t msg[MAXMSG];
  uint8_t dig[DIG_B];
  int count = 1, i, k, pat;
  for (pat = 0; pat < 3; pat++) {
    for (i = 0; i < (int)(sizeof lens / sizeof lens[0]); i++) {
      int len = lens[i];
      if (pat > 0 && len == 0) continue;            /* empty only once */
      for (k = 0; k < len; k++)
        msg[k] = pat == 0 ? (uint8_t)k : pat == 1 ? 0xFF : (uint8_t)rnd32();
      crypto_hash(dig, msg, (unsigned long long)len);
      printf("Count = %d\nMsg = ", count++);
      print_bytes(msg, (size_t)len);
      printf("\nMD = ");
      print_bytes(dig, DIG_B);
      printf("\n\n");
    }
  }
  return 0;
}

int main(int argc, char **argv)
{
  if (argc >= 3 && !strcmp(argv[1], "hash"))  return cmd_hash(argv[2]);
  if (argc >= 3 && !strcmp(argv[1], "debug")) return cmd_debug(argv[2]);
  if (argc >= 4 && !strcmp(argv[1], "alzette")) {
    rng_state = strtoull(argv[3], 0, 0) | 1; return cmd_alzette(atoi(argv[2]));
  }
  if (argc >= 4 && !strcmp(argv[1], "linear")) {
    rng_state = strtoull(argv[3], 0, 0) | 1; return cmd_linear(atoi(argv[2]));
  }
  if (argc >= 5 && !strcmp(argv[1], "sparkle")) {
    rng_state = strtoull(argv[4], 0, 0) | 1;
    return cmd_sparkle(atoi(argv[2]), atoi(argv[3]));
  }
  if (argc >= 2 && !strcmp(argv[1], "kat")) { rng_state = 545; return cmd_kat(); }
  fprintf(stderr,
    "usage: esch_tool hash|debug <hexmsg>\n"
    "       esch_tool alzette|linear <count> <seed>\n"
    "       esch_tool sparkle <steps> <count> <seed>\n"
    "       esch_tool kat\n");
  return 2;
}
