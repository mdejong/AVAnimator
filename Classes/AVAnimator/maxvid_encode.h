// maxvid_encode module
//
//  License terms defined in License.txt.
//
// This module defines the encoder portion of the maxvid video codec for iOS.

#import "maxvid_decode.h"

#import <Foundation/Foundation.h>

@class AVMvidFileWriter;

#ifndef __OPTIMIZE__
// Automatically define EXTRA_CHECKS when not optimizing (in debug mode)
# define EXTRA_CHECKS
#endif // DEBUG

// Extensions should not use this method

static inline
uint32_t
maxvid16_internal_code(MV_GENERIC_CODE opCode, const uint32_t val, const uint32_t num) {
#if defined(EXTRA_CHECKS)
  if (num > 0xFFFF) {
    assert(0);
  }
  if (val > MV_MAX_14_BITS) {
    assert(0);
  }
  if (num > MV_MAX_16_BITS) {
    assert(0);
  }
  if (opCode == SKIP) {
    assert(num > 0);
  } else if (opCode == DUP) {
    assert(num > 1);
  } else if (opCode == COPY) {
    assert(num > 0);
  } else if (opCode == DONE) {
    assert(num == 0);
    assert(val == 0);
  } else {
    assert(0);
  }
#endif // EXTRA_CHECKS
  
  uint32_t opCodeWord = (uint32_t)opCode;
  uint32_t valPartWord = (uint32_t)val;
  uint32_t numPartWord = (uint32_t)num;
  
  const uint32_t word = (opCodeWord << 30) | (valPartWord << 16) | numPartWord;
    
#ifdef EXTRA_CHECKS
    {
      MV16_READ_OP_VAL_NUM(word, opCodeValue, opValue, numValue);
      assert(opCodeValue == opCodeWord);
      assert(opValue == valPartWord);
      assert(numValue == numPartWord);
    }
#endif // EXTRA_CHECKS    
    
  return word;
}

// This utility method is provided for converter extensions,
// it will construct an input op code and verify that the
// arguments are valid.
//
// opCode is one of (SKIP, DUP, COPY, DONE)
// num is a 16 bit integer with a max value of 0xFFFF.

static inline
uint32_t
maxvid16_code(MV_GENERIC_CODE opCode, const uint32_t num) {
  return maxvid16_internal_code(opCode, 0, num);
}

// Generate a 32 bit "c4" code for a 16 bit pixel value. The 2 bit opCode and 14 bit numPart
// fields are joined as the top half word. The low half word is pixelPart.

static inline
uint32_t
maxvid16_c4_code(MV_GENERIC_CODE opCode, uint32_t numPart, uint16_t pixelPart) {
#if defined(EXTRA_CHECKS)
  if (numPart > 0xFFFF) {
    assert(0);
  }
#endif // EXTRA_CHECKS
  
  uint32_t opCodeWord = (uint32_t)opCode;
  uint32_t numPartWord = (uint32_t)numPart;
  uint32_t pixelPartWord = (uint32_t)pixelPart;
  uint32_t wordCode = (opCodeWord << 30) | (numPartWord << 16) | pixelPartWord;
  return wordCode;
}

// Internal 32 bit word code util method. This method should not
// be invoked by converter extensions.

static inline
uint32_t
maxvid32_internal_code(MV_GENERIC_CODE opCode, const uint32_t num, const uint32_t skipAfter) {
#ifdef EXTRA_CHECKS
  if (num > MV_MAX_22_BITS) {
    assert(0);
  }
  if (skipAfter > MV_MAX_8_BITS) {
    assert(0);
  }  
  
  if (opCode == SKIP) {
    assert(num > 0);
    assert(skipAfter == 0);
  } else if (opCode == DUP) {
    assert(num > 1);
  } else if (opCode == COPY) {
    assert(num > 0);
  } else if (opCode == DONE) {
    assert(num == 0);
    assert(skipAfter == 0);
  } else {
    assert(0);
  }
#endif // EXTRA_CHECKS
  uint32_t opCodeWord = (uint32_t)opCode;
  uint32_t numWord = (uint32_t)num;
  uint32_t skipAfterWord = (uint32_t)skipAfter;
#ifdef EXTRA_CHECKS
  assert((opCodeWord & MV_MAX_2_BITS) == opCodeWord);
  assert((numWord & MV_MAX_22_BITS) == numWord);
  assert((skipAfterWord & MV_MAX_8_BITS) == skipAfter);
#endif // EXTRA_CHECKS
  // num is the upper most 22 bits in the word
  // opCode is the next 2 bits
  // the lowest 8 bits are a small "skip after" value
  uint32_t word = (numWord << 8+2) | (opCodeWord << 8) | skipAfterWord;
#ifdef EXTRA_CHECKS
  {
    MV32_PARSE_OP_NUM_SKIP(word, opVal, numVal, skipVal);
    assert(opVal == opCodeWord);
    assert(numVal == numWord);
    assert(skipVal == skipAfterWord);
  }
#endif // EXTRA_CHECKS
  return word;
}

// Public "generic" encoding util for a 24/32 bit pixel code.
// Note that the pixels following a word code always take up
// a whole pixel. In the 24 bit case, the top byte is always zero.
// The num value is a 22 bit integer.

static inline
uint32_t
maxvid32_code(MV_GENERIC_CODE opCode, const uint32_t num) {
  return maxvid32_internal_code(opCode, num, 0);
}

// These method encode an array of generic word codes to a specific
// encoding and write the result to a file. If the file pointer is
// non-NULL then the codes will be appended to the file. Otherwise
// a new file will be opened.

int
maxvid_encode_c4_sample16(
                          const uint32_t * restrict inputBuffer32,
                          const uint32_t inputBufferNumWords,
                          const uint32_t frameBufferNumPixels,
                          const char * restrict filePath,
                          FILE * restrict file,
                          const uint32_t encodeFlags);

int
maxvid_encode_c4_sample32(
                          const uint32_t * restrict inputBuffer32,
                          const uint32_t inputBufferNumWords,
                          const uint32_t frameBufferNumPixels,
                          const char * restrict filePath,
                          FILE * restrict file,
                          const uint32_t encodeFlags);

// These utility methods work for either a 16 bpp or 24/32 bpp buffer and
// encode the pixels that changed from one frame to the next as maxvid
// generic codes stored in a NSData.

NSData*
maxvid_encode_generic_delta_pixels16(const uint16_t * restrict prevInputBuffer16,
                                     const uint16_t * restrict currentInputBuffer16,
                                     const uint32_t inputBufferNumWords,
                                     uint32_t width,
                                     uint32_t height);

NSData*
maxvid_encode_generic_delta_pixels32(const uint32_t * restrict prevInputBuffer32,
                                     const uint32_t * restrict currentInputBuffer32,
                                     const uint32_t inputBufferNumWords,
                                     uint32_t width,
                                     uint32_t height);

// This method will convert maxvid codes to the final output format, calculate an adler
// checksum for the frame data and then write the data to the mvidWriter.

BOOL
maxvid_write_delta_pixels(AVMvidFileWriter *mvidWriter,
                          NSData *maxvidData,
                          void *inputBuffer,
                          uint32_t inputBufferNumBytes,
                          NSUInteger frameBufferNumPixels);

#undef EXTRA_CHECKS
