// maxvid_encode module
//
//  License terms defined in License.txt.
//
// This module defines the encoder portion of the maxvid video codec for iOS.

// Note that EXTRA_CHECKS is conditionally define and then undefined in this header, so it
// must appear before the EXTRA_CHECKS logic below.

#import "maxvid_encode.h"

#import "maxvid_file.h"

#import "AVMvidFileWriter.h"

static
BOOL
maxvid_calculate_delta_pixels(NSArray *deltaPixels,
                              int bpp,
                              NSMutableData *mData,
                              NSUInteger frameBufferNumPixels);

// Testing indicates that there is no performance improvement in emitting ARM code for this
// encode module.

//#define EXTRA_CHECKS 1

#ifndef __OPTIMIZE__
// Automatically define EXTRA_CHECKS when not optimizing (in debug mode)
# define EXTRA_CHECKS
#endif // DEBUG

#define MAXVID_ASSERT(cond, str) assert(cond)

// Define conditional macro that will assert in debug mode, or return an error code in optimized mode

#if defined(EXTRA_CHECKS)
# define EXTRA_RETURN(code) \
assert(0); \
return code;
#else
# define EXTRA_RETURN(code) \
return code;
#endif // EXTRA_CHECKS

static inline
int
fwrite_word(FILE *fp, uint32_t word) {
  size_t size = fwrite(&word, sizeof(uint32_t), 1, fp);
  if (size != 1) {
    return MV_ERROR_CODE_WRITE_FAILED;
  }
  return 0;
}

static inline
int
fwrite_half_word(FILE *fp, uint16_t hw) {
  size_t size = fwrite(&hw, sizeof(uint16_t), 1, fp);
  if (size != 1) {
    return MV_ERROR_CODE_WRITE_FAILED;
  }
  return 0;
}

static inline
int
fwrite_byte(FILE *fp, uint8_t b) {
  size_t size = fwrite(&b, sizeof(uint8_t), 1, fp);
  if (size != 1) {
    return MV_ERROR_CODE_WRITE_FAILED;
  }
  return 0;
}

// util to test evenness

static inline
int is_even(uint32_t num) {
  return (num % 2) == 0;
}

static inline
int is_black_16bpp(uint16_t pixel) {
  return (pixel == 0);
}

static inline
int is_white_16bpp(uint16_t pixel) {
  // (A)RGB555 or RGB565
  return (pixel == 0x7FFF) || (pixel == 0xFFFF);
}

static inline
uint32_t num_words_16bpp(uint32_t numPixels) {
  // Return the number of words required to contain
  // the given number of pixels.
  return (numPixels >> 1) + (numPixels & 0x1);
}

// Query open file size, then rewind to start

static
int fpsize(FILE *fp, uint32_t *filesize) {
  int retcode;
  retcode = fseek(fp, 0, SEEK_END);
  assert(retcode == 0);
  uint32_t size = ftell(fp);
  *filesize = size;
  fseek(fp, 0, SEEK_SET);
  return 0;
}

// Util struct/object used only in this module

@interface DeltaPixel : NSObject {
@public
	uint32_t x;
	uint32_t y;
	uint32_t offset;
	uint32_t oldValue;
	uint32_t newValue;  
}
@end

// Scan for next generic op code, one of (SKIP, DUP, COPY, DONE)
//
// These methods do not change the input Buffer, it simply
// examines the next word for the op code.

static inline
MV_GENERIC_CODE
maxvid_encode_sample16_generic_nextcode(const uint32_t inword)
{
  MV16_READ_OP_VAL_NUM(inword, opCode, val, num);
  
  // Verify that the "num" field of a skip code word is larger than zero. Invalid input of
  // all zero bytes (skip == 0) is likely, so catch that error as quickly and directly as possible.

#ifdef EXTRA_CHECKS
  if (opCode == DONE) {
    assert(num == 0);
  } else {
    assert(num > 0);
  }
  assert(val == 0);
#endif
  
  return opCode;
}

static inline
MV_GENERIC_CODE
maxvid_encode_sample32_generic_nextcode(uint32_t inword)
{
  MV32_PARSE_OP_NUM_SKIP(inword, opCode, num, skip);
  
#ifdef EXTRA_CHECKS
  // Verify that the "num" field of a skip code word is larger than zero. Invalid input of
  // all zero bytes (skip == 0) is likely, so catch that error as quickly and directly as possible.
  
  if (opCode == DONE) {
    assert(num == 0);
  } else {
    assert(num > 0);
  }
  
  // SKIP can't also have an implicit skip after
  
  if (opCode == SKIP) {
    assert(skip == 0);
  }  
#endif
  
  return opCode;
}

// Read 1 to N 16 bit SKIP codes in the input buffer and figure out how many
// pixels to skip are indicated by the N codes.

static inline
int
maxvid_encode_sample16_generic_decode_skipcodes(
                                                const uint32_t * restrict inputBuffer32,
                                                uint32_t *inputBuffer32NumWordsRead,
                                                uint32_t inword,
                                                uint32_t *skipNumPixelsPtr)
{
  const uint32_t * restrict inputBuffer32Start = inputBuffer32;
  inputBuffer32++;
  uint32_t skipNumPixels = 0;
  
  while (1) {
    MV16_READ_OP_VAL_NUM(inword, opCode, val, num);

    if (opCode != SKIP) {
      if (skipNumPixels == 0) {
        EXTRA_RETURN(MV_ERROR_CODE_INVALID_INPUT);
      }
      
      inputBuffer32--;
      break;
    }
    
#if defined(EXTRA_CHECKS)
    assert(val == 0);
#endif // EXTRA_CHECKS
    
    if (num == 0) {
      EXTRA_RETURN(MV_ERROR_CODE_INVALID_INPUT);
    }
    
    // If the skip count is larger than MAX_27_BITS, then
    // the input data must have been corrupted somehow.
    // There is no way a set of skip operations could be
    // this large.
    
    uint32_t canAdd = MV_MAX_27_BITS - skipNumPixels;
    
    if ((skipNumPixels + num) > canAdd) {
      EXTRA_RETURN(MV_ERROR_CODE_INVALID_INPUT);
    }
    
    skipNumPixels += num;
    
    inword = *inputBuffer32++;
  }
    
  *inputBuffer32NumWordsRead = (inputBuffer32 - inputBuffer32Start);
  *skipNumPixelsPtr = skipNumPixels;
  return 0;
}

// Read 1 to N 32 bit SKIP codes in the input buffer and figure out how many
// pixels to skip are indicated by the N codes.

static inline
int
maxvid_encode_sample32_generic_decode_skipcodes(
                                                const uint32_t * restrict inputBuffer32,
                                                uint32_t *inputBuffer32NumWordsRead,
                                                uint32_t inword,
                                                uint32_t *skipNumPixelsPtr)
{
  const uint32_t * restrict inputBuffer32Start = inputBuffer32;
  inputBuffer32++;
  uint32_t skipNumPixels = 0;
  
  while (1) {
    MV32_PARSE_OP_NUM_SKIP(inword, opCode, num, skip);
    
    if (opCode != SKIP) {
      if (skipNumPixels == 0) {
        EXTRA_RETURN(MV_ERROR_CODE_INVALID_INPUT);
      }
      
      // Done condensing SKIP codes if we found something other than SKIP
      inputBuffer32--;
      break;
    }
    
    if (num == 0) {
      EXTRA_RETURN(MV_ERROR_CODE_INVALID_INPUT);
    }    
    
    // Generic skip value must always be zero
    
    if (skip != 0) {
      EXTRA_RETURN(MV_ERROR_CODE_INVALID_INPUT);
    }
    
    // If the skip count is larger than MAX_22_BITS, then
    // the input data must have been corrupted somehow.
    // There is no way a set of skip operations could be
    // this large.
    
    uint32_t canAdd = MV_MAX_22_BITS - skipNumPixels;
    
    if ((skipNumPixels + num) > canAdd) {
      EXTRA_RETURN(MV_ERROR_CODE_INVALID_INPUT);
    }
    
    skipNumPixels += num;
    
    inword = *inputBuffer32++;
  }
  
  *inputBuffer32NumWordsRead = (inputBuffer32 - inputBuffer32Start);
  *skipNumPixelsPtr = skipNumPixels;
  return 0;
}

// Condense multiple 16 bit DUP codes down into the largest single DUP that
// can be supported. Two DUP operations can only be combined if the pixel
// value is the same.

static inline
int
maxvid_encode_sample16_generic_decode_dupcodes(
                                               const uint32_t * restrict inputBuffer32,
                                               uint32_t *inputBuffer32NumWordsRead,
                                               uint32_t inword,
                                               uint32_t *dupNumPixelsPtr,
                                               uint16_t *dupPixelPtr)
{
  const uint32_t * restrict inputBuffer32Start = inputBuffer32;
  inputBuffer32++;
  uint32_t dupNumPixels = 0;
  uint32_t dupPixel = 0;
  uint32_t dupPixelSet = 0;
      
  // Iterate over N DUP codes to determine where the end of a series
  // of identical DUP codes is. A line oriented encoder might emit multiple
  // line repeat operations with the same pixel value, for example.
  
  while (1) {
    MV16_READ_OP_VAL_NUM(inword, opCode, val, num);
#if defined(EXTRA_CHECKS)
    assert(val == 0);
#endif
    
    if (opCode != DUP) {
      inputBuffer32--;
      break;
    }
        
    // Verify basic requirements about input data
    
    if (num < 2) {
      EXTRA_RETURN(MV_ERROR_CODE_INVALID_INPUT);
    }
    
    // 1 word implicitly follows a dup op
    
    uint32_t pixel32 = *inputBuffer32++;
    
    // The pixel values in the word must match
    
    if ((uint16_t)pixel32 != (uint16_t)(pixel32 >> 16)) {
      EXTRA_RETURN(MV_ERROR_CODE_INVALID_INPUT);
    }
    
    // DUP codes can't be combined if the pixel values don't match
    
    uint16_t pixel16 = (uint16_t) pixel32;

    if (!dupPixelSet) {
      dupPixel = pixel16;
      dupPixelSet = 1;
    } else {
      if (dupPixel != pixel16) {
        // DUP follows a previous DUP, but the pixel value is not the same.
        // rewind input buffer to the point before this DUP code.
        
        // FIXME: This seems wrong, why rewind 2 words when a DUP contains the pixel in 1 word?
        
        inputBuffer32 -= 2;
        break;
      }
    }
    
    // FIXME: use DUP max count logic from 32 bit version below.
    
    if (dupNumPixels == ~0) {
      // Already at the max number of pixels that can be represented in a 32 bit
      // integer, the input data must be invalid.
      EXTRA_RETURN(MV_ERROR_CODE_INVALID_INPUT);
    }
    dupNumPixels += num;
    
    inword = *inputBuffer32++;
  }

  // Can't DUP 0 pixels
  if (dupNumPixels == 0) {
    EXTRA_RETURN(MV_ERROR_CODE_INVALID_INPUT);
  }
  // Can't DUP just 1 pixel
  if (dupNumPixels == 1) {
    EXTRA_RETURN(MV_ERROR_CODE_INVALID_INPUT);
  }  
  
  *inputBuffer32NumWordsRead = (inputBuffer32 - inputBuffer32Start);
  *dupNumPixelsPtr = dupNumPixels;
  *dupPixelPtr = dupPixel;
  return 0;  
}

// Condense multiple 32 bit DUP codes down into the largest single DUP that
// can be supported. Two DUP operations can only be combined if the pixel
// value is the same.

static inline
int
maxvid_encode_sample32_generic_decode_dupcodes(
                                               const uint32_t * restrict inputBuffer32,
                                               uint32_t *inputBuffer32NumWordsRead,
                                               uint32_t inword,
                                               uint32_t *dupNumPixelsPtr,
                                               uint32_t *dupPixelPtr)
{
  const uint32_t * restrict inputBuffer32Start = inputBuffer32;
  inputBuffer32++;
  uint32_t dupNumPixels = 0;
  uint32_t dupPixel = 0;
  uint32_t dupPixelSet = 0;
  
  // Iterate over N DUP codes to determine where the end of a series
  // of identical DUP codes is. A line oriented encoder might emit multiple
  // line repeat operations with the same pixel value, for example.
  
  while (1) {
    MV32_PARSE_OP_NUM_SKIP(inword, opCode, num, skip);
    
    if (opCode != DUP) {
      inputBuffer32--;
      break;
    }
    
    // Verify basic requirements about input data
    
    if (num < 2) {
      EXTRA_RETURN(MV_ERROR_CODE_INVALID_INPUT);
    }
    
    // Generic skip value must always be zero
    
    if (skip != 0) {
      EXTRA_RETURN(MV_ERROR_CODE_INVALID_INPUT);
    }
    
    // 1 word implicitly follows a dup op (the 32 bit pixel)

    uint32_t pixel32 = *inputBuffer32++;
        
    // DUP codes can't be combined if the pixel values don't match
    
    if (!dupPixelSet) {
      dupPixel = pixel32;
      dupPixelSet = 1;
    } else {
      if (dupPixel != pixel32) {
        // DUP follows a previous DUP, but the pixel value is not the same.
        // rewind input buffer so it points to the start of this DUP code.
        
        inputBuffer32 -= 2;
        break;
      }
    }
    
    // Can combine a full 32 bit integer worth of DUP codes. The only thing to protect
    // against is overflow of the 32 bit number. This should never happen.
    
    uint32_t canAdd = ~((uint32_t)0) - dupNumPixels;

    if (num > canAdd) {
      // Adding num DUP pixels would overflow the 32 bit integer, ignore this DUP
      inputBuffer32 -= 2;
      break;      
    }
      
    dupNumPixels += num;
    
    inword = *inputBuffer32++;
  }
  
  // Can't DUP 0 pixels
  if (dupNumPixels == 0) {
    EXTRA_RETURN(MV_ERROR_CODE_INVALID_INPUT);
  }
  // Can't DUP just 1 pixel
  if (dupNumPixels == 1) {
    EXTRA_RETURN(MV_ERROR_CODE_INVALID_INPUT);
  }  
  
#if defined(EXTRA_CHECKS)
  assert((inputBuffer32 - inputBuffer32Start) > 0);
#endif
  
  *inputBuffer32NumWordsRead = (inputBuffer32 - inputBuffer32Start);
  *dupNumPixelsPtr = dupNumPixels;
  *dupPixelPtr = dupPixel;
  return 0;  
}

// Condense multiple 16 bit COPY codes down into the largest single COPY that
// can be supported. Any two COPY operations can be combined into a larger
// copy. Note that we can't actually do anything with the COPY pixels at this
// point, this logic can only count the total number of copies that could
// be combined in N codes.

static inline
int
maxvid_encode_sample16_generic_decode_copycodes(
                                               const uint32_t * restrict inputBuffer32,
                                               uint32_t *inputBuffer32NumWordsRead,
                                               uint32_t inword,
                                               uint32_t *copyNumPixelsPtr)
{
  const uint32_t * restrict inputBuffer32Start = inputBuffer32;
  inputBuffer32++;
  uint32_t copyNumPixels = 0;
  
  while (1) {
    MV16_READ_OP_VAL_NUM(inword, opCode, val, num);
    
    if (opCode != COPY) {
      inputBuffer32--;
      break;
    }
    
    if (val != 0) {
      EXTRA_RETURN(MV_ERROR_CODE_INVALID_INPUT);
    }
    if (num == 0) {
      EXTRA_RETURN(MV_ERROR_CODE_INVALID_INPUT);
    }
    
    // Don't exceed uint32_t limits when combining.
    // There is no way there is going to be this
    // much input, but protect against invalid
    // input data in any case.
    
    uint32_t canAdd = ~((uint32_t)0) - copyNumPixels;

    if (num > canAdd) {
      // FIXME: stop condesing COPY operations, don't fail in this case
      EXTRA_RETURN(MV_ERROR_CODE_INVALID_INPUT);
    }
    
    copyNumPixels += num;
    
    // "num" half words, padded to a whole word implicitly follow a copy op
    
    uint32_t numWords = num_words_16bpp(num);
    
    if (numWords == 0) {
      EXTRA_RETURN(MV_ERROR_CODE_INVALID_INPUT);
    }
    
    inputBuffer32 += numWords;
    
    inword = *inputBuffer32++;
  }
  
  if (copyNumPixels == 0) {
    EXTRA_RETURN(MV_ERROR_CODE_INVALID_INPUT);
  }
  
  *inputBuffer32NumWordsRead = (inputBuffer32 - inputBuffer32Start);
  *copyNumPixelsPtr = copyNumPixels;
  return 0;  
}

// Condense multiple 32 bit COPY codes down into the largest single COPY that
// can be supported. Any two COPY operations can be combined into a larger
// copy. Note that we can't actually do anything with the COPY pixels at this
// point, this logic can only count the total number of copies that could
// be combined in N codes.

static inline
int
maxvid_encode_sample32_generic_decode_copycodes(
                                                const uint32_t * restrict inputBuffer32,
                                                uint32_t *inputBuffer32NumWordsRead,
                                                uint32_t inword,
                                                uint32_t *copyNumPixelsPtr)
{
  const uint32_t * restrict inputBuffer32Start = inputBuffer32;
  inputBuffer32++;
  uint32_t copyNumPixels = 0;
  
  while (1) {
    MV32_PARSE_OP_NUM_SKIP(inword, opCode, num, skip);
    
    if (opCode != COPY) {
      inputBuffer32--;
      break;
    }
    
    if (skip != 0) {
      EXTRA_RETURN(MV_ERROR_CODE_INVALID_INPUT);
    }
    if (num == 0) {
      EXTRA_RETURN(MV_ERROR_CODE_INVALID_INPUT);
    }
    
    // Don't exceed uint32_t limits when combining.
    // There is no way there is going to be this
    // much input, but protect against invalid
    // input data in any case.
    
    uint32_t canAdd = ~((uint32_t)0) - copyNumPixels;
    
    if (num > canAdd) {
      // Combining this COPY would overflow the 32 bit integer, ignore this COPY
      // Note that no rewind of inputBuffer32 is needed since it has not been incremented.
      
      inputBuffer32--;
      break;      
    }
    
    copyNumPixels += num;
    
    // "num" whole words of pixel data follow the COPY op.
    
    inputBuffer32 += num;
    
    inword = *inputBuffer32++;
  }
  
  if (copyNumPixels == 0) {
    EXTRA_RETURN(MV_ERROR_CODE_INVALID_INPUT);
  }
  
#if defined(EXTRA_CHECKS)
  assert((inputBuffer32 - inputBuffer32Start) > 0);
#endif
  
  *inputBuffer32NumWordsRead = (inputBuffer32 - inputBuffer32Start);
  *copyNumPixelsPtr = copyNumPixels;
  return 0;  
}

// util helper to manage incoming COPY pixels from multiple codes.

typedef struct {
  const uint32_t * inputBuffer32;
  const uint32_t * originalInputBuffer32;
  uint32_t inputBuffer32NumWordsRead;
  uint16_t pixelBuffer[3];
  uint32_t pixelBufferLen;
  uint32_t numPixelsLeft;
  uint32_t numPixelsLeftThisSegment;
} Maxvid16PixelInCodeStruct;

// Init struct

static inline
void
maxvid16_pixelincode_init(Maxvid16PixelInCodeStruct *sPtr,
                          const uint32_t * restrict inputBuffer32,
                          const uint32_t inputBuffer32NumWordsRead,
                          const uint32_t copyNumPixels)
{
  sPtr->inputBuffer32 = inputBuffer32;
  sPtr->originalInputBuffer32 = inputBuffer32;  
  sPtr->inputBuffer32NumWordsRead = inputBuffer32NumWordsRead;
  sPtr->pixelBufferLen = 0;
  sPtr->numPixelsLeft = copyNumPixels;
  sPtr->numPixelsLeftThisSegment = 0;
}

// Read a word of pixel data from input and save pixels into tmp buffer.

static inline
void
maxvid16_pixelincode_read_word(Maxvid16PixelInCodeStruct *sPtr)
{
  // Read a word from input stream, could contain 1 or 2 pixels.
  
#if defined(EXTRA_CHECKS)
  assert(sPtr->numPixelsLeftThisSegment > 0);
#endif
  
  uint32_t nextWord = *sPtr->inputBuffer32++;
  uint16_t nextPixel1 = (uint16_t) nextWord;
  uint16_t nextPixel2 = (uint16_t) (nextWord >> 16);
  
  if (sPtr->numPixelsLeftThisSegment == 1) {
    // read 1 pixel
    sPtr->pixelBuffer[sPtr->pixelBufferLen] = nextPixel1;
    sPtr->pixelBufferLen++;
    // The second half word must be zero padding
#if defined(EXTRA_CHECKS)
    assert(nextPixel2 == 0);
#endif
    sPtr->numPixelsLeftThisSegment--;
  } else {
    // read 2 pixels
#if defined(EXTRA_CHECKS)
    assert(sPtr->pixelBufferLen < 2);
#endif
    sPtr->pixelBuffer[sPtr->pixelBufferLen] = nextPixel1;
    sPtr->pixelBufferLen++;
    sPtr->pixelBuffer[sPtr->pixelBufferLen] = nextPixel2;
    sPtr->pixelBufferLen++;
#if defined(EXTRA_CHECKS)
    assert(sPtr->numPixelsLeftThisSegment >= 2);
#endif
    sPtr->numPixelsLeftThisSegment -= 2;
  }
}  

static inline
void
maxvid16_pixelincode_pushback_pixel(Maxvid16PixelInCodeStruct *sPtr, const uint16_t pixel)
{
#if defined(EXTRA_CHECKS)
  assert(sPtr->pixelBufferLen <= 2);
#endif
  if (sPtr->pixelBufferLen == 2) {
    sPtr->pixelBuffer[2] = sPtr->pixelBuffer[1];
    sPtr->pixelBuffer[1] = sPtr->pixelBuffer[0];
    sPtr->pixelBuffer[0] = pixel;
  } else if (sPtr->pixelBufferLen == 1) {
    sPtr->pixelBuffer[1] = sPtr->pixelBuffer[0];
    sPtr->pixelBuffer[0] = pixel;
  } else if (sPtr->pixelBufferLen == 0) {
    sPtr->pixelBuffer[0] = pixel;
  }
  sPtr->pixelBufferLen++;
  sPtr->numPixelsLeft++;
}

// Read a word that contains 2 pixels. The final pixel has
// a trailing zero padding added if only a single pixel.

static inline
uint32_t
maxvid16_pixelincode_next_word(
                               Maxvid16PixelInCodeStruct *sPtr,
                               uint32_t *numPixelsWrittenPtr)
{
  int readNextSegment = 0;
#if defined(EXTRA_CHECKS)
  assert(sPtr->pixelBufferLen == 0 || sPtr->pixelBufferLen == 1 || sPtr->pixelBufferLen == 2);
#endif
  
// FIXME: 3rd shoudl be just
// (sPtr->pixelBufferLen < sPtr->numPixelsLeft)
// Instead of:
// ((sPtr->pixelBufferLen == 0) || (sPtr->pixelBufferLen < sPtr->numPixelsLeft))

NEXTSEGMENT:
  if ((sPtr->numPixelsLeftThisSegment == 0) &&
      (sPtr->numPixelsLeft > 0) &&
      (sPtr->pixelBufferLen < sPtr->numPixelsLeft)) {
    // No more pixels, but more in the following segment. This logic is also used to fill
    // the buffer the firt time a word is read.
    
#ifdef EXTRA_CHECKS
    MAXVID_ASSERT((sPtr->inputBuffer32 - sPtr->originalInputBuffer32) < sPtr->inputBuffer32NumWordsRead, "exceeded num words");
#endif        

    uint32_t inword = *sPtr->inputBuffer32++;
    
    MV16_READ_OP_VAL_NUM(inword, opCode, val, num);
    //opCode + 0;
    //val + 0;
    
#ifdef EXTRA_CHECKS
    assert(val == 0);
    MAXVID_ASSERT(opCode == COPY, "opCode");
#endif    
    
    sPtr->numPixelsLeftThisSegment = num;
    
#if defined(EXTRA_CHECKS)
    assert(sPtr->numPixelsLeftThisSegment != 0);
#endif
  }

  // Read a word of input, this could read 1 or 2 pixels.
  
  if (sPtr->pixelBufferLen < 2 && (sPtr->pixelBufferLen < sPtr->numPixelsLeft)) {
    maxvid16_pixelincode_read_word(sPtr);
  }
    
  // Special case where only 1 pixel of input remains
  
  if (sPtr->numPixelsLeft == 1) {
#if defined(EXTRA_CHECKS)
    assert(sPtr->pixelBufferLen == 1);
#endif
    uint16_t nextPixel1 = sPtr->pixelBuffer[0];
    uint16_t nextPixel2 = 0;
    sPtr->pixelBufferLen = 0;
    uint32_t nextWord = (nextPixel2 << 16) | nextPixel1;
    sPtr->numPixelsLeft--;
    *numPixelsWrittenPtr = 1;
    return nextWord;
  }

  // If too few pixels in this segment, then continue
  // with the next segment.

  if (sPtr->pixelBufferLen < 2) {
#if defined(EXTRA_CHECKS)
    assert(readNextSegment == 0);
#endif
    readNextSegment = 1;
    goto NEXTSEGMENT;
  }
  
#if defined(EXTRA_CHECKS)
  assert(sPtr->pixelBufferLen >= 2);
#endif
  
  // Now return a single word and remove 2 pixels from the buffer
  
  uint16_t nextPixel1 = sPtr->pixelBuffer[0];
  uint16_t nextPixel2 = sPtr->pixelBuffer[1];
  uint32_t nextWord = (nextPixel2 << 16) | nextPixel1;
  
#if defined(EXTRA_CHECKS)
  assert(sPtr->numPixelsLeft >= 2);
#endif
  sPtr->numPixelsLeft -= 2;

  if (sPtr->pixelBufferLen == 3) {
    sPtr->pixelBufferLen = 1;
    sPtr->pixelBuffer[0] = sPtr->pixelBuffer[2];
  } else {
    sPtr->pixelBufferLen = 0;
  }
  
  *numPixelsWrittenPtr = 2;
  return nextWord;
}

// Emit SKIP "c4" code(s) to skip over the indicated number of pixels

static inline
int
maxvid_encode_sample16_c4_encode_skipcodes(FILE *fp, uint32_t encodeFlags,
                                           uint32_t *pixelsWrittenPtr,
                                           const uint32_t skipNumPixels)
{
  uint32_t pixelsWritten = *pixelsWrittenPtr;
#if defined(EXTRA_CHECKS)
  uint32_t originalPixelsWritten = pixelsWritten;
#endif
  
  // code is 2 bits, skip num is 30 bits.
  
  uint32_t wholeNum = (skipNumPixels & MV_MAX_30_BITS);
  if (wholeNum != skipNumPixels) {
    EXTRA_RETURN(MV_ERROR_CODE_INVALID_INPUT);
  }
  MV_GENERIC_CODE opCode = SKIP;
  uint16_t numPart = ((wholeNum >> 16) & 0xFFFF);
  uint16_t pixelPart = (wholeNum & 0xFFFF);
  uint32_t skipCode = maxvid16_c4_code(opCode, numPart, pixelPart);    

#ifdef EXTRA_CHECKS
  uint32_t opCodeDecoded = (skipCode >> (16 + 14));
  assert(opCodeDecoded == opCode);
  assert(skipCode == wholeNum);
#endif

  int status = fwrite_word(fp, skipCode);
  if (status) {
    return status;
  }
  
  pixelsWritten += skipNumPixels;
  
#if defined(EXTRA_CHECKS)
  assert((pixelsWritten - originalPixelsWritten) == skipNumPixels);
#endif
  *pixelsWrittenPtr = pixelsWritten;
  return 0;
}

// Emit DUP "c4" code(s) to dup N instances of the indicated pixel value.

static inline
int
maxvid_encode_sample16_c4_encode_dupcodes(FILE *fp, uint32_t encodeFlags,
                                          uint32_t *pixelsWrittenPtr,
                                          const uint32_t dupNumPixels,
                                          const uint16_t dupPixel)
{
  uint32_t pixelsWritten = *pixelsWrittenPtr;
#if defined(EXTRA_CHECKS)
  uint32_t originalPixelsWritten = pixelsWritten;
#endif
  
  // each dup code can store a maximum of 14 bits worth of pixels.
  
  const uint32_t maxDupNumPixels = MV_MAX_14_BITS;
  
  uint32_t dupCountLeft = dupNumPixels;
  while (dupCountLeft > 0) {
    uint32_t dupCountThisLoop;
    
    if (dupCountLeft > maxDupNumPixels) {
      dupCountThisLoop = maxDupNumPixels;
    } else {
      dupCountThisLoop = dupCountLeft;
    }
    
    MV_GENERIC_CODE opCode = DUP;
    uint32_t dupCode = maxvid16_c4_code(opCode, dupCountThisLoop, dupPixel);

#ifdef EXTRA_CHECKS
    uint32_t opCodeDecoded = (dupCode >> (16 + 14));
    assert(opCodeDecoded == opCode);
    uint32_t numPartDecoded = ((dupCode << 2) >> 2+16);
    assert(numPartDecoded == dupCountThisLoop);
    uint16_t pixelPartDecoded = (uint16_t)dupPixel;
    assert(pixelPartDecoded == dupPixel);
#endif    
    
    int status = fwrite_word(fp, dupCode);
    if (status) {
      return status;
    }
    
    dupCountLeft -= dupCountThisLoop;
    pixelsWritten += dupCountThisLoop;
  }
  
#if defined(EXTRA_CHECKS)
  assert((pixelsWritten - originalPixelsWritten) == dupNumPixels);
#endif
  *pixelsWrittenPtr = pixelsWritten;
  
  return 0;
}

// Emit "c4" COPY op, if framebuffer is half word aligned then emit an initial
// 16 bit value to word align the framebuffer.

static inline
int
maxvid_encode_sample16_c4_encode_copycodes(FILE *fp, uint32_t encodeFlags,
                                           const uint32_t * restrict inputBuffer32,
                                           const uint32_t inputBuffer32NumWordsRead,
                                           uint32_t *pixelsWrittenPtr,
                                           const uint32_t copyNumPixels)
{
  uint32_t pixelsWritten = *pixelsWrittenPtr;
#ifdef EXTRA_CHECKS
  uint32_t originalPixelsWritten = pixelsWritten;
#endif
  
  // Break copies into chunks taking the copy "num" max into account. The tricky part
  // about this logic is dealing with the fact that the original copy operations could
  // have an odd number of copies that are word padded.
  
  Maxvid16PixelInCodeStruct mvPic;
  Maxvid16PixelInCodeStruct *mvPicPtr = &mvPic;
  maxvid16_pixelincode_init(mvPicPtr, inputBuffer32, inputBuffer32NumWordsRead, copyNumPixels);
  
  const uint32_t maxCopyPixelsNum = MV_MAX_14_BITS;
  
  for (uint32_t copyCountLeft = copyNumPixels; copyCountLeft; ) {
    uint32_t copyCountThisLoop;
    
    if (copyCountLeft > maxCopyPixelsNum) {
      copyCountThisLoop = maxCopyPixelsNum;
    } else {
      copyCountThisLoop = copyCountLeft;
    }
    
    uint32_t numPart = (copyCountThisLoop & MV_MAX_14_BITS);
    if (numPart != copyCountThisLoop) {
      EXTRA_RETURN(MV_ERROR_CODE_INVALID_INPUT);
    }
    
    uint32_t numPixelsWrittenThisLoop = 0;
    
    uint16_t copyPixel = 0;
    if (!is_even(pixelsWritten) || (mvPicPtr->numPixelsLeft == 1)) {
      // framebuffer is half word aligned, grab first pixel from the
      // stream of pixels to copy and stuff it into the "num" field
      // in the first word. The writing logic is a lot faster if
      // pairs of pixels being read are word aligned, so the initial
      // pixel used to align the framebuffer has a large performance impact.
            
      uint32_t numPixelWritten = 0;
      uint32_t nextWord = maxvid16_pixelincode_next_word(mvPicPtr, &numPixelWritten);
      
      uint16_t nextPixel1 = (uint16_t) nextWord;
      uint16_t nextPixel2 = (uint16_t) (nextWord >> 16);
      
      copyPixel = nextPixel1;
      
      if (numPixelWritten == 2) {
        maxvid16_pixelincode_pushback_pixel(mvPicPtr, nextPixel2);
      }

#ifdef EXTRA_CHECKS
      MAXVID_ASSERT(copyCountThisLoop > 0, "underflow");
      MAXVID_ASSERT(copyCountLeft > 0, "underflow");
#endif

      numPixelsWrittenThisLoop += 1;
    }
    
    copyCountLeft -= copyCountThisLoop;
    
    MV_GENERIC_CODE opCode = COPY;
    uint32_t copyCode = maxvid16_c4_code(opCode, numPart, copyPixel);
    
#ifdef EXTRA_CHECKS
    uint32_t opCodeDecoded = (copyCode >> (16 + 14));
    assert(opCodeDecoded == opCode);
    uint32_t numPartDecoded = ((copyCode << 2) >> 2+16);
    assert(numPartDecoded == numPart);
    uint16_t pixelPartDecoded = (uint16_t)copyCode;
    assert(pixelPartDecoded == copyPixel);
#endif    
    
    int status;
    if ((status = fwrite_word(fp, copyCode))) {
      return status;
    }
    
    // Copy N pixels from inputBuffer32 to the output stream as whole words.
    
    while (mvPicPtr->numPixelsLeft > 0)
    {
      uint32_t numPixelWritten = 0;
      uint32_t nextWord = maxvid16_pixelincode_next_word(mvPicPtr, &numPixelWritten);
      
      int status;
      if ((status = fwrite_word(fp, nextWord))) {
        return status;
      }
      
      numPixelsWrittenThisLoop += numPixelWritten;
    } // while loop
    
    // Done writing pixels after the op code.
    
#if defined(EXTRA_CHECKS)
    assert(numPixelsWrittenThisLoop == copyCountThisLoop);
#endif
    pixelsWritten += numPixelsWrittenThisLoop;

#if defined(EXTRA_CHECKS)
    assert(mvPicPtr->numPixelsLeft == 0);
    assert(mvPicPtr->pixelBufferLen == 0);
#endif
  }

#ifdef EXTRA_CHECKS
  uint32_t numPixelsWritten = (pixelsWritten - originalPixelsWritten);
  MAXVID_ASSERT(numPixelsWritten == copyNumPixels, "copyNumPixels");
  assert((pixelsWritten - originalPixelsWritten) == copyNumPixels);
#endif

  *pixelsWrittenPtr = pixelsWritten;
  return 0;
}

// Emit DONE "c4" code at the end of a framebuffer.

static inline
int
maxvid_encode_sample16_c4_encode_donecode(FILE *fp, uint32_t encodeFlags)
{
  uint32_t numPart = 0;
  MV_GENERIC_CODE opCode = DONE;
  
  uint32_t doneCode = (opCode << 30) | numPart;  
  
  return fwrite_word(fp, doneCode);
}

// maxvid_encode_c4_sample16()
//
// encode pixel stream as "c4", there are only 4 conditions in
// this encoding (SKIP, DUP, COPY, DONE).

// At a high level, encoding is a process of combining input
// codes that are the same, then processing the combined
// values and emitting from that. Input is an array of
// words, parsed into pointers to elements. Need to be
// able to read and validate the input, one framebuffer at
// a time?

int
maxvid_encode_c4_sample16(
                          const uint32_t * restrict inputBuffer32,
                          const uint32_t inputBufferNumWords,
                          const uint32_t frameBufferNumPixels,
                          const char * restrict filePath,
                          FILE * restrict file,
                          const uint32_t encodeFlags)
{
  uint32_t retcode = 0;
  
#ifdef EXTRA_CHECKS
  const int pagesize = getpagesize();
  MAXVID_ASSERT(pagesize == MV_PAGESIZE, "pagesize");
  MAXVID_ASSERT(inputBuffer32, "inputBuffer32");
  // The input buffer must be word aligned
  MAXVID_ASSERT(UINTMOD(inputBuffer32, sizeof(uint32_t)) == 0, "inputBuffer32 initial alignment");
  MAXVID_ASSERT(inputBufferNumWords > 0, "inputBufferNumWords");
  MAXVID_ASSERT(frameBufferNumPixels > 0, "frameBufferNumPixels");
  const uint32_t * restrict originalInputBuffer32 = inputBuffer32;
  // Verify that the DONE code appears at the end of the input
  const uint32_t * restrict inputBuffer32Max = originalInputBuffer32 + inputBufferNumWords;
  {
    uint32_t word = *(inputBuffer32Max - 1);
    MV16_READ_OP_VAL_NUM(word, op, val, num);
    assert(op == DONE);
  }  
#endif

  int didOpenFile = 0;
  
  if (file == NULL) {
    file = fopen(filePath, "w");
    if (file == NULL) {
      return MV_ERROR_CODE_INVALID_FILENAME;
    }
    didOpenFile = 1;
  }
  
  const uint32_t maxNumPixels = frameBufferNumPixels;
  uint32_t pixelsWritten = 0;
  
  while (1) {
#ifdef EXTRA_CHECKS
    uint32_t wordOffset = (inputBuffer32 - originalInputBuffer32);    
    MAXVID_ASSERT(wordOffset < inputBufferNumWords, "read past indicated inputBufferNumWords");
#endif
    
#undef RETCODE
#define RETCODE(status) \
if (status != 0) { \
retcode = status; \
goto done; \
}
    
    int status = 0;
    uint32_t inword = *inputBuffer32;
    MV_GENERIC_CODE code = maxvid_encode_sample16_generic_nextcode(inword);
    
    if (code == SKIP) {
      uint32_t skipNumPixels;
      uint32_t inputBuffer32NumWordsRead;
      
      status = maxvid_encode_sample16_generic_decode_skipcodes(inputBuffer32, &inputBuffer32NumWordsRead, inword, &skipNumPixels);
      RETCODE(status);
      
      status = maxvid_encode_sample16_c4_encode_skipcodes(file, encodeFlags, &pixelsWritten, skipNumPixels);
      RETCODE(status);
      
      inputBuffer32 += inputBuffer32NumWordsRead;
    } else if (code == DUP) {
      uint32_t dupNumPixels;
      uint16_t dupPixel;
      uint32_t inputBuffer32NumWordsRead;
      
      status = maxvid_encode_sample16_generic_decode_dupcodes(inputBuffer32, &inputBuffer32NumWordsRead, inword,
                                                              &dupNumPixels, &dupPixel);
      RETCODE(status);
      
      status = maxvid_encode_sample16_c4_encode_dupcodes(file, encodeFlags, &pixelsWritten, dupNumPixels, dupPixel);
      RETCODE(status);
      
      inputBuffer32 += inputBuffer32NumWordsRead;      
    } else if (code == COPY) {
      uint32_t copyNumPixels;
      uint32_t inputBuffer32NumWordsRead;
      
      status = maxvid_encode_sample16_generic_decode_copycodes(inputBuffer32, &inputBuffer32NumWordsRead, inword,
                                                               &copyNumPixels);
      RETCODE(status);
            
      status = maxvid_encode_sample16_c4_encode_copycodes(file, encodeFlags,
                                                          inputBuffer32, inputBuffer32NumWordsRead,
                                                          &pixelsWritten,
                                                          copyNumPixels);
      RETCODE(status);
      
      inputBuffer32 += inputBuffer32NumWordsRead;
    } else if (code == DONE) {
      status = maxvid_encode_sample16_c4_encode_donecode(file, encodeFlags);
      RETCODE(status);
      inputBuffer32 += 1;
      
#ifdef EXTRA_CHECKS
      MAXVID_ASSERT((inputBuffer32 - originalInputBuffer32) == inputBufferNumWords, "end of input buffer");
#endif      
      
      if (pixelsWritten != maxNumPixels) {
        // Even if EXTRA_CHECKS is not compiled in, return an error if
        // the logic did not fully write the framebuffer.
        status = MV_ERROR_CODE_INVALID_INPUT;
        RETCODE(status);
      }
      
      goto done;
    } else {
      assert(0);
    }
    
    if (pixelsWritten > maxNumPixels) {
      status = MV_ERROR_CODE_INVALID_INPUT;
      RETCODE(status);
    }
  }
  
done:
#if defined(EXTRA_CHECKS)
  assert(file);
#endif
  if (didOpenFile) {
    fclose(file);
  }
  
  return retcode;  
}

// Emit 24/32 bit c4 SKIP code(s) to skip over the indicated number of pixels

static inline
int
maxvid_encode_sample32_c4_encode_skipcodes(FILE *fp, uint32_t encodeFlags,
                                           uint32_t *pixelsWrittenPtr,
                                           const uint32_t skipNumPixels)
{
  uint32_t pixelsWritten = *pixelsWrittenPtr;
#if defined(EXTRA_CHECKS)
  uint32_t originalPixelsWritten = pixelsWritten;
#endif
  
  // code is 2 bits, skip num is 22 bits
  
  uint32_t wholeNum = (skipNumPixels & MV_MAX_22_BITS);
  if (wholeNum != skipNumPixels) {
    EXTRA_RETURN(MV_ERROR_CODE_INVALID_INPUT);
  }  
  uint32_t skipCode = maxvid32_code(SKIP, skipNumPixels);
  
  int status = fwrite_word(fp, skipCode);
  if (status) {
    return status;
  }
  
  pixelsWritten += skipNumPixels;
  
#if defined(EXTRA_CHECKS)
  assert((pixelsWritten - originalPixelsWritten) == skipNumPixels);
#endif
  *pixelsWrittenPtr = pixelsWritten;
  return 0;
}

// Emit 24/32 bit DUP c4 code(s) to dup N instances of the indicated pixel value.

static inline
int
maxvid_encode_sample32_c4_encode_dupcodes(FILE *fp, uint32_t encodeFlags,
                                          uint32_t *pixelsWrittenPtr,
                                          const uint32_t dupNumPixels,
                                          const uint32_t dupPixel,
                                          const uint32_t skipAfter)
{
  uint32_t pixelsWritten = *pixelsWrittenPtr;
#if defined(EXTRA_CHECKS)
  uint32_t originalPixelsWritten = pixelsWritten;
#endif
  uint32_t skipAfterThisLoop = skipAfter;
  
  // each dup code can store a maximum of 22 bits worth of numPixels
  
  const uint32_t maxDupNumPixels = MV_MAX_22_BITS;
  
  uint32_t dupCountLeft = dupNumPixels;
  while (dupCountLeft > 0) {
    uint32_t dupCountThisLoop;
    
    if (dupCountLeft > maxDupNumPixels) {
      dupCountThisLoop = maxDupNumPixels;
    } else {
      dupCountThisLoop = dupCountLeft;
    }

    uint32_t dupCode = maxvid32_internal_code(DUP, dupCountThisLoop, skipAfterThisLoop);
    if (skipAfterThisLoop != 0) {
      pixelsWritten += skipAfterThisLoop;
      skipAfterThisLoop = 0;
    }
    
    int status = fwrite_word(fp, dupCode);
    if (status) {
      return status;
    }
    
    // Write the pixel
    
    status = fwrite_word(fp, dupPixel);
    if (status) {
      return status;
    }
    
    dupCountLeft -= dupCountThisLoop;
    pixelsWritten += dupCountThisLoop;
  }
  
#if defined(EXTRA_CHECKS)
  assert((pixelsWritten - originalPixelsWritten) == (dupNumPixels + skipAfter));
#endif
  *pixelsWrittenPtr = pixelsWritten;
  
  return 0;
}

// Emit 24/32 bit c4 COPY codes. Note that a COPY always has at least 1 word
// following it, even in the optimized COPY1 case.

static inline
int
maxvid_encode_sample32_c4_encode_copycodes(FILE *fp, uint32_t encodeFlags,
                                           const uint32_t * restrict inputBuffer32,
                                           const uint32_t inputBuffer32NumWordsRead,
                                           uint32_t *pixelsWrittenPtr,
                                           const uint32_t copyNumPixels,
                                           const uint32_t skipAfter)
{
  uint32_t pixelsWritten = *pixelsWrittenPtr;
#if defined(EXTRA_CHECKS)
  uint32_t originalPixelsWritten = pixelsWritten;
#endif
  uint32_t skipAfterThisLoop = skipAfter;
  
#ifdef EXTRA_CHECKS
  const uint32_t *inputBuffer32Max = inputBuffer32 + inputBuffer32NumWordsRead;
#endif
  
  // Break copies into chunks taking the copy "num" max into account.
    
  const uint32_t maxCopyPixelsNum = MV_MAX_22_BITS;
  
  for (uint32_t copyCountLeft = copyNumPixels; copyCountLeft; ) {
    uint32_t copyCountThisLoop;
    
    if (copyCountLeft > maxCopyPixelsNum) {
      copyCountThisLoop = maxCopyPixelsNum;
    } else {
      copyCountThisLoop = copyCountLeft;
    }
    
#ifdef EXTRA_CHECKS
    assert(copyCountThisLoop > 0);
    assert((copyCountThisLoop & MV_MAX_22_BITS) == copyCountThisLoop);
#endif
    
    uint32_t numPixelsWrittenThisLoop = 0;
        
    copyCountLeft -= copyCountThisLoop;
    
    uint32_t copyCode = maxvid32_internal_code(COPY, copyCountThisLoop, skipAfterThisLoop);
    if (skipAfterThisLoop != 0) {
      pixelsWritten += skipAfterThisLoop;
      skipAfterThisLoop = 0;
    }    
    
    int status;
    if ((status = fwrite_word(fp, copyCode))) {
      return status;
    }
    
    // Copy a total of copyCountThisLoop pixels from N code/pixel segments.
    
    uint32_t numPixels = copyCountThisLoop;
    uint32_t numPixelsThisSegment = 0;
    
    do {
      if (numPixelsThisSegment == 0) {
#ifdef EXTRA_CHECKS
        MAXVID_ASSERT(inputBuffer32 < inputBuffer32Max, "exceeded num words in COPY");
#endif
        
        uint32_t word = *inputBuffer32;
        MV32_PARSE_OP_NUM_SKIP(word, opCode, num, skip);
        
        // Validate contents of word, to avoid parsing pixel data in case of wrong index

        if (opCode != COPY) {
          EXTRA_RETURN(MV_ERROR_CODE_INVALID_INPUT);
        }

#ifdef EXTRA_CHECKS
        if (opCode != COPY) {
          assert(0);
        }
        if (num == 0) {
          assert(0);
        }
        if (skip != 0) {
          assert(0);
        }
#endif
        
        numPixelsThisSegment = num;
        
        inputBuffer32++;
      }
      
      uint32_t pixel = *inputBuffer32++;
      
      int status;
      if ((status = fwrite_word(fp, pixel))) {
        return status;
      }
      
      numPixelsWrittenThisLoop += 1;
      numPixelsThisSegment -= 1;
    } while (--numPixels != 0);
     
    // Done writing pixels after the op code.
    
#ifdef EXTRA_CHECKS
    assert(numPixelsWrittenThisLoop == copyCountThisLoop);
#endif
    pixelsWritten += numPixelsWrittenThisLoop;    
  }
  
#ifdef EXTRA_CHECKS
  uint32_t numPixelsWritten = (pixelsWritten - originalPixelsWritten);
  MAXVID_ASSERT(numPixelsWritten == (copyNumPixels + skipAfter), "copyNumPixels");
  assert((pixelsWritten - originalPixelsWritten) == (copyNumPixels + skipAfter));
#endif  
  
  *pixelsWrittenPtr = pixelsWritten;
  return 0;
}

// Emit 24/32 bit c4 DONE code at the end of a framebuffer. Note that
// a DONE code is always passed with an extra zero word.

static inline
int
maxvid_encode_sample32_c4_encode_donecode(FILE *fp, uint32_t encodeFlags)
{
  uint32_t doneCode = maxvid32_code(DONE, 0);
  
  int status = fwrite_word(fp, doneCode);
  if (status != 0) {
    return status;
  }
  
  // DONE is always followed by a zero word of padding

  return fwrite_word(fp, 0);
}

// maxvid_encode_c4_sample32()
//
// encode generic code stream using 24/32 bit c4 encoding (SKIP, DUP, COPY, DONE).

// At a high level, encoding is a process of combining input
// codes that are the same, then processing the combined
// values and emitting from that. Input is an array of
// words, parsed into pointers to elements. Need to be
// able to read and validate the input, one framebuffer at
// a time?

// FIXME: 2^18 or 2^20 is the most pixels that could really
// appear in even the largest framebuffer. Likely using
// more that 18 or 19 pixels is a waste if the bits could
// be used for something. Even a huge 2000x2000 is about
// 20 bits worth of pixels max.

int
maxvid_encode_c4_sample32(
                          const uint32_t * restrict inputBuffer32,
                          const uint32_t inputBufferNumWords,
                          const uint32_t frameBufferNumPixels,
                          const char * restrict filePath,
                          FILE * restrict file,
                          const uint32_t encodeFlags)
{
  uint32_t retcode = 0;
  
#ifdef EXTRA_CHECKS
  const int pagesize = getpagesize();
  MAXVID_ASSERT(pagesize == MV_PAGESIZE, "pagesize");
  MAXVID_ASSERT(inputBuffer32, "inputBuffer32");
  // The input buffer must be word aligned
  MAXVID_ASSERT(UINTMOD(inputBuffer32, sizeof(uint32_t)) == 0, "inputBuffer32 initial alignment");
  MAXVID_ASSERT(inputBufferNumWords > 0, "inputBufferNumWords");
  MAXVID_ASSERT(frameBufferNumPixels > 0, "frameBufferNumPixels");
  const uint32_t * restrict originalInputBuffer32 = inputBuffer32;
  
  // Verify that the DONE code appears at the end of the input
  const uint32_t * restrict inputBuffer32Max = originalInputBuffer32 + inputBufferNumWords;
  {
    uint32_t word = *(inputBuffer32Max - 1);
    MV32_PARSE_OP_NUM_SKIP(word, opVal, numVal, skipVal);
    assert(opVal == DONE);
  }
#endif
 
  int didOpenFile = 0;
  
  if (file == NULL) {
    // If NULL is passed as file argument, then open a few file for writing.
    // Otherwise, use an existing FILE and append to the current file location.
    file = fopen(filePath, "w");
    if (file == NULL) {
      return MV_ERROR_CODE_INVALID_FILENAME;
    }
    didOpenFile = 1;
  }
  
  const uint32_t maxNumPixels = frameBufferNumPixels;
  uint32_t pixelsWritten = 0;
  uint32_t skipAfterNumPixels = 0;
  
  while (1) {
#ifdef EXTRA_CHECKS
    uint32_t wordOffset = (inputBuffer32 - originalInputBuffer32);    
    MAXVID_ASSERT(wordOffset < inputBufferNumWords, "read past indicated inputBufferNumWords");
#endif
    
#undef RETCODE
#define RETCODE(status) \
if (status != 0) { \
retcode = status; \
goto done; \
}
    
    int status = 0;
    
    if (skipAfterNumPixels != 0) {
      // Emit any left over SKIP value in the event that a big skip could not be folded into a DUP or COPY op

      status = maxvid_encode_sample32_c4_encode_skipcodes(file, encodeFlags, &pixelsWritten, skipAfterNumPixels);
      RETCODE(status);
      
      skipAfterNumPixels = 0;
    }

#ifdef EXTRA_CHECKS
    MAXVID_ASSERT(skipAfterNumPixels == 0, "skipAfterNumPixels");
#endif
    
    uint32_t inword = *inputBuffer32;
    MV_GENERIC_CODE code = maxvid_encode_sample32_generic_nextcode(inword);
    
    if (code == SKIP) {
      uint32_t skipNumPixels;
      uint32_t inputBuffer32NumWordsRead;
      
      status = maxvid_encode_sample32_generic_decode_skipcodes(inputBuffer32, &inputBuffer32NumWordsRead, inword, &skipNumPixels);
      RETCODE(status);
      
      status = maxvid_encode_sample32_c4_encode_skipcodes(file, encodeFlags, &pixelsWritten, skipNumPixels);
      RETCODE(status);
      
      inputBuffer32 += inputBuffer32NumWordsRead;      
    } else if (code == DUP) {
      uint32_t dupNumPixels;
      uint32_t dupPixel;
      uint32_t inputBuffer32NumWordsRead;
      uint32_t skipAfterThisOp = 0;
      
      status = maxvid_encode_sample32_generic_decode_dupcodes(inputBuffer32, &inputBuffer32NumWordsRead, inword,
                                                              &dupNumPixels, &dupPixel);
      RETCODE(status);
      
      inputBuffer32 += inputBuffer32NumWordsRead;
      
      // If the code following a DUP is a SKIP code, then condense 1 to N SKIP codes and select
      // 8 bits worth of SKIP pixels to fold into the DUP code.
      
      inword = *inputBuffer32;
      MV_GENERIC_CODE nextCode = maxvid_encode_sample32_generic_nextcode(inword);
      
      if (nextCode == SKIP) {
        status = maxvid_encode_sample32_generic_decode_skipcodes(inputBuffer32, &inputBuffer32NumWordsRead, inword, &skipAfterNumPixels);
        RETCODE(status);
        
        if (skipAfterNumPixels > MV_MAX_8_BITS) {
          skipAfterThisOp = MV_MAX_8_BITS;
          skipAfterNumPixels -= MV_MAX_8_BITS;
        } else {
          skipAfterThisOp = skipAfterNumPixels;
          skipAfterNumPixels = 0;
        }
        
        inputBuffer32 += inputBuffer32NumWordsRead;
      }
      
      status = maxvid_encode_sample32_c4_encode_dupcodes(file, encodeFlags, &pixelsWritten, dupNumPixels, dupPixel, skipAfterThisOp);
      RETCODE(status);
    } else if (code == COPY) {
      uint32_t copyNumPixels;
      uint32_t inputBuffer32NumWordsRead;
      uint32_t skipAfterThisOp = 0;
      uint32_t inputBuffer32NumWordsReadForSkip;
      const uint32_t *inputBuffer32AtCopyStart;
      
      status = maxvid_encode_sample32_generic_decode_copycodes(inputBuffer32, &inputBuffer32NumWordsRead, inword,
                                                               &copyNumPixels);
      RETCODE(status);
      
      inputBuffer32AtCopyStart = inputBuffer32;
      inputBuffer32 += inputBuffer32NumWordsRead;
      
      // If the code following a COPY is a SKIP code, then condense 1 to N SKIP codes and select
      // 8 bits worth of SKIP pixels to fold into the DUP code.
      
      inword = *inputBuffer32;
      MV_GENERIC_CODE nextCode = maxvid_encode_sample32_generic_nextcode(inword);
      
      if (nextCode == SKIP) {
        status = maxvid_encode_sample32_generic_decode_skipcodes(inputBuffer32, &inputBuffer32NumWordsReadForSkip, inword, &skipAfterNumPixels);
        RETCODE(status);
        
        if (skipAfterNumPixels > MV_MAX_8_BITS) {
          skipAfterThisOp = MV_MAX_8_BITS;
          skipAfterNumPixels -= MV_MAX_8_BITS;
        } else {
          skipAfterThisOp = skipAfterNumPixels;
          skipAfterNumPixels = 0;
        }
        
        inputBuffer32 += inputBuffer32NumWordsReadForSkip;
      }
      
      status = maxvid_encode_sample32_c4_encode_copycodes(file, encodeFlags,
                                                          inputBuffer32AtCopyStart, inputBuffer32NumWordsRead,
                                                          &pixelsWritten,
                                                          copyNumPixels,
                                                          skipAfterThisOp);
      RETCODE(status);
    } else if (code == DONE) {
      status = maxvid_encode_sample32_c4_encode_donecode(file, encodeFlags);
      RETCODE(status);
      inputBuffer32 += 1;
      
#ifdef EXTRA_CHECKS
      MAXVID_ASSERT((inputBuffer32 - originalInputBuffer32) == inputBufferNumWords, "end of input buffer");
#endif      
      
      if (pixelsWritten != maxNumPixels) {
        // Even if EXTRA_CHECKS is not compiled in, return an error if
        // the logic did not fully write the framebuffer.
        status = MV_ERROR_CODE_INVALID_INPUT;
        RETCODE(status);
      }
      
      goto done;
    } else {
      assert(0);
    }
    
    if (pixelsWritten > maxNumPixels) {
      status = MV_ERROR_CODE_INVALID_INPUT;
      RETCODE(status);
    }
  }
  
done:
#if defined(EXTRA_CHECKS)
  assert(file);
#endif
  if (didOpenFile) {
    fclose(file);
  }

  return retcode;
}

// --------------------------------------------------------------------------------------------------------

@implementation DeltaPixel

- (NSString*) description
{
  return [NSString stringWithFormat:@"x,y %d,%d at offset %d = 0x%X", self->x, self->y, self->offset, self->newValue];
}

@end // DeltaPixel

// Calculate deltas between this frame and the indicated other frame.
// The return value is an array of DeltaPixel values that store
// the location of the pixel, the old value (the one in this frame)
// and the new value (the one in the new frame).

static
NSArray* calculateDeltaPixels16(
                                const uint16_t * restrict prevInputBuffer16,
                                const uint16_t * restrict currentInputBuffer16,
                                const uint32_t inputBufferNumWords,
                                int width,
                                int height)
{
  NSMutableArray *deltaPixels = [NSMutableArray arrayWithCapacity:1024];
  
  //NSAssert(prevFrame.width == currentFrame.width, @"frame widths don't match");
  //NSAssert(prevFrame.height == currentFrame.height, @"frame heights don't match");
  
  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      uint32_t offset = (width * y) + x;
      uint16_t old_pixel = prevInputBuffer16[offset];
      uint16_t new_pixel = currentInputBuffer16[offset];
      
      if (old_pixel != new_pixel) {
        DeltaPixel *deltaPixel = [[DeltaPixel alloc] init];
        deltaPixel->x = x;
        deltaPixel->y = y;
        deltaPixel->offset = offset;
        deltaPixel->oldValue = old_pixel;
        deltaPixel->newValue = new_pixel;
        
        [deltaPixels addObject:deltaPixel];
        [deltaPixel release];
      }
    }
  }
  
  return deltaPixels;
}

// Calculate deltas between this frame and the indicated other frame.
// The return value is an array of DeltaPixel values that store
// the location of the pixel, the old value (the one in this frame)
// and the new value (the one in the new frame).

static
NSArray* calculateDeltaPixels32(
                                const uint32_t * restrict prevInputBuffer32,
                                const uint32_t * restrict currentInputBuffer32,
                                const uint32_t inputBufferNumWords,
                                int width,
                                int height)
{
  NSMutableArray *deltaPixels = [NSMutableArray arrayWithCapacity:1024];
  
  //NSAssert(prevFrame.width == currentFrame.width, @"frame widths don't match");
  //NSAssert(prevFrame.height == currentFrame.height, @"frame heights don't match");
  
  for (int y = 0; y < height; y++) {
    for (int x = 0; x < width; x++) {
      uint32_t offset = (width * y) + x;
      uint32_t old_pixel = prevInputBuffer32[offset];
      uint32_t new_pixel = currentInputBuffer32[offset];
      
      if (old_pixel != new_pixel) {
        DeltaPixel *deltaPixel = [[DeltaPixel alloc] init];
        deltaPixel->x = x;
        deltaPixel->y = y;
        deltaPixel->offset = offset;
        deltaPixel->oldValue = old_pixel;
        deltaPixel->newValue = new_pixel;
        
        [deltaPixels addObject:deltaPixel];
        [deltaPixel release];
      }
    }
  }
  
  return deltaPixels;
}

// Calculate delta between previous framebuffer and the current one. If there is
// no change, then nil is returned.

NSData*
maxvid_encode_generic_delta_pixels16(const uint16_t * restrict prevInputBuffer16,
                                     const uint16_t * restrict currentInputBuffer16,
                                     const uint32_t inputBufferNumWords,
                                     uint32_t width,
                                     uint32_t height,
                                     BOOL *emitKeyframeAnyway)
{
  // Calculate delta between previous framebuffer and the current one
  
  NSMutableData *mData = [NSMutableData data];
  
  NSArray *deltaPixels = calculateDeltaPixels16(prevInputBuffer16,
                                                currentInputBuffer16,
                                                inputBufferNumWords,
                                                width, height);
  
  if ([deltaPixels count] == 0) {
    return nil;
  } else if ((emitKeyframeAnyway != NULL) && ([deltaPixels count] == (width * height))) {
    *emitKeyframeAnyway = TRUE;
    return nil;
  } else {
    // FIXME: what if this method fails? What would we return?
    BOOL worked = maxvid_calculate_delta_pixels(deltaPixels,
                                                16,
                                                mData,
                                                width * height);
    
    assert(worked);
  }
  
  return [NSData dataWithData:mData];
}

// Calculate delta between previous framebuffer and the current one. If there is
// no change, then nil is returned. This method returns a buffer of mvid generic
// code elements.

NSData*
maxvid_encode_generic_delta_pixels32(const uint32_t * restrict prevInputBuffer32,
                                     const uint32_t * restrict currentInputBuffer32,
                                     const uint32_t inputBufferNumWords,
                                     uint32_t width,
                                     uint32_t height,
                                     BOOL *emitKeyframeAnyway)
{
  // Calculate delta between previous framebuffer and the current one
  
  NSMutableData *mData = [NSMutableData data];
  
  NSArray *deltaPixels = calculateDeltaPixels32(prevInputBuffer32,
                                                currentInputBuffer32,
                                                inputBufferNumWords,
                                                width, height);
  
  if ([deltaPixels count] == 0) {
    return nil;
  } else if ((emitKeyframeAnyway != NULL) && ([deltaPixels count] == (width * height))) {
    *emitKeyframeAnyway = TRUE;
    return nil;
  } else {
    // FIXME: what if this method fails? What would we return?
    BOOL worked = maxvid_calculate_delta_pixels(deltaPixels,
                                                32,
                                                mData,
                                                width * height);
    
    assert(worked);
  }
  
  return [NSData dataWithData:mData];
}

// Emit a DUP code for a specific run of pixels with all the same value

static
void emit_dup_run(NSMutableData *mvidWordCodes,
                  uint32_t dupCount,
                  uint32_t pixelValue,
                  int bpp)

{
  // Maximum number of pixels that can be duplicated in one 16 bit code is
  // 0xFFFF, so don't emit a DUP larger than that. No specific reason to
  // use a different constant for 16 vs 32 bit values since the encoding
  // logic will recombine DUP values later for a specific encoding.
  
  while (dupCount != 0) {
    uint32_t dupCode;
    uint32_t pixel32;
    uint32_t numToDupThisLoop;
    
    if (dupCount > MV_MAX_16_BITS) {
      numToDupThisLoop = MV_MAX_16_BITS;
    } else {
      numToDupThisLoop = dupCount;
    }
    
    if (bpp == 16) {
      dupCode = maxvid16_code(DUP, numToDupThisLoop);
      uint16_t pixel = (uint16_t) pixelValue;
      pixel32 = (pixel << 16) | pixel;
    } else {
      dupCode = maxvid32_code(DUP, numToDupThisLoop);
      pixel32 = pixelValue;
    }
    
    [mvidWordCodes appendBytes:&dupCode length:sizeof(uint32_t)];
    [mvidWordCodes appendBytes:&pixel32 length:sizeof(uint32_t)];
    
    dupCount -= numToDupThisLoop;
  }
}

// Emit a COPY code for a run of pixels with different values

static
void emit_copy_run(NSMutableData *mvidWordCodes,
                   NSMutableArray *copyPixels,
                   int bpp)

{
  uint32_t copyCount = [copyPixels count];
  uint32_t numToCopyThisLoop;

  while (copyCount != 0) {
    if (copyCount > MV_MAX_16_BITS) {
      numToCopyThisLoop = MV_MAX_16_BITS;
    } else {
      numToCopyThisLoop = copyCount;
    }
    
    if (bpp == 16) {
      // Write COPY code followed by pairs of 16 bit pixels
      
      uint32_t copyCode = maxvid16_code(COPY, numToCopyThisLoop);
      [mvidWordCodes appendBytes:&copyCode length:sizeof(uint32_t)];

      // Copy N pixels (not N words) by creating a new array that is a
      // subset of the existing number of pixels in copyPixels.
      
      uint32_t numPixelsLeftThisLoop = numToCopyThisLoop;
      NSRange firstN;
      firstN.location = 0;
      firstN.length = numPixelsLeftThisLoop;
      
      assert([copyPixels count] >= numPixelsLeftThisLoop);
      NSMutableArray *copyPixelsThisLoop = [NSMutableArray arrayWithArray:[copyPixels subarrayWithRange:firstN]];
      [copyPixels removeObjectsInRange:firstN];
      
      for ( ; numPixelsLeftThisLoop > 0; ) {
        DeltaPixel *copyDeltaPixel;
        uint32_t pixel32 = 0;
        
        if (numPixelsLeftThisLoop == 1) {
          // Only 1 16 bit pixel left
          
          copyDeltaPixel = [copyPixelsThisLoop objectAtIndex:0];
          uint16_t pixel1 = (uint16_t) copyDeltaPixel->newValue;
          [copyPixelsThisLoop removeObjectAtIndex:0];
          
          // Note that the high half word is zero
          pixel32 = pixel1;
          
          numPixelsLeftThisLoop--;
        } else {
          // Emit 2 pixels as 1 word
          
          // FIXME: more optimal to only remove 1 entries from the array.
          
          copyDeltaPixel = [copyPixelsThisLoop objectAtIndex:0];
          uint16_t pixel1 = (uint16_t) copyDeltaPixel->newValue;
          [copyPixelsThisLoop removeObjectAtIndex:0];
          
          copyDeltaPixel = [copyPixelsThisLoop objectAtIndex:0];
          uint16_t pixel2 = (uint16_t) copyDeltaPixel->newValue;
          [copyPixelsThisLoop removeObjectAtIndex:0];        
          
          pixel32 = (pixel2 << 16) | pixel1;
          
          assert(numPixelsLeftThisLoop >= 2);
          numPixelsLeftThisLoop -= 2;
        }
        
        [mvidWordCodes appendBytes:&pixel32 length:sizeof(uint32_t)];
      }
    } else {
      // Write COPY code followed by 32 bit pixels
      
      uint32_t copyCode = maxvid32_code(COPY, numToCopyThisLoop);
      [mvidWordCodes appendBytes:&copyCode length:sizeof(uint32_t)];

      uint32_t numPixelsLeftThisLoop = numToCopyThisLoop;
      assert([copyPixels count] >= numPixelsLeftThisLoop);
      
      for ( ; numPixelsLeftThisLoop > 0; numPixelsLeftThisLoop-- ) {
        DeltaPixel *copyDeltaPixel = [copyPixels objectAtIndex:0];
        uint32_t copyPixelValue = copyDeltaPixel->newValue;
        [copyPixels removeObjectAtIndex:0];
        
        [mvidWordCodes appendBytes:&copyPixelValue length:sizeof(uint32_t)];
      }
    }
    
    copyCount -= numToCopyThisLoop;
  } // end of while loop
  
  // All copyPixels have to have been removed by pixel loop
  assert([copyPixels count] == 0);
}

static
void emit_skip_run(NSMutableData *mvidWordCodes,
                   uint32_t numPixelsToSkip,
                   int bpp)

{
  // Maximum number of pixels that can be skipped over in one 16 bit code is
  // 0xFFFF, so don't emit a skip larger than that. No specific reason to
  // use a different constant for 16 vs 32 bit values since the encoding
  // logic will recombine SKIP values later for a specific encoding.

  while (numPixelsToSkip != 0) {
    uint32_t skipCode;
    uint32_t numToSkipThisLoop;
    
    if (numPixelsToSkip > MV_MAX_16_BITS) {
      numToSkipThisLoop = MV_MAX_16_BITS;
    } else {
      numToSkipThisLoop = numPixelsToSkip;
    }
    
    if (bpp == 16) {
      skipCode = maxvid16_code(SKIP, numToSkipThisLoop);
    } else {
      skipCode = maxvid32_code(SKIP, numToSkipThisLoop);
    }
    NSData *wordCode = [NSData dataWithBytes:&skipCode length:sizeof(uint32_t)];
    [mvidWordCodes appendData:wordCode];
    
    numPixelsToSkip -= numToSkipThisLoop;
  }
}

// Given a buffer of modified pixels, figure out how to write the pixels
// into mvidWordCodes. Pixels are emitted as COPY unless there is a run
// of 2 or more of the same value. Use a DUP in the case of a run.

static
void process_pixel_run(NSMutableData *mvidWordCodes,
                       NSMutableArray *mPixelRun,
                       int prevPixelOffset,
                       int nextPixelOffset,
                       int bpp)
{
  if ([mPixelRun count] > 0) {
    // Emit codes for this run of pixels
    
    int runLength = 0;
    int firstPixelOffset = -1;
    int lastPixelOffset = -1;
    
    runLength = [mPixelRun count];
      
    firstPixelOffset = ((DeltaPixel*)[mPixelRun objectAtIndex:0])->offset;
    lastPixelOffset = ((DeltaPixel*)[mPixelRun lastObject])->offset;
    
    assert((lastPixelOffset - firstPixelOffset + 1) == runLength);
    
    // Scan over the pixels in a run looking for a DUP pattern,
    // meaning a run of delta pixels where each value is the same
    // as the previous one.
    
    uint32_t dupCount = 0;
    NSMutableArray *copyPixels = [NSMutableArray array];
    
    uint32_t prevPixelValue;
    BOOL isFirstPixelInRun = TRUE;
    
    for (DeltaPixel *deltaPixel in mPixelRun) {
      uint32_t value = deltaPixel->newValue;
      
      if ((isFirstPixelInRun == FALSE) && (value == prevPixelValue)) {
        // This delta pixel is the same value as the previous one
        
        if ((dupCount == 0) && ([copyPixels count] > 0)) {
          // This pixel is the second pixel in a DUP series, but the
          // previous loop appended the previous pixel to copyPixels.
          // Undo that addition so that the COPY emit can be completed.
          
          [copyPixels removeLastObject];
        }
        
        if ([copyPixels count] > 0) {
          // Emit previous run of COPY pixels and empty copyPixels array
          
          emit_copy_run(mvidWordCodes, copyPixels, bpp);
        }

        if (dupCount == 0) {
          dupCount = 2;
        } else {
          dupCount++;          
        }
      } else {
        // This pixel is not the same value as the previous one, or it is the first pixel
        
        if (dupCount != 0) {
          // Emit a previous DUP pattern when durrent pixel does not match previous
          
          emit_dup_run(mvidWordCodes, dupCount, prevPixelValue, bpp);
          dupCount = 0;
        }
        
        // FIXME: max COPY count that can be emitted is 0xFFFF
        
        [copyPixels addObject:deltaPixel];
      }
      
      isFirstPixelInRun = FALSE;
      prevPixelValue = value;
    }
        
    // After loop, check for pending COPY or DUP op
    
    if (dupCount != 0) {
      assert([copyPixels count] == 0);
      
      emit_dup_run(mvidWordCodes, dupCount, prevPixelValue, bpp);
    } else if ([copyPixels count] > 0) {
      assert(dupCount == 0);
      
      // Emit previous run of COPY pixels and empty copyPixels array
      
      emit_copy_run(mvidWordCodes, copyPixels, bpp);
    }
    
    // Update prevPixelOffset so that it contains the offset that the pixel run just
    // wrote up to. This is needed to determine if we need to SKIP pixels up to the
    // nextPixelOffset value.
    
    prevPixelOffset = lastPixelOffset;
    prevPixelOffset++;
  }
  
  // Emit SKIP pixels to advance from the last offset written as part of
  // the pixel run up to the index indicated by pixelOffset.
  
  int numToSkip = nextPixelOffset - prevPixelOffset;
  
  // Emit SKIP pixels to advance up to the offset for this pixel
  
  if (numToSkip > 0)
  {
    emit_skip_run(mvidWordCodes, numToSkip, bpp);
  }
  
  [mPixelRun removeAllObjects];
}

// Given an array of delta pixel values, generate maxvid codes that describe
// the delta pixels and encode the information as a delta frame in the
// mvid file.

static
BOOL
maxvid_calculate_delta_pixels(NSArray *deltaPixels,
                              int bpp,
                              NSMutableData *mData,
                              NSUInteger frameBufferNumPixels)
{
  NSMutableData *mvidWordCodes = [NSMutableData dataWithCapacity:1024];
  
  int prevPixelOffset = 0;
  BOOL isFirstPixel = TRUE;
  
  NSMutableArray *mPixelRun = [NSMutableArray array];
  
  for (DeltaPixel *deltaPixel in deltaPixels) {
    int nextPixelOffset = deltaPixel->offset;
    
    if ((isFirstPixel == FALSE) && (nextPixelOffset == (prevPixelOffset + 1))) {
      // Processing a pixel other than the first one, and this pixel appears
      // directly after the last pixel. This means that the modified pixel is
      // the next pixel in a pixel run.
      
      [mPixelRun addObject:deltaPixel];
    } else {
      // This is the first pixel in a new pixel run. It might be the first pixel
      // and in that case the existing run is of zero length. Otherwise, emit
      // the previous run of pixels so that we can start a new run.
      
      process_pixel_run(mvidWordCodes, mPixelRun, prevPixelOffset, nextPixelOffset, bpp);
      
      [mPixelRun addObject:deltaPixel];
    }
    
    isFirstPixel = FALSE;    
    prevPixelOffset = nextPixelOffset;
  }
  
  // At the end of the delta pixels, we could have a run of pixels that still need to
  // be processed. In addition, we might need to SKIP to the end of the framebuffer.
  
  process_pixel_run(mvidWordCodes, mPixelRun, prevPixelOffset, frameBufferNumPixels, bpp);
  
  // Emit DONE code to indicate that all codes have been emitted
  {
    uint32_t doneCode;
    if (bpp == 16) {
      doneCode = maxvid16_code(DONE, 0x0);
    } else {
      doneCode = maxvid32_code(DONE, 0x0);    
    }
    
    NSData *wordCode = [NSData dataWithBytes:&doneCode length:sizeof(uint32_t)];
    [mvidWordCodes appendData:wordCode];
  }
  
  // App end all word codes specific to this run of pixels
  
  [mData appendData:mvidWordCodes];
  
  return TRUE;
}

// Write generic maxvid codes to output AVMvidFileWriter.
// Returns TRUE if successful, FALSE otherwise.

BOOL
maxvid_write_delta_pixels(AVMvidFileWriter *mvidWriter,
                          NSData *maxvidData,
                          void *inputBuffer,
                          uint32_t inputBufferNumBytes,
                          NSUInteger frameBufferNumPixels)
{
  int retcode;
  
  int bpp = mvidWriter.bpp;
  
  // Calculate adler32 checksum on original frame data. Note that this
  // adler will include any zero padding pixels in the event that the
  // framebuffer has an odd number of pixels.
  
  uint32_t adler = 0;
  adler = maxvid_adler32(0, (unsigned char *)inputBuffer, inputBufferNumBytes);
  assert(adler != 0);
  
  // Convert the generic maxvid codes to the optimized c4 encoding and append to the output file
  
  FILE *tmpfp = tmpfile();
  if (tmpfp == NULL) {
    assert(0);
  }
  
  uint32_t *maxvidCodeBuffer = (uint32_t*)maxvidData.bytes;
  uint32_t numMaxvidCodeWords = maxvidData.length / sizeof(uint32_t);
  
  if (bpp == 16) {
    retcode = maxvid_encode_c4_sample16(maxvidCodeBuffer, numMaxvidCodeWords, frameBufferNumPixels, NULL, tmpfp, 0);
  } else if (bpp == 24 || bpp == 32) {
    retcode = maxvid_encode_c4_sample32(maxvidCodeBuffer, numMaxvidCodeWords, frameBufferNumPixels, NULL, tmpfp, 0);
  } else {
    assert(FALSE);
  }
  
  // Read tmp file contents into buffer.
  
  if (retcode == 0) {
    // Read file contents into a buffer, then write that buffer into .mvid file
    
    uint32_t filesize;
    
    fpsize(tmpfp, &filesize);
    
    assert(filesize > 0);
    
    char *buffer = malloc(filesize);
    
    if (buffer == NULL) {
      // Malloc failed
      
      retcode = MV_ERROR_CODE_WRITE_FAILED;
    } else {
      size_t result = fread(buffer, filesize, 1, tmpfp);
      
      if (result != 1) {
        retcode = MV_ERROR_CODE_READ_FAILED;
      } else {        
        // Write codes to mvid file
        
        BOOL worked = [mvidWriter writeDeltaframe:buffer bufferSize:filesize adler:adler];
        
        if (worked == FALSE) {
          retcode = MV_ERROR_CODE_WRITE_FAILED;
        }
      }
      
      free(buffer);
    }
  }
  
  if (tmpfp != NULL) {
    fclose(tmpfp);
  }
  
  if (retcode == 0) {
    return TRUE;
  } else {
    return FALSE;
  }
}

