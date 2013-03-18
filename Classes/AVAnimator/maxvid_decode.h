// maxvid_decode module
//
//  License terms defined in License.txt.
//
// This module defines a runtime execution speed optimized video decoder library for iOS.

#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <stdlib.h>

#include <sys/types.h>
#include <sys/stat.h>
#include <math.h>
#include <assert.h>
#include <limits.h>
#include <unistd.h>

typedef enum {
  SKIP = 0,
  DUP = 1,
  COPY = 2,
  DONE = 3
} MV_GENERIC_CODE;

// Error codes returned by encode functions

#define MV_ERROR_CODE_INVALID_INPUT 1
#define MV_ERROR_CODE_INVALID_FILENAME 2
#define MV_ERROR_CODE_WRITE_FAILED 3
#define MV_ERROR_CODE_READ_FAILED 4

// These bit packing macros should not be invoked in user code

// This is the upper limit for a combined "num" and "val"
// field. This number is so large, that it is basically
// impossible for any reasonable app to ever need to emit
// more than this many pixels in any operation.

#define MV_MAX_2_BITS 0x3
#define MV_MAX_5_BITS 0x1F
#define MV_MAX_8_BITS 0xFF
#define MV_MAX_11_BITS 0x7FF
#define MV_MAX_14_BITS 0x3FFF
#define MV_MAX_16_BITS 0xFFFF
#define MV_MAX_22_BITS 0x3FFFFF
#define MV_MAX_24_BITS 0xFFFFFF
#define MV_MAX_27_BITS 0x7FFFFFF
#define MV_MAX_30_BITS 0x3FFFFFFF
#define MV_MAX_32_BITS 0xFFFFFFFF

#define MV_PAGESIZE 4096
#define MV16_NUM_PIXELS_ONE_PAGE (MV_PAGESIZE / sizeof(uint16_t))
#define MV_NUM_WORDS_ONE_PAGE (MV_PAGESIZE / sizeof(uint32_t))

// bitwise AND version of (ptr % pot)

#if defined(_LP64)
// CPU uses 64 bit pointers, need additional cast to avoid compiler warning
#define UINTMOD(ptr, pot) (((uint32_t)(uint64_t)ptr) & (pot - 1))
#else
// Regular 32 bit system
#define UINTMOD(ptr, pot) (((uint32_t)ptr) & (pot - 1))
#endif

// These next two macros will decode 3 values from a word code
// and save the results in const variables.
// word is a uint32_t that contains the word to be parsed
// op is a 2 bit MV_GENERIC_CODE.
// val is a 14 bit value.
// num is a 16 bit value.

# define MV16_READ_OP_VAL_NUM(word, op, val, num) \
const uint32_t op = word >> 30; \
const uint32_t val = (word >> 16) & MV_MAX_14_BITS; \
const uint32_t num = (uint16_t) word; \
if (0) { assert(op); } \
if (0) { assert(val); } \
if (0) { assert(num); }

// 24 and 32 bit generic codes share a common format, each pixel is a whole word

# define MV32_PARSE_OP_NUM_SKIP(word, op, num, skip) \
const uint32_t op = (word >> 8) & 0x3; \
const uint32_t num = ((word >> 8+2) & MV_MAX_22_BITS); \
const uint32_t skip = (word & MV_MAX_8_BITS); \
if (0) { assert(op); } \
if (0) { assert(num); } \
if (0) { assert(skip); }

#if !defined(MAXVID_NON_DEFAULT_MODULE_PREFIX)

uint32_t
maxvid_decode_c4_sample16(
                          uint16_t * restrict frameBuffer16,
                          const uint32_t * restrict inputBuffer32,
                          const uint32_t inputBuffer32NumWords,
                          const uint32_t frameBufferSize);

uint32_t
maxvid_decode_c4_sample32(
                          uint32_t * restrict frameBuffer32,
                          const uint32_t * restrict inputBuffer32,
                          const uint32_t inputBuffer32NumWords,
                          const uint32_t frameBufferSize);

#endif // MAXVID_DEFAULT_MODULE_PREFIX
