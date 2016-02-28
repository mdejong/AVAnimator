// maxvid module
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

// Define EXTRA_CHECKS to enable assert checks in the decoder

//#define EXTRA_CHECKS
//#define MAXVID_ALWAYS_ASSERT_EXTRA_CHECKS

/*
#ifndef __OPTIMIZE__
// Automatically define EXTRA_CHECKS when not optimizing (in debug mode)
# define EXTRA_CHECKS
#endif // DEBUG
*/

/*
#if TARGET_IPHONE_SIMULATOR
// Automatically define EXTRA_CHECKS when running in the simulator
# define EXTRA_CHECKS
#endif // DEBUG
*/

#if defined(MAXVID_EXTRA_CHECKS) && !defined(EXTRA_CHECKS)
# define EXTRA_CHECKS
#endif

// Note that ASM logic needs to be defined after optional EXTRA_CHECKS

#if defined(__arm__)
# define COMPILE_ARM 1
# if defined(__thumb__)
#  define COMPILE_ARM_THUMB_ASM 1
# else
#  define COMPILE_ARM_ASM 1
# endif
#endif

// Xcode 4.2 supports clang only, but the ARM asm integration depends on specifics
// of register allocation and as a result only works when compiled with gcc.

#if defined(__clang__)
#  define COMPILE_CLANG 1
#endif // defined(__clang__)

// For CLANG build on ARM, skip this entire module and use custom ARM asm imp instead.
// It is possible that clang is compiling in Thumb2 mode, just use the already generated
// ARM code and do not generate an error in this case.

#if defined(COMPILE_CLANG) && defined(COMPILE_ARM)
#define USE_GENERATED_ARM_ASM 1
#endif // SKIP __clang__ && ARM

// GCC 4.2 and newer seems to allocate registers in a way that breaks the inline
// arm asm in maxvid_decode.c, so use the ARM asm in this case.

#if defined(__GNUC__) && !defined(__clang__) && defined(COMPILE_ARM)
# define __GNUC_PREREQ(maj, min) \
((__GNUC__ << 16) + __GNUC_MINOR__ >= ((maj) << 16) + (min))
# if __GNUC_PREREQ(4,2)
#  define USE_GENERATED_ARM_ASM 1
# endif
#endif

// This inline asm flag would only be used if USE_GENERATED_ARM_ASM was not defined

#if defined(COMPILE_ARM)
# define USE_INLINE_ARM_ASM 1
#endif

// It is possible one might want to actually compile the C code on an
// ARM system and simply not use the inline ASM blocks and let the
// compiler generate ARM code automatically. Set the argument
// value for this if to 1 to enable build on ARM without inline ASM.

#if 0 && defined(USE_GENERATED_ARM_ASM)
#undef USE_GENERATED_ARM_ASM
#undef USE_INLINE_ARM_ASM
#endif

#if defined(USE_GENERATED_ARM_ASM)
  // No-op, skip compilation of this entire module!
#else // defined(USE_GENERATED_ARM_ASM)

#ifdef COMPILE_ARM_ASM
#define ASM_NOP __asm__ __volatile__ ("nop");
#else
#define ASM_NOP
#endif

// Generate a compile time error if compiled in Thumb mode. This module includes ARM specific
// ASM code, so it can't be compiled in Thumb mode.

#if defined(COMPILE_ARM_THUMB_ASM)
#error "Module should not be compiled in Thumb mode, enable ARM mode by adding -mno-thumb to file specific target flags"
#endif

#if defined(MAXVID_MODULE_PREFIX)
# define MODULE_PREFIX MAXVID_MODULE_PREFIX
# define MAXVID_NON_DEFAULT_MODULE_PREFIX
#else
# define MODULE_PREFIX maxvid_
# define MAXVID_DEFAULT_MODULE_PREFIX
#endif

// The header defines only the default exported function names. If this module is being pulled into
// the test module, then the default symbols are not declared to avoid accidently using them.
#include "maxvid_decode.h"

// Fancy macro expansion so that FUNCTION_NAME(MODULE_PREFIX, decode_sample16) -> maxvid_decode_sample16
#define MAKE_FN_NAME(mprefix, x) mprefix ## x
#define FUNCTION_NAME(mprefix, fname) MAKE_FN_NAME(mprefix, fname)

//#ifdef EXTRA_CHECKS

// Combine two 16 bit pixels into a single uint32_t word
#define HwToWord(pixel) ((((uint32_t) pixel) << 16) | (uint32_t)pixel)

#define MAX_5_BITS MV_MAX_5_BITS
#define MAX_11_BITS MV_MAX_11_BITS

// The ARM docs indicate that stm is faster when the output buffer is 64 bit
// aligned since 2 words can be written with each cycle. If the cache line
// can be filled with 1 write, that will perform better. The cache line
// size for a Cortex-A8 is 16 words (64 bytes), the cache line size for
// a Cortext-A9 is 8 words (32 bytes). Old iPhone 3G Arm 11 CPUs also used
// a cache line that was 8 words. Since there is no method to attempt to
// detect device capabilities, use the common 8 word bound size
// and assume that writing 8 word blocks will fill one cache line for 2/3
// known ARM CPUs.
//
// While reads do need to be 32 bit aligned, it is not as critical for the
// reads to be 64 bit aligned in a memcpy type read/write loop.

#define MV_CACHE_LINE_SIZE 8
#define BOUNDSIZE (MV_CACHE_LINE_SIZE * sizeof(uint32_t))

// Note that the following code can only be built with EXTRA_CHECKS in debug mode, because the
// inlined ASM uses the stack frame register.

#undef EXTRA_CHECKS

// Note that this module can't be compiled with debug symbols without also enabling
// EXTRA_CHECKS. The result is that execution time is significantly slowed down
// when debug mode is enabled. But, gcc will bomb out with a register allocation
// error if EXTRA_CHECKS is not enabled, so there is little choice.

#ifndef __OPTIMIZE__
// Automatically define EXTRA_CHECKS when not optimizing (in debug mode)
# define EXTRA_CHECKS
#endif // __OPTIMIZE__

// "No stack" safe assert macro, invokes inlined function call and restores
// the registers. This macro is needed to use ASSERT logic in a function with no free registers.

#if defined(USE_INLINE_ARM_ASM)
#ifdef EXTRA_CHECKS
static uint32_t r0r1r2r3r4r5r6r8r10r11r12r14[12];
#endif
#endif // USE_INLINE_ARM_ASM

#ifndef __OPTIMIZE__

//__attribute__ ((noinline))
static inline
void maxvid_test_assert_util_c4(int cond) {
#if defined(USE_INLINE_ARM_ASM)
#if 0 && defined(EXTRA_CHECKS)
  __asm__ __volatile__ (
                        "cmp r0, #0\n\t"
                        "mov r9, %[ptr]\n\t"
                        "ldm r9, {r0, r1, r2, r3, r4, r5, r6, r8, r10, r11, r12, r14}\n\t"
                        "pop {r9}\n\t"
                        "moveq r0, #0\n\t"
                        "streq r0, [r0]\n\t"
                        :
                        :
                        [ptr] "l" (r0r1r2r3r4r5r6r8r10r11r12r14)
                        );
#else
  __asm__ __volatile__ (
                        "cmp r0, #0\n\t"
                        "moveq r0, #0\n\t"
                        "streq r0, [r0]\n\t"
                        );
#endif // EXTRA_CHECKS
  
#else // USE_INLINE_ARM_ASM

  if (cond == 0) {
    // This is handy so that one can set a breakpoint on this assert call
    *((volatile uint32_t*)NULL) = 0;
  }

#endif // USE_INLINE_ARM_ASM
  
  return;
}
#endif // __OPTIMIZE__

#undef MAXVID_ASSERT

#if defined(USE_INLINE_ARM_ASM)

# define MAXVID_ASSERT(cond, cstr) \
__asm__ __volatile__ ( \
"nop\n\t" \
"push {r9}\n\t" \
"push {r0, r1, r2, r3, r4, r5, r6, r8, r10, r11, r12, r14}\n\t" \
: \
: \
); \
__asm__ __volatile__ ( \
"mov r9, %[ptr]\n\t" \
"pop {r0, r1, r2, r3, r4, r5, r6, r8, r10, r11, r12, r14}\n\t" \
"stm r9, {r0, r1, r2, r3, r4, r5, r6, r8, r10, r11, r12, r14}\n\t" \
"pop {r9}\n\t" \
: \
: \
[ptr] "l" (r0r1r2r3r4r5r6r8r10r11r12r14) \
); \
maxvid_test_assert_util_c4(cond); \
__asm__ __volatile__ ( \
"push {r9}\n\t" \
"mov r9, %[ptr]\n\t" \
"ldm r9, {r0, r1, r2, r3, r4, r5, r6, r8, r10, r11, r12, r14}\n\t" \
"pop {r9}\n\t" \
"nop\n\t" \
: \
: \
[ptr] "l" (r0r1r2r3r4r5r6r8r10r11r12r14) \
);

#else

# define MAXVID_ASSERT(cond, cstr) maxvid_test_assert_util_c4(cond);

#endif // USE_INLINE_ARM_ASM

// Create optimized impl

// This template is used to create a test and an optimized version of the c4 decode sample logic.
// This can't be implemented with the inline trick used elsewhere because the compiler runs
// out of registers while inlining static functions.

// maxvid_decode_c4_sample16
// Decode input RLE, input data is already validated

__attribute__ ((noinline))
uint32_t
FUNCTION_NAME(MODULE_PREFIX, decode_c4_sample16) (
                               uint16_t * restrict frameBuffer16Arg,
                               const uint32_t * restrict inputBuffer32Arg,
                               const uint32_t inputBuffer32NumWords,
                               const uint32_t frameBufferSize)
{
  // Usable registers:
  // r0 -> r3 (scratch, compiler will write over these registers at sneaky times)
  // r4 -> r10 (r7 in thumb mode is the frame pointer, gdb uses r7 in arm mode)
  // r11 is the frame pointer in ARM mode
  // r12 tmp register (can't seem to bind to this register)
  // r13 stack pointer (only usable if no stack use in function)
  // r14 link register (gcc runs out of registers if you use this one)
  // r15 is the program counter (don't use)
  
#if !defined(USE_INLINE_ARM_ASM) || defined(EXTRA_CHECKS)
  const uint32_t copyOnePixelHighHalfWord = (((uint32_t)COPY) << 14 | 0x1);
  const uint32_t dupTwoPixelsHighHalfWord = (((uint32_t)DUP) << 14 | 0x2);
  const uint32_t extractNumPixelsHighHalfWord = 0x3FFF;
#endif // !USE_INLINE_ARM_ASM || EXTRA_CHECKS

#if defined(EXTRA_CHECKS)
  // Double check that half word constants are not just totally wrong
  {
    //uint32_t expectedDup2Word = maxvid16_c4_code(DUP, 2, 0xFFFF);
    uint32_t expectedDup2Word = 0x4002FFFF;
    uint16_t expectedDup2HighHalfWord = (expectedDup2Word >> 16);
    if (dupTwoPixelsHighHalfWord != expectedDup2HighHalfWord) {
      MAXVID_ASSERT(dupTwoPixelsHighHalfWord == expectedDup2HighHalfWord, "dupTwoPixelsHighHalfWord");
    }
  }
  {
    //uint32_t expectedCopy1Word = maxvid16_c4_code(COPY, 1, 0xFFFF);
    uint32_t expectedCopy1Word = 0x8001ffff;
    uint16_t expectedCopy1HighHalfWord = (expectedCopy1Word >> 16);
    if (copyOnePixelHighHalfWord != expectedCopy1HighHalfWord) {
      MAXVID_ASSERT(copyOnePixelHighHalfWord == expectedCopy1HighHalfWord, "copyOnePixelHighHalfWord");
    }
  }
#endif
  
#if 1 && defined(USE_INLINE_ARM_ASM)
  register uint32_t * restrict inputBuffer32 __asm__ ("r9") = (uint32_t * restrict) inputBuffer32Arg;
  register uint16_t * restrict frameBuffer16 __asm__ ("r10") = frameBuffer16Arg;
  
#ifdef EXTRA_CHECKS
  MAXVID_ASSERT(inputBuffer32 == inputBuffer32Arg, "inputBuffer32Arg");
  MAXVID_ASSERT(frameBuffer16 == frameBuffer16Arg, "frameBuffer16Arg");
#endif
  
  // This register holds the input word, it is clobbered by the 8 word loop
  register uint32_t inW1 __asm__ ("r8"); // AKA WR8
  
  // This register holds the op code during the initial parse, it is clobbered by the 8 word loop
  register uint32_t opCode __asm__ ("r6"); // AKA WR7
  
  // This register holds the numPixels value during a COPY or DUP operation.
  // It does not get clobbered by the 8 word loop.
  register uint32_t numPixels __asm__ ("r12");
  
  // This register counts down the numWords during a COPY or DUP operation,
  // it does not get clobbered by the 8 word loop.
  register uint32_t numWords __asm__ ("r14");
  
  // This register holds a one pixel constant value, it is not clobbered by the word 8 loop.
#ifdef EXTRA_CHECKS
  // Frame and stack pointers needed in debug mode
  uint32_t copyOnePixelHighHalfWordConstRegister;
#else // EXTRA_CHECKS
  register uint32_t copyOnePixelHighHalfWordConstRegister __asm__ ("r11");
#endif // EXTRA_CHECKS
  
  // These alias vars is used to hold a constant value for use in the DECODE block. Clobbered by the word8 loop.
  register uint32_t extractNumPixelsHighHalfWordConstRegister __asm__ ("r4"); // AKA WR5
  register uint32_t dupTwoPixelsHighHalfWordConstRegister __asm__ ("r5"); // AKA WR6
  
  // Explicitly define the registers outside the r0 -> r3 range
  
  // These registers are used with ldm and stm instructions.
  // During a write loop, these values could write over other
  // values mapped to the same registers. Note that we skip r7
  // since gdb uses it for debugging. Also be aware that gcc
  // could secretly write over the value in r0 to r3 in
  // debug mode.
  
  register uint32_t WR1 __asm__ ("r0");
  register uint32_t WR2 __asm__ ("r1");
  register uint32_t WR3 __asm__ ("r2");
  register uint32_t WR4 __asm__ ("r3");
  register uint32_t WR5 __asm__ ("r4");
  register uint32_t WR6 __asm__ ("r5");
  register uint32_t WR7 __asm__ ("r6");
  register uint32_t WR8 __asm__ ("r8");
  
  // gcc is buggy when it comes to initializing register variables. Explicitly initialize the
  // registers with inline ASM. This is required to avoid problems with the optimizer removing
  // init code because it incorrectly thinks assignments are aliases.
  
  __asm__ __volatile__ (
                        "mov %[inW1], #0\n\t"
                        :
                        [inW1] "+l" (inW1)
                        );
#ifdef EXTRA_CHECKS
  MAXVID_ASSERT(inW1 == 0, "inW1");
#endif
  
#else // USE_INLINE_ARM_ASM
  register uint32_t * restrict inputBuffer32 = (uint32_t * restrict) inputBuffer32Arg;
  register uint16_t * restrict frameBuffer16 = frameBuffer16Arg;
  register uint32_t inW1 = 0;
  uint32_t opCode;
  register uint32_t numPixels;
  register uint32_t numWords;
  register uint32_t WR1 = 0;
  register uint32_t WR2;
  register uint32_t WR3;
  register uint32_t WR4 = 0;
  register uint32_t WR5;
#endif // USE_INLINE_ARM_ASM
  
  // Init constants in registers
  
  // FIXME: If DUP were 2 and COPY were 1, only a single right shift would be needed
  // to convert from COPY1 to DUP2. Could also do 0xC003 with an xor. But, all this
  // could be done in 1 immediate compare is ccode and numPixels were switchedin the word
  
#if defined(USE_INLINE_ARM_ASM)
  __asm__ __volatile__ (
                        "mov %[constReg1], #1\n\t"
                        "mvn %[constReg2], #0xC000\n\t"
                        "orr %[constReg1], %[constReg1], %[constReg1], lsl #15\n\t"
                        "mov %[constReg3], #2\n\t"
                        "orr %[constReg3], %[constReg3], %[constReg1], lsr #1\n\t"
                        :
                        [constReg1] "+l" (copyOnePixelHighHalfWordConstRegister),
                        [constReg2] "+l" (extractNumPixelsHighHalfWordConstRegister),
                        [constReg3] "+l" (dupTwoPixelsHighHalfWordConstRegister)
                        );
  
#ifdef EXTRA_CHECKS
  MAXVID_ASSERT(copyOnePixelHighHalfWordConstRegister == copyOnePixelHighHalfWord, "copyOnePixelHighHalfWordConstRegister");
  MAXVID_ASSERT(dupTwoPixelsHighHalfWordConstRegister == dupTwoPixelsHighHalfWord, "dupTwoPixelsHighHalfWordConstRegister");
  MAXVID_ASSERT(extractNumPixelsHighHalfWordConstRegister == ((0xFFFF << 16) | extractNumPixelsHighHalfWord), "extractNumPixelsHighHalfConstRegister");
#endif // EXTRA_CHECKS
#endif // USE_INLINE_ARM_ASM
  
#ifdef EXTRA_CHECKS
  
  const int pagesize = getpagesize();
#if __LP64__
  MAXVID_ASSERT((MV_PAGESIZE % pagesize) == 0, "pagesize");
#else
  MAXVID_ASSERT(pagesize == MV_PAGESIZE/4, "pagesize");
#endif // __LP64__

  MAXVID_ASSERT(inputBuffer32 != NULL, "inputBuffer32");
  // The input buffer must be word aligned
  MAXVID_ASSERT(UINTMOD(inputBuffer32, sizeof(uint32_t)) == 0, "inputBuffer32 initial alignment");
  MAXVID_ASSERT(frameBuffer16 != NULL, "frameBuffer16");
  // The framebuffer must be word aligned to start out with
  MAXVID_ASSERT(UINTMOD(frameBuffer16, sizeof(uint32_t)) == 0, "frameBuffer16 initial alignment");
  // In addition, the framebuffer must begin on a page boundry
  MAXVID_ASSERT(UINTMOD(frameBuffer16, pagesize) == 0, "frameBuffer16 initial page alignment");
  MAXVID_ASSERT(frameBufferSize > 0, "frameBufferSize");
  uint16_t * restrict inframeBuffer16 = frameBuffer16;
  uint16_t * restrict frameBuffer16Max = frameBuffer16 + frameBufferSize;
  uint32_t * restrict inInputBuffer32 = (uint32_t *)inputBuffer32;
  
  uint32_t * restrict inputBuffer32Max = inInputBuffer32 + inputBuffer32NumWords;
  
  // inputBuffer32 - inInputBuffer32 gives the input word offset
  MAXVID_ASSERT(inInputBuffer32 != NULL, "inInputBuffer32");
  // Init to phony value
  uint32_t * restrict prevInputBuffer32 = inInputBuffer32 - 1;
  
  // Verify that the DONE code appears at the end of the input, followed by a zero word.
  MAXVID_ASSERT(*(inputBuffer32Max - 1) == (DONE << 30), "DONE");
  
  // These stack values save the expected contents of registers on the stack, to double check that
  // the values were not between the time they were set and when they were used.
  uint32_t opCodeSaved;
  uint32_t numPixelsSaved;
  uint32_t numWordsSaved;
  uint32_t inW1Saved;
  uint32_t pixel32Saved;
#endif
  
#ifdef EXTRA_CHECKS
  MAXVID_ASSERT(inputBuffer32 != NULL, "inputBuffer32");
  MAXVID_ASSERT(UINTMOD(inputBuffer32, sizeof(uint32_t)) == 0, "inputBuffer32 alignment");
  // inputBuffer32 should be 1 word ahead of the previous read (ignored in COPY case)
  MAXVID_ASSERT(inputBuffer32 == (prevInputBuffer32 + 1), "inputBuffer32 != previous");
  prevInputBuffer32 = inputBuffer32;
#endif
  
#if defined(USE_INLINE_ARM_ASM)
  __asm__ __volatile__ (
                        // inW1 = *inputBuffer32++
                        "ldr %[inW1], [%[inputBuffer32]], #4\n\t"
                        :
                        [inW1] "+l" (inW1),
                        [inputBuffer32] "+l" (inputBuffer32)
                        );
#else
  inW1 = *inputBuffer32++;
#endif // USE_INLINE_ARM_ASM
  
#ifdef EXTRA_CHECKS
  inW1Saved = inW1;
  MAXVID_ASSERT(inputBuffer32 == (prevInputBuffer32 + 1), "inputBuffer32 != previous");
#endif
  
#if defined(USE_INLINE_ARM_ASM)
  __asm__ __volatile__ (
                        "@ goto DECODE_16BPP\n\t"
                        :
                        );
#endif // USE_INLINE_ARM_ASM
  goto DECODE_16BPP;
  
DUP_16BPP:
  // This block is just here to work around what appears to be a compiler bug related to a label.
  {
  }
  
#ifdef USE_INLINE_ARM_ASM
  __asm__ __volatile__ (
                        "@ DUP\n\t"
                        );
#endif // USE_INLINE_ARM_ASM
  
  // Word align the framebuffer, if needed.
  // Note that DUP2 was handled inline already.
  
#ifdef EXTRA_CHECKS
  MAXVID_ASSERT(numPixels == numPixelsSaved, "numPixelsSaved");
  MAXVID_ASSERT(numPixels != 0, "numPixels != 0");
  MAXVID_ASSERT(numPixels != 1, "numPixels != 1");
  MAXVID_ASSERT(numPixels > 2, "numPixels > 2");
#endif
  
#ifdef EXTRA_CHECKS
  MAXVID_ASSERT(inputBuffer32 != NULL, "inputBuffer32");
  MAXVID_ASSERT(UINTMOD(inputBuffer32, sizeof(uint32_t)) == 0, "inputBuffer32 alignment");
  MAXVID_ASSERT(frameBuffer16 != NULL, "frameBuffer16");
  MAXVID_ASSERT(UINTMOD(frameBuffer16, sizeof(uint16_t)) == 0, "frameBuffer16 alignment");
  MAXVID_ASSERT((((frameBuffer16 + numPixels - 1) - inframeBuffer16) < frameBufferSize), "MV16_CODE_COPY past end of framebuffer");
#endif
  
#ifdef EXTRA_CHECKS
  MAXVID_ASSERT(inW1 == inW1Saved, "inW1Saved");
#endif // EXTRA_CHECKS
  
  // Duplicate the 16 bit pixel as a pair of 32 bit pixels in the first write register
#define pixel32Alias WR1
  
#ifdef EXTRA_CHECKS
  MAXVID_ASSERT(((frameBuffer16 - inframeBuffer16) < frameBufferSize), "word align: already past end of framebuffer");
  MAXVID_ASSERT(numPixels == numPixelsSaved, "numPixelsSaved");
#endif // EXTRA_CHECKS
  
#if defined(USE_INLINE_ARM_ASM)
  // Duplicate the 16 bit pixel as a pair of 32 bit pixels in the first write register.
  // This logic is mixed into the framebuffer align between the compare and the
  // conditional instruction in an attempt to get better pipeline results.
  __asm__ __volatile__ (
                        "tst %[frameBuffer16], #3\n\t"
                        "pkhbt %[pixel32], %[inW1], %[inW1], lsl #16\n\t"
                        "subne %[numPixels], %[numPixels], #1\n\t"
                        "strneh %[inW1], [%[frameBuffer16]], #2\n\t"
                        :
                        [frameBuffer16] "+l" (frameBuffer16),
                        [numPixels] "+l" (numPixels),
                        [pixel32] "+l" (pixel32Alias)
                        :
                        [inW1] "l" (inW1)
                        );
#else // USE_INLINE_ARM_ASM
  if (UINTMOD(frameBuffer16, 4) != 0) {
    // Framebuffer is half word aligned, write 16 bit pixel in the low half word
    *frameBuffer16++ = inW1;
    numPixels--;
  }
#endif // USE_INLINE_ARM_ASM
  
#ifdef EXTRA_CHECKS
  numPixelsSaved = numPixels;
  pixel32Saved = pixel32Alias;
  MAXVID_ASSERT(pixel32Alias == pixel32Saved, "pixel32Saved");
  
  // DUP numPixels min was 3, now min is 2 because of word alignment
  MAXVID_ASSERT(numPixels >= 2, "numPixels >= 2");
#endif // EXTRA_CHECKS
  
#ifdef EXTRA_CHECKS
  MAXVID_ASSERT(numPixels == numPixelsSaved, "numPixelsSaved");
  MAXVID_ASSERT(opCode == opCodeSaved, "opCodeSaved");
  
  MAXVID_ASSERT(frameBuffer16 != NULL, "frameBuffer16");
  MAXVID_ASSERT(UINTMOD(frameBuffer16, sizeof(uint16_t)) == 0, "frameBuffer16 alignment");
#endif // EXTRA_CHECKS
  
  // numWords is numPixels/2, counts down to zero in the word8 loop.
  // num is a 14 bit number that indicates the number of pixels to copy.
  // This logic must appear after the framebuffer has been word aligned
  // since that logic can decrement the numPixels by 1 in the
  // unaligned case.
  
#ifdef EXTRA_CHECKS
  MAXVID_ASSERT(numPixels == numPixelsSaved, "numPixelsSaved");
#endif
#ifdef USE_INLINE_ARM_ASM
  __asm__ __volatile__ (
                        "mov %[numWords], %[numPixels], lsr #1\n\t"
                        :
                        [numWords] "+l" (numWords)
                        :
                        [numPixels] "l" (numPixels)
                        );
#else // USE_INLINE_ARM_ASM
  // Note that the inline ASM above is needed to avoid stack use in conditional case
  numWords = (numPixels >> 1);
#endif // USE_INLINE_ARM_ASM
  
#ifdef EXTRA_CHECKS
  numWordsSaved = numWords;
  MAXVID_ASSERT(numWordsSaved == (numPixels >> 1), "numWordsSaved");
  MAXVID_ASSERT(numPixels > numWords, "numPixels > numPixels");
  // numPixels is a 14 bit number, so numWords can't be larger than 0x3FFF / 2
  MAXVID_ASSERT(numWords <= (0x3FFF >> 1), "numWords");
  
  // The min num pixels at this point is 2, so min number of words is 1, zero is not a valid value
  MAXVID_ASSERT(numWords >= 1, "numWords >= 1");
#endif
  
  // pixel32
  
#ifdef EXTRA_CHECKS
  MAXVID_ASSERT(inW1 == inW1Saved, "inW1Saved");
#endif // EXTRA_CHECKS
  
#if defined(USE_INLINE_ARM_ASM)
  // Copy the low half word into the high half with with 1 ASM instruction, instead of 2
  // PKHBT   r0, r3, r5, LSL #16 ; combine the bottom halfword of r3 with the bottom halfword of r5
  //  __asm__ __volatile__ (
  //                        "pkhbt %[pixel32], %[inW1], %[inW1], lsl #16\n\t"
  //                        :
  //                        [pixel32] "+l" (pixel32Alias)
  //                        :
  //                        [inW1] "l" (inW1)
  //                        );
#else // USE_INLINE_ARM_ASM
  pixel32Alias = (uint16_t) inW1;
  pixel32Alias |= (inW1 << 16);
  
#ifdef EXTRA_CHECKS
  pixel32Saved = pixel32Alias;
#endif // EXTRA_CHECKS
  
#endif // USE_INLINE_ARM_ASM
  
#ifdef EXTRA_CHECKS
  MAXVID_ASSERT(pixel32Alias == pixel32Saved, "pixel32Saved");
  MAXVID_ASSERT(pixel32Alias == (((uint16_t) inW1) | (inW1 << 16)), "pixel32");
#endif // EXTRA_CHECKS
  
  // Read next word into inW1, this is with enough latency that fall through to DECODE will not be delayed
  
#ifdef EXTRA_CHECKS
  MAXVID_ASSERT(inputBuffer32 != NULL, "inputBuffer32");
  MAXVID_ASSERT(UINTMOD(inputBuffer32, sizeof(uint32_t)) == 0, "inputBuffer32 alignment");
  // inputBuffer32 should be 1 word ahead of the previous read (ignored in COPY case)
  MAXVID_ASSERT(inputBuffer32 == (prevInputBuffer32 + 1), "inputBuffer32 != previous");
  prevInputBuffer32 = inputBuffer32;
#endif
  
#if defined(USE_INLINE_ARM_ASM)
  __asm__ __volatile__ (
                        // inW1 = *inputBuffer32++
                        "ldr %[inW1], [%[inputBuffer32]], #4\n\t"
                        :
                        [inW1] "+l" (inW1),
                        [inputBuffer32] "+l" (inputBuffer32)
                        );
#else
  inW1 = *inputBuffer32++;
#endif // USE_INLINE_ARM_ASM
  
#ifdef EXTRA_CHECKS
  inW1Saved = inW1;
  MAXVID_ASSERT(inputBuffer32 == (prevInputBuffer32 + 1), "inputBuffer32 != previous");
  MAXVID_ASSERT(inW1 == inW1Saved, "inW1Saved");
#endif
  
  // DUPBIG_16BPP : branch forward to handle the case of a large number of words to DUP.
  // The code in this path is optimized for 6 words or fewer. (12 pixels)
  
#ifdef EXTRA_CHECKS
  MAXVID_ASSERT(numWords == numWordsSaved, "numWordsSaved");
  MAXVID_ASSERT(numWords > 0, "numWords");
#endif
  
#if defined(USE_INLINE_ARM_ASM)
  __asm__ __volatile__ (
                        "@ if (numWords > 6) goto DUPBIG_16BPP\n\t"
                        :
                        );
#endif // USE_INLINE_ARM_ASM
  
  if (numWords > 6) {
    goto DUPBIG_16BPP;
  }
  
#if defined(USE_INLINE_ARM_ASM)
  __asm__ __volatile__ (
                        "@ DUPSMALL_16BPP\n\t"
                        );
#endif //  USE_INLINE_ARM_ASM
  
#ifdef EXTRA_CHECKS
  MAXVID_ASSERT(numWords == numWordsSaved, "numWordsSaved");
  MAXVID_ASSERT(numWords >= 1, "numWords");
  MAXVID_ASSERT(numWords <= 6, "numWords");
  
  MAXVID_ASSERT(frameBuffer16 != NULL, "frameBuffer16");
  MAXVID_ASSERT(UINTMOD(frameBuffer16, sizeof(uint32_t)) == 0, "frameBuffer16 alignment");
  
  MAXVID_ASSERT(numPixels == numPixelsSaved, "numPixelsSaved");
  MAXVID_ASSERT(numWords == numWordsSaved, "numWordsSaved");
  
  uint16_t *expectedDUPSmallPost8FrameBuffer16 = frameBuffer16;
  expectedDUPSmallPost8FrameBuffer16 += (numWords * 2);
  
  uint16_t *expectedDUPSmallFinalFrameBuffer16 = frameBuffer16 + numPixels;
  
  MAXVID_ASSERT((expectedDUPSmallFinalFrameBuffer16 == expectedDUPSmallPost8FrameBuffer16) || 
                (expectedDUPSmallFinalFrameBuffer16 == expectedDUPSmallPost8FrameBuffer16+1), "expected pointers");
  
  MAXVID_ASSERT(numPixels == numPixelsSaved, "numPixelsSaved");
  MAXVID_ASSERT(numWords == numWordsSaved, "numWordsSaved");
  
  MAXVID_ASSERT(numPixels == numPixelsSaved, "numPixelsSaved");
  MAXVID_ASSERT(numWords == numWordsSaved, "numWordsSaved");
  
  if (numWords >= 3) {
    MAXVID_ASSERT((numWords - 3) <= 3, "numWords - 3");
  }
#endif
  
#if defined(USE_INLINE_ARM_ASM)
  __asm__ __volatile__ (
                        "mov %[wr2], %[wr1]\n\t"
                        // if (numWords >= 3) then write 3 words
                        "cmp %[numWords], #2\n\t"
                        "mov %[wr3], %[wr1]\n\t"
                        "subgt %[numWords], %[numWords], #3\n\t"
                        "stmgt %[frameBuffer16]!, {%[wr1], %[wr2], %[wr3]}\n\t"
                        // if (numWords >= 2) then write 2 words
                        "cmp %[numWords], #1\n\t"
                        "stmgt %[frameBuffer16], {%[wr1], %[wr2]}\n\t"
                        // frameBuffer32 += numPixels;
                        "add %[frameBuffer16], %[frameBuffer16], %[numWords], lsl #2\n\t"
                        // if (numWords == 1 || numWords == 3) then write 1 word
                        "tst %[numWords], #0x1\n\t"
                        "strne %[wr1], [%[frameBuffer16], #-4]\n\t"
                        :
                        [frameBuffer16] "+l" (frameBuffer16),
                        [numWords] "+l" (numWords),
                        [wr1] "+l" (WR1),
                        [wr2] "+l" (WR2),
                        [wr3] "+l" (WR3)
                        );
#else // USE_INLINE_ARM_ASM
  {
    if (numWords >= 3) {
      *((uint32_t*)frameBuffer16) = pixel32Alias;
      *(((uint32_t*)frameBuffer16) + 1) = pixel32Alias;
      *(((uint32_t*)frameBuffer16) + 2) = pixel32Alias;
      frameBuffer16 += (3 * 2);
      numWords -= 3;
    }
    if (numWords >= 2) {
      *((uint32_t*)frameBuffer16) = pixel32Alias;
      *(((uint32_t*)frameBuffer16) + 1) = pixel32Alias;
    }
#ifdef EXTRA_CHECKS
    MAXVID_ASSERT(numWords >=0 && numWords <= 3, "numWords must be in range 0 to 3 here");
#endif
    frameBuffer16 += (numWords << 1);
    if (numWords & 0x1) {
      *(((uint32_t*)frameBuffer16) - 1) = pixel32Alias;
    }
  }
#endif // USE_INLINE_ARM_ASM
  
#ifdef EXTRA_CHECKS
  MAXVID_ASSERT(frameBuffer16 != NULL, "frameBuffer16");
  MAXVID_ASSERT(UINTMOD(frameBuffer16, sizeof(uint32_t)) == 0, "frameBuffer16 alignment");
  
  MAXVID_ASSERT(frameBuffer16 == expectedDUPSmallPost8FrameBuffer16, "frameBuffer16 post8");
  MAXVID_ASSERT(numWords >= 0 && numWords <= 3, "numWords");
#endif
  
  // Emit trailing single pixel, if needed
  
#if defined(USE_INLINE_ARM_ASM)
  
#ifdef EXTRA_CHECKS
  MAXVID_ASSERT(numPixels == numPixelsSaved, "numPixelsSaved");
  
  if (numPixels & 0x1) {
    MAXVID_ASSERT(((frameBuffer16 - inframeBuffer16) < frameBufferSize), "DUP already past end of framebuffer");
  }
#endif // EXTRA_CHECKS
  __asm__ __volatile__ (
                        "tst %[numPixels], #1\n\t"
                        "strneh %[pixel32], [%[outPtr]], #2\n\t"
                        :
                        [outPtr] "+l" (frameBuffer16),
                        [numPixels] "+l" (numPixels),
                        [pixel32] "+l" (pixel32Alias)
                        );
#else // USE_INLINE_ARM_ASM
  // By default, gcc would emit a conditional branch backwards,
  // then the half word assign followed by an unconditional
  // branch backwards. Putting the NOP asm in makes gcc
  // emit the one conditional instruction folowed by an
  // unconditional branch backwards.
  if (numPixels & 0x1) {
#ifdef EXTRA_CHECKS
    MAXVID_ASSERT(((frameBuffer16 - inframeBuffer16) < frameBufferSize), "DUP already past end of framebuffer");
#endif // EXTRA_CHECKS
    *frameBuffer16++ = pixel32Alias;
  }
  ASM_NOP
#endif // USE_INLINE_ARM_ASM
  
#ifdef EXTRA_CHECKS
  MAXVID_ASSERT(frameBuffer16 != NULL, "frameBuffer16");
  MAXVID_ASSERT(UINTMOD(frameBuffer16, sizeof(uint16_t)) == 0, "frameBuffer16 alignment");
  
  MAXVID_ASSERT(frameBuffer16 == expectedDUPSmallFinalFrameBuffer16, "frameBuffer16 final");
#endif
  
#ifdef EXTRA_CHECKS
  MAXVID_ASSERT(inW1 == inW1Saved, "inW1Saved");
#endif // EXTRA_CHECKS
  
  // Regen constants in registers (not needed in small DUP case)
  
#if defined(USE_INLINE_ARM_ASM)
//   __asm__ __volatile__ (
//   "mov %[constReg3], #2\n\t"
//   "mvn %[constReg2], #0xC000\n\t"
//   "orr %[constReg3], %[constReg3], %[constReg1], lsr #1\n\t"
//   :
//   [constReg1] "+l" (copyOnePixelHighHalfWordConstRegister),
//   [constReg2] "+l" (extractNumPixelsHighHalfWordConstRegister),
//   [constReg3] "+l" (dupTwoPixelsHighHalfWordConstRegister)
//   );
  
#ifdef EXTRA_CHECKS
  MAXVID_ASSERT(copyOnePixelHighHalfWordConstRegister == copyOnePixelHighHalfWord, "copyOnePixelHighHalfWordConstRegister");
  MAXVID_ASSERT(dupTwoPixelsHighHalfWordConstRegister == dupTwoPixelsHighHalfWord, "dupTwoPixelsHighHalfWordConstRegister");
  MAXVID_ASSERT(extractNumPixelsHighHalfWordConstRegister == ((0xFFFF << 16) | extractNumPixelsHighHalfWord), "extractNumPixelsHighHalfConstRegister");
#endif // EXTRA_CHECKS
#endif // USE_INLINE_ARM_ASM
  
#if defined(USE_INLINE_ARM_ASM)
  __asm__ __volatile__ (
                        "@ fall through to DECODE\n\t"
                        :
                        );
#endif // USE_INLINE_ARM_ASM
  
DECODE_16BPP:
#ifdef USE_INLINE_ARM_ASM
  // These checks are done before the read, after the DECODE_16BPP label
  
#ifdef EXTRA_CHECKS
  MAXVID_ASSERT(inputBuffer32 != NULL, "inputBuffer32");
  MAXVID_ASSERT(UINTMOD(inputBuffer32, sizeof(uint32_t)) == 0, "inputBuffer32 alignment");
  MAXVID_ASSERT(frameBuffer16 != NULL, "frameBuffer16");
  MAXVID_ASSERT(UINTMOD(frameBuffer16, sizeof(uint16_t)) == 0, "frameBuffer16 alignment");
  // inputBuffer32 should be 1 word ahead of the previous read (ignored in COPY case)
  MAXVID_ASSERT(inputBuffer32 == (prevInputBuffer32 + 1), "inputBuffer32 != previous");
#endif

#ifdef EXTRA_CHECKS
  MAXVID_ASSERT(inW1 == inW1Saved, "inW1Saved");
  MAXVID_ASSERT(copyOnePixelHighHalfWordConstRegister == copyOnePixelHighHalfWord, "copyOnePixelHighHalfWordConstRegister");
  MAXVID_ASSERT(dupTwoPixelsHighHalfWordConstRegister == dupTwoPixelsHighHalfWord, "dupTwoPixelsHighHalfWordConstRegister");
#endif // EXTRA_CHECKS

  // This impl of the inline ASM no longer matches the optimized implementation. Too much
  // of the structure has changed to keep this inline block and the optimized ARM asm in sync.
  // The optimized assembly does forward branches instead of conditional instrs as it is faster.
  
  __asm__ __volatile__ (
                        "@ DECODE_16BPP\n\t"
                        "2:\n\t"
                        "@ if ((opCode = (inW1 >> 30)) == SKIP) ...\n\t"
                        "movs %[opCode], %[inW1], lsr #30\n\t"
                        "addeq %[frameBuffer16], %[frameBuffer16], %[inW1], lsl #1\n\t"
                        "ldreq %[inW1], [%[inputBuffer32]], #4\n\t"
                        "beq 2b\n\t"
                        "@ if (COPY1 == (inW1 >> 16)) ...\n\t"
                        "cmp %[copyOnePixelHighHalfWordConstRegister], %[inW1], lsr #16\n\t"
                        "streqh %[inW1], [%[frameBuffer16]], #2\n\t"
                        "ldreq %[inW1], [%[inputBuffer32]], #4\n\t"
                        "beq 2b\n\t"
                        "@ if (DUP2 == (inW1 >> 16)) ...\n\t"
                        "cmp %[dupTwoPixelsHighHalfWordConstRegister], %[inW1], lsr #16\n\t"
                        "streqh %[inW1], [%[frameBuffer16]], #2\n\t"
                        "streqh %[inW1], [%[frameBuffer16]], #2\n\t"
                        "ldreq %[inW1], [%[inputBuffer32]], #4\n\t"
                        "beq 2b\n\t"
                        :
                        [inputBuffer32] "+l" (inputBuffer32),
                        [inW1] "+l" (inW1),
                        [frameBuffer16] "+l" (frameBuffer16),
                        [opCode] "+l" (opCode),
                        [copyOnePixelHighHalfWordConstRegister] "+l" (copyOnePixelHighHalfWordConstRegister),
                        [dupTwoPixelsHighHalfWordConstRegister] "+l" (dupTwoPixelsHighHalfWordConstRegister)
                        );
  
#ifdef EXTRA_CHECKS
  prevInputBuffer32 = inputBuffer32 - 1;
  inW1Saved = inW1;
  MAXVID_ASSERT(inputBuffer32 == (prevInputBuffer32 + 1), "inputBuffer32 != previous");
#endif
  
#ifdef EXTRA_CHECKS
  opCodeSaved = opCode;
#endif // EXTRA_CHECKS
  
#ifdef EXTRA_CHECKS
  MAXVID_ASSERT(inW1 == inW1Saved, "inW1Saved");
  MAXVID_ASSERT(copyOnePixelHighHalfWordConstRegister == copyOnePixelHighHalfWord, "copyOnePixelHighHalfWordConstRegister");
  MAXVID_ASSERT(dupTwoPixelsHighHalfWordConstRegister == dupTwoPixelsHighHalfWord, "dupTwoPixelsHighHalfWordConstRegister");
#endif // EXTRA_CHECKS
  
#else // USE_INLINE_ARM_ASM
  
#ifdef EXTRA_CHECKS
  MAXVID_ASSERT(inputBuffer32 != NULL, "inputBuffer32");
  MAXVID_ASSERT(UINTMOD(inputBuffer32, sizeof(uint32_t)) == 0, "inputBuffer32 alignment");
  MAXVID_ASSERT(frameBuffer16 != NULL, "frameBuffer16");
  MAXVID_ASSERT(UINTMOD(frameBuffer16, sizeof(uint16_t)) == 0, "frameBuffer16 alignment");
#endif
  
  if ((opCode = (inW1 >> 30)) == SKIP) {
#ifdef EXTRA_CHECKS
    MAXVID_ASSERT(((frameBuffer16 - inframeBuffer16) < frameBufferSize), "SKIP already past end of framebuffer");
    MAXVID_ASSERT(inW1 == inW1Saved, "inW1Saved");
#endif // EXTRA_CHECKS
    // SKIP over N 16bit pixels
    frameBuffer16 += inW1;
    
#ifdef EXTRA_CHECKS
    MAXVID_ASSERT(((frameBuffer16 - inframeBuffer16) <= frameBufferSize), "post SKIP now past end of framebuffer");
    MAXVID_ASSERT(inputBuffer32 != NULL, "inputBuffer32");
    MAXVID_ASSERT(UINTMOD(inputBuffer32, sizeof(uint32_t)) == 0, "inputBuffer32 alignment");
    MAXVID_ASSERT(frameBuffer16 != NULL, "frameBuffer16");
  MAXVID_ASSERT(UINTMOD(frameBuffer16, sizeof(uint16_t)) == 0, "frameBuffer16 alignment");
    // inputBuffer32 should be 1 word ahead of the previous read (ignored in COPY case)
    MAXVID_ASSERT(inputBuffer32 == (prevInputBuffer32 + 1), "inputBuffer32 != previous");
    prevInputBuffer32 = inputBuffer32;
#endif
    inW1 = *inputBuffer32++;
#ifdef EXTRA_CHECKS
    inW1Saved = inW1;
    MAXVID_ASSERT(inputBuffer32 == (prevInputBuffer32 + 1), "inputBuffer32 != previous");
#endif
    
    goto DECODE_16BPP;
  }
  
#ifdef EXTRA_CHECKS
  opCodeSaved = opCode;
#endif // EXTRA_CHECKS
  
  // FIXME: if the code were on the low part of the word, would only need to
  // shift by 2 to get the number. Instead of this having to compare to
  // a big constant. Could be a compare to 0x5 in this case.
  
  // Use WR2 = r1 as a scratch tmp to check for COPY1
  
  WR2 = copyOnePixelHighHalfWord;
  
#ifdef EXTRA_CHECKS
  MAXVID_ASSERT(inW1 == inW1Saved, "inW1Saved");
  MAXVID_ASSERT(WR2 == copyOnePixelHighHalfWord, "copyOnePixelHighHalfWord");
#endif // EXTRA_CHECKS
  if (WR2 == (inW1 >> 16))
    //  if (num == 1 && opCode == COPY)
  {
    // Special case where a COPY operation operates on only one 16 bit pixel.
#ifdef EXTRA_CHECKS
    MAXVID_ASSERT(((frameBuffer16 - inframeBuffer16) < frameBufferSize), "COPY already past end of framebuffer");
    MAXVID_ASSERT(inW1 == inW1Saved, "inW1Saved");
#endif // EXTRA_CHECKS
    *frameBuffer16++ = inW1;
    
#ifdef EXTRA_CHECKS
    MAXVID_ASSERT(inputBuffer32 != NULL, "inputBuffer32");
    MAXVID_ASSERT(UINTMOD(inputBuffer32, sizeof(uint32_t)) == 0, "inputBuffer32 alignment");
    MAXVID_ASSERT(frameBuffer16 != NULL, "frameBuffer16");
    MAXVID_ASSERT(UINTMOD(frameBuffer16, sizeof(uint16_t)) == 0, "frameBuffer16 alignment");
    // inputBuffer32 should be 1 word ahead of the previous read (ignored in COPY case)
    MAXVID_ASSERT(inputBuffer32 == (prevInputBuffer32 + 1), "inputBuffer32 != previous");
    prevInputBuffer32 = inputBuffer32;
#endif
    
    inW1 = *inputBuffer32++;
    
#ifdef EXTRA_CHECKS
    inW1Saved = inW1;
    MAXVID_ASSERT(inputBuffer32 == (prevInputBuffer32 + 1), "inputBuffer32 != previous");
#endif
        
    goto DECODE_16BPP;
  }
  
  // Use WR2 = r1 as a scratch tmp to check for DUP2
  
  WR2 = dupTwoPixelsHighHalfWord;
  
#ifdef EXTRA_CHECKS
  MAXVID_ASSERT(inW1 == inW1Saved, "inW1Saved");
  MAXVID_ASSERT(WR2 == dupTwoPixelsHighHalfWord, "dupTwoPixelsHighHalfWord");
#endif // EXTRA_CHECKS
  if (WR2 == (inW1 >> 16))
    //  if (num == 2 && opCode == DUP)
  {
    // Special case where DUP writes 2 pixels. It is faster to do two half word writes than
    // check the alignment, create the register bank, write, then check for trailing pixel.
#ifdef EXTRA_CHECKS
    MAXVID_ASSERT(((frameBuffer16 - inframeBuffer16) < frameBufferSize), "DUP already past end of framebuffer");
    MAXVID_ASSERT(inW1 == inW1Saved, "inW1Saved");
#endif // EXTRA_CHECKS
    
    // Execute two 16 bit writes, does not depend on alignment
    *frameBuffer16++ = inW1;
    *frameBuffer16++ = inW1;
    
#ifdef EXTRA_CHECKS
    MAXVID_ASSERT(inputBuffer32 != NULL, "inputBuffer32");
    MAXVID_ASSERT(UINTMOD(inputBuffer32, sizeof(uint32_t)) == 0, "inputBuffer32 alignment");
    MAXVID_ASSERT(frameBuffer16 != NULL, "frameBuffer16");
    MAXVID_ASSERT(UINTMOD(frameBuffer16, sizeof(uint16_t)) == 0, "frameBuffer16 alignment");
    // inputBuffer32 should be 1 word ahead of the previous read (ignored in COPY case)
    MAXVID_ASSERT(inputBuffer32 == (prevInputBuffer32 + 1), "inputBuffer32 != previous");
    prevInputBuffer32 = inputBuffer32;
#endif
    
    inW1 = *inputBuffer32++;
    
#ifdef EXTRA_CHECKS
    inW1Saved = inW1;
    MAXVID_ASSERT(inputBuffer32 == (prevInputBuffer32 + 1), "inputBuffer32 != previous");
#endif
    
    goto DECODE_16BPP;
  }
#endif // USE_INLINE_ARM_ASM
  
#ifdef EXTRA_CHECKS
  MAXVID_ASSERT(inW1 == inW1Saved, "inW1Saved");
  // COPY1 should have been handled above, so it should not be possible to get here with a COPY code and numPixels = 1
  
  MAXVID_ASSERT(((inW1 >> 16) & extractNumPixelsHighHalfWord) != copyOnePixelHighHalfWord, "numPixels");
  if (opCode == COPY) {
    MAXVID_ASSERT((((inW1 >> 16) & extractNumPixelsHighHalfWord) != 0), "COPY1 numPixels");
    MAXVID_ASSERT((((inW1 >> 16) & extractNumPixelsHighHalfWord) != 1), "COPY1 numPixels");
  }
  if (opCode == DUP) {
    MAXVID_ASSERT((((inW1 >> 16) & extractNumPixelsHighHalfWord) != 0), "DUP2 numPixels");
    MAXVID_ASSERT((((inW1 >> 16) & extractNumPixelsHighHalfWord) != 1), "DUP2 numPixels");
    MAXVID_ASSERT((((inW1 >> 16) & extractNumPixelsHighHalfWord) != 2), "DUP2 numPixels");
  }  
#endif // USE_INLINE_ARM_ASM
  
#ifdef EXTRA_CHECKS
  MAXVID_ASSERT(frameBuffer16 != NULL, "frameBuffer16");
  MAXVID_ASSERT(UINTMOD(frameBuffer16, sizeof(uint16_t)) == 0, "frameBuffer16 alignment");
#endif
  
  // Parse numPixels from inW1
  
#ifdef EXTRA_CHECKS
  MAXVID_ASSERT(inW1 == inW1Saved, "inW1Saved");
#endif // EXTRA_CHECKS
  
#ifdef USE_INLINE_ARM_ASM
  __asm__ __volatile__ (
                        "and %[numPixels], %[extractNumPixelsHighHalfWordConstRegister], %[inW1], lsr #16\n\t"
                        :
                        [numPixels] "+l" (numPixels)
                        :
                        [inW1] "l" (inW1),
                        [extractNumPixelsHighHalfWordConstRegister] "l" (extractNumPixelsHighHalfWordConstRegister)
                        );
#else // USE_INLINE_ARM_ASM
  numPixels = (inW1 >> 16) & extractNumPixelsHighHalfWord;
#endif // USE_INLINE_ARM_ASM
  
#ifdef EXTRA_CHECKS
  numPixelsSaved = numPixels;
  MAXVID_ASSERT(numPixels == ((inW1 >> 16) & extractNumPixelsHighHalfWord), "numPixels");
  if (opCode != DONE) {
    MAXVID_ASSERT(numPixels != 0, "numPixels != 0");
    MAXVID_ASSERT(numPixels != 1, "numPixels != 1");
  }
#endif
  
#ifdef USE_INLINE_ARM_ASM
  // GCC emits a phantom assign to "r11" when compiling the C code.
  // This weird empty asm statement keeps GCC from doing that.
  
  __asm__ __volatile__ (
                        "@ Phantom assign to opCode\n\t"
                        : \
                        [opCode] "+l" (opCode)
                        );
#endif // USE_INLINE_ARM_ASM

#if defined(USE_INLINE_ARM_ASM)
  __asm__ __volatile__ (
                        "@ if (opCode == DUP) goto DUP_16BPP\n\t"
                        :
                        );
#endif // USE_INLINE_ARM_ASM
  
  if (opCode == DUP) {
    // COPY
    
    goto DUP_16BPP;
  }  
  
  // Handle DONE after COPY branch. This provides a small improvement
  // in execution time as compared to checking for DONE before COPY.
  
#ifdef EXTRA_CHECKS
  MAXVID_ASSERT(opCode == opCodeSaved, "opCodeSaved");
#endif // EXTRA_CHECKS
  
#ifdef USE_INLINE_ARM_ASM
  // GCC emits a phantom assign to "r11" when compiling the C code.
  // This weird empty asm statement keeps GCC from doing that.
  
  __asm__ __volatile__ (
                        "@ Phantom assign to opCode\n\t"
                        : \
                        [opCode] "+l" (opCode)
                        );
#endif // USE_INLINE_ARM_ASM
  
#ifdef USE_INLINE_ARM_ASM
  __asm__ __volatile__ (
                        "@ if (opCode == DONE) goto DONE_16BPP\n\t"
                        );
#endif // USE_INLINE_ARM_ASM
  
  if (opCode == DONE) {
#ifdef EXTRA_CHECKS
    MAXVID_ASSERT(numPixels == 0, "numPixels");
#endif // EXTRA_CHECKS
    
    goto DONE_16BPP;
  }
  
  // COPY operation, generic code for either big or small copy

#ifdef USE_INLINE_ARM_ASM
  __asm__ __volatile__ (
                        "@ COPY 16BPP\n\t"
                        );
#endif // USE_INLINE_ARM_ASM

  // Word align the framebuffer, if needed.
  // Note that the special COPY case where numPixels = 1 was handled already.
  
#ifdef EXTRA_CHECKS
  MAXVID_ASSERT(numPixels == numPixelsSaved, "numPixelsSaved");
  MAXVID_ASSERT(numPixels != 0, "numPixels != 0");
  MAXVID_ASSERT(numPixels != 1, "numPixels != 1");
  MAXVID_ASSERT(numPixels >= 2, "numPixels >= 2");
#endif
  
#ifdef EXTRA_CHECKS
  MAXVID_ASSERT(inputBuffer32 != NULL, "inputBuffer32");
  MAXVID_ASSERT(UINTMOD(inputBuffer32, sizeof(uint32_t)) == 0, "inputBuffer32 alignment");
  MAXVID_ASSERT(frameBuffer16 != NULL, "frameBuffer16");
  MAXVID_ASSERT(UINTMOD(frameBuffer16, sizeof(uint16_t)) == 0, "frameBuffer16 alignment");
  MAXVID_ASSERT((((frameBuffer16 + numPixels - 1) - inframeBuffer16) < frameBufferSize), "MV16_CODE_COPY past end of framebuffer");
#endif
  
#ifdef EXTRA_CHECKS
  MAXVID_ASSERT(inW1 == inW1Saved, "inW1Saved");
#endif // EXTRA_CHECKS
  
  // START align32 block
  
#ifdef EXTRA_CHECKS
  MAXVID_ASSERT(((frameBuffer16 - inframeBuffer16) < frameBufferSize), "word align: already past end of framebuffer");
  MAXVID_ASSERT(numPixels == numPixelsSaved, "numPixelsSaved");
#endif // EXTRA_CHECKS
  
#if defined(USE_INLINE_ARM_ASM)
  __asm__ __volatile__ (
                        "@ align32\n\t"
                        "tst %[frameBuffer16], #3\n\t"
                        "subne %[numPixels], %[numPixels], #1\n\t"
                        "strneh %[inW1], [%[frameBuffer16]], #2\n\t"
                        :
                        [frameBuffer16] "+l" (frameBuffer16),
                        [numPixels] "+l" (numPixels)
                        :
                        [inW1] "l" (inW1)
                        );
#else // USE_INLINE_ARM_ASM
  if (UINTMOD(frameBuffer16, 4) != 0) {
    // Framebuffer is half word aligned, write 16 bit pixel in the low half word
    *frameBuffer16++ = inW1;
    numPixels--;
  }
#endif // USE_INLINE_ARM_ASM
  
#ifdef EXTRA_CHECKS
  numPixelsSaved = numPixels;
#endif // EXTRA_CHECKS
  
#ifdef EXTRA_CHECKS
  MAXVID_ASSERT(numPixels == numPixelsSaved, "numPixelsSaved");
  MAXVID_ASSERT(opCode == opCodeSaved, "opCodeSaved");
  
  MAXVID_ASSERT(frameBuffer16 != NULL, "frameBuffer16");
  MAXVID_ASSERT(UINTMOD(frameBuffer16, sizeof(uint32_t)) == 0, "frameBuffer16 alignment");
#endif // EXTRA_CHECKS
  
// END align32 block

// START numWords block
  
  // numWords is numPixels/2, could count down to zero in a loop.
  // num is a 14 bit number that indicates the number of pixels to copy.
  // This logic must appear after the framebuffer has been aligned
  // since that logic can decrement the numPixels by 1 in the
  // unaligned case.
  
#ifdef EXTRA_CHECKS
  MAXVID_ASSERT(numPixels == numPixelsSaved, "numPixelsSaved");
#endif
  
#ifdef USE_INLINE_ARM_ASM
  __asm__ __volatile__ (
                        "@ numWords\n\t"
                        "mov %[numWords], %[numPixels], lsr #1\n\t"
                        :
                        [numWords] "+l" (numWords)
                        :
                        [numPixels] "l" (numPixels)
                        );
#else // USE_INLINE_ARM_ASM
  // Note that the inline ASM above is needed to avoid stack use in conditional case
  numWords = (numPixels >> 1);
#endif // USE_INLINE_ARM_ASM
  
#ifdef EXTRA_CHECKS
  numWordsSaved = numWords;
  MAXVID_ASSERT(numWordsSaved == (numPixels >> 1), "numWordsSaved");
  MAXVID_ASSERT(numPixels > numWords, "numPixels > numPixels");
#endif
  
#ifdef EXTRA_CHECKS
  MAXVID_ASSERT(numWords < 0x3FFFFFFF, "numWords");
#endif

// END numWords block

  // Branch to big copy handler if larger than cutoff size,
  // otherwise fall through to most optimal small copy instructions.
  
#ifdef USE_INLINE_ARM_ASM
  __asm__ __volatile__ (
                        "@ if (numWords > 7) goto COPYBIG_16BPP\n\t"
                        );
#endif // USE_INLINE_ARM_ASM
  
  if (numPixels >= (8*2)) {
#ifdef EXTRA_CHECKS
    MAXVID_ASSERT(opCode == COPY, "opCode");
#endif // EXTRA_CHECKS
    
    goto COPYBIG_16BPP;
  }
  
  // Note that opCode is not used after this point
  
  // COPYSMALL_16BPP
  //
  // When there are 7 or fewer words to be copied, process with COPYSMALL.
  
COPYSMALL_16BPP:
  {}
  
#if defined(USE_INLINE_ARM_ASM)
  __asm__ __volatile__ (
                        "@ COPYSMALL_16BPP\n\t"
                        );
#endif //  USE_INLINE_ARM_ASM
  
  // Word align the framebuffer, if needed.
  // Note that the special case where COPY and numPixels = 1 was handled already.
  
#ifdef EXTRA_CHECKS
  MAXVID_ASSERT(numPixels == numPixelsSaved, "numPixelsSaved");
#endif
  
#ifdef EXTRA_CHECKS
  MAXVID_ASSERT(inputBuffer32 != NULL, "inputBuffer32");
  MAXVID_ASSERT(UINTMOD(inputBuffer32, sizeof(uint32_t)) == 0, "inputBuffer32 alignment");
  MAXVID_ASSERT(frameBuffer16 != NULL, "frameBuffer16");
  MAXVID_ASSERT(UINTMOD(frameBuffer16, sizeof(uint32_t)) == 0, "frameBuffer16 word alignment");
  MAXVID_ASSERT((((frameBuffer16 + numPixels - 1) - inframeBuffer16) < frameBufferSize), "MV16_CODE_COPY past end of framebuffer");
#endif
  
#ifdef EXTRA_CHECKS
  MAXVID_ASSERT(inputBuffer32 != NULL, "inputBuffer32");
  MAXVID_ASSERT(frameBuffer16 != NULL, "frameBuffer16");
  
  MAXVID_ASSERT(UINTMOD(inputBuffer32, sizeof(uint32_t)) == 0, "inputBuffer32 alignment");
  MAXVID_ASSERT(UINTMOD(frameBuffer16, sizeof(uint32_t)) == 0, "frameBuffer16 alignment");
  
  MAXVID_ASSERT(numPixels == numPixelsSaved, "numPixelsSaved");
  MAXVID_ASSERT(numWords == numWordsSaved, "numWordsSaved");
  MAXVID_ASSERT(numPixels > numWords, "numPixels > numPixels");
  
  MAXVID_ASSERT(numWords < 8, "numWords");
  //MAXVID_ASSERT(numWords > 0, "numWords");
  
  uint16_t *expectedCOPYSmallFinalFrameBuffer16 = frameBuffer16 + numPixels;
  uint32_t *expectedCOPYSmallFinalOutInputBuffer32 = ((uint32_t *)inputBuffer32) + (numPixels >> 1);
  expectedCOPYSmallFinalOutInputBuffer32 += (numPixels & 0x1);
  
  uint16_t *expectedCOPYSmallPost8FrameBuffer16 = (uint16_t*) (((uint32_t *) frameBuffer16) + numWords);
  uint32_t *expectedCOPYSmallPost8InputBuffer32 = ((uint32_t *) inputBuffer32) + numWords;
  
  MAXVID_ASSERT(
                ((uint16_t*)expectedCOPYSmallFinalFrameBuffer16 == expectedCOPYSmallPost8FrameBuffer16) || 
                (expectedCOPYSmallFinalFrameBuffer16 == expectedCOPYSmallPost8FrameBuffer16+1), "expected pointers");
  
  MAXVID_ASSERT(expectedCOPYSmallPost8InputBuffer32 == (((uint32_t *) inputBuffer32) + numWords), "expected pointers");
  
  MAXVID_ASSERT(numPixels == numPixelsSaved, "numPixelsSaved");
  MAXVID_ASSERT(numWords == numWordsSaved, "numWordsSaved");
  MAXVID_ASSERT(numWords < 0x3FFFFFFF, "numWords");
#endif

  // Execute small copy logic for 7 words or less (14 pixels)
  
#if defined(USE_INLINE_ARM_ASM)
  __asm__ __volatile__ (
                        "cmp %[numWords], #3\n\t"
                        "ldmgtia %[inWordPtr]!, {%[wr1], %[wr2], %[wr3], %[wr4]}\n\t"
                        "subgt %[numWords], %[numWords], #4\n\t"
                        "stmgtia %[outWordPtr]!, {%[wr1], %[wr2], %[wr3], %[wr4]}\n\t"
                        "cmp %[numWords], #1\n\t"
                        "ldmgtia %[inWordPtr]!, {%[wr1], %[wr2]}\n\t"
                        "subgt %[numWords], %[numWords], #2\n\t"
                        "stmgtia %[outWordPtr]!, {%[wr1], %[wr2]}\n\t"
                        "cmp %[numWords], #1\n\t"
                        "ldreq %[wr1], [%[inWordPtr]], #4\n\t"
                        "streq %[wr1], [%[outWordPtr]], #4\n\t"
                        :
                        [outWordPtr] "+l" (frameBuffer16),
                        [inWordPtr] "+l" (inputBuffer32),
                        [numWords] "+l" (numWords),
                        [wr1] "+l" (WR1),
                        [wr2] "+l" (WR2),
                        [wr3] "+l" (WR3),
                        [wr4] "+l" (WR4)
                        );

#else // USE_INLINE_ARM_ASM
  // Valid numWords values are 1, 2, 3, 4, 5, 6, 7 at this point
  
  // Read/Write 4 words, when numWords is 4, 5, 6, 7
  
  if (numWords > 3) {
    *((uint32_t*)frameBuffer16 + 0) = *(inputBuffer32 + 0);
    *((uint32_t*)frameBuffer16 + 1) = *(inputBuffer32 + 1);
    *((uint32_t*)frameBuffer16 + 2) = *(inputBuffer32 + 2);
    *((uint32_t*)frameBuffer16 + 3) = *(inputBuffer32 + 3);
    frameBuffer16 += 4 << 1;
    inputBuffer32 += 4;
    numWords -= 4;
  }
  
  // Read/Write 2 words, when numWords is 2, 3
  
  if (numWords > 1) {
    *((uint32_t*)frameBuffer16 + 0) = *(inputBuffer32 + 0);
    *((uint32_t*)frameBuffer16 + 1) = *(inputBuffer32 + 1);
  }
  
#ifdef EXTRA_CHECKS
  MAXVID_ASSERT(numWords >=0 && numWords <= 3, "numWords must be in range");
#endif
  
  frameBuffer16 += numWords << 1;
  inputBuffer32 += numWords;
  
  // Read/Write 1 word, when numWords is 1, 3
  
  if (numWords & 0x1) {
    *((uint32_t*)frameBuffer16 - 1) = *(inputBuffer32 - 1);
  }

#endif // USE_INLINE_ARM_ASM
  
#ifdef EXTRA_CHECKS
  MAXVID_ASSERT(frameBuffer16 == expectedCOPYSmallPost8FrameBuffer16, "COPY post word8 framebuffer");
  MAXVID_ASSERT(inputBuffer32 == expectedCOPYSmallPost8InputBuffer32, "COPY input post word8");
#endif
  
#ifdef EXTRA_CHECKS
  MAXVID_ASSERT(numPixels == numPixelsSaved, "numPixelsSaved");
  if (numPixels & 0x1) {
    MAXVID_ASSERT(((frameBuffer16 - inframeBuffer16) < frameBufferSize), "COPY already past end of framebuffer");
  }
#endif // EXTRA_CHECKS
  
  // Write 1 more pixel in the case where copyNumPixels is odd
  // WTF? GCC bug is emitting a load but it misses the incr in debug mode.
  // This looks like a compiler bug in ARM mode that should be reported.
  
#if defined(USE_INLINE_ARM_ASM)
  __asm__ __volatile__ (
                        // if (numPixels & 0x1)
                        "tst %[numPixels], #0x1\n\t"
                        // WR4 = *inputBuffer32++;
                        "ldrne %[TMP], [%[inputBuffer32]], #4\n\t"
                        // *frameBuffer16++ = WR4;
                        "strneh %[TMP], [%[frameBuffer16]], #2\n\t"
                        :
                        [numPixels] "+l" (numPixels),
                        [frameBuffer16] "+l" (frameBuffer16),
                        [TMP] "+l" (WR4),
                        [inputBuffer32] "+l" (inputBuffer32)
                        );
#else
  if (numPixels & 0x1) {
    WR4 = *inputBuffer32++;
    *frameBuffer16++ = WR4;
  }
#endif // USE_INLINE_ARM_ASM
  
#ifdef EXTRA_CHECKS
  if (numPixels & 0x1) {
    MAXVID_ASSERT((WR4 >> 16) == 0, "high half must be zero");
  }
#endif // EXTRA_CHECKS
  
#ifdef EXTRA_CHECKS
  MAXVID_ASSERT(frameBuffer16 == expectedCOPYSmallFinalFrameBuffer16, "expectedCOPYFinalFrameBuffer16");
  MAXVID_ASSERT(inputBuffer32 == expectedCOPYSmallFinalOutInputBuffer32, "expectedCOPYFinalOutInputBuffer32");
#endif
  
  // Load inW1 again. The final half word read above needs to be completed before
  // the next word can be read, so this read could stall for a couple of cycles.
  
#ifdef EXTRA_CHECKS
  MAXVID_ASSERT(inputBuffer32 != NULL, "inputBuffer32");
  MAXVID_ASSERT(UINTMOD(inputBuffer32, sizeof(uint32_t)) == 0, "inputBuffer32 alignment");
  MAXVID_ASSERT(inW1 == inW1Saved, "inW1Saved");
  // inputBuffer32 should be 1 word ahead of the previous read (ignored in COPY case)
  //MAXVID_ASSERT(inputBuffer32 == (prevInputBuffer32 + 1), "inputBuffer32 != previous");
  prevInputBuffer32 = inputBuffer32;
#endif
  
#if defined(USE_INLINE_ARM_ASM)
  __asm__ __volatile__ (
                        // inW1 = *inputBuffer32++
                        "ldr %[inW1], [%[inputBuffer32]], #4\n\t"
                        :
                        [inW1] "+l" (inW1),
                        [inputBuffer32] "+l" (inputBuffer32)
                        );
#else
  inW1 = *inputBuffer32++;
#endif // USE_INLINE_ARM_ASM
  
#ifdef EXTRA_CHECKS
  inW1Saved = inW1;
  MAXVID_ASSERT(inputBuffer32 == (prevInputBuffer32 + 1), "inputBuffer32 != previous");
#endif
  
  // Regen constants in registers
  
#if defined(USE_INLINE_ARM_ASM)
  /*
  __asm__ __volatile__ (
                        "mov %[constReg3], #2\n\t"
                        "mvn %[constReg2], #0xC000\n\t"
                        "orr %[constReg3], %[constReg3], %[constReg1], lsr #1\n\t"
                        :
                        [constReg1] "+l" (copyOnePixelHighHalfWordConstRegister),
                        [constReg2] "+l" (extractNumPixelsHighHalfWordConstRegister),
                        [constReg3] "+l" (dupTwoPixelsHighHalfWordConstRegister)
                        );
  */
  
#ifdef EXTRA_CHECKS
  MAXVID_ASSERT(copyOnePixelHighHalfWordConstRegister == copyOnePixelHighHalfWord, "copyOnePixelHighHalfWordConstRegister");
  MAXVID_ASSERT(dupTwoPixelsHighHalfWordConstRegister == dupTwoPixelsHighHalfWord, "dupTwoPixelsHighHalfWordConstRegister");
  MAXVID_ASSERT(extractNumPixelsHighHalfWordConstRegister == ((0xFFFF << 16) | extractNumPixelsHighHalfWord), "extractNumPixelsHighHalfConstRegister");
#endif // EXTRA_CHECKS
#endif // USE_INLINE_ARM_ASM
  
#if defined(USE_INLINE_ARM_ASM)
  __asm__ __volatile__ (
                        "@ goto DECODE_16BPP\n\t"
                        :
                        );
#endif // USE_INLINE_ARM_ASM
  
  goto DECODE_16BPP;
  
COPYBIG_16BPP:
  {}
  
  // COPYBIG_16BPP
  
#if defined(USE_INLINE_ARM_ASM)
  __asm__ __volatile__ (
                        "@ COPYBIG_16BPP\n\t"
                        );
#endif //  USE_INLINE_ARM_ASM
  
#ifdef EXTRA_CHECKS
  MAXVID_ASSERT(numPixels == numPixelsSaved, "numPixelsSaved");
  MAXVID_ASSERT(numPixels >= (7*2), "numPixels");
#endif
  
#ifdef EXTRA_CHECKS
  MAXVID_ASSERT(inputBuffer32 != NULL, "inputBuffer32");
  MAXVID_ASSERT(UINTMOD(inputBuffer32, sizeof(uint32_t)) == 0, "inputBuffer32 alignment");
  MAXVID_ASSERT(frameBuffer16 != NULL, "frameBuffer16");
  MAXVID_ASSERT(UINTMOD(frameBuffer16, sizeof(uint32_t)) == 0, "frameBuffer16 word alignment");
  MAXVID_ASSERT((((frameBuffer16 + numPixels - 1) - inframeBuffer16) < frameBufferSize), "MV16_CODE_COPY past end of framebuffer");
#endif
  
#ifdef EXTRA_CHECKS
  MAXVID_ASSERT(numWords >= 7, "numWords");
  MAXVID_ASSERT(numWords < 0x3FFFFFFF, "numWords");
#endif
  
#ifdef EXTRA_CHECKS
  MAXVID_ASSERT(inputBuffer32 != NULL, "inputBuffer32");
  MAXVID_ASSERT(frameBuffer16 != NULL, "frameBuffer16");
  
  MAXVID_ASSERT(UINTMOD(inputBuffer32, sizeof(uint32_t)) == 0, "inputBuffer32 alignment");
  MAXVID_ASSERT(UINTMOD(frameBuffer16, sizeof(uint32_t)) == 0, "frameBuffer16 alignment");
  
  MAXVID_ASSERT(numPixels == numPixelsSaved, "numPixelsSaved");
  MAXVID_ASSERT(numWords == numWordsSaved, "numWordsSaved");
  MAXVID_ASSERT(numPixels > numWords, "numPixels > numPixels");
  
  uint16_t *expectedCOPYBigFinalFrameBuffer16 = frameBuffer16 + numPixels;
  uint32_t *expectedCOPYBigFinalOutInputBuffer32 = ((uint32_t *)inputBuffer32) + (numPixels >> 1);
  expectedCOPYBigFinalOutInputBuffer32 += (numPixels & 0x1);
  
  uint16_t *expectedCOPYBigPost8FrameBuffer16 = (uint16_t*) (((uint32_t *) frameBuffer16) + numWords);
  uint32_t *expectedCOPYBigPost8InputBuffer32 = ((uint32_t *) inputBuffer32) + numWords;
  
  MAXVID_ASSERT(
                ((uint16_t*)expectedCOPYBigFinalFrameBuffer16 == expectedCOPYBigPost8FrameBuffer16) || 
                (expectedCOPYBigFinalFrameBuffer16 == expectedCOPYBigPost8FrameBuffer16+1), "expected pointers");
  
  MAXVID_ASSERT(expectedCOPYBigPost8InputBuffer32 == (((uint32_t *) inputBuffer32) + numWords), "expected pointers");
#endif

#ifdef USE_INLINE_ARM_ASM
  // GCC emits a phantom assign to "r11" when compiling the C code.
  // This weird empty asm statement keeps GCC from doing that.
  
  __asm__ __volatile__ (
                        "@ Phantom assign to numWords\n\t"
                        : \
                        [numWords] "+l" (numWords)
                        );
#endif // USE_INLINE_ARM_ASM
  
// START align64 block
  
  // Align to 64 bits to speed up stm writes with only a few conditional instrs.
  
#ifdef EXTRA_CHECKS
  MAXVID_ASSERT(((frameBuffer16 - inframeBuffer16) < frameBufferSize), "dword align already past end of framebuffer");
  MAXVID_ASSERT(numWords >= 7, "dword align: numWords");
#endif // EXTRA_CHECKS
  
#if defined(USE_INLINE_ARM_ASM)
  __asm__ __volatile__ (
                        // if (UINTMOD(frameBuffer16, sizeof(uint64_t)) != 0)
                        "tst %[frameBuffer16], #7\n\t"
                        // WR1 = *inputBuffer32++;
                        "ldrne %[wr1], [%[inputBuffer32]], #4\n\t"
                        // numWords -= 1;
                        "subne %[numWords], %[numWords], #1\n\t"
                        // *((uint32_t*)frameBuffer16) = WR1; frameBuffer16 += 2;
                        "strne %[wr1], [%[frameBuffer16]], #4\n\t"
                        :
                        [numWords] "+l" (numWords),
                        [wr1] "+l" (WR1),
                        [wr2] "+l" (WR2),
                        [inputBuffer32] "+l" (inputBuffer32),
                        [frameBuffer16] "+l" (frameBuffer16)
                        );
#else // USE_INLINE_ARM_ASM
  
  if (UINTMOD(frameBuffer16, sizeof(uint64_t)) != 0) {
    // Framebuffer is word aligned, read/write a word (1 pixel) to dword align.
    
    WR1 = *inputBuffer32++;
    numWords -= 1;
    *((uint32_t*)frameBuffer16) = WR1;
    frameBuffer16 += 2;
  }
  
#endif //USE_INLINE_ARM_ASM
  
#ifdef EXTRA_CHECKS
  // The min numWords was 7, now could be >= 6
  MAXVID_ASSERT(numWords >= 6, "dword align: numWords");
  MAXVID_ASSERT(frameBuffer16 != NULL, "frameBuffer16");
  MAXVID_ASSERT(UINTMOD(frameBuffer16, sizeof(uint64_t)) == 0, "frameBuffer16 dword alignment");
#endif // EXTRA_CHECKS
  
// END align64 block
  
  // if (numWords >= 32) block disabled because it seems to be faster to align64
  // for the output buffer. That avoids a branch forward and a bunch of instructions.
  
  if (0) {
    // 16 word copy loop will be run more than 1 time, so align to 8 word cache line
    
    // Align the input pointer to the start of the next cache line. On ARM6 a
    // cache line is 8 words. ON ARM7, the cache is 16 words.
    // Use WR5 as a tmp countdown register, it won't be written over in debug
    // mode and it is set again after the word8 loop.
    
    WR5 = UINTMOD(inputBuffer32, BOUNDSIZE);
    
#ifdef EXTRA_CHECKS
    MAXVID_ASSERT(UINTMOD(inputBuffer32, sizeof(uint32_t)) == 0, "inputBuffer32 alignment");
    MAXVID_ASSERT(WR5 >= 0 && WR5 <= BOUNDSIZE, "in bounds");
#endif
    
    WR5 = BOUNDSIZE - WR5;
    WR5 >>= 2;
    WR5 &= (MV_CACHE_LINE_SIZE - 1);
    
#ifdef EXTRA_CHECKS
    MAXVID_ASSERT(WR5 >= 0, "invalid num words to bound");
    MAXVID_ASSERT(WR5 != MV_CACHE_LINE_SIZE, "invalid num words to bound");
    MAXVID_ASSERT(WR5 < MV_CACHE_LINE_SIZE, "invalid num words to bound");
    uint32_t *expectedPostAlignInputBuffer32 = inputBuffer32 + WR5;
    MAXVID_ASSERT(UINTMOD(expectedPostAlignInputBuffer32, BOUNDSIZE) == 0, "input ptr should be at bound");
#endif
    
#if defined(USE_INLINE_ARM_ASM)
    __asm__ __volatile__ (
                          "sub %[numWords], %[numWords], %[TMP]\n\t"
                          "cmp %[TMP], #1\n\t"
                          "ldmgtia %[inputBuffer32]!, {%[wr3], %[wr4]}\n\t"
                          "3:\n\t"
                          "subgt %[TMP], %[TMP], #2\n\t"
                          "stmgtia %[frameBuffer16]!, {%[wr3], %[wr4]}\n\t"
                          "cmp %[TMP], #1\n\t"
                          "ldmgtia %[inputBuffer32]!, {%[wr3], %[wr4]}\n\t"
                          "bgt 3b\n\t"
                          // if (TMP == 1)
                          "ldreq %[wr3], [%[inputBuffer32]], #4\n\t"
                          "streq %[wr3], [%[frameBuffer16]], #4\n\t"
                          :
                          [numWords] "+l" (numWords),
                          [TMP] "+l" (WR5),
                          [wr3] "+l" (WR3),
                          [wr4] "+l" (WR4),
                          [inputBuffer32] "+l" (inputBuffer32),
                          [frameBuffer16] "+l" (frameBuffer16)
                          );
#else
    numWords -= WR5;
    
    for (; WR5 > 1; WR5 -= 2) {
      memcpy(frameBuffer16, inputBuffer32, sizeof(uint32_t) * 2);
      frameBuffer16 += 2 * sizeof(uint16_t);
      inputBuffer32 += 2;
    }
    if (WR5 == 1) {
      WR3 = *inputBuffer32++;
      *((uint32_t*)frameBuffer16) = WR3;
      frameBuffer16 += 1 * sizeof(uint16_t);
    }
#endif // USE_INLINE_ARM_ASM
    
#ifdef EXTRA_CHECKS
    MAXVID_ASSERT(WR5 == 0 || WR5 == 1, "WR5");
    MAXVID_ASSERT(expectedPostAlignInputBuffer32 == inputBuffer32, "expectedPostAlignInputBuffer32");
    MAXVID_ASSERT(UINTMOD(inputBuffer32, BOUNDSIZE) == 0, "input ptr should be at bound");
#endif
  } // end of if (numWords >= 32)
  
#ifdef EXTRA_CHECKS
  MAXVID_ASSERT(numWords >= 6, "numWords");
#endif

  // Big write loop, use stm to read and write 8 words at a time, 16 words in each loop
  
#if defined(USE_INLINE_ARM_ASM)

  if (numWords >= 16) {
    // Once we know there are at least 16 words to be copied then do an
    // additional check to see if it is worth it to invoke memcpy()
    // for a very large copy operation. The platform defined memcpy()
    // is optimized for the specific processor type (A8 vs A9) and as
    // a result it is faster for large copies.
    
    if (numWords >= (MV_PAGESIZE / 4 / sizeof(uint32_t))) {
      memcpy(frameBuffer16, inputBuffer32, numWords << 2);
      frameBuffer16 += numWords << 1;
      inputBuffer32 += numWords;
      // Skip the 8 word loop and any remaining copies by setting to zero
      numWords = 0;
    } else {
    
    __asm__ __volatile__ (
                          "1:\n\t"
    
                          "ldmia %[inWordPtr]!, {%[wr1], %[wr2], %[wr3], %[wr4], %[wr5], %[wr6], %[wr7], %[wr8]}\n\t"
                          "pld	[%[inWordPtr], #32]\n\t"
                          "sub %[numWords], %[numWords], #16\n\t"
                          "stmia %[outWordPtr]!, {%[wr1], %[wr2], %[wr3], %[wr4], %[wr5], %[wr6], %[wr7], %[wr8]}\n\t"
                          "ldmia %[inWordPtr]!, {%[wr1], %[wr2], %[wr3], %[wr4], %[wr5], %[wr6], %[wr7], %[wr8]}\n\t"
                          "pld	[%[inWordPtr], #32]\n\t"
                          "cmp %[numWords], #15\n\t"
                          "stmia %[outWordPtr]!, {%[wr1], %[wr2], %[wr3], %[wr4], %[wr5], %[wr6], %[wr7], %[wr8]}\n\t"
                          "bgt 1b\n\t"
                          :
                          [outWordPtr] "+l" (frameBuffer16),
                          [inWordPtr] "+l" (inputBuffer32),
                          [numWords] "+l" (numWords),
                          [wr1] "+l" (WR1),
                          [wr2] "+l" (WR2),
                          [wr3] "+l" (WR3),
                          [wr4] "+l" (WR4),
                          [wr5] "+l" (WR5),
                          [wr6] "+l" (WR6),
                          [wr7] "+l" (WR7),
                          [wr8] "+l" (WR8)
                          );
    }
  }
  
#ifdef EXTRA_CHECKS
  MAXVID_ASSERT(numWords < 0x3FFFFFFF, "numWords");
  MAXVID_ASSERT(numWords < 16, "numWords");
#endif
  
  __asm__ __volatile__ (
                        "cmp %[numWords], #7\n\t"
                        "ldmgtia %[inWordPtr]!, {%[wr1], %[wr2], %[wr3], %[wr4], %[wr5], %[wr6], %[wr7], %[wr8]}\n\t"
                        "subgt %[numWords], %[numWords], #8\n\t"
                        "stmgtia %[outWordPtr]!, {%[wr1], %[wr2], %[wr3], %[wr4], %[wr5], %[wr6], %[wr7], %[wr8]}\n\t"
                        "cmp %[numWords], #3\n\t"
                        "ldmgtia %[inWordPtr]!, {%[wr1], %[wr2], %[wr3], %[wr4]}\n\t"
                        "subgt %[numWords], %[numWords], #4\n\t"
                        "stmgtia %[outWordPtr]!, {%[wr1], %[wr2], %[wr3], %[wr4]}\n\t"
                        "cmp %[numWords], #1\n\t"
                        "ldmgtia %[inWordPtr]!, {%[wr1], %[wr2]}\n\t"
                        "subgt %[numWords], %[numWords], #2\n\t"
                        "stmgtia %[outWordPtr]!, {%[wr1], %[wr2]}\n\t"
                        "cmp %[numWords], #1\n\t"
                        "ldreq %[wr1], [%[inWordPtr]], #4\n\t"
                        "streq %[wr1], [%[outWordPtr]], #4\n\t"
                        :
                        [outWordPtr] "+l" (frameBuffer16),
                        [inWordPtr] "+l" (inputBuffer32),
                        [numWords] "+l" (numWords),
                        [wr1] "+l" (WR1),
                        [wr2] "+l" (WR2),
                        [wr3] "+l" (WR3),
                        [wr4] "+l" (WR4),
                        [wr5] "+l" (WR5),
                        [wr6] "+l" (WR6),
                        [wr7] "+l" (WR7),
                        [wr8] "+l" (WR8)
                        );
#else // USE_INLINE_ARM_ASM
  memcpy(frameBuffer16, inputBuffer32, numWords << 2);
  frameBuffer16 += numWords << 1;
  inputBuffer32 += numWords;
#endif // USE_INLINE_ARM_ASM
    
#ifdef EXTRA_CHECKS
  MAXVID_ASSERT(UINTMOD(frameBuffer16, sizeof(uint32_t)) == 0, "frameBuffer16 word alignment");
  MAXVID_ASSERT(UINTMOD(inputBuffer32, sizeof(uint32_t)) == 0, "inputBuffer32 word alignment");
  
  MAXVID_ASSERT(frameBuffer16 == expectedCOPYBigPost8FrameBuffer16, "COPY post word8 framebuffer");
  MAXVID_ASSERT(inputBuffer32 == expectedCOPYBigPost8InputBuffer32, "COPY input post word8");
#endif
  
#ifdef EXTRA_CHECKS
  MAXVID_ASSERT(numPixels == numPixelsSaved, "numPixelsSaved");
  if (numPixels & 0x1) {
    MAXVID_ASSERT(((frameBuffer16 - inframeBuffer16) < frameBufferSize), "COPY already past end of framebuffer");
  }
#endif // EXTRA_CHECKS
  
  // Write 1 more pixel in the case where copyNumPixels is odd
  
#if defined(USE_INLINE_ARM_ASM)
  // WTF? GCC bug is emitting a load but it misses the incr in debug mode.
  // This looks like a compiler bug in ARM mode that should be reported.
  
  __asm__ __volatile__ (
                        // if (numPixels & 0x1)
                        "tst %[numPixels], #0x1\n\t"
                        // WR4 = *inputBuffer32++;
                        "ldrne %[TMP], [%[inputBuffer32]], #4\n\t"
                        // *frameBuffer16++ = WR4;
                        "strneh %[TMP], [%[frameBuffer16]], #2\n\t"
                        :
                        [numPixels] "+l" (numPixels),
                        [frameBuffer16] "+l" (frameBuffer16),
                        [TMP] "+l" (WR4),
                        [inputBuffer32] "+l" (inputBuffer32)
                        );
#else
  if (numPixels & 0x1) {
    WR4 = *inputBuffer32++;
    *frameBuffer16++ = WR4;
  }
#endif // USE_INLINE_ARM_ASM
  
#ifdef EXTRA_CHECKS
  if (numPixels & 0x1) {
    MAXVID_ASSERT((WR4 >> 16) == 0, "high half must be zero");
  }
#endif // EXTRA_CHECKS
  
#ifdef EXTRA_CHECKS
  MAXVID_ASSERT(frameBuffer16 == expectedCOPYBigFinalFrameBuffer16, "expectedCOPYFinalFrameBuffer16");
  MAXVID_ASSERT(inputBuffer32 == expectedCOPYBigFinalOutInputBuffer32, "expectedCOPYFinalOutInputBuffer32");
#endif // EXTRA_CHECKS
  
  // Load inW1 again. The final half word read above needs to be completed before
  // the next word can be read, so this read could stall for a couple of cycles.
  
#ifdef EXTRA_CHECKS
  MAXVID_ASSERT(inputBuffer32 != NULL, "inputBuffer32");
  MAXVID_ASSERT(UINTMOD(inputBuffer32, sizeof(uint32_t)) == 0, "inputBuffer32 alignment");
  // inputBuffer32 should be 1 word ahead of the previous read (ignored in COPY case)
  //MAXVID_ASSERT(inputBuffer32 == (prevInputBuffer32 + 1), "inputBuffer32 != previous");
  prevInputBuffer32 = inputBuffer32;
  MAXVID_ASSERT(inW1 == inW1Saved, "inW1Saved");
#endif
  
#if defined(USE_INLINE_ARM_ASM)
  __asm__ __volatile__ (
                        // inW1 = *inputBuffer32++
                        "ldr %[inW1], [%[inputBuffer32]], #4\n\t"
                        :
                        [inW1] "+l" (inW1),
                        [inputBuffer32] "+l" (inputBuffer32)
                        );
#else
  inW1 = *inputBuffer32++;
#endif // USE_INLINE_ARM_ASM
  
#ifdef EXTRA_CHECKS
  inW1Saved = inW1;
  MAXVID_ASSERT(inputBuffer32 == (prevInputBuffer32 + 1), "inputBuffer32 != previous");
#endif
  
  // Regen constants in registers
  
#if defined(USE_INLINE_ARM_ASM)
  __asm__ __volatile__ (
                        "mov %[constReg3], #2\n\t"
                        "mvn %[constReg2], #0xC000\n\t"
                        "orr %[constReg3], %[constReg3], %[constReg1], lsr #1\n\t"
                        :
                        [constReg1] "+l" (copyOnePixelHighHalfWordConstRegister),
                        [constReg2] "+l" (extractNumPixelsHighHalfWordConstRegister),
                        [constReg3] "+l" (dupTwoPixelsHighHalfWordConstRegister)
                        );
  
#ifdef EXTRA_CHECKS
  MAXVID_ASSERT(copyOnePixelHighHalfWordConstRegister == copyOnePixelHighHalfWord, "copyOnePixelHighHalfWordConstRegister");
  MAXVID_ASSERT(dupTwoPixelsHighHalfWordConstRegister == dupTwoPixelsHighHalfWord, "dupTwoPixelsHighHalfWordConstRegister");
  MAXVID_ASSERT(extractNumPixelsHighHalfWordConstRegister == ((0xFFFF << 16) | extractNumPixelsHighHalfWord), "extractNumPixelsHighHalfConstRegister");
#endif // EXTRA_CHECKS
#endif // USE_INLINE_ARM_ASM
  
#if defined(USE_INLINE_ARM_ASM)
  __asm__ __volatile__ (
                        "@ goto DECODE_16BPP\n\t"
                        :
                        );
#endif // USE_INLINE_ARM_ASM
  
  goto DECODE_16BPP;
  
DUPBIG_16BPP:
  // This block is just here to work around what appears to be a compiler bug related to a label.
  {
  }
  
#ifdef USE_INLINE_ARM_ASM
  __asm__ __volatile__ (
                        "@ DUPBIG_16BPP\n\t"
                        );
#endif // USE_INLINE_ARM_ASM
  
  // DUPBIG_16BPP is jumped to when there are more than 6 words (12 pixels) in a DUP operation.
  // The optimal implementation is filling 8 words at a time. Note that the framebuffer
  // alignment logic has already been run at this point, and that DUP2 was inlined.
  
#ifdef EXTRA_CHECKS
  MAXVID_ASSERT(numPixels == numPixelsSaved, "numPixelsSaved");
  MAXVID_ASSERT(numPixels != 0, "numPixels != 0");
  MAXVID_ASSERT(numPixels != 1, "numPixels != 1");
  MAXVID_ASSERT(numPixels > 2, "numPixels > 2");
  MAXVID_ASSERT(numPixels > 13, "numPixels");
#endif
  
#ifdef EXTRA_CHECKS
  MAXVID_ASSERT(inputBuffer32 != NULL, "inputBuffer32");
  MAXVID_ASSERT(UINTMOD(inputBuffer32, sizeof(uint32_t)) == 0, "inputBuffer32 alignment");
  MAXVID_ASSERT(frameBuffer16 != NULL, "frameBuffer16");
  MAXVID_ASSERT(UINTMOD(frameBuffer16, sizeof(uint32_t)) == 0, "frameBuffer16 alignment");
  MAXVID_ASSERT((((frameBuffer16 + numPixels - 1) - inframeBuffer16) < frameBufferSize), "MV16_CODE_COPY past end of framebuffer");
#endif
  
#ifdef EXTRA_CHECKS
  MAXVID_ASSERT(numPixels == numPixelsSaved, "numPixelsSaved");
  MAXVID_ASSERT(opCode == opCodeSaved, "opCodeSaved");
  
  MAXVID_ASSERT(frameBuffer16 != NULL, "frameBuffer16");
  MAXVID_ASSERT(UINTMOD(frameBuffer16, sizeof(uint32_t)) == 0, "frameBuffer16 alignment");
#endif // EXTRA_CHECKS
  
#ifdef EXTRA_CHECKS
  numWordsSaved = numWords;
  MAXVID_ASSERT(numWordsSaved == (numPixels >> 1), "numWordsSaved");
  MAXVID_ASSERT(numPixels > numWords, "numPixels > numPixels");
  // numPixels is a 14 bit number, so numWords can't be larger than 0x3FFF / 2
  MAXVID_ASSERT(numWords <= (0x3FFF >> 1), "numWords");
  
  MAXVID_ASSERT(numWords > 6, "numWords");
#endif
  
#ifdef EXTRA_CHECKS
  MAXVID_ASSERT(inW1 == inW1Saved, "inW1Saved");
#endif // EXTRA_CHECKS
  
#ifdef EXTRA_CHECKS
  MAXVID_ASSERT(frameBuffer16 != NULL, "frameBuffer16");
  MAXVID_ASSERT(UINTMOD(frameBuffer16, sizeof(uint32_t)) == 0, "frameBuffer16 alignment");
  
  MAXVID_ASSERT(numPixels == numPixelsSaved, "numPixelsSaved");
  MAXVID_ASSERT(numWords == numWordsSaved, "numWordsSaved");
  
  MAXVID_ASSERT(pixel32Alias == pixel32Saved, "pixel32Saved");
  
  uint16_t *expectedDUPBigPost8FrameBuffer16 = frameBuffer16;
  expectedDUPBigPost8FrameBuffer16 += (numWords * 2);
  
  uint16_t *expectedDUPBigFinalFrameBuffer16 = frameBuffer16 + numPixels;
  
  MAXVID_ASSERT((expectedDUPBigFinalFrameBuffer16 == expectedDUPBigPost8FrameBuffer16) || 
                (expectedDUPBigFinalFrameBuffer16 == expectedDUPBigPost8FrameBuffer16+1), "expected pointers");
  
  MAXVID_ASSERT(numPixels == numPixelsSaved, "numPixelsSaved");
  MAXVID_ASSERT(numWords == numWordsSaved, "numWordsSaved");
  
  MAXVID_ASSERT(numPixels == numPixelsSaved, "numPixelsSaved");
  MAXVID_ASSERT(numWords == numWordsSaved, "numWordsSaved");
#endif
  
// START align64 block
  
  // Earlier code has already aligned the output pointer to 32bits, now align to 64bits
  // so that writing 8 words starts out already aligned.
  
#ifdef EXTRA_CHECKS
  MAXVID_ASSERT(((frameBuffer16 - inframeBuffer16) < frameBufferSize), "dword align: already past end of framebuffer");
  MAXVID_ASSERT(numWords >= 7, "dword align: numWords");
#endif // EXTRA_CHECKS
  
#if defined(USE_INLINE_ARM_ASM)
  __asm__ __volatile__ (
                        // if (UINTMOD(frameBuffer16, sizeof(uint64_t)) != 0)
                        "tst %[frameBuffer16], #7\n\t"
                        // schedule unconditional init of wr2 here!
                        "mov %[wr2], %[wr1]\n\t"
                        // *((uint32_t*)frameBuffer16) = WR1; (also adds 4 bytes to ptr)
                        "strne %[TMP], [%[frameBuffer16]], #4\n\t"
                        // numWords -= 1;
                        "subne %[numWords], %[numWords], #1\n\t"
                        :
                        [numWords] "+l" (numWords),
                        [TMP] "+l" (pixel32Alias),
                        [inputBuffer32] "+l" (inputBuffer32),
                        [frameBuffer16] "+l" (frameBuffer16),
                        [wr1] "+l" (WR1),
                        [wr2] "+l" (WR2),
                        [wr3] "+l" (WR3)
                        );
#else // USE_INLINE_ARM_ASM
  
  if (UINTMOD(frameBuffer16, sizeof(uint64_t)) != 0) {
    // Framebuffer is word aligned, read/write a word (2 pixels) to dword align.
    
    *((uint32_t*)frameBuffer16) = pixel32Alias;
    frameBuffer16 += 2;
    numWords -= 1;
  }
  
#endif //USE_INLINE_ARM_ASM

#ifdef EXTRA_CHECKS
  // The min numwords was 7, now could be >= 6
  MAXVID_ASSERT(numWords >= 6, "dword align: numWords");
  MAXVID_ASSERT(frameBuffer16 != NULL, "frameBuffer16");
  MAXVID_ASSERT(UINTMOD(frameBuffer16, sizeof(uint64_t)) == 0, "frameBuffer16 dword alignment");
#endif // EXTRA_CHECKS
  
// END align64 block
  
  // Dup big 8 word loop
  
#if defined(USE_INLINE_ARM_ASM)
  __asm__ __volatile__ (
                        // Note that wr2 was initialized unconditionally above
                        "mov %[wr3], %[wr1]\n\t"
                        "mov %[wr4], %[wr1]\n\t"
                        
                        // In the case where the 8 word loop will not be executed, skip forward
                        // over the next 8 instructions. This provides a nice speed boost on A8
                        // processors and is a little bit faster on A9 too.
                        "cmp %[numWords], #8\n\t"
                        "blt 2f\n\t"

                        "mov %[wr5], %[wr1]\n\t"
                        "mov %[wr6], %[wr1]\n\t"
                        "mov %[wr7], %[wr1]\n\t"
                        "mov %[wr8], %[wr1]\n\t"
                        "1:\n\t"
                        "cmp %[numWords], #15\n\t"
                        "stm %[frameBuffer16]!, {%[wr1], %[wr2], %[wr3], %[wr4], %[wr5], %[wr6], %[wr7], %[wr8]}\n\t"
                        "sub %[numWords], %[numWords], #8\n\t"
                        "bgt 1b\n\t"
                        "2:\n\t"

                        // handle 7 words or fewer
                        "cmp %[numWords], #3\n\t"
                        // constant init
                        "subgt %[numWords], %[numWords], #4\n\t"
                        "stmgt %[frameBuffer16]!, {%[wr1], %[wr2], %[wr3], %[wr4]}\n\t"
                        // constant init
                        "cmp %[numWords], #2\n\t"
                        // constant init
                        "stmgt %[frameBuffer16], {%[wr1], %[wr2], %[wr3]}\n\t"
                        "stmeq %[frameBuffer16], {%[wr1], %[wr2]}\n\t"
                        // frameBuffer16 += (numWords << 1)
                        "add %[frameBuffer16], %[frameBuffer16], %[numWords], lsl #2\n\t"
                        "cmp %[numWords], #1\n\t"
                        // constant init
                        "streq %[wr1], [%[frameBuffer16], #-4]\n\t"
                        :
                        [frameBuffer16] "+l" (frameBuffer16),
                        [numWords] "+l" (numWords),
                        [wr1] "+l" (WR1),
                        [wr2] "+l" (WR2),
                        [wr3] "+l" (WR3),
                        [wr4] "+l" (WR4),
                        [wr5] "+l" (WR5),
                        [wr6] "+l" (WR6),
                        [wr7] "+l" (WR7),
                        [wr8] "+l" (WR8)
                        );
#else // USE_INLINE_ARM_ASM
  {
    uint32_t inWordPtr = pixel32Alias;
    memset_pattern4(frameBuffer16, &inWordPtr, numWords << 2);
    frameBuffer16 += numWords << 1;
#ifdef EXTRA_CHECKS
    numWords = 0;
#endif
  }
#endif // USE_INLINE_ARM_ASM
  
#ifdef EXTRA_CHECKS
  MAXVID_ASSERT(frameBuffer16 != NULL, "frameBuffer16");
  MAXVID_ASSERT(UINTMOD(frameBuffer16, sizeof(uint32_t)) == 0, "frameBuffer16 word alignment");
  
  MAXVID_ASSERT(frameBuffer16 == expectedDUPBigPost8FrameBuffer16, "frameBuffer16 post8");
  MAXVID_ASSERT(numWords >= 0 && numWords <= 3, "numWords");
#endif
  
  // Emit trailing single pixel, if needed
  
#if defined(USE_INLINE_ARM_ASM)
  
#ifdef EXTRA_CHECKS
  MAXVID_ASSERT(numPixels == numPixelsSaved, "numPixelsSaved");
  
  if (numPixels & 0x1) {
    MAXVID_ASSERT(((frameBuffer16 - inframeBuffer16) < frameBufferSize), "DUP already past end of framebuffer");
    MAXVID_ASSERT(pixel32Alias == pixel32Saved, "pixel32Saved");
  }
#endif // EXTRA_CHECKS
  __asm__ __volatile__ (
                        "tst %[numPixels], #1\n\t"
                        "strneh %[pixel32], [%[outPtr]], #2\n\t"
                        :
                        [outPtr] "+l" (frameBuffer16),
                        [numPixels] "+l" (numPixels),
                        [pixel32] "+l" (pixel32Alias)
                        );
#else // USE_INLINE_ARM_ASM
  // By default, gcc would emit a conditional branch backwards,
  // then the half word assign followed by an unconditional
  // branch backwards. Putting the NOP asm in makes gcc
  // emit the one conditional instruction folowed by an
  // unconditional branch backwards.
  if (numPixels & 0x1) {
#ifdef EXTRA_CHECKS
    MAXVID_ASSERT(((frameBuffer16 - inframeBuffer16) < frameBufferSize), "DUP already past end of framebuffer");
    MAXVID_ASSERT(pixel32Alias == pixel32Saved, "pixel32Saved");
#endif // EXTRA_CHECKS
    *frameBuffer16++ = pixel32Alias;
  }
  ASM_NOP
#endif // USE_INLINE_ARM_ASM
  
#ifdef EXTRA_CHECKS
  MAXVID_ASSERT(frameBuffer16 != NULL, "frameBuffer16");
  MAXVID_ASSERT(UINTMOD(frameBuffer16, sizeof(uint16_t)) == 0, "frameBuffer16 alignment");
  
  MAXVID_ASSERT(frameBuffer16 == expectedDUPBigFinalFrameBuffer16, "frameBuffer16 final");
#endif
  
#undef pixel32Alias
  
  // inW1 was blown away by the word8 loop, read it again, without updating the pointer
  inW1 = *(inputBuffer32 - 1);
  
#ifdef EXTRA_CHECKS
  MAXVID_ASSERT(inW1 == inW1Saved, "inW1Saved");
#endif // EXTRA_CHECKS
  
  // Regen constants in registers
  
#if defined(USE_INLINE_ARM_ASM)
  __asm__ __volatile__ (
                        "mov %[constReg3], #2\n\t"
                        "mvn %[constReg2], #0xC000\n\t"
                        "orr %[constReg3], %[constReg3], %[constReg1], lsr #1\n\t"
                        :
                        [constReg1] "+l" (copyOnePixelHighHalfWordConstRegister),
                        [constReg2] "+l" (extractNumPixelsHighHalfWordConstRegister),
                        [constReg3] "+l" (dupTwoPixelsHighHalfWordConstRegister)
                        );
  
#ifdef EXTRA_CHECKS
  MAXVID_ASSERT(copyOnePixelHighHalfWordConstRegister == copyOnePixelHighHalfWord, "copyOnePixelHighHalfWordConstRegister");
  MAXVID_ASSERT(dupTwoPixelsHighHalfWordConstRegister == dupTwoPixelsHighHalfWord, "dupTwoPixelsHighHalfWordConstRegister");
  MAXVID_ASSERT(extractNumPixelsHighHalfWordConstRegister == ((0xFFFF << 16) | extractNumPixelsHighHalfWord), "extractNumPixelsHighHalfConstRegister");
#endif // EXTRA_CHECKS
#endif // USE_INLINE_ARM_ASM
  
#undef pixel32Alias
  
#if defined(USE_INLINE_ARM_ASM)
  __asm__ __volatile__ (
                        "@ goto DECODE_16BPP\n\t"
                        :
                        );
#endif // USE_INLINE_ARM_ASM
  
  goto DECODE_16BPP;
  
DONE_16BPP:
#if defined(USE_INLINE_ARM_ASM)
  __asm__ __volatile__ (
                        "@ DONE_16BPP\n\t"
                        );
#endif //  USE_INLINE_ARM_ASM
  
#if defined(EXTRA_CHECKS)
  MAXVID_ASSERT(frameBuffer16 == frameBuffer16Max, "must be at end of framebuffer");
#endif // EXTRA_CHECKS
  
  return 0;
}

// maxvid_decode_c4_sample32
// Decode input RLE, input data is already validated.
// This method decodes 24 or 32 bit pixels.

__attribute__ ((noinline))
uint32_t
FUNCTION_NAME(MODULE_PREFIX, decode_c4_sample32) (
                                                  uint32_t * restrict frameBuffer32Arg,
                                                  const uint32_t * restrict inputBuffer32Arg,
                                                  const uint32_t inputBuffer32NumWords,
                                                  const uint32_t frameBufferSize)
{
  // Usable registers:
  // r0 -> r3 (scratch, compiler will write over these registers at sneaky times)
  // r4 -> r10 (r7 in thumb mode is the frame pointer, gdb uses r7 in arm mode)
  // r11 is the frame pointer in ARM mode
  // r12 tmp register
  // r13 stack pointer (only usable if no stack use in function)
  // r14 link register (gcc runs out of registers if you use this one)
  // r15 is the program counter (don't use)
  
#define copyOnePixelWord ((((uint32_t)0x1) << 2) | ((uint32_t)COPY))
#define dupTwoPixelsWord ((((uint32_t)0x2) << 2) | ((uint32_t)DUP))
#define opCodeMask 0x3
#define oneConstWord 0x1

#if defined(EXTRA_CHECKS)
  // Double check that half word constants are not just totally wrong
  {
    //uint32_t dupCode = maxvid32_internal_code(DUP, 2, 0);
    uint32_t expectedDup2Word = 0x900;
    uint32_t expectedDup2HighPart = (expectedDup2Word >> 8);
    
    if (dupTwoPixelsWord != expectedDup2HighPart) {
      MAXVID_ASSERT(dupTwoPixelsWord == expectedDup2HighPart, "dupTwoPixelsWord");
    }
  }
  // Double check that half word constants are not just totally wrong
  {
    //uint32_t copyCode = maxvid32_internal_code(COPY, 1, 0);
    uint32_t expectedCopy1Word = 0x600;
    uint32_t expectedCopy1HighPart = (expectedCopy1Word >> 8);

    if (copyOnePixelWord != expectedCopy1HighPart) {
      MAXVID_ASSERT(copyOnePixelWord == expectedCopy1HighPart, "copyOnePixelWord");
    }
  }
#endif
  
#if 1 && defined(USE_INLINE_ARM_ASM)
  register uint32_t * restrict inputBuffer32 __asm__ ("r9") = (uint32_t * restrict) inputBuffer32Arg;
  register uint32_t * restrict frameBuffer32 __asm__ ("r10") = frameBuffer32Arg;
  
#ifdef EXTRA_CHECKS
  MAXVID_ASSERT(inputBuffer32 == inputBuffer32Arg, "inputBuffer32Arg");
  MAXVID_ASSERT(frameBuffer32 == frameBuffer32Arg, "frameBuffer32Arg");
#endif
  
  // This register holds the input word, it is clobbered by the 8 word loop
  register uint32_t inW1 __asm__ ("r8"); // AKA WR8
  // This register holds the input pixel value, it is not clobbered by the word8 loop.
  register uint32_t inW2 __asm__ ("r14");
  
  // This register is used to hold the opCode, note that it is the same register as numPixels
  register uint32_t opCode __asm__ ("r12");
  
  // This register holds the numPixels, same as numWords. This register is not clobbered by the word8 loop.
  register uint32_t numPixels __asm__ ("r12");
  
  // This register hold the "skip after" value, it is not clobbered by the word 8 loop.
#ifdef EXTRA_CHECKS
  // Frame and stack pointers needed in debug mode
  uint32_t skipAfter = 0;
#else
  register uint32_t skipAfter __asm__ ("r11") = 0;
#endif // EXTRA_CHECKS
  
#ifdef EXTRA_CHECKS
  // Can't assume that the compiler will not blow away the first 4 registers in debug mode.
  register uint32_t oneConstRegister;
#else
  register uint32_t oneConstRegister __asm__ ("r3"); // AKA WR4
#endif // EXTRA_CHECKS
  
  // These alias vars are used to hold a constant value for use in the DECODE block. Clobbered by the word8 loop.
  register uint32_t copyOneConstRegister __asm__ ("r4"); // AKA WR5
  register uint32_t dupTwoConstRegister __asm__ ("r5"); // AKA WR6
  register uint32_t opCodeMaskConstRegister __asm__ ("r6"); // AKA WR7
  
  // Explicitly define the registers outside the r0 -> r3 range
  
  // These registers are used with ldm and stm instructions.
  // During a write loop, these values could write over other
  // values mapped to the same registers. Note that we skip r7
  // since gdb uses it for debugging. Also be aware that gcc
  // could secretly write over the value in r0 to r3 in
  // debug mode.
  
  register uint32_t WR1 __asm__ ("r0");
  register uint32_t WR2 __asm__ ("r1");
  register uint32_t WR3 __asm__ ("r2");
  register uint32_t WR4 __asm__ ("r3");
  register uint32_t WR5 __asm__ ("r4");
  register uint32_t WR6 __asm__ ("r5");
  register uint32_t WR7 __asm__ ("r6");
  register uint32_t WR8 __asm__ ("r8");
  
  // gcc is buggy when it comes to initializing register variables. Explicitly initialize the
  // registers with inline ASM. This is required to avoid problems with the optimizer removing
  // init code because it incorrectly thinks assignments are aliases.
  
  __asm__ __volatile__ (
                        "mov %[inW1], #0\n\t"
                        "mov %[inW2], #0\n\t"
                        :
                        [inW1] "+l" (inW1),
                        [inW2] "+l" (inW2)
                        );
#ifdef EXTRA_CHECKS
  MAXVID_ASSERT(inW1 == 0, "inW1");
  MAXVID_ASSERT(inW2 == 0, "inW2");
#endif
  
#else // USE_INLINE_ARM_ASM
  register uint32_t * restrict inputBuffer32 = (uint32_t * restrict) inputBuffer32Arg;
  register uint32_t * restrict frameBuffer32 = frameBuffer32Arg;
  register uint32_t inW1 = 0;
  register uint32_t inW2 = 0;
  uint32_t opCode;
  register uint32_t numPixels;
  register uint32_t skipAfter = 0;
  register uint32_t WR1;
  register uint32_t WR2;
  register uint32_t WR3;
  //register uint32_t WR4;
  register uint32_t WR5;
  uint32_t oneConstRegister = 1;
  if ((0)) { oneConstRegister += 0; } // silence warning
#endif // USE_INLINE_ARM_ASM
  
#ifdef EXTRA_CHECKS
  
  const int pagesize = getpagesize();
#if __LP64__
  MAXVID_ASSERT((MV_PAGESIZE % pagesize) == 0, "pagesize");
#else
  MAXVID_ASSERT(pagesize == MV_PAGESIZE/4, "pagesize");
#endif // __LP64__
  
  MAXVID_ASSERT(inputBuffer32 != NULL, "inputBuffer32");
  // The input buffer must be word aligned
  MAXVID_ASSERT(UINTMOD(inputBuffer32, sizeof(uint32_t)) == 0, "inputBuffer32 initial alignment");
  MAXVID_ASSERT(frameBuffer32 != NULL, "frameBuffer32");
  // The framebuffer is always word aligned
  MAXVID_ASSERT(UINTMOD(frameBuffer32, sizeof(uint32_t)) == 0, "frameBuffer32 initial alignment");
  // In addition, the framebuffer must begin on a page boundry
  MAXVID_ASSERT(UINTMOD(frameBuffer32, pagesize) == 0, "frameBuffer32 initial page alignment");
  MAXVID_ASSERT(frameBufferSize > 0, "frameBufferSize");
  uint32_t * restrict inframeBuffer32 = frameBuffer32;
  uint32_t * restrict frameBuffer32Max = frameBuffer32 + frameBufferSize;
  MAXVID_ASSERT(frameBuffer32Max == (frameBuffer32 + frameBufferSize), "frameBuffer32Max");
  uint32_t * restrict inInputBuffer32 = (uint32_t *)inputBuffer32;
  uint32_t * restrict inputBuffer32Max = inInputBuffer32 + inputBuffer32NumWords;
  MAXVID_ASSERT(inputBuffer32NumWords >= 2, "inputBuffer32NumWords >= 2");
  // inputBuffer32 - inInputBuffer32 gives the input word offset
  MAXVID_ASSERT(inInputBuffer32 != NULL, "inInputBuffer32");
  // Init to phony value
  uint32_t * restrict prevInputBuffer32 = inInputBuffer32 - 2;
  
  // Verify that the DONE code appears at the end of the input, followed by a zero word.
  MAXVID_ASSERT(*(inputBuffer32Max - 2) == (DONE << 8), "DONE");
  MAXVID_ASSERT(*(inputBuffer32Max - 1) == 0, "DONE zero");
  
  // These stack values save the expected contents of registers on the stack, to double check that
  // the values were not between the time they were set and when they were used.
  uint32_t opCodeSaved;
  uint32_t numPixelsSaved;
  uint32_t inW1Saved;
  uint32_t inW2Saved;
  uint32_t skipAfterSaved = 0;
  uint32_t WR1Saved;
#endif
  
#ifdef EXTRA_CHECKS
  MAXVID_ASSERT(inputBuffer32 != NULL, "inputBuffer32");
  MAXVID_ASSERT(UINTMOD(inputBuffer32, sizeof(uint32_t)) == 0, "inputBuffer32 alignment");
  // inputBuffer32 should be 2 words ahead of the previous read (ignored in COPY case)
  MAXVID_ASSERT(inputBuffer32 == (prevInputBuffer32 + 2), "inputBuffer32 != previous");
  prevInputBuffer32 = inputBuffer32;
#endif
  
#ifdef EXTRA_CHECKS
  MAXVID_ASSERT(inputBuffer32 < inputBuffer32Max, "inputBuffer32Max");
  MAXVID_ASSERT((inputBuffer32 + 1) < inputBuffer32Max, "inputBuffer32Max");
#endif
  
#if defined(USE_INLINE_ARM_ASM)
  __asm__ __volatile__ (
                        // inW1 = *inputBuffer32++
                        // inW2 = *inputBuffer32++
                        "ldmia %[inputBuffer32]!, {%[inW1], %[inW2]}\n\t"
                        :
                        [inW1] "+l" (inW1),
                        [inW2] "+l" (inW2),
                        [inputBuffer32] "+l" (inputBuffer32)
                        );
#else
  inW1 = *inputBuffer32++;
  inW2 = *inputBuffer32++;
#endif // USE_INLINE_ARM_ASM
  
#ifdef EXTRA_CHECKS
  inW1Saved = inW1;
  inW2Saved = inW2;
  MAXVID_ASSERT(inputBuffer32 == (prevInputBuffer32 + 2), "inputBuffer32 != previous");
#endif
  
  // Init constants in registers
  
#if defined(USE_INLINE_ARM_ASM)
  __asm__ __volatile__ (
                        "mov %[oneReg], %[oneConst]\n\t"
                        "mov %[copyOneReg], %[copyOneConst]\n\t"
                        "mov %[dupTwoReg], %[dupTwoConst]\n\t"
                        "mov %[opCodeMaskReg], %[opCodeMaskConst]\n\t"
                        :
                        [oneReg] "+l" (oneConstRegister),
                        [copyOneReg] "+l" (copyOneConstRegister),
                        [dupTwoReg] "+l" (dupTwoConstRegister),
                        [opCodeMaskReg] "+l" (opCodeMaskConstRegister)
                        :
                        [oneConst] "i" (oneConstWord),
                        [copyOneConst] "i" (copyOnePixelWord),
                        [dupTwoConst] "i" (dupTwoPixelsWord),
                        [opCodeMaskConst] "i" (opCodeMask)
                        );
  
#ifdef EXTRA_CHECKS
  MAXVID_ASSERT(oneConstRegister == oneConstWord, "oneConstRegister");
  MAXVID_ASSERT(copyOneConstRegister == copyOnePixelWord, "copyOneConstRegister");
  MAXVID_ASSERT(dupTwoConstRegister == dupTwoPixelsWord, "dupTwoConstRegister");
  MAXVID_ASSERT(opCodeMaskConstRegister == opCodeMask, "opCodeMaskConstRegister");
#endif // EXTRA_CHECKS
#endif // USE_INLINE_ARM_ASM
  
#if defined(USE_INLINE_ARM_ASM)
  __asm__ __volatile__ (
                        "@ goto DECODE_32BPP\n\t"
                        :
                        );
#endif // USE_INLINE_ARM_ASM
  
  goto DECODE_32BPP;
  
DUP_32BPP:
  // This block is just here to work around what appears to be a compiler bug related to a label.
  {
  }
  
#ifdef USE_INLINE_ARM_ASM
  __asm__ __volatile__ (
                        "@ DUP\n\t"
                        );
#endif // USE_INLINE_ARM_ASM
  
#if defined(USE_INLINE_ARM_ASM)
  // Set numPixels in DUP case, it was defered from DECODE_32BPP logic
#ifdef EXTRA_CHECKS
  MAXVID_ASSERT(inW1 == inW1Saved, "inW1Saved");
#endif
  __asm__ __volatile__ (
                        "mov %[numPixels], %[inW1], lsr #10\n\t"
                        :
                        [numPixels] "+l" (numPixels),
                        [inW1] "+l" (inW1)
                        );
#ifdef EXTRA_CHECKS
  numPixelsSaved = numPixels;
#endif // EXTRA_CHECKS
#endif // USE_INLINE_ARM_ASM
  
#ifdef EXTRA_CHECKS
  MAXVID_ASSERT(numPixels == numPixelsSaved, "numPixelsSaved");
  
  MAXVID_ASSERT(inputBuffer32 != NULL, "inputBuffer32");
  MAXVID_ASSERT(UINTMOD(inputBuffer32, sizeof(uint32_t)) == 0, "inputBuffer32 alignment");
  MAXVID_ASSERT(frameBuffer32 != NULL, "frameBuffer32");
  MAXVID_ASSERT(UINTMOD(frameBuffer32, sizeof(uint32_t)) == 0, "frameBuffer32 alignment");
  
  MAXVID_ASSERT(((frameBuffer32 - inframeBuffer32) < frameBufferSize), "DUP already past end of framebuffer");
  MAXVID_ASSERT((((frameBuffer32 + numPixels - 1) - inframeBuffer32) < frameBufferSize), "DUP past end of framebuffer");
#endif
  
#ifdef EXTRA_CHECKS
  MAXVID_ASSERT(numPixels == numPixelsSaved, "numPixelsSaved");
  // numPixels is a 22 bit number
  MAXVID_ASSERT(numPixels >= 3, "numPixels");
  MAXVID_ASSERT(numPixels <= MV_MAX_22_BITS, "numPixels");
#endif
  
  // Copy inW2 into WR1 before reading next pair of words
  
#ifdef EXTRA_CHECKS
  MAXVID_ASSERT(inW2 == inW2Saved, "inW2Saved");
#endif // EXTRA_CHECKS
  
#if defined(USE_INLINE_ARM_ASM)
  __asm__ __volatile__ (
                        "mov %[wr1], %[inW2]\n\t"
                        :
                        [wr1] "+l" (WR1),
                        [inW2] "+l" (inW2)
                        );
#else // USE_INLINE_ARM_ASM
  WR1 = inW2;
#endif // USE_INLINE_ARM_ASM
  
#ifdef EXTRA_CHECKS
  WR1Saved = WR1;
#endif // EXTRA_CHECKS
  
  // Read next inW1 and inW2 in is with enough latency that fall through to DECODE will not be delayed
  
#ifdef EXTRA_CHECKS
  MAXVID_ASSERT(inputBuffer32 != NULL, "inputBuffer32");
  MAXVID_ASSERT(UINTMOD(inputBuffer32, sizeof(uint32_t)) == 0, "inputBuffer32 alignment");
  // inputBuffer32 should be 2 words ahead of the previous read (ignored in COPY case)
  MAXVID_ASSERT(inputBuffer32 == (prevInputBuffer32 + 2), "inputBuffer32 != previous");
  prevInputBuffer32 = inputBuffer32;
#endif // EXTRA_CHECKS
  
#ifdef EXTRA_CHECKS
  MAXVID_ASSERT(inputBuffer32 < inputBuffer32Max, "inputBuffer32Max");
  MAXVID_ASSERT((inputBuffer32 + 1) < inputBuffer32Max, "inputBuffer32Max");
#endif
  
#if defined(USE_INLINE_ARM_ASM)
  __asm__ __volatile__ (
                        // inW1 = *inputBuffer32++
                        // inW2 = *inputBuffer32++
                        "ldmia %[inputBuffer32]!, {%[inW1], %[inW2]}\n\t"
                        :
                        [inW1] "+l" (inW1),
                        [inW2] "+l" (inW2),
                        [inputBuffer32] "+l" (inputBuffer32)
                        );
#else
  inW1 = *inputBuffer32++;
  inW2 = *inputBuffer32++;
#endif // USE_INLINE_ARM_ASM
  
#ifdef EXTRA_CHECKS
  inW1Saved = inW1;
  inW2Saved = inW2;
  MAXVID_ASSERT(inputBuffer32 == (prevInputBuffer32 + 2), "inputBuffer32 != previous");
#endif
  
  // DUPBIG_32BPP : branch forward to handle the case of a large number of words to DUP.
  // The code in this path is optimized for 6 words or fewer. (12 pixels)
  
#ifdef EXTRA_CHECKS
  MAXVID_ASSERT(numPixels == numPixelsSaved, "numPixelsSaved");
  MAXVID_ASSERT(numPixels > 0, "numPixels");
#endif
  
#if defined(USE_INLINE_ARM_ASM)
  __asm__ __volatile__ (
                        "@ if (numWords > 6) goto DUPBIG_32BPP\n\t"
                        :
                        );
#endif // USE_INLINE_ARM_ASM
  
  if (numPixels > 6) {
    goto DUPBIG_32BPP;
  }
  
#if defined(USE_INLINE_ARM_ASM)
  __asm__ __volatile__ (
                        "@ DUPSMALL_32BPP\n\t"
                        );
#endif //  USE_INLINE_ARM_ASM
  
#ifdef EXTRA_CHECKS
  MAXVID_ASSERT(numPixels == numPixelsSaved, "numPixelsSaved");
  MAXVID_ASSERT(numPixels <= 6, "numPixels");
  
  MAXVID_ASSERT(frameBuffer32 != NULL, "frameBuffer32");
  MAXVID_ASSERT(UINTMOD(frameBuffer32, sizeof(uint32_t)) == 0, "frameBuffer32 alignment");
  MAXVID_ASSERT(numPixels == numPixelsSaved, "numPixelsSaved");
  
  uint32_t *expectedDUPSmallPost8FrameBuffer32 = frameBuffer32 + numPixels;
  
  MAXVID_ASSERT(numPixels == numPixelsSaved, "numPixelsSaved");
  
  // Valid numPixels (numWords) values are 3, 4, 5, 6 at this point
  
  MAXVID_ASSERT(numPixels >= 3 && numPixels <= 6, "numPixels");
  
  if (1) {
    MAXVID_ASSERT(((int)numPixels - 3) >= 0, "numPixels - 3 >= 0");
    MAXVID_ASSERT((numPixels - 3) <= 3, "numPixels - 3 <= 3");
  }
  
  MAXVID_ASSERT(WR1 == WR1Saved, "WR1Saved");
#endif

  // Note that this inline ASM code no longer matches the optimized implementation
  // which has been significantly rescheduled to optimied execution on A8 and A9
  // processors. Loading was folded into this logic, the C code was updated but
  // this ASM is no longer the optimal logic.
  
#if defined(USE_INLINE_ARM_ASM)
  __asm__ __volatile__ (
                        "mov %[wr2], %[wr1]\n\t"
                        "mov %[wr3], %[wr1]\n\t"
                        // unconditionally write 3 words
                        "stm %[frameBuffer32]!, {%[wr1], %[wr2], %[wr3]}\n\t"
                        // if (numWords > 4) then write 2 words
                        "cmp %[numWords], #4\n\t"
                        "stmgt %[frameBuffer32]!, {%[wr1], %[wr2]}\n\t"
                        // if (numWords == 4 || numWords == 6) then write 1 word
                        "tst %[numWords], #0x1\n\t"
                        "streq %[wr1], [%[frameBuffer32]], #4\n\t"
                        :
                        [frameBuffer32] "+l" (frameBuffer32),
                        [numWords] "+l" (numPixels),
                        [wr1] "+l" (WR1),
                        [wr2] "+l" (WR2),
                        [wr3] "+l" (WR3)
                        );
#else // USE_INLINE_ARM_ASM
  {
    // Valid numPixels (numWords) values are 3, 4, 5, 6 at this point
    
    // 3 = write 3
    // 4 = write 3, write 1
    // 5 = write 3, write 2,
    // 6 = write 3, write 2, write 1
    
    // Write 3 words unconditionally since all 4 cases include a write 3
    
    if (1) {
      *(frameBuffer32 + 0) = WR1;
      *(frameBuffer32 + 1) = WR1;
      *(frameBuffer32 + 2) = WR1;
    }
    
    // Write 2, when numPixels is 5, 6
    
    if (numPixels > 4) {
      *(frameBuffer32 + 3) = WR1;
      *(frameBuffer32 + 4) = WR1;
    }

    #ifdef EXTRA_CHECKS
        MAXVID_ASSERT(numPixels >=3 && numPixels <= 6, "numPixels must be in range");
    #endif
    
    frameBuffer32 += numPixels;
    
    // Write 1 word, when numPixels is 4, 6
    // Note that numPixels cannot be 0, 2
    
    if ((numPixels & 0x1) == 0) {
      *(frameBuffer32 - 1) = WR1;
    }
  }
#endif // USE_INLINE_ARM_ASM
  
#ifdef EXTRA_CHECKS
  MAXVID_ASSERT(inputBuffer32 != NULL, "inputBuffer32");
  MAXVID_ASSERT(UINTMOD(inputBuffer32, sizeof(uint32_t)) == 0, "inputBuffer32 alignment");
  MAXVID_ASSERT(frameBuffer32 != NULL, "frameBuffer32");
  MAXVID_ASSERT(UINTMOD(frameBuffer32, sizeof(uint32_t)) == 0, "frameBuffer32 alignment");
#endif
  
#ifdef EXTRA_CHECKS
  MAXVID_ASSERT(frameBuffer32 == expectedDUPSmallPost8FrameBuffer32, "frameBuffer32 post8");
//  MAXVID_ASSERT(numPixels >= 0 && numPixels <= 3, "numPixels");
#endif
  
#ifdef EXTRA_CHECKS
  MAXVID_ASSERT(((frameBuffer32 - inframeBuffer32) <= frameBufferSize), "post DUP, now past end of framebuffer");
#endif // EXTRA_CHECKS
  
#ifdef EXTRA_CHECKS
  MAXVID_ASSERT(inW1 == inW1Saved, "inW1Saved");
  MAXVID_ASSERT(inW2 == inW2Saved, "inW2Saved");
#endif // EXTRA_CHECKS
  
#if defined(USE_INLINE_ARM_ASM)
#ifdef EXTRA_CHECKS
  MAXVID_ASSERT(oneConstRegister == oneConstWord, "oneConstRegister");
  MAXVID_ASSERT(copyOneConstRegister == copyOnePixelWord, "copyOneConstRegister");
  MAXVID_ASSERT(dupTwoConstRegister == dupTwoPixelsWord, "dupTwoConstRegister");
  MAXVID_ASSERT(opCodeMaskConstRegister == opCodeMask, "opCodeMaskConstRegister");
#endif // EXTRA_CHECKS
#endif // USE_INLINE_ARM_ASM
  
#if defined(USE_INLINE_ARM_ASM)
  __asm__ __volatile__ (
                        "@ fall through to DECODE\n\t"
                        :
                        );
#endif // USE_INLINE_ARM_ASM
  
DECODE_32BPP:
#ifdef EXTRA_CHECKS
  MAXVID_ASSERT(inputBuffer32 != NULL, "inputBuffer32");
  MAXVID_ASSERT(UINTMOD(inputBuffer32, sizeof(uint32_t)) == 0, "inputBuffer32 alignment");
  MAXVID_ASSERT(frameBuffer32 != NULL, "frameBuffer32");
  MAXVID_ASSERT(UINTMOD(frameBuffer32, sizeof(uint32_t)) == 0, "frameBuffer32 alignment");
#endif
  
#ifdef USE_INLINE_ARM_ASM
  // These checks are done before the read, after the DECODE label
  
#ifdef EXTRA_CHECKS
  // inputBuffer32 should be 2 words ahead of the previous read (ignored in COPY case)
  MAXVID_ASSERT(inputBuffer32 == (prevInputBuffer32 + 2), "inputBuffer32 != previous");
  
  MAXVID_ASSERT(skipAfter == skipAfterSaved, "skipAfterSaved");
#endif

  // Note that the optimized instruction order in the generated ASM no longer matches
  // this asm block.
  
  __asm__ __volatile__ (
                        "@ DECODE_32BPP\n\t"
                        "2:\n\t"
                        // frameBuffer32 += skipAfter;
                        "add %[frameBuffer32], %[frameBuffer32], %[skipAfter], lsl #2\n\t"
                        // skipAfter = inW1 & 0xFF;
                        "and %[skipAfter], %[inW1], #0xFF\n\t"
                        
                        // if ((inW1 >> 8) == copyOnePixelWord)
                        "cmp %[copyOneReg], %[inW1], lsr #8\n\t"
                        // *frameBuffer32++ = inW2;
                        "streq %[inW2], [%[frameBuffer32]], #4\n\t"
                        // inW1 = *inputBuffer32++; inW2 = *inputBuffer32++;
                        "ldmeqia %[inputBuffer32]!, {%[inW1], %[inW2]}\n\t"
                        "beq 2b\n\t"
                        
                        // if ((inW1 >> 8) == dupTwoPixelsWord)
                        "cmp %[dupTwoReg], %[inW1], lsr #8\n\t"
                        // *frameBuffer32++ = inW2;
                        // *frameBuffer32++ = inW2;
                        "streq %[inW2], [%[frameBuffer32]], #4\n\t"
                        "streq %[inW2], [%[frameBuffer32]], #4\n\t"
                        // inW1 = *inputBuffer32++; inW2 = *inputBuffer32++;
                        "ldmeqia %[inputBuffer32]!, {%[inW1], %[inW2]}\n\t"
                        "beq 2b\n\t"
                        
                        // opCode = (inW1 >> 8) & 0x3;
                        "ands %[opCode], %[opCodeMaskReg], %[inW1], lsr #8\n\t"
                        // if (opCode == SKIP)
                        // frameBuffer32 += ((inW1 >> 8) >> 2);
                        "addeq %[frameBuffer32], %[frameBuffer32], %[inW1], lsr #8\n\t"
                        // inW1 = inW2;
                        "moveq %[inW1], %[inW2]\n\t"
                        // inW2 = *inputBuffer32++;
                        "ldreq %[inW2], [%[inputBuffer32]], #4\n\t"
                        "beq 2b\n\t"
                        :
                        [inputBuffer32] "+l" (inputBuffer32),
                        [frameBuffer32] "+l" (frameBuffer32),
                        [opCode] "+l" (opCode),
                        [inW1] "+l" (inW1),
                        [inW2] "+l" (inW2),
                        [skipAfter] "+l" (skipAfter),
                        [copyOneReg] "+l" (copyOneConstRegister),
                        [dupTwoReg] "+l" (dupTwoConstRegister),
                        [opCodeMaskReg] "+l" (opCodeMaskConstRegister)
                        );
  
#ifdef EXTRA_CHECKS
  opCodeSaved = opCode;
  inW1Saved = inW1;
  inW2Saved = inW2;
  skipAfterSaved = skipAfter;
  prevInputBuffer32 = inputBuffer32 - 2;
  MAXVID_ASSERT(inputBuffer32 == (prevInputBuffer32 + 2), "inputBuffer32 != previous");
#endif
  
#ifdef EXTRA_CHECKS
#endif // EXTRA_CHECKS
  
#ifdef EXTRA_CHECKS
  MAXVID_ASSERT(inW1 == inW1Saved, "inW1Saved");
#endif // EXTRA_CHECKS
  
#else // USE_INLINE_ARM_ASM
  
  // SKIP after (advances the framebuffer if non-zero, no-op when skipAfter is zero)
  
#ifdef EXTRA_CHECKS
  MAXVID_ASSERT(skipAfter == skipAfterSaved, "skipAfterSaved");
#endif
  
  frameBuffer32 += skipAfter;
  
  // The (num + opCode) values are contained in the upper most 24 bits. Save the
  // 24 bit value in a temp register and save the opCode. Ignore the skip 8 bit
  // value for the moment.
  
  WR2 = inW1 >> 8;
  skipAfter = inW1 & 0xFF;
  opCode = WR2 & 0x3;
  
#ifdef EXTRA_CHECKS
  opCodeSaved = opCode;
  skipAfterSaved = skipAfter;
#endif // EXTRA_CHECKS
  
  if (opCode == SKIP) {
#ifdef EXTRA_CHECKS
    MAXVID_ASSERT((inW1 & 0xFF) == 0, "SKIP after byte must be zero");
    MAXVID_ASSERT(inW1 == inW1Saved, "inW1Saved");
    MAXVID_ASSERT(inW2 == inW2Saved, "inW2Saved");
#endif // EXTRA_CHECKS
    
#ifdef EXTRA_CHECKS
    MAXVID_ASSERT(((frameBuffer32 - inframeBuffer32) < frameBufferSize), "SKIP already past end of framebuffer");
    MAXVID_ASSERT(inW1 == inW1Saved, "inW1Saved");
    MAXVID_ASSERT(inW2 == inW2Saved, "inW2Saved");
#endif // EXTRA_CHECKS
    
    // SKIP
    frameBuffer32 += (WR2 >> 2);
    
#ifdef EXTRA_CHECKS
    MAXVID_ASSERT(((frameBuffer32 - inframeBuffer32) <= frameBufferSize), "post SKIP, now past end of framebuffer");
    MAXVID_ASSERT(inW1 == inW1Saved, "inW1Saved");
    MAXVID_ASSERT(inW2 == inW2Saved, "inW2Saved");
#endif // EXTRA_CHECKS
    
    // SKIP has no word argument following it, so move previously read inW2 into inW1
    // and then read a new value for inW2 from the stream.
    
    inW1 = inW2;
    
#ifdef EXTRA_CHECKS
    MAXVID_ASSERT(inputBuffer32 != NULL, "inputBuffer32");
    MAXVID_ASSERT(UINTMOD(inputBuffer32, sizeof(uint32_t)) == 0, "inputBuffer32 alignment");
    MAXVID_ASSERT(frameBuffer32 != NULL, "frameBuffer32");
    MAXVID_ASSERT(UINTMOD(frameBuffer32, sizeof(uint32_t)) == 0, "frameBuffer32 alignment");
    // inputBuffer32 should be 2 words ahead of the previous read (ignored in COPY case)
    MAXVID_ASSERT(inputBuffer32 == (prevInputBuffer32 + 2), "inputBuffer32 != previous");
    prevInputBuffer32 += 1;
#endif
    
#ifdef EXTRA_CHECKS
    MAXVID_ASSERT(inputBuffer32 < inputBuffer32Max, "inputBuffer32Max");
#endif
    
    inW2 = *inputBuffer32++;
    
#ifdef EXTRA_CHECKS
    inW1Saved = inW1;
    inW2Saved = inW2;
    MAXVID_ASSERT(inputBuffer32 == (prevInputBuffer32 + 2), "inputBuffer32 != previous");
#endif
    
    goto DECODE_32BPP;
  }
  
  // COPY1 handled inline
  
  if (WR2 == copyOnePixelWord)
    //  if (num == 1 && opCode == COPY)
  {
    // Special case where a COPY operation operates on only one pixel.
#ifdef EXTRA_CHECKS
    MAXVID_ASSERT(((frameBuffer32 - inframeBuffer32) < frameBufferSize), "COPY1 already past end of framebuffer");
    MAXVID_ASSERT(inW1 == inW1Saved, "inW1Saved");
    MAXVID_ASSERT(inW2 == inW2Saved, "inW2Saved");
#endif // EXTRA_CHECKS
    
    *frameBuffer32++ = inW2;
    
#ifdef EXTRA_CHECKS
    MAXVID_ASSERT(((frameBuffer32 - inframeBuffer32) <= frameBufferSize), "post COPY1, now past end of framebuffer");
#endif // EXTRA_CHECKS
    
    // Read next inW1 and inW2
    
#ifdef EXTRA_CHECKS
    MAXVID_ASSERT(inputBuffer32 != NULL, "inputBuffer32");
    MAXVID_ASSERT(UINTMOD(inputBuffer32, sizeof(uint32_t)) == 0, "inputBuffer32 alignment");
    // inputBuffer32 should be 2 words ahead of the previous read (ignored in COPY case)
    MAXVID_ASSERT(inputBuffer32 == (prevInputBuffer32 + 2), "inputBuffer32 != previous");
    prevInputBuffer32 = inputBuffer32;
#endif
    
#ifdef EXTRA_CHECKS
    MAXVID_ASSERT(inputBuffer32 < inputBuffer32Max, "inputBuffer32Max");
    MAXVID_ASSERT((inputBuffer32 + 1) < inputBuffer32Max, "inputBuffer32Max");
#endif
    
    inW1 = *inputBuffer32++;
    inW2 = *inputBuffer32++;
    
#ifdef EXTRA_CHECKS
    inW1Saved = inW1;
    inW2Saved = inW2;
    MAXVID_ASSERT(inputBuffer32 == (prevInputBuffer32 + 2), "inputBuffer32 != previous");
#endif
    
    goto DECODE_32BPP;
  }
  
  // DUP2 handled inline
  
  if (WR2 == dupTwoPixelsWord)
    //  if (num == 2 && opCode == DUP)
  {
    // Special case where DUP writes 2 pixels.
#ifdef EXTRA_CHECKS
    MAXVID_ASSERT(((frameBuffer32 - inframeBuffer32) < frameBufferSize), "DUP2 already past end of framebuffer");
    MAXVID_ASSERT(inW1 == inW1Saved, "inW1Saved");
#endif // EXTRA_CHECKS
    
    // Write inW2 to framebuffer 2 times
    
    *frameBuffer32++ = inW2;
    *frameBuffer32++ = inW2;
    
#ifdef EXTRA_CHECKS
    MAXVID_ASSERT(((frameBuffer32 - inframeBuffer32) <= frameBufferSize), "post DUP2, now past end of framebuffer");
#endif // EXTRA_CHECKS
    
    // Read next inW1 and inW2
    
#ifdef EXTRA_CHECKS
    MAXVID_ASSERT(inputBuffer32 != NULL, "inputBuffer32");
    MAXVID_ASSERT(UINTMOD(inputBuffer32, sizeof(uint32_t)) == 0, "inputBuffer32 alignment");
    // inputBuffer32 should be 2 words ahead of the previous read (ignored in COPY case)
    MAXVID_ASSERT(inputBuffer32 == (prevInputBuffer32 + 2), "inputBuffer32 != previous");
    prevInputBuffer32 = inputBuffer32;
#endif
    
#ifdef EXTRA_CHECKS
    MAXVID_ASSERT(inputBuffer32 < inputBuffer32Max, "inputBuffer32Max");
    MAXVID_ASSERT((inputBuffer32 + 1) < inputBuffer32Max, "inputBuffer32Max");
#endif
    
    inW1 = *inputBuffer32++;
    inW2 = *inputBuffer32++;
    
#ifdef EXTRA_CHECKS
    inW1Saved = inW1;
    inW2Saved = inW2;
    MAXVID_ASSERT(inputBuffer32 == (prevInputBuffer32 + 2), "inputBuffer32 != previous");
#endif
    
    goto DECODE_32BPP;
  }
  
  // Extract numPixels, aka numWords
  
  numPixels = WR2 >> 2;
  
#ifdef EXTRA_CHECKS
  numPixelsSaved = numPixels;
#endif // EXTRA_CHECKS
  
#endif // USE_INLINE_ARM_ASM
  
#ifdef EXTRA_CHECKS
  MAXVID_ASSERT(inputBuffer32 != NULL, "inputBuffer32");
  MAXVID_ASSERT(UINTMOD(inputBuffer32, sizeof(uint32_t)) == 0, "inputBuffer32 alignment");
  MAXVID_ASSERT(frameBuffer32 != NULL, "frameBuffer32");
  MAXVID_ASSERT(UINTMOD(frameBuffer32, sizeof(uint32_t)) == 0, "frameBuffer32 alignment");
#endif
  
  // At this point, opCode has been parsed from inW1. If not in ASM mode, then numPixels was parsed too.
  
#ifdef EXTRA_CHECKS
  MAXVID_ASSERT(inW1 == inW1Saved, "inW1Saved");
  MAXVID_ASSERT(inW2 == inW2Saved, "inW2Saved");
#endif // USE_INLINE_ARM_ASM
  
#ifdef EXTRA_CHECKS
  MAXVID_ASSERT(inputBuffer32 != NULL, "inputBuffer32");
  MAXVID_ASSERT(UINTMOD(inputBuffer32, sizeof(uint32_t)) == 0, "inputBuffer32 alignment");
  MAXVID_ASSERT(frameBuffer32 != NULL, "frameBuffer32");
  MAXVID_ASSERT(UINTMOD(frameBuffer32, sizeof(uint32_t)) == 0, "frameBuffer32 alignment");
#endif
  
#ifdef USE_INLINE_ARM_ASM
  // GCC emits a phantom assign to "r11" when compiling the C code.
  // This weird empty asm statement keeps GCC from doing that.
  
  __asm__ __volatile__ (
                        "@ Phantom assign to opCode\n\t"
                        : \
                        [opCode] "+l" (opCode)
                        );
#endif // USE_INLINE_ARM_ASM
  
#if defined(USE_INLINE_ARM_ASM)
  __asm__ __volatile__ (
                        "@ if (opCode == DUP) goto DUP_32BPP\n\t"
                        :
                        );
#endif // USE_INLINE_ARM_ASM
  
  if (opCode == DUP) {
    // DUP
    
#ifdef EXTRA_CHECKS
    numPixels = inW1 >> (8+2);
    
    MAXVID_ASSERT(numPixels != 0, "DUP2 numPixels");
    MAXVID_ASSERT(numPixels != 1, "DUP2 numPixels");
    MAXVID_ASSERT(numPixels != 2, "DUP2 numPixels");
#endif
    
    goto DUP_32BPP;
  }
  
  // Handle DONE after COPY branch. This provides a small improvement
  // in execution time as compared to checking for DONE before COPY.
  
#ifdef EXTRA_CHECKS
  MAXVID_ASSERT(opCode == opCodeSaved, "opCodeSaved");
#endif // EXTRA_CHECKS
  
#ifdef USE_INLINE_ARM_ASM
  // GCC emits a phantom assign to "r11" when compiling the C code.
  // This weird empty asm statement keeps GCC from doing that.
  
  __asm__ __volatile__ (
                        "@ Phantom assign to opCode\n\t"
                        : \
                        [opCode] "+l" (opCode)
                        );
#endif // USE_INLINE_ARM_ASM
  
#ifdef USE_INLINE_ARM_ASM
  __asm__ __volatile__ (
                        "@ if (opCode == DONE) goto DONE_32BPP\n\t"
                        );
#endif // USE_INLINE_ARM_ASM
  
  if (opCode == DONE) {
#ifdef EXTRA_CHECKS
    numPixels = inW1 >> (8+2);
    
    MAXVID_ASSERT(numPixels == 0, "numPixels");
    MAXVID_ASSERT(inW1 == (DONE << 8), "DONE");
#endif // EXTRA_CHECKS
    
    goto DONE_32BPP;
  }
  
  // COPY operation, generic code for either big or small copy
  
#ifdef USE_INLINE_ARM_ASM
  __asm__ __volatile__ (
                        "@ COPY 32BPP\n\t"
                        );
#endif // USE_INLINE_ARM_ASM
  
  // Either a COPYBIG or COPYSMALL. In either case, inW2 contains
  // a pixel that needs to be copied to the framebuffer.
  
#ifdef EXTRA_CHECKS
  MAXVID_ASSERT(opCode == opCodeSaved, "opCodeSaved");
  
  MAXVID_ASSERT(opCode == COPY, "opCode");
  MAXVID_ASSERT(inW1 == inW1Saved, "inW1Saved");
  MAXVID_ASSERT(inW2 == inW2Saved, "inW2Saved");
  
  numPixels = inW1 >> (8+2);
  
  MAXVID_ASSERT(numPixels != 0, "COPY1 numPixels");
  MAXVID_ASSERT(numPixels != 1, "COPY1 numPixels");
  
  MAXVID_ASSERT(oneConstRegister == 1, "oneConstRegister");
#endif
  
#if defined(USE_INLINE_ARM_ASM)
  __asm__ __volatile__ (
                        // numPixels = (inW1 >> 8+2) - 1;
                        "rsb %[numPixels], %[oneConstRegister], %[inW1], lsr #10\n\t"
                        // *frameBuffer32++ = inW2;
                        "str %[inW2], [%[frameBuffer32]], #4\n\t"
                        :
                        [numPixels] "+l" (numPixels),
                        [inW1] "+l" (inW1),
                        [inW2] "+l" (inW2),
                        [frameBuffer32] "+l" (frameBuffer32),
                        [oneConstRegister] "+l" (oneConstRegister)
                        );
  
#ifdef EXTRA_CHECKS
  MAXVID_ASSERT((numPixels + 1) == (inW1 >> 10), "numPixels");
#endif
  
#else
  *frameBuffer32++ = inW2;
#ifdef EXTRA_CHECKS
  MAXVID_ASSERT(numPixels == (inW1 >> 10), "numPixels");
#endif
  numPixels--;
#endif // USE_INLINE_ARM_ASM
  
#ifdef EXTRA_CHECKS
  numPixelsSaved = numPixels;
  MAXVID_ASSERT(numPixels >= 1, "COPY numPixels");
#endif // EXTRA_CHECKS
  
  // A COPYBIG loop must has more than 7 words to write
  // A COPYSMALL loops has 7 or fewer
  
#ifdef USE_INLINE_ARM_ASM
  __asm__ __volatile__ (
                        "@ if (numWords > 7) goto COPYBIG_32BPP\n\t"
                        );
#endif // USE_INLINE_ARM_ASM
  
  if (numPixels > 7) {
    goto COPYBIG_32BPP;
  }
  
  // Note that opCode is not used after this point
  
  // COPYSMALL_32BPP
  //
  // When there are 7 or fewer words to be copied, process with COPYSMALL.
  
COPYSMALL_32BPP:
  {}
  
#if defined(USE_INLINE_ARM_ASM)
  __asm__ __volatile__ (
                        "@ COPYSMALL_32BPP\n\t"
                        );
#endif //  USE_INLINE_ARM_ASM
  
#ifdef EXTRA_CHECKS
  MAXVID_ASSERT(inputBuffer32 != NULL, "inputBuffer32");
  MAXVID_ASSERT(UINTMOD(inputBuffer32, sizeof(uint32_t)) == 0, "inputBuffer32 alignment");
  MAXVID_ASSERT(frameBuffer32 != NULL, "frameBuffer32");
  MAXVID_ASSERT(UINTMOD(frameBuffer32, sizeof(uint32_t)) == 0, "frameBuffer32 alignment");
#endif
  
#ifdef EXTRA_CHECKS
  MAXVID_ASSERT(numPixels == numPixelsSaved, "numPixelsSaved");
  MAXVID_ASSERT(((frameBuffer32 - inframeBuffer32) < frameBufferSize), "COPY already past end of framebuffer");
  MAXVID_ASSERT((((frameBuffer32 + numPixels - 1) - inframeBuffer32) < frameBufferSize), "COPY past end of framebuffer");
#endif
  
#ifdef EXTRA_CHECKS
  MAXVID_ASSERT(inputBuffer32 != NULL, "inputBuffer32");
  MAXVID_ASSERT(UINTMOD(inputBuffer32, sizeof(uint32_t)) == 0, "inputBuffer32 alignment");
  MAXVID_ASSERT(frameBuffer32 != NULL, "frameBuffer32");
  MAXVID_ASSERT(UINTMOD(frameBuffer32, sizeof(uint32_t)) == 0, "frameBuffer32 alignment");
  
  MAXVID_ASSERT(numPixels == numPixelsSaved, "numPixelsSaved");

  // Inlined COPY 1 takes care of a single pixel, but count could have been 2 and
  // then 1 of those was copied to the framebuffer by the generic copy entry block.
  // In this case, only 1 remains.
  
  MAXVID_ASSERT(numPixels >= 1, "numPixels");
  MAXVID_ASSERT(numPixels < 8, "numPixels");
  
  uint32_t *expectedCOPYSmallPost8FrameBuffer32 = ((uint32_t *) frameBuffer32) + numPixels;
  uint32_t *expectedCOPYSmallPost8InputBuffer32 = ((uint32_t *) inputBuffer32) + numPixels;
  
  MAXVID_ASSERT(expectedCOPYSmallPost8FrameBuffer32 == (((uint32_t *) frameBuffer32) + numPixels), "expected pointers");
  MAXVID_ASSERT(expectedCOPYSmallPost8InputBuffer32 == (((uint32_t *) inputBuffer32) + numPixels), "expected pointers");
  
  MAXVID_ASSERT(numPixels == numPixelsSaved, "numPixelsSaved");
  MAXVID_ASSERT(numPixels < MV_MAX_22_BITS, "numPixels");
#endif
  
#if defined(USE_INLINE_ARM_ASM)
  
  __asm__ __volatile__ (
                        "cmp %[numWords], #3\n\t"
                        "ldmgtia %[inWordPtr]!, {%[wr1], %[wr2], %[wr3], %[wr4]}\n\t"
                        "subgt %[numWords], %[numWords], #4\n\t"
                        "stmgtia %[outWordPtr]!, {%[wr1], %[wr2], %[wr3], %[wr4]}\n\t"
                        "cmp %[numWords], #1\n\t"
                        "ldmgtia %[inWordPtr]!, {%[wr1], %[wr2]}\n\t"
                        "subgt %[numWords], %[numWords], #2\n\t"
                        "stmgtia %[outWordPtr]!, {%[wr1], %[wr2]}\n\t"
                        "cmp %[numWords], #1\n\t"
                        "ldreq %[wr1], [%[inWordPtr]], #4\n\t"
                        "streq %[wr1], [%[outWordPtr]], #4\n\t"
                        :
                        [outWordPtr] "+l" (frameBuffer32),
                        [inWordPtr] "+l" (inputBuffer32),
                        [numWords] "+l" (numPixels),
                        [wr1] "+l" (WR1),
                        [wr2] "+l" (WR2),
                        [wr3] "+l" (WR3),
                        [wr4] "+l" (WR4)
                        );
  
#else // USE_INLINE_ARM_ASM
  // Valid numPixels (numWords) values are 1, 2, 3, 4, 5, 6, 7 at this point

  // Read/Write 4 words, when numPixels is 4, 5, 6, 7
  
  if (numPixels > 3) {
    *(frameBuffer32 + 0) = *(inputBuffer32 + 0);
    *(frameBuffer32 + 1) = *(inputBuffer32 + 1);
    *(frameBuffer32 + 2) = *(inputBuffer32 + 2);
    *(frameBuffer32 + 3) = *(inputBuffer32 + 3);
    frameBuffer32 += 4;
    inputBuffer32 += 4;
    numPixels -= 4;
  }
  
  // Read/Write 2 words, when numPixels is 2, 3
  
  if (numPixels > 1) {
    *(frameBuffer32 + 0) = *(inputBuffer32 + 0);
    *(frameBuffer32 + 1) = *(inputBuffer32 + 1);
  }
  
#ifdef EXTRA_CHECKS
  MAXVID_ASSERT(numPixels >=0 && numPixels <= 3, "numPixels must be in range");
#endif
  
  frameBuffer32 += numPixels;
  inputBuffer32 += numPixels;
  
  // Read/Write 1 word, when numPixels is 1, 3
  
  if (numPixels & 0x1) {
    *(frameBuffer32 - 1) = *(inputBuffer32 - 1);
  }

#endif // USE_INLINE_ARM_ASM
  
#ifdef EXTRA_CHECKS
  MAXVID_ASSERT(frameBuffer32 == expectedCOPYSmallPost8FrameBuffer32, "COPY post word8 framebuffer");
  MAXVID_ASSERT(inputBuffer32 == expectedCOPYSmallPost8InputBuffer32, "COPY input post word8");
#endif
  
#ifdef EXTRA_CHECKS
  MAXVID_ASSERT(((frameBuffer32 - inframeBuffer32) <= frameBufferSize), "post COPY, now past end of framebuffer");
#endif // EXTRA_CHECKS
  
#ifdef EXTRA_CHECKS
  MAXVID_ASSERT(inputBuffer32 != NULL, "inputBuffer32");
  MAXVID_ASSERT(UINTMOD(inputBuffer32, sizeof(uint32_t)) == 0, "inputBuffer32 alignment");
  MAXVID_ASSERT(frameBuffer32 != NULL, "frameBuffer32");
  MAXVID_ASSERT(UINTMOD(frameBuffer32, sizeof(uint32_t)) == 0, "frameBuffer32 alignment");
#endif
  
  // Read in next inW1 and inW2
  
#ifdef EXTRA_CHECKS
  // inputBuffer32 should be 2 words ahead of the previous read (ignored in COPY case)
  //MAXVID_ASSERT(inputBuffer32 == (prevInputBuffer32 + 2), "inputBuffer32 != previous");
  prevInputBuffer32 = inputBuffer32;
#endif
  
#ifdef EXTRA_CHECKS
  MAXVID_ASSERT(inputBuffer32 < inputBuffer32Max, "inputBuffer32Max");
  MAXVID_ASSERT((inputBuffer32 + 1) < inputBuffer32Max, "inputBuffer32Max");
#endif
  
#if defined(USE_INLINE_ARM_ASM)
  __asm__ __volatile__ (
                        // inW1 = *inputBuffer32++
                        // inW2 = *inputBuffer32++
                        "ldmia %[inputBuffer32]!, {%[inW1], %[inW2]}\n\t"
                        :
                        [inW1] "+l" (inW1),
                        [inW2] "+l" (inW2),
                        [inputBuffer32] "+l" (inputBuffer32)
                        );
#else
  inW1 = *inputBuffer32++;
  inW2 = *inputBuffer32++;
#endif // USE_INLINE_ARM_ASM
  
#ifdef EXTRA_CHECKS
  inW1Saved = inW1;
  inW2Saved = inW2;
  MAXVID_ASSERT(inputBuffer32 == (prevInputBuffer32 + 2), "inputBuffer32 != previous");
#endif
  
  // Regen constants in registers
  
#if defined(USE_INLINE_ARM_ASM)
  __asm__ __volatile__ (
                        "mov %[oneReg], %[oneConst]\n\t"
                        //"mov %[copyOneReg], %[copyOneConst]\n\t"
                        //"mov %[dupTwoReg], %[dupTwoConst]\n\t"
                        //"mov %[opCodeMaskReg], %[opCodeMaskConst]\n\t"
                        :
                        [oneReg] "+l" (oneConstRegister),
                        [copyOneReg] "+l" (copyOneConstRegister),
                        [dupTwoReg] "+l" (dupTwoConstRegister),
                        [opCodeMaskReg] "+l" (opCodeMaskConstRegister)
                        :
                        [oneConst] "i" (oneConstWord),
                        [copyOneConst] "i" (copyOnePixelWord),
                        [dupTwoConst] "i" (dupTwoPixelsWord),
                        [opCodeMaskConst] "i" (opCodeMask)
                        );
  
#ifdef EXTRA_CHECKS
  MAXVID_ASSERT(oneConstRegister == oneConstWord, "oneConstRegister");
  MAXVID_ASSERT(copyOneConstRegister == copyOnePixelWord, "copyOneConstRegister");
  MAXVID_ASSERT(dupTwoConstRegister == dupTwoPixelsWord, "dupTwoConstRegister");
  MAXVID_ASSERT(opCodeMaskConstRegister == opCodeMask, "opCodeMaskConstRegister");
#endif // EXTRA_CHECKS
#endif // USE_INLINE_ARM_ASM
  
#if defined(USE_INLINE_ARM_ASM)
  __asm__ __volatile__ (
                        "@ goto DECODE_32BPP\n\t"
                        :
                        );
#endif // USE_INLINE_ARM_ASM
  
  goto DECODE_32BPP;
  
COPYBIG_32BPP:
  {}
  
  // COPYBIG_32BPP
  
#if defined(USE_INLINE_ARM_ASM)
  __asm__ __volatile__ (
                        "@ COPYBIG_32BPP\n\t"
                        );
#endif //  USE_INLINE_ARM_ASM
  
#ifdef EXTRA_CHECKS
  MAXVID_ASSERT(numPixels == numPixelsSaved, "numPixelsSaved");
  MAXVID_ASSERT(numPixels <= MV_MAX_22_BITS, "numPixels");
  MAXVID_ASSERT(numPixels > 7, "numPixels");
#endif
  
#ifdef EXTRA_CHECKS
  MAXVID_ASSERT(inputBuffer32 != NULL, "inputBuffer32");
  MAXVID_ASSERT(UINTMOD(inputBuffer32, sizeof(uint32_t)) == 0, "inputBuffer32 alignment");
  MAXVID_ASSERT(frameBuffer32 != NULL, "frameBuffer32");
  MAXVID_ASSERT(UINTMOD(frameBuffer32, sizeof(uint32_t)) == 0, "frameBuffer32 alignment");
#endif
  
#ifdef EXTRA_CHECKS
  MAXVID_ASSERT(((frameBuffer32 - inframeBuffer32) < frameBufferSize), "COPY already past end of framebuffer");
  MAXVID_ASSERT((((frameBuffer32 + numPixels - 1) - inframeBuffer32) < frameBufferSize), "COPY past end of framebuffer");
#endif
  
#ifdef EXTRA_CHECKS
  MAXVID_ASSERT(inputBuffer32 != NULL, "inputBuffer32");
  MAXVID_ASSERT(UINTMOD(inputBuffer32, sizeof(uint32_t)) == 0, "inputBuffer32 alignment");
  MAXVID_ASSERT(frameBuffer32 != NULL, "frameBuffer32");
  MAXVID_ASSERT(UINTMOD(frameBuffer32, sizeof(uint32_t)) == 0, "frameBuffer32 alignment");
  
  MAXVID_ASSERT(numPixels == numPixelsSaved, "numPixelsSaved");
  
  uint32_t *expectedCOPYBigPost8FrameBuffer32 = frameBuffer32 + numPixels;
  uint32_t *expectedCOPYBigPost8InputBuffer32 = ((uint32_t *) inputBuffer32) + numPixels;
  
  MAXVID_ASSERT(expectedCOPYBigPost8FrameBuffer32 == (frameBuffer32 + numPixels), "expected pointers");
  MAXVID_ASSERT(expectedCOPYBigPost8InputBuffer32 == (((uint32_t *) inputBuffer32) + numPixels), "expected pointers");
#endif
  
#ifdef EXTRA_CHECKS
  MAXVID_ASSERT(inputBuffer32 < inputBuffer32Max, "inputBuffer32Max");
#endif
  
#ifdef USE_INLINE_ARM_ASM
  // GCC emits a phantom assign to "r11" when compiling the C code.
  // This weird empty asm statement keeps GCC from doing that.
  
  __asm__ __volatile__ (
                        "@ Phantom assign to numPixels\n\t"
                        : \
                        [numPixels] "+l" (numPixels)
                        );
#endif // USE_INLINE_ARM_ASM
  
// START align64 block
  
  // Align to 64 bits to speed up stm writes with only a few conditional instrs.
  
#ifdef EXTRA_CHECKS
  MAXVID_ASSERT(((frameBuffer32 - inframeBuffer32) <= frameBufferSize), "dword align: already past end of framebuffer");
  MAXVID_ASSERT(numPixels >= 7, "dword align: numPixels");
#endif // EXTRA_CHECKS
  
#if defined(USE_INLINE_ARM_ASM)
  __asm__ __volatile__ (
                        // if (UINTMOD(frameBuffer32, sizeof(uint64_t)) != 0)
                        "tst %[frameBuffer32], #7\n\t"
                        // WR1 = *inputBuffer32++;
                        "ldrne %[wr1], [%[inputBuffer32]], #4\n\t"
                        // numWords -= 1;
                        "subne %[numPixels], %[numPixels], #1\n\t"
                        // *frameBuffer32++ = WR1;
                        "strne %[wr1], [%[frameBuffer32]], #4\n\t"
                        :
                        [numPixels] "+l" (numPixels),
                        [wr1] "+l" (WR1),
                        [wr2] "+l" (WR2),
                        [inputBuffer32] "+l" (inputBuffer32),
                        [frameBuffer32] "+l" (frameBuffer32)
                        );
#else // USE_INLINE_ARM_ASM
  
  if (UINTMOD(frameBuffer32, sizeof(uint64_t)) != 0) {
    // Framebuffer is word aligned, read/write a word (1 pixel) to dword align.

    WR1 = *inputBuffer32++;
    numPixels -= 1;
    *frameBuffer32++ = WR1;
  }
  
#endif //USE_INLINE_ARM_ASM
  
#ifdef EXTRA_CHECKS
  // The min numwords was 7, now could be >= 6
  MAXVID_ASSERT(numPixels >= 6, "dword align: numWords");
  MAXVID_ASSERT(frameBuffer32 != NULL, "frameBuffer32");
  MAXVID_ASSERT(UINTMOD(frameBuffer32, sizeof(uint64_t)) == 0, "frameBuffer32 dword alignment");
#endif // EXTRA_CHECKS
  
// END align64 block
  
  // if (numPixels >= 32) block disabled because it seems to be faster to align64
  // for the output buffer. That avoids a branch forward and a bunch of instructions.
  
  if (0) {
    // 16 word copy loop will be run more than 1 time, so align to 8 word cache line
    
    // Align the input pointer to the start of the next cache line. On ARM6 a
    // cache line is 8 words. ON ARM7, the cache is 16 words.
    // Use WR5 as a tmp countdown register, it won't be written over in debug
    // mode and it is set again after the word8 loop.
    
    WR5 = UINTMOD(inputBuffer32, BOUNDSIZE);
    
#ifdef EXTRA_CHECKS
    MAXVID_ASSERT(UINTMOD(inputBuffer32, sizeof(uint32_t)) == 0, "inputBuffer32 alignment");
    MAXVID_ASSERT(WR5 >= 0 && WR5 <= BOUNDSIZE, "in bounds");
#endif
    
    WR5 = BOUNDSIZE - WR5;
    WR5 >>= 2;
    WR5 &= (MV_CACHE_LINE_SIZE - 1);
    
#ifdef EXTRA_CHECKS
    MAXVID_ASSERT(WR5 >= 0, "invalid num words to bound");
    MAXVID_ASSERT(WR5 != MV_CACHE_LINE_SIZE, "invalid num words to bound");
    MAXVID_ASSERT(WR5 < MV_CACHE_LINE_SIZE, "invalid num words to bound");
    uint32_t *expectedPostAlignInputBuffer32 = inputBuffer32 + WR5;
#endif
    
#if defined(USE_INLINE_ARM_ASM)
    __asm__ __volatile__ (
                          "sub %[numPixels], %[numPixels], %[TMP]\n\t"
                          "cmp %[TMP], #1\n\t"
                          "ldmgtia %[inputBuffer32]!, {%[wr3], %[wr4]}\n\t"
                          "3:\n\t"
                          "subgt %[TMP], %[TMP], #2\n\t"
                          "stmgtia %[frameBuffer32]!, {%[wr3], %[wr4]}\n\t"
                          "cmp %[TMP], #1\n\t"
                          "ldmgtia %[inputBuffer32]!, {%[wr3], %[wr4]}\n\t"
                          "bgt 3b\n\t"
                          // if (TMP == 1)
                          "ldreq %[wr3], [%[inputBuffer32]], #4\n\t"
                          "streq %[wr3], [%[frameBuffer32]], #4\n\t"
                          :
                          [numPixels] "+l" (numPixels),
                          [TMP] "+l" (WR5),
                          [wr3] "+l" (WR3),
                          [wr4] "+l" (WR4),
                          [inputBuffer32] "+l" (inputBuffer32),
                          [frameBuffer32] "+l" (frameBuffer32)
                          );
#else
    numPixels -= WR5;
    
    for (; WR5 > 1; WR5 -= 2) {
      memcpy(frameBuffer32, inputBuffer32, sizeof(uint32_t) * 2);
      frameBuffer32 += 2;
      inputBuffer32 += 2;
    }
    if (WR5 == 1) {
      WR3 = *inputBuffer32++;
      *frameBuffer32++ = WR3;
    }
#endif // USE_INLINE_ARM_ASM
    
#ifdef EXTRA_CHECKS
    MAXVID_ASSERT(WR5 == 0 || WR5 == 1, "WR5");
    MAXVID_ASSERT(expectedPostAlignInputBuffer32 == inputBuffer32, "expectedPostAlignInputBuffer32");
    MAXVID_ASSERT(UINTMOD(inputBuffer32, BOUNDSIZE) == 0, "input ptr should be at bound");
#endif
  } // end of if (numPixels >= 32)
  
#ifdef EXTRA_CHECKS
  MAXVID_ASSERT(numPixels >= 6, "numPixels");
#endif
  
  // Big write loop, use stm to read and write 8 words at a time, 16 words in each loop
  
#if defined(USE_INLINE_ARM_ASM)
  if (numPixels >= 16) {
    // Once we know there are at least 16 words to be copied then do an
    // additional check to see if it is worth it to invoke memcpy()
    // for a very large copy operation. The platform defined memcpy()
    // is optimized for the specific processor type (A8 vs A9) and as
    // a result it is faster for large copies.
    
    if (numPixels >= (MV_PAGESIZE / 4 / sizeof(uint32_t))) {
      memcpy(frameBuffer32, inputBuffer32, numPixels << 2);
      frameBuffer32 += numPixels;
      inputBuffer32 += numPixels;
      // Skip the 8 word loop and any remaining copies by setting to zero
      numPixels = 0;
    } else {
    
    __asm__ __volatile__ (
                          "1:\n\t"
                          "ldm %[inWordPtr]!, {%[wr1], %[wr2], %[wr3], %[wr4], %[wr5], %[wr6], %[wr7], %[wr8]}\n\t"
                          "pld	[%[inWordPtr], #32]\n\t"
                          "sub %[numWords], %[numWords], #16\n\t"
                          "stm %[outWordPtr]!, {%[wr1], %[wr2], %[wr3], %[wr4], %[wr5], %[wr6], %[wr7], %[wr8]}\n\t"
                          "ldm %[inWordPtr]!, {%[wr1], %[wr2], %[wr3], %[wr4], %[wr5], %[wr6], %[wr7], %[wr8]}\n\t"
                          "pld	[%[inWordPtr], #32]\n\t"
                          "cmp %[numWords], #15\n\t"
                          "stm %[outWordPtr]!, {%[wr1], %[wr2], %[wr3], %[wr4], %[wr5], %[wr6], %[wr7], %[wr8]}\n\t"
                          "bgt 1b\n\t"
                          :
                          [outWordPtr] "+l" (frameBuffer32),
                          [inWordPtr] "+l" (inputBuffer32),
                          [numWords] "+l" (numPixels),
                          [wr1] "+l" (WR1),
                          [wr2] "+l" (WR2),
                          [wr3] "+l" (WR3),
                          [wr4] "+l" (WR4),
                          [wr5] "+l" (WR5),
                          [wr6] "+l" (WR6),
                          [wr7] "+l" (WR7),
                          [wr8] "+l" (WR8)
                          );
    }
  }
  
#ifdef EXTRA_CHECKS
  MAXVID_ASSERT(numPixels <= MV_MAX_22_BITS, "numPixels");
  MAXVID_ASSERT(numPixels < 16, "numPixels");
#endif
  
#ifdef EXTRA_CHECKS
  MAXVID_ASSERT(inputBuffer32 < inputBuffer32Max, "inputBuffer32Max");
#endif
  
  // emit any remaining words (less than 16) as dwords followed by a single word
  
  __asm__ __volatile__ (
                        "cmp %[numWords], #7\n\t"
                        "ldmgt %[inWordPtr]!, {%[wr1], %[wr2], %[wr3], %[wr4], %[wr5], %[wr6], %[wr7], %[wr8]}\n\t"
                        "subgt %[numWords], %[numWords], #8\n\t"
                        "stmgt %[outWordPtr]!, {%[wr1], %[wr2], %[wr3], %[wr4], %[wr5], %[wr6], %[wr7], %[wr8]}\n\t"
                        "cmp %[numWords], #3\n\t"
                        "ldmgt %[inWordPtr]!, {%[wr1], %[wr2], %[wr3], %[wr4]}\n\t"
                        "subgt %[numWords], %[numWords], #4\n\t"
                        "stmgt %[outWordPtr]!, {%[wr1], %[wr2], %[wr3], %[wr4]}\n\t"
                        "cmp %[numWords], #1\n\t"
                        "ldmgt %[inWordPtr]!, {%[wr1], %[wr2]}\n\t"
                        "subgt %[numWords], %[numWords], #2\n\t"
                        "stmgt %[outWordPtr]!, {%[wr1], %[wr2]}\n\t"
                        "cmp %[numWords], #1\n\t"
                        "ldreq %[wr1], [%[inWordPtr]], #4\n\t"
                        "streq %[wr1], [%[outWordPtr]], #4\n\t"
                        :
                        [outWordPtr] "+l" (frameBuffer32),
                        [inWordPtr] "+l" (inputBuffer32),
                        [numWords] "+l" (numPixels),
                        [wr1] "+l" (WR1),
                        [wr2] "+l" (WR2),
                        [wr3] "+l" (WR3),
                        [wr4] "+l" (WR4),
                        [wr5] "+l" (WR5),
                        [wr6] "+l" (WR6),
                        [wr7] "+l" (WR7),
                        [wr8] "+l" (WR8)
                        );
  
#else // USE_INLINE_ARM_ASM
  memcpy(frameBuffer32, inputBuffer32, numPixels << 2);
  frameBuffer32 += numPixels;
  inputBuffer32 += numPixels;
#endif // USE_INLINE_ARM_ASM
  
#ifdef EXTRA_CHECKS
  MAXVID_ASSERT(frameBuffer32 == expectedCOPYBigPost8FrameBuffer32, "COPY post word8 framebuffer");
  MAXVID_ASSERT(inputBuffer32 == expectedCOPYBigPost8InputBuffer32, "COPY input post word8");
#endif
  
#ifdef EXTRA_CHECKS
  MAXVID_ASSERT(((frameBuffer32 - inframeBuffer32) <= frameBufferSize), "post COPY, now past end of framebuffer");
#endif // EXTRA_CHECKS
  
  // Read in next inW1 and inW2
  
#ifdef EXTRA_CHECKS
  MAXVID_ASSERT(inputBuffer32 != NULL, "inputBuffer32");
  MAXVID_ASSERT(UINTMOD(inputBuffer32, sizeof(uint32_t)) == 0, "inputBuffer32 initial alignment");
  // inputBuffer32 should be 2 words ahead of the previous read (ignored in COPY case)
  //MAXVID_ASSERT(inputBuffer32 == (prevInputBuffer32 + 2), "inputBuffer32 != previous");
  prevInputBuffer32 = inputBuffer32;
#endif
  
#ifdef EXTRA_CHECKS
  MAXVID_ASSERT(inputBuffer32 < inputBuffer32Max, "inputBuffer32Max");
  MAXVID_ASSERT((inputBuffer32 + 1) < inputBuffer32Max, "inputBuffer32Max");
#endif
  
#if defined(USE_INLINE_ARM_ASM)
  __asm__ __volatile__ (
                        // inW1 = *inputBuffer32++
                        // inW2 = *inputBuffer32++
                        "ldm %[inputBuffer32]!, {%[inW1], %[inW2]}\n\t"
                        :
                        [inW1] "+l" (inW1),
                        [inW2] "+l" (inW2),
                        [inputBuffer32] "+l" (inputBuffer32)
                        );
#else
  inW1 = *inputBuffer32++;
  inW2 = *inputBuffer32++;
#endif // USE_INLINE_ARM_ASM
  
#ifdef EXTRA_CHECKS
  inW1Saved = inW1;
  inW2Saved = inW2;
  MAXVID_ASSERT(inputBuffer32 == (prevInputBuffer32 + 2), "inputBuffer32 != previous");
#endif
  
  // Regen constants in registers
  
#if defined(USE_INLINE_ARM_ASM)
  __asm__ __volatile__ (
                        "mov %[oneReg], %[oneConst]\n\t"
                        "mov %[copyOneReg], %[copyOneConst]\n\t"
                        "mov %[dupTwoReg], %[dupTwoConst]\n\t"
                        "mov %[opCodeMaskReg], %[opCodeMaskConst]\n\t"
                        :
                        [oneReg] "+l" (oneConstRegister),
                        [copyOneReg] "+l" (copyOneConstRegister),
                        [dupTwoReg] "+l" (dupTwoConstRegister),
                        [opCodeMaskReg] "+l" (opCodeMaskConstRegister)
                        :
                        [oneConst] "i" (oneConstWord),
                        [copyOneConst] "i" (copyOnePixelWord),
                        [dupTwoConst] "i" (dupTwoPixelsWord),
                        [opCodeMaskConst] "i" (opCodeMask)
                        );
  
#ifdef EXTRA_CHECKS
  MAXVID_ASSERT(oneConstRegister == oneConstWord, "oneConstRegister");
  MAXVID_ASSERT(copyOneConstRegister == copyOnePixelWord, "copyOneConstRegister");
  MAXVID_ASSERT(dupTwoConstRegister == dupTwoPixelsWord, "dupTwoConstRegister");
  MAXVID_ASSERT(opCodeMaskConstRegister == opCodeMask, "opCodeMaskConstRegister");
#endif // EXTRA_CHECKS
#endif // USE_INLINE_ARM_ASM
  
#if defined(USE_INLINE_ARM_ASM)
  __asm__ __volatile__ (
                        "@ goto DECODE_32BPP\n\t"
                        :
                        );
#endif // USE_INLINE_ARM_ASM
  
  goto DECODE_32BPP;
  
DUPBIG_32BPP:
  // This block is just here to work around what appears to be a compiler bug related to a label.
  {
  }
  
#ifdef USE_INLINE_ARM_ASM
  __asm__ __volatile__ (
                        "@ DUPBIG_32BPP\n\t"
                        );
#endif // USE_INLINE_ARM_ASM
  
  // DUPBIG is jumped to when there are more than 6 words/pixels in a DUP operation.
  // The optimal implementation is filling 8 words at a time. DUP2 was already handled.
  
#ifdef EXTRA_CHECKS
  MAXVID_ASSERT(numPixels == numPixelsSaved, "numPixelsSaved");
#endif // EXTRA_CHECKS
  
#ifdef EXTRA_CHECKS
  MAXVID_ASSERT(inputBuffer32 != NULL, "inputBuffer32");
  MAXVID_ASSERT(UINTMOD(inputBuffer32, sizeof(uint32_t)) == 0, "inputBuffer32 initial alignment");
  MAXVID_ASSERT(frameBuffer32 != NULL, "frameBuffer32");
  MAXVID_ASSERT(UINTMOD(frameBuffer32, sizeof(uint32_t)) == 0, "frameBuffer32 initial alignment");
#endif
  
#ifdef EXTRA_CHECKS
  MAXVID_ASSERT(((frameBuffer32 - inframeBuffer32) < frameBufferSize), "DUP already past end of framebuffer");
  MAXVID_ASSERT((((frameBuffer32 + numPixels - 1) - inframeBuffer32) < frameBufferSize), "DUP past end of framebuffer");
#endif
  
#ifdef EXTRA_CHECKS
  MAXVID_ASSERT(numPixels == numPixelsSaved, "numPixelsSaved");
  // numPixels is a 22 bit number
  MAXVID_ASSERT(numPixels > 2, "numPixels");
  MAXVID_ASSERT(numPixels <= MV_MAX_22_BITS, "numPixels");
  MAXVID_ASSERT(numPixels >= 7, "numPixels");
#endif
  
  // Save inW1 as inW2 since inW2 is not clobbered by the word8 loop. Later, reset inW1 and reread inW2.
  // This should be slightly faster since reads will not get out of order.
  
#if defined(USE_INLINE_ARM_ASM)
  __asm__ __volatile__ (
                        "mov %[inW2], %[inW1]\n\t"
                        :
                        [inW1] "+l" (inW1),
                        [inW2] "+l" (inW2)
                        );
#else
  inW2 = inW1;
#endif
  
#ifdef EXTRA_CHECKS
  MAXVID_ASSERT(inputBuffer32 != NULL, "inputBuffer32");
  MAXVID_ASSERT(UINTMOD(inputBuffer32, sizeof(uint32_t)) == 0, "inputBuffer32 alignment");
  MAXVID_ASSERT(frameBuffer32 != NULL, "frameBuffer32");
  MAXVID_ASSERT(UINTMOD(frameBuffer32, sizeof(uint32_t)) == 0, "frameBuffer32 alignment");
  MAXVID_ASSERT(numPixels == numPixelsSaved, "numPixelsSaved");
  
  //MAXVID_ASSERT(inW1 == inW1Saved, "inW1Saved");
  //MAXVID_ASSERT(inW2 == inW2Saved, "inW2Saved");
  
  uint32_t *expectedDUPBigPost8FrameBuffer32 = frameBuffer32 + numPixels;
  
  MAXVID_ASSERT(expectedDUPBigPost8FrameBuffer32 == (frameBuffer32 + numPixels), "expectedDUPBigPost8FrameBuffer32");
  
  MAXVID_ASSERT(numPixels == numPixelsSaved, "numPixelsSaved");
  
  MAXVID_ASSERT(WR1 == WR1Saved, "WR1Saved");
#endif
  
// START align64 block
  
  // Earlier code has already aligned the output pointer to 32bits, now align to 64bits
  // so that writing 8 words starts out already aligned.
  
#ifdef EXTRA_CHECKS
  MAXVID_ASSERT(((frameBuffer32 - inframeBuffer32) <= frameBufferSize), "dword align: already past end of framebuffer");
  MAXVID_ASSERT(numPixels >= 7, "dword align: numPixels");
#endif // EXTRA_CHECKS
  
#if defined(USE_INLINE_ARM_ASM)
  __asm__ __volatile__ (
                        // if (UINTMOD(frameBuffer32, sizeof(uint64_t)) != 0)
                        "tst %[frameBuffer32], #7\n\t"
                        // schedule unconditional init of wr2 here!
                        "mov %[wr2], %[wr1]\n\t"
                        // *frameBuffer32++ = WR1;
                        "strne %[wr1], [%[frameBuffer32]], #4\n\t"
                        // numWords -= 1;
                        "subne %[numPixels], %[numPixels], #1\n\t"
                        :
                        [numPixels] "+l" (numPixels),
                        [wr1] "+l" (WR1),
                        [wr2] "+l" (WR2),
                        [frameBuffer32] "+l" (frameBuffer32)
                        );
#else // USE_INLINE_ARM_ASM
  
  if (UINTMOD(frameBuffer32, sizeof(uint64_t)) != 0) {
    // Framebuffer is word aligned, read/write a word (1 pixel) to dword align.
    
    *frameBuffer32++ = WR1;
    numPixels -= 1;
  }
  
#endif //USE_INLINE_ARM_ASM
  
#ifdef EXTRA_CHECKS
  // The min numwords was 7, now could be >= 6
  MAXVID_ASSERT(numPixels >= 6, "dword align: numWords");
  MAXVID_ASSERT(frameBuffer32 != NULL, "frameBuffer32");
  MAXVID_ASSERT(UINTMOD(frameBuffer32, sizeof(uint64_t)) == 0, "frameBuffer32 dword alignment");
#endif // EXTRA_CHECKS
  
// END align64 block
  
// START align 8 word block
  
  // This entire align to 8 words block is disabled because it actually hurt performance
  // for medium and large size blocks. It seems that as long as the output pointer is
  // 64bit aligned that the hardware can deal with writes more effectively than more code.
  
  if (0) {
    // To get maximum performance, each big stm of 8 words is aligned to an 8 word block.
    
    // Use WR5 as a tmp countdown register, it won't be written over in debug
    // mode and it is set again after the word8 loop.
    
    // set WR5 to the number of dwords from the bound size. Since the framebuffer
    // is already aligned to 64bits, the number of bytes to the bound is a multiple of 8.

#ifdef EXTRA_CHECKS
    MAXVID_ASSERT(UINTMOD(frameBuffer32, sizeof(uint64_t)) == 0, "frameBuffer32 dword alignment");
    uint32_t *savedInputBuffer32 = inputBuffer32;
#endif
    
#if defined(USE_INLINE_ARM_ASM)

#ifdef EXTRA_CHECKS
    MAXVID_ASSERT(WR1 == WR2, "wr2 init");
    MAXVID_ASSERT(opCodeMaskConstRegister == opCodeMask, "opCodeMaskConstRegister");
    
    // Verify that advancing as much as 3 dwords would not go over the min
    // number of pixels including one reduced to do a 64 bit align.
    MAXVID_ASSERT(numPixels >= 6, "dword align: numWords");
#endif
    
    // Note that these instructions require significant rescheduling to avoid
    // locking on register r4. The actual ARM asm is not in this order.
    
    __asm__ __volatile__ (
                          // TMP = (frameBuffer32 >> 3) & 0x3
                          // possible results : 0, 1, 2, 3 dwords
                          // This instruction will also set the flags so that the
                          // rsb need only be done if needed and so that the loop
                          // condition when the loop is entered.
                          "ands %[TMP], %[opCodeMaskReg], %[frameBuffer32], lsr #3\n\t"
                          // TMP = (BOUNDSIZE >> 3) - TMP;
                          "rsbne %[TMP], %[TMP], #4\n\t"
                          
                          // write dwords loop
                          
                          // numPixels -= numWords
                          "sub %[numPixels], %[numPixels], %[TMP], lsl #1\n\t"
                          //"cmp %[TMP], #0\n\t"
                          "3:\n\t"
                          "stmgt %[frameBuffer32]!, {%[wr1], %[wr2]}\n\t"
                          "subgts %[TMP], %[TMP], #1\n\t"
                          "bgt 3b\n\t"
                          :
                          [numPixels] "+l" (numPixels),
                          [TMP] "+l" (WR5),
                          [wr1] "+l" (WR1),
                          [wr2] "+l" (WR2),
                          [opCodeMaskReg] "+l" (opCodeMaskConstRegister),
                          [frameBuffer32] "+l" (frameBuffer32)
                          );
#else // USE_INLINE_ARM_ASM
    
    WR5 = UINTMOD(frameBuffer32, BOUNDSIZE);
    
#ifdef EXTRA_CHECKS
    MAXVID_ASSERT(UINTMOD(frameBuffer32, sizeof(uint32_t)) == 0, "frameBuffer32 alignment");
    MAXVID_ASSERT(UINTMOD(frameBuffer32, sizeof(uint64_t)) == 0, "frameBuffer32 dword alignment");
    MAXVID_ASSERT(WR5 >= 0 && WR5 <= BOUNDSIZE, "in bounds");
    MAXVID_ASSERT((WR5 % 2) == 0, "should be even number of bytes");
    MAXVID_ASSERT(((WR5 >> 2) % 2) == 0, "should be even number of words");
    MAXVID_ASSERT(WR5 == 0 || WR5 == 8 || WR5 == 16 || WR5 == 24, "bound on dword interval");
#endif
    
    // Convert number of bytes from the bound to number of bytes from
    // the bound to the current pointer. The unconditional AND operation
    // clamps the max value back to zero. Finally, shift to convert to
    // number of words to the bound.
    
    WR5 = BOUNDSIZE - WR5;
    WR5 &= (BOUNDSIZE - 1);
    WR5 >>= 2;
    
#ifdef EXTRA_CHECKS
    MAXVID_ASSERT(WR5 != MV_CACHE_LINE_SIZE, "invalid num words to bound");
    MAXVID_ASSERT(WR5 < MV_CACHE_LINE_SIZE, "invalid num words to bound");
    MAXVID_ASSERT((WR5 % 2) == 0, "should be even number of words");
    uint32_t *expectedPostAlignFrameBuffer32 = frameBuffer32 + WR5;
    MAXVID_ASSERT(WR5 == 0 || WR5 == 2 || WR5 == 4 || WR5 == 6, "bound on dword interval");
#endif
    
    numPixels -= WR5;
    WR5 = WR5 >> 1;

#ifdef EXTRA_CHECKS
    MAXVID_ASSERT(WR5 == 0 || WR5 == 1 || WR5 == 2 || WR5 == 3, "bound on dword interval");
#endif
    
    // write a dword (2 words = 2 pixels) each iteration.
    
    uint64_t dWordValue = (((uint64_t)WR1) << 32)|(uint64_t)WR1;
    for (; WR5; WR5--) {
      // clang seems rather dumb as it does not want to generate a stm or strd for this 64bit write
      memcpy(frameBuffer32, &dWordValue, sizeof(uint64_t));
      frameBuffer32 += 2;
    }
    
#ifdef EXTRA_CHECKS
    MAXVID_ASSERT(expectedPostAlignFrameBuffer32 == frameBuffer32, "expectedPostAlignFrameBuffer32");
#endif
    
#endif // USE_INLINE_ARM_ASM
    
#ifdef EXTRA_CHECKS
    MAXVID_ASSERT(WR5 == 0, "WR5");
    MAXVID_ASSERT(UINTMOD(frameBuffer32, BOUNDSIZE) == 0, "output ptr should be at bound");
    MAXVID_ASSERT(UINTMOD(frameBuffer32, sizeof(uint64_t)) == 0, "frameBuffer32 dword alignment");
    MAXVID_ASSERT(UINTMOD(inputBuffer32, sizeof(uint32_t)) == 0, "inputBuffer32 word alignment");

    MAXVID_ASSERT(inputBuffer32 == savedInputBuffer32, "savedInputBuffer32");
#endif
  }
  
  // Verify numPixels min again, one word could have been consumed by align to 64bit address
  
#ifdef EXTRA_CHECKS
  MAXVID_ASSERT(numPixels >= 6, "numPixels");
#endif
  
// END align 8 word block

  // Dup big 8 word loop
  
#if defined(USE_INLINE_ARM_ASM)
  __asm__ __volatile__ (
                        // Note that wr2 was initialized unconditionally above
                        "mov %[wr3], %[wr1]\n\t"
                        "mov %[wr4], %[wr1]\n\t"
                        
                        // In the case where the 8 word loop will not be executed, skip forward
                        // over the next 8 instructions. This provides a nice speed boost on A8
                        // processors and is a little bit faster on A9 too.
                        "cmp %[numWords], #8\n\t"
                        "blt 2f\n\t"
                        
                        "mov %[wr5], %[wr1]\n\t"
                        "mov %[wr6], %[wr1]\n\t"
                        "mov %[wr7], %[wr1]\n\t"
                        "mov %[wr8], %[wr1]\n\t"
                        "1:\n\t"
                        "cmp %[numWords], #15\n\t"
                        "stm %[frameBuffer32]!, {%[wr1], %[wr2], %[wr3], %[wr4], %[wr5], %[wr6], %[wr7], %[wr8]}\n\t"
                        "sub %[numWords], %[numWords], #8\n\t"
                        "bgt 1b\n\t"
                        "2:\n\t"
                        
                        "cmp %[numWords], #3\n\t"
                        // In the optimized ASM code, constants are scheduled into this block from below.
                        // constant init
                        "subgt %[numWords], %[numWords], #4\n\t"
                        "stmgt %[frameBuffer32]!, {%[wr1], %[wr2], %[wr3], %[wr4]}\n\t"
                        "cmp %[numWords], #2\n\t"
                        // constant init
                        "stmgt %[frameBuffer32], {%[wr1], %[wr2], %[wr3]}\n\t"
                        "stmeq %[frameBuffer32], {%[wr1], %[wr2]}\n\t"
                        // frameBuffer32 += (numWords << 1)
                        "add %[frameBuffer32], %[frameBuffer32], %[numWords], lsl #2\n\t"
                        "cmp %[numWords], #1\n\t"
                        // constant init
                        "streq %[wr1], [%[frameBuffer32], #-4]\n\t"
                        :
                        [frameBuffer32] "+l" (frameBuffer32),
                        [numWords] "+l" (numPixels),
                        [wr1] "+l" (WR1),
                        [wr2] "+l" (WR2),
                        [wr3] "+l" (WR3),
                        [wr4] "+l" (WR4),
                        [wr5] "+l" (WR5),
                        [wr6] "+l" (WR6),
                        [wr7] "+l" (WR7),
                        [wr8] "+l" (WR8)
                        );
#else // USE_INLINE_ARM_ASM
  {
    uint32_t inWordPtr = WR1;
    memset_pattern4(frameBuffer32, &inWordPtr, numPixels << 2);
    frameBuffer32 += numPixels;
#ifdef EXTRA_CHECKS
    numPixels = 0;
#endif
  }
#endif // USE_INLINE_ARM_ASM
  
#ifdef EXTRA_CHECKS
  MAXVID_ASSERT(inputBuffer32 != NULL, "inputBuffer32");
  MAXVID_ASSERT(UINTMOD(inputBuffer32, sizeof(uint32_t)) == 0, "inputBuffer32 alignment");
  MAXVID_ASSERT(frameBuffer32 != NULL, "frameBuffer32");
  MAXVID_ASSERT(UINTMOD(frameBuffer32, sizeof(uint32_t)) == 0, "frameBuffer32 alignment");
  
  MAXVID_ASSERT(frameBuffer32 == expectedDUPBigPost8FrameBuffer32, "frameBuffer32 post8");
  MAXVID_ASSERT(numPixels >= 0 && numPixels <= 3, "numPixels");
#endif
  
#ifdef EXTRA_CHECKS
  MAXVID_ASSERT(((frameBuffer32 - inframeBuffer32) <= frameBufferSize), "post DUP, now past end of framebuffer");
#endif // EXTRA_CHECKS
  
  // Restore inW1 and reread inW2 after word8 loop
  
#ifdef EXTRA_CHECKS
  MAXVID_ASSERT(inputBuffer32 != NULL, "inputBuffer32");
  MAXVID_ASSERT(UINTMOD(inputBuffer32, sizeof(uint32_t)) == 0, "inputBuffer32 alignment");
  // inputBuffer32 should be 2 words ahead of the previous read (ignored in COPY case)
  MAXVID_ASSERT(inputBuffer32 == (prevInputBuffer32 + 2), "inputBuffer32 != previous");
#endif
  
#ifdef EXTRA_CHECKS
#endif
  
  // Reset inW1 and reread the previous inW2 value after the word8 loop is finished. This logic
  // ensures that reads are not getting out of order.
  
#if defined(USE_INLINE_ARM_ASM)
  __asm__ __volatile__ (
                        // inW1 = inW2;
                        // inW2 = *(inputBuffer32 - 1);
                        "mov %[inW1], %[inW2]\n\t"
                        "ldr %[inW2], [%[inputBuffer32], #-4]\n\t"
                        :
                        [inW1] "+l" (inW1),
                        [inW2] "+l" (inW2),
                        [inputBuffer32] "+l" (inputBuffer32)
                        );
#else
  inW1 = inW2;
  inW2 = *(inputBuffer32 - 1);
#endif // USE_INLINE_ARM_ASM
  
#ifdef EXTRA_CHECKS
  MAXVID_ASSERT(inW1 == inW1Saved, "inW1Saved");
  MAXVID_ASSERT(inW2 == inW2Saved, "inW2Saved");
#endif // EXTRA_CHECKS
  
#ifdef EXTRA_CHECKS
  inW1Saved = inW1;
  inW2Saved = inW2;
  MAXVID_ASSERT(inputBuffer32 == (prevInputBuffer32 + 2), "inputBuffer32 != previous");
#endif
  
  // Regen constants in registers
  
#if defined(USE_INLINE_ARM_ASM)
  __asm__ __volatile__ (
                        "mov %[oneReg], %[oneConst]\n\t"
                        "mov %[copyOneReg], %[copyOneConst]\n\t"
                        "mov %[dupTwoReg], %[dupTwoConst]\n\t"
                        "mov %[opCodeMaskReg], %[opCodeMaskConst]\n\t"
                        :
                        [oneReg] "+l" (oneConstRegister),
                        [copyOneReg] "+l" (copyOneConstRegister),
                        [dupTwoReg] "+l" (dupTwoConstRegister),
                        [opCodeMaskReg] "+l" (opCodeMaskConstRegister)
                        :
                        [oneConst] "i" (oneConstWord),
                        [copyOneConst] "i" (copyOnePixelWord),
                        [dupTwoConst] "i" (dupTwoPixelsWord),
                        [opCodeMaskConst] "i" (opCodeMask)
                        );
  
#ifdef EXTRA_CHECKS
  MAXVID_ASSERT(oneConstRegister == oneConstWord, "oneConstRegister");
  MAXVID_ASSERT(copyOneConstRegister == copyOnePixelWord, "copyOneConstRegister");
  MAXVID_ASSERT(dupTwoConstRegister == dupTwoPixelsWord, "dupTwoConstRegister");
  MAXVID_ASSERT(opCodeMaskConstRegister == opCodeMask, "opCodeMaskConstRegister");
#endif // EXTRA_CHECKS
#endif // USE_INLINE_ARM_ASM
  
#if defined(USE_INLINE_ARM_ASM)
  __asm__ __volatile__ (
                        "@ goto DECODE_32BPP\n\t"
                        :
                        );
#endif // USE_INLINE_ARM_ASM
  
  goto DECODE_32BPP;
  
DONE_32BPP:
#if defined(USE_INLINE_ARM_ASM)
  __asm__ __volatile__ (
                        "@ DONE_32BPP\n\t"
                        );
#endif //  USE_INLINE_ARM_ASM
  
#if defined(EXTRA_CHECKS)
  MAXVID_ASSERT(inputBuffer32 == inputBuffer32Max, "must be at end of input");
#endif // EXTRA_CHECKS
  
#if defined(EXTRA_CHECKS)
  MAXVID_ASSERT(frameBuffer32 == frameBuffer32Max, "must be at end of framebuffer");
#endif // EXTRA_CHECKS
  
  // The word following a DONE code must be zero. This trailing padding ensures that any 2 word read will
  // not read past the end of the allocated buffer.
  
#if defined(EXTRA_CHECKS)
  MAXVID_ASSERT(inW2 == 0, "DONE code must be followed by a zero word");
#endif // EXTRA_CHECKS
  
  return 0;
}

#endif // defined(USE_GENERATED_ARM_ASM)
