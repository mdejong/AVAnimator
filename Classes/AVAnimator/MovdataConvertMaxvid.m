// movdata conversion module
//
//  License terms defined in License.txt.
//
// This module implements a self contained Quicktime MOV file parser
// with verification that the MOV contains only a single Animation video track.
// This file should be #included into an implementation main file
// so that inline functions are seen as being in the same module.

#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <stdlib.h>

#include <fcntl.h>

#include <sys/types.h>
#include <sys/stat.h>
#include <math.h>
#include <assert.h>
#include <limits.h>
#include <unistd.h>

#import "MovdataConvertMaxvid.h"

#import "AVMvidFileWriter.h"

#import "movdata.h"

#import "maxvid_decode.h"
#import "maxvid_encode.h"
#import "maxvid_file.h"

static
void init_alphaTables();

// recurse into atoms and process them. Return 0 on success
// otherwise non-zero to indicate an error.

// Read a big endian uint16_t from a char* and store in result.

#define READ_UINT16(result, ptr) \
{ \
uint8_t b1 = *ptr++; \
uint8_t b2 = *ptr++; \
result = (b1 << 8) | b2; \
}

// Read a big endian uint24_t from a char* and store in result (ARGB) with zero for the alpha.

#define READ_UINT24(result, ptr) \
{ \
uint8_t b1 = *ptr++; \
uint8_t b2 = *ptr++; \
uint8_t b3 = *ptr++; \
result = (b1 << 16) | (b2 << 8) | b3; \
}

// Read a big endian uint32_t from a char* and store in result (ARGB).
// Each pixel needs to be multiplied by the alpha channel value.
// Optimized premultiplication implementation using table lookups

#define TABLEMAX 256
//#define TABLEDUMP

static
uint8_t alphaTables[TABLEMAX*TABLEMAX];
static
int alphaTablesInitialized = 0;

#define READ_AND_PREMULTIPLY(result, ptr) \
{ \
uint8_t alpha = *ptr++; \
uint8_t red = *ptr++; \
uint8_t green = *ptr++; \
uint8_t blue = *ptr++; \
uint8_t * restrict alphaTable = &alphaTables[alpha * TABLEMAX]; \
result = (alpha << 24) | (alphaTable[red] << 16) | (alphaTable[green] << 8) | alphaTable[blue]; \
}

static
void init_alphaTables() {
  if (alphaTablesInitialized) {
    return;
  }
  
  for (int alpha = 0; alpha < TABLEMAX; alpha++) {
    uint8_t *alphaTable = &alphaTables[alpha * TABLEMAX];
    float alphaf = alpha / 255.0; // (TABLEMAX - 1)
#ifdef TABLEDUMP
    fprintf(stdout, "alpha table for alpha %d = %f\n", alpha, alphaf);
#endif
    for (int i = 0; i < TABLEMAX; i++) {
      int rounded = (int) round(i * alphaf);
      if (rounded < 0 || rounded >= TABLEMAX) {
        assert(0);
      }
      assert(rounded == (int) (i * alphaf + 0.5));
      alphaTable[i] = (uint8_t)rounded;
#ifdef TABLEDUMP
      if (i == 0 || i == 1 || i == 2 || i == 126 || i == 127 || i == 128 || i == 254 || i == 255) {
        fprintf(stdout, "alphaTable[%d] = %d\n", i, alphaTable[i]);
      }
#endif
    }
  }
  
  // alpha = 0.0
  
  assert(alphaTables[(0 * TABLEMAX) + 0] == 0);
  assert(alphaTables[(0 * TABLEMAX) + 255] == 0);
  
  // alpha = 1.0
  
  assert(alphaTables[(255 * TABLEMAX) + 0] == 0);
  assert(alphaTables[(255 * TABLEMAX) + 127] == 127);
  assert(alphaTables[(255 * TABLEMAX) + 255] == 255);
  
  // Test all generated alpha values in table using
  // read_ARGB_and_premultiply()
  
  for (int alphai = 0; alphai < TABLEMAX; alphai++) {
    for (int i = 0; i < TABLEMAX; i++) {
      uint8_t in_alpha = (uint8_t) alphai;
      uint8_t in_red = 0;
      uint8_t in_green = (uint8_t) i;
      uint8_t in_blue = (uint8_t) i;
      //if (i == 1) {
      //  assert(alphaTables[(255 * TABLEMAX) + 0] == 0);
      //}
      uint32_t in_pixel = (in_alpha << 24) | (in_red << 16) | (in_green << 8) | in_blue;
      uint32_t in_pixel_be = htonl(in_pixel); // pixel in BE byte order
      uint32_t premult_pixel_le;
      char *inPixelPtr = (char*) &in_pixel_be;
      READ_AND_PREMULTIPLY(premult_pixel_le, inPixelPtr);
      
      // Compare read_ARGB_and_premultiply() result to known good value
      
      float alphaf = in_alpha / 255.0; // (TABLEMAX - 1)
      int rounded = (int) round(i * alphaf);      
      uint8_t round_alpha = in_alpha;
      uint8_t round_red = 0;
      uint8_t round_green = (uint8_t) rounded;
      uint8_t round_blue = (uint8_t) rounded;
      // Special case: If alpha is 0, then all 3 components are zero
      if (round_alpha == 0) {
        round_red = round_green = round_blue = 0;
      }
      uint32_t expected_pixel_le = (round_alpha << 24) | (round_red << 16) | (round_green << 8) | round_blue;
      if (premult_pixel_le != expected_pixel_le) {
        uint8_t premult_pixel_alpha = (premult_pixel_le >> 24) & 0xFF;
        uint8_t premult_pixel_red = (premult_pixel_le >> 16) & 0xFF;
        uint8_t premult_pixel_green = (premult_pixel_le >> 8) & 0xFF;
        uint8_t premult_pixel_blue = (premult_pixel_le >> 0) & 0xFF;
        
        uint8_t rounded_pixel_alpha = (expected_pixel_le >> 24) & 0xFF;
        uint8_t rounded_pixel_red = (expected_pixel_le >> 16) & 0xFF;
        uint8_t rounded_pixel_green = (expected_pixel_le >> 8) & 0xFF;
        uint8_t rounded_pixel_blue = (expected_pixel_le >> 0) & 0xFF;        
        
        assert(premult_pixel_alpha == rounded_pixel_alpha);
        assert(premult_pixel_red == rounded_pixel_red);
        assert(premult_pixel_green == rounded_pixel_green);
        assert(premult_pixel_blue == rounded_pixel_blue);
        
        assert(premult_pixel_le == expected_pixel_le);
      }
    }
  }
  
  // Everything worked
  
  alphaTablesInitialized = 1;
}

/*

// This is the old floating point multiplicaiton impl
 
static inline
uint32_t
read_ARGB_and_premultiply(const char *ptr) {
  uint8_t alpha = *ptr++;
  uint8_t red = *ptr++;
  uint8_t green = *ptr++;
  uint8_t blue = *ptr++;
  uint32_t pixel;

  if (0) {
    // Skip premultiplication, useful for debugging
  } else if (alpha == 0) {
    // Any pixel that is fully transparent can be represented by zero (bzero is fast)
    return 0;
  } else if (alpha == 0xFF) {
    // Any pixel that is fully opaque need not be multiplied by 1.0
  } else {
    float alphaf = alpha / 255.0;
    red = (int) (red * alphaf + 0.5);
    green = (int) (green * alphaf + 0.5);
    blue = (int) (blue * alphaf + 0.5);
  }
  pixel = (alpha << 24) | (red << 16) | (green << 8) | blue;
  return pixel;
}
 
*/

static inline
uint32_t num_words_16bpp(uint32_t numPixels) {
  // Return the number of words required to contain
  // the given number of pixels.
  return (numPixels >> 1) + (numPixels & 0x1);
}

// 16 bit rgb555 pixels with no alpha channel
// Works for (RBG555, RGB5551, or RGB565) though only XRRRRRGGGGGBBBBB is supported.

static inline
uint32_t
convert_maxvid_rle_sample16(
                  const void* restrict sampleBuffer,
                  uint32_t sampleBufferSize,
                  uint32_t isKeyFrame,
                  uint32_t * restrict maxvidCodes,
                  uint32_t * restrict numCodesWords,
                  uint32_t frameBufferWidth,
                  uint32_t frameBufferHeight)
{
  assert(sampleBuffer);
  assert(sampleBufferSize > 0);
//  assert(frameBuffer);
  
  uint32_t bytesRemaining = sampleBufferSize;
  
//  uint16_t* restrict rowPtr = NULL;
//  uint16_t* restrict rowPtrMax = NULL;
  
  uint32_t totalNumPixelsConverted = 0;
  uint32_t numCodesWordIn = *numCodesWords;
  uint32_t numCodesWordOut = 0;
  *numCodesWords = 0;
  
  // Optionally use passed in buffer that is known to be large enough to hold the sample.
  
  const char* restrict samplePtr = sampleBuffer;
  
  if (1) {
    // http://wiki.multimedia.cx/index.php?title=Apple_QuickTime_RLE
    //
    // sample size : 4 bytes
    // header : 2 bytes
    // optional : 8 bytes
    //  starting line at which to begin updating frame : 2 bytes
    //  unknown : 2 bytes
    //  the number of lines to update : 2 bytes
    //  unknown    
    // compressed lines : ?
    
    // Dump the bytes that remain at this point in the sample reading process.
    
#ifdef DUMP_WHILE_DECODING
    if (1) {
      fprintf(stdout, "sample bytes dump : bytesRemaining %d, sample length %d\n", bytesRemaining, sampleBufferSize);
      for (int i = 0; i < bytesRemaining; i++ ) {
        uint8_t b = *(samplePtr + i);
        fprintf(stdout, "0x%X ", b);
      }
      fprintf(stdout, "\n");
      
      uint32_t size = byte_read_be_uint32(samplePtr);
      uint32_t size_m24 = byte_read_be_uint32(samplePtr) & 0xFFFFFF;
      uint32_t flags = (byte_read_be_uint32(samplePtr) >> 24) & 0xFF;
      fprintf(stdout, "sample size : flags %d, size %d, size mask24 %d\n", flags, size, size_m24);
      for (int i = 0; i < 4; i++ ) {
        uint8_t b = *(samplePtr + i);
        fprintf(stdout, "0x%X ", b);
      }
      fprintf(stdout, "\n");
      
      uint32_t header = byte_read_be_uint16(samplePtr + 4);
      fprintf(stdout, "header %d\n", header);
      for (int i = 4; i < 6; i++ ) {
        uint8_t b = *(samplePtr + i);
        fprintf(stdout, "0x%X ", b);
      }
      fprintf(stdout, "\n");
      
      if (header == 0) {
        // No optional 8 bytes
        fprintf(stdout, "no optional line info\n");
      } else {
        fprintf(stdout, "optional line info\n");
        for (int i = 6; i < 6+8; i++ ) {
          uint8_t b = *(samplePtr + i);
          fprintf(stdout, "0x%X ", b);
        }
        fprintf(stdout, "\n");        
      }
      
      uint8_t skip_code = *(samplePtr + 6 + 8);
      fprintf(stdout, "skip code 0x%X = %d\n", skip_code, skip_code);
    }
#endif // DUMP_WHILE_DECODING
    
    // Skip sample size, this field looks like a 1 byte flags value and then a 24 bit length
    // value (size & 0xFFFFFF) results in a correct 24 bit length. The flag element seems to
    // be 0x1 when set. But, this field is undocumented and can be safely skipped because
    // the sample length is already known.
    
    assert(bytesRemaining >= 4);
    samplePtr += 4;
    bytesRemaining -= 4;
    
    assert(bytesRemaining >= 2);
    uint32_t header;
    READ_UINT16(header, samplePtr);
    bytesRemaining -= 2;
    
    assert(header == 0x0 || header == 0x0008);
    
    uint32_t starting_line, lines_to_update;
    
    if (header != 0) {
      // Frame delta
      
      assert(bytesRemaining >= 8);
      
      READ_UINT16(starting_line, samplePtr);
      bytesRemaining -= 2;
      
      // skip 2 unknown bytes
      samplePtr += 2;
      bytesRemaining -= 2;
      
      READ_UINT16(lines_to_update, samplePtr);
      bytesRemaining -= 2;
      
      // skip 2 unknown bytes
      samplePtr += 2;
      bytesRemaining -= 2;
    } else {
      // Keyframe
      
      starting_line = 0;
      lines_to_update = frameBufferHeight;
    }
    assert(lines_to_update > 0);
    
#ifdef DUMP_WHILE_DECODING
    if (isKeyFrame) {
      fprintf(stdout, "key frame!\n");
    } else {
      fprintf(stdout, "starting line %d\n", starting_line);
      fprintf(stdout, "lines to update %d\n", lines_to_update);
    }
#endif // DUMP_WHILE_DECODING
    
    // Get a pointer to the start of a row in the framebuffer based on the starting_line
    
    uint32_t current_line = starting_line;
    assert(current_line < frameBufferHeight);
    
// FIXME: Add a test to this converter so that the total output number of pixels
// either copied, skipped, or duped matches the expected number of pixels.
    
    // If starting line is not the first line, encode as skip pixels op.
    // Note that maxvid16_code() can only skip up to 0xFFFF pixels in
    // one op code, so iterate over lines to skip.

    if (starting_line > 0) {
      for (int i = 0; i < starting_line; i++ ) {
        uint32_t skipNumPixels = frameBufferWidth;
        assert(skipNumPixels != 0);
        uint32_t m16_skipCode = maxvid16_code(SKIP, skipNumPixels);
        numCodesWordIn--; numCodesWordOut++;
        assert(numCodesWordIn > 0);
        *maxvidCodes++ = m16_skipCode;
        
        totalNumPixelsConverted += skipNumPixels;        
      }
    }
    
//    rowPtr = frameBuffer + (current_line * frameBufferWidth);
//    rowPtrMax = rowPtr + frameBufferWidth;
    
    uint32_t rowOffset = 0;
    uint32_t rowMaxOffset = frameBufferWidth;
    
    // Increment the input/output line after seeing a -1 skip byte
    
    uint32_t incr_current_line = 0;
    
    while (1) {
#ifdef DUMP_WHILE_DECODING
      if (1) {
        fprintf(stdout, "skip code bytes dump : bytesRemaining %d, sample length %d\n", bytesRemaining, sampleBufferSize);
        for (int i = 0; i < bytesRemaining; i++ ) {
          uint8_t b = *(samplePtr + i);
          fprintf(stdout, "0x%X ", b);
        }
        fprintf(stdout, "\n");
      }
#endif // DUMP_WHILE_DECODING
      
      // Skip code
      
      assert(bytesRemaining >= 1);
      uint8_t skip_code = *samplePtr++;
      bytesRemaining--;
      
      if (skip_code == 0) {
        // Done decoding all lines in this frame
        // a zero skip code should only be found at the end of the sample
        assert(bytesRemaining == 0);
        
        // Emit pixel skip operations up to the end of the frame buffer
        // if the delta data does not advance to the end. Use multiple
        // skip ops so we don't have to worry about passing a number
        // larger than the 16 bit max.
        
        uint32_t pixelsLeftInLine = (rowOffset == 0) ? 0 : (rowMaxOffset - rowOffset);
        
        if (pixelsLeftInLine > 0) {
          uint32_t num_to_skip = pixelsLeftInLine;
          
          uint32_t skipCode = maxvid16_code(SKIP, num_to_skip);
          numCodesWordIn--; numCodesWordOut++;
          assert(numCodesWordIn > 0);
          *maxvidCodes++ = skipCode;
          
          totalNumPixelsConverted += num_to_skip;
        }        
        
        uint32_t numLinesLeft = (frameBufferHeight - 1) - current_line;

        if (numLinesLeft > 0) {
          for (int i = 0; i < numLinesLeft; i++) {
            uint32_t num_to_skip = frameBufferWidth;
            
            uint32_t skipCode = maxvid16_code(SKIP, num_to_skip);
            numCodesWordIn--; numCodesWordOut++;
            assert(numCodesWordIn > 0);
            *maxvidCodes++ = skipCode;
            
            totalNumPixelsConverted += num_to_skip;            
          }
        }
        
        // In the tricky case where a line ends and then the whole delta ends
        // but there are no additional line deltas 

        assert(totalNumPixelsConverted == (frameBufferWidth * frameBufferHeight));
        
        uint32_t doneCode = maxvid16_code(DONE, 0x0);
        numCodesWordIn--; numCodesWordOut++;
        assert(numCodesWordIn > 0);
        *maxvidCodes++ = doneCode;
        
        *numCodesWords = numCodesWordOut;
        
        break;
      }
      
      // Increment the current line once we know that another line
      // will be written (skip code is non-zero). This is useful
      // here since we don't want the row pointer to ever point past
      // the number of valid rows.
      
      if (incr_current_line) {
        incr_current_line = 0;
        current_line++;
        
        assert(current_line < frameBufferHeight);
        
        //rowPtr = frameBuffer + (current_line * frameBufferWidth);
        //rowPtrMax = rowPtr + frameBufferWidth;
        
        uint32_t pixelsLeftInLine = (rowMaxOffset - rowOffset);
        
        if (pixelsLeftInLine > 0) {
          assert(pixelsLeftInLine != 0);
          uint32_t skipCode = maxvid16_code(SKIP, pixelsLeftInLine);
          numCodesWordIn--; numCodesWordOut++;
          assert(numCodesWordIn > 0);
          *maxvidCodes++ = skipCode;
          
          totalNumPixelsConverted += pixelsLeftInLine;
        }
        
        rowOffset = 0;
      }
      
      uint8_t num_to_skip = skip_code - 1;
      
      if (num_to_skip > 0) {
#ifdef DUMP_WHILE_DECODING
        fprintf(stdout, "skip %d pixels\n", num_to_skip);
#endif // DUMP_WHILE_DECODING
        
        // Advance the row ptr by skip pixels checking that it does
        // not skip past the end of the row.
        
//        assert((rowPtr + num_to_skip) < rowPtrMax);          
//        rowPtr += num_to_skip;
        
        assert((rowOffset + num_to_skip - 1) < rowMaxOffset);          
        rowOffset += num_to_skip;
        
        assert(num_to_skip != 0);
        uint32_t skipCode = maxvid16_code(SKIP, num_to_skip);
        numCodesWordIn--; numCodesWordOut++;
        assert(numCodesWordIn > 0);
        *maxvidCodes++ = skipCode;
        
        totalNumPixelsConverted += num_to_skip;
      }
      
      while (1) {
        // RLE code (signed)
        
        assert(bytesRemaining >= 1);
        int8_t rle_code = *samplePtr++;
        bytesRemaining--;
        
        if (rle_code == 0) {
          // There is another skip code ahead in the stream, continue with next skip code
#ifdef DUMP_WHILE_DECODING
          fprintf(stdout, "rle_code == 0x0 (0) found to indicate another skip code\n");
#endif // DUMP_WHILE_DECODING
          break;
        } else if (rle_code == -1) {
          // When a RLE line is finished decoding, increment the current line row ptr.
          // Note that multiple -1 codes can be used to skip multiple unchanged lines.
          
#ifdef DUMP_WHILE_DECODING
          fprintf(stdout, "rle_code == 0xFF (-1) found to indicate end of RLE line %d\n", current_line);
#endif // DUMP_WHILE_DECODING
          
          incr_current_line = 1;
          
          break;
        } else if (rle_code < -1) {
          // Read pixel value and repeat it -rle_code times in the frame buffer
          
          uint32_t numTimesToRepeat = -rle_code;
          
          // 16 bit pixels : rgb555 or rgb565
          
          assert(bytesRemaining >= 2);
          uint32_t pixel;
          READ_UINT16(pixel, samplePtr);
          bytesRemaining -= 2;
          
#ifdef DUMP_WHILE_DECODING
          fprintf(stdout, "repeat 16 bit pixel 0x%X %d times\n", pixel, numTimesToRepeat);
#endif // DUMP_WHILE_DECODING
          
          //assert((rowPtr + numTimesToRepeat - 1) < rowPtrMax);
          assert((rowOffset + numTimesToRepeat - 1) < rowMaxOffset);

          rowOffset += numTimesToRepeat;
          
          // Repeated pixel is handled with common DUP op code
          // The "num" argument indicates the number of pixels to duplicate.
          
          uint32_t dupCode = maxvid16_code(DUP, numTimesToRepeat);
          numCodesWordIn--; numCodesWordOut++;
          assert(numCodesWordIn > 0);
          *maxvidCodes++ = dupCode;
          
          totalNumPixelsConverted += numTimesToRepeat;
          
          // One additional word appears after the DUP code
          
          uint32_t pixel32 = (pixel << 16) | pixel;
          numCodesWordIn--; numCodesWordOut++;
          assert(numCodesWordIn > 0);
          *maxvidCodes++ = pixel32;

        } else {
          // Greater than 0, copy pixels from input to output stream
          assert(rle_code > 0);
          
          // 16 bit pixels
          
          uint32_t numBytesToCopy = sizeof(uint16_t) * rle_code;
          
          assert(bytesRemaining >= numBytesToCopy);
          
          bytesRemaining -= numBytesToCopy;
          
          //assert((rowPtr + rle_code - 1) < rowPtrMax);
          assert((rowOffset + rle_code - 1) < rowMaxOffset);
          
          uint32_t numPixelsToWrite = rle_code;
          const uint32_t numWordsToWrite = num_words_16bpp(numPixelsToWrite);
          
          // Create maxvid op code, num indicates the number of half word
          // pixels that will be written after the COPY word. The actual number
          // of words must be large enough to fit all the half words.
          
          uint32_t copyCode = maxvid16_code(COPY, numPixelsToWrite);
          numCodesWordIn--; numCodesWordOut++;
          assert(numCodesWordIn > 0);
          *maxvidCodes++ = copyCode;
          
          uint32_t numWholeWords = numWordsToWrite;
          uint32_t numHalfWords = 0;
          if ((numWordsToWrite << 1) != numPixelsToWrite) {
            // Odd number of pixels
            numWholeWords--;
            numHalfWords = 1;
          }
          
          for (int i = 0; i < numWholeWords; i++) {
            uint32_t pixel32;
            uint32_t pixel;
            READ_UINT16(pixel, samplePtr);
            pixel32 = pixel;
            READ_UINT16(pixel, samplePtr);
            pixel32 |= (pixel << 16);

            rowOffset += 2;
            
            totalNumPixelsConverted += 2;
            
            numCodesWordIn--; numCodesWordOut++;
            assert(numCodesWordIn > 0);
            *maxvidCodes++ = pixel32;
          }
          
          // Write half word pixel as a zero padded whole word
          
          if (numHalfWords) {
            uint32_t pixel32;
            READ_UINT16(pixel32, samplePtr);
            // high half word is zero
            assert((pixel32 >> 16) == 0);
            
            rowOffset += 1;
                        
            totalNumPixelsConverted++;
            
            numCodesWordIn--; numCodesWordOut++;
            assert(numCodesWordIn > 0);
            *maxvidCodes++ = pixel32;            
          }                    
        }        
      }
    }
  }
  
  return 0;
}

// 24 bit RGB pixels with no alpha channel
// Each 24 bit pixel is written as a word with the high byte set to zero

static inline
uint32_t
convert_maxvid_rle_sample24(
                            const void* restrict sampleBuffer,
                            uint32_t sampleBufferSize,
                            uint32_t isKeyFrame,
                            uint32_t * restrict maxvidCodes,
                            uint32_t * restrict numCodesWords,
                            uint32_t frameBufferWidth,
                            uint32_t frameBufferHeight)
{
  assert(sampleBuffer);
  assert(sampleBufferSize > 0);
  //  assert(frameBuffer);
  
  uint32_t bytesRemaining = sampleBufferSize;
  
  //  uint16_t* restrict rowPtr = NULL;
  //  uint16_t* restrict rowPtrMax = NULL;
  
  uint32_t totalNumPixelsConverted = 0;
  uint32_t numCodesWordIn = *numCodesWords;
  uint32_t numCodesWordOut = 0;
  *numCodesWords = 0;
  
  // Optionally use passed in buffer that is known to be large enough to hold the sample.
  
  const char* restrict samplePtr = sampleBuffer;
  
  if (1) {
    // http://wiki.multimedia.cx/index.php?title=Apple_QuickTime_RLE
    //
    // sample size : 4 bytes
    // header : 2 bytes
    // optional : 8 bytes
    //  starting line at which to begin updating frame : 2 bytes
    //  unknown : 2 bytes
    //  the number of lines to update : 2 bytes
    //  unknown    
    // compressed lines : ?
    
    // Dump the bytes that remain at this point in the sample reading process.
    
#ifdef DUMP_WHILE_DECODING
    if (1) {
      fprintf(stdout, "sample bytes dump : bytesRemaining %d, sample length %d\n", bytesRemaining, sampleBufferSize);
      for (int i = 0; i < bytesRemaining; i++ ) {
        uint8_t b = *(samplePtr + i);
        fprintf(stdout, "0x%X ", b);
      }
      fprintf(stdout, "\n");
      
      uint32_t size = byte_read_be_uint32(samplePtr);
      uint32_t size_m24 = byte_read_be_uint32(samplePtr) & 0xFFFFFF;
      uint32_t flags = (byte_read_be_uint32(samplePtr) >> 24) & 0xFF;
      fprintf(stdout, "sample size : flags %d, size %d, size mask24 %d\n", flags, size, size_m24);
      for (int i = 0; i < 4; i++ ) {
        uint8_t b = *(samplePtr + i);
        fprintf(stdout, "0x%X ", b);
      }
      fprintf(stdout, "\n");
      
      uint32_t header = byte_read_be_uint16(samplePtr + 4);
      fprintf(stdout, "header %d\n", header);
      for (int i = 4; i < 6; i++ ) {
        uint8_t b = *(samplePtr + i);
        fprintf(stdout, "0x%X ", b);
      }
      fprintf(stdout, "\n");
      
      if (header == 0) {
        // No optional 8 bytes
        fprintf(stdout, "no optional line info\n");
      } else {
        fprintf(stdout, "optional line info\n");
        for (int i = 6; i < 6+8; i++ ) {
          uint8_t b = *(samplePtr + i);
          fprintf(stdout, "0x%X ", b);
        }
        fprintf(stdout, "\n");        
      }
      
      uint8_t skip_code = *(samplePtr + 6 + 8);
      fprintf(stdout, "skip code 0x%X = %d\n", skip_code, skip_code);
    }
#endif // DUMP_WHILE_DECODING
    
    // Skip sample size, this field looks like a 1 byte flags value and then a 24 bit length
    // value (size & 0xFFFFFF) results in a correct 24 bit length. The flag element seems to
    // be 0x1 when set. But, this field is undocumented and can be safely skipped because
    // the sample length is already known.
    
    assert(bytesRemaining >= 4);
    samplePtr += 4;
    bytesRemaining -= 4;
    
    assert(bytesRemaining >= 2);
    uint32_t header;
    READ_UINT16(header, samplePtr);
    bytesRemaining -= 2;
    
    assert(header == 0x0 || header == 0x0008);
    
    uint32_t starting_line, lines_to_update;
    
    if (header != 0) {
      // Frame delta
      
      assert(bytesRemaining >= 8);
      
      READ_UINT16(starting_line, samplePtr);
      bytesRemaining -= 2;
      
      // skip 2 unknown bytes
      samplePtr += 2;
      bytesRemaining -= 2;
      
      READ_UINT16(lines_to_update, samplePtr);
      bytesRemaining -= 2;
      
      // skip 2 unknown bytes
      samplePtr += 2;
      bytesRemaining -= 2;
    } else {
      // Keyframe
      
      starting_line = 0;
      lines_to_update = frameBufferHeight;
    }
    assert(lines_to_update > 0);
    
#ifdef DUMP_WHILE_DECODING
    if (isKeyFrame) {
      fprintf(stdout, "key frame!\n");
    } else {
      fprintf(stdout, "starting line %d\n", starting_line);
      fprintf(stdout, "lines to update %d\n", lines_to_update);
    }
#endif // DUMP_WHILE_DECODING
    
    // Get a pointer to the start of a row in the framebuffer based on the starting_line
    
    uint32_t current_line = starting_line;
    assert(current_line < frameBufferHeight);
    
    // FIXME: Add a test to this converter so that the total output number of pixels
    // either copied, skipped, or duped matches the expected number of pixels.
    
    // If starting line is not the first line, encode as skip pixels op.
    
    if (starting_line > 0) {
      uint32_t skipNumPixels = starting_line * frameBufferWidth;
      assert(skipNumPixels != 0);
      uint32_t m16_skipCode = maxvid32_code(SKIP, skipNumPixels);
      numCodesWordIn--; numCodesWordOut++;
      assert(numCodesWordIn > 0);
      *maxvidCodes++ = m16_skipCode;
      
      totalNumPixelsConverted += skipNumPixels;
    }
    
    //    rowPtr = frameBuffer + (current_line * frameBufferWidth);
    //    rowPtrMax = rowPtr + frameBufferWidth;
    
    uint32_t rowOffset = 0;
    uint32_t rowMaxOffset = frameBufferWidth;
    
    // Increment the input/output line after seeing a -1 skip byte
    
    uint32_t incr_current_line = 0;
    
    while (1) {
#ifdef DUMP_WHILE_DECODING
      if (1) {
        fprintf(stdout, "skip code bytes dump : bytesRemaining %d, sample length %d\n", bytesRemaining, sampleBufferSize);
        for (int i = 0; i < bytesRemaining; i++ ) {
          uint8_t b = *(samplePtr + i);
          fprintf(stdout, "0x%X ", b);
        }
        fprintf(stdout, "\n");
      }
#endif // DUMP_WHILE_DECODING
      
      // Skip code
      
      assert(bytesRemaining >= 1);
      uint8_t skip_code = *samplePtr++;
      bytesRemaining--;
      
      if (skip_code == 0) {
        // Done decoding all lines in this frame
        // a zero skip code should only be found at the end of the sample
        assert(bytesRemaining == 0);
        
        // Emit pixel skip operations up to the end of the frame buffer
        // if the delta data does not advance to the end. Use multiple
        // skip ops so we don't have to worry about passing a number
        // larger than the 16 bit max.
        
        uint32_t pixelsLeftInLine = (rowOffset == 0) ? 0 : (rowMaxOffset - rowOffset);
        
        if (pixelsLeftInLine > 0) {
          uint32_t num_to_skip = pixelsLeftInLine;
          
          uint32_t skipCode = maxvid32_code(SKIP, num_to_skip);
          numCodesWordIn--; numCodesWordOut++;
          assert(numCodesWordIn > 0);
          *maxvidCodes++ = skipCode;
          
          totalNumPixelsConverted += num_to_skip;
        }        
        
        uint32_t numLinesLeft = (frameBufferHeight - 1) - current_line;
        
        if (numLinesLeft > 0) {
          for (int i = 0; i < numLinesLeft; i++) {
            uint32_t num_to_skip = frameBufferWidth;
            
            uint32_t skipCode = maxvid32_code(SKIP, num_to_skip);
            numCodesWordIn--; numCodesWordOut++;
            assert(numCodesWordIn > 0);
            *maxvidCodes++ = skipCode;
            
            totalNumPixelsConverted += num_to_skip;            
          }
        }
        
        // In the tricky case where a line ends and then the whole delta ends
        // but there are no additional line deltas 
        
        assert(totalNumPixelsConverted == (frameBufferWidth * frameBufferHeight));
        
        uint32_t doneCode = maxvid32_code(DONE, 0x0);
        numCodesWordIn--; numCodesWordOut++;
        assert(numCodesWordIn > 0);
        *maxvidCodes++ = doneCode;
        
        *numCodesWords = numCodesWordOut;
        
        break;
      }
      
      // Increment the current line once we know that another line
      // will be written (skip code is non-zero). This is useful
      // here since we don't want the row pointer to ever point past
      // the number of valid rows.
      
      if (incr_current_line) {
        incr_current_line = 0;
        current_line++;
        
        assert(current_line < frameBufferHeight);
        
        //rowPtr = frameBuffer + (current_line * frameBufferWidth);
        //rowPtrMax = rowPtr + frameBufferWidth;
        
        uint32_t pixelsLeftInLine = (rowMaxOffset - rowOffset);
        
        if (pixelsLeftInLine > 0) {
          assert(pixelsLeftInLine != 0);
          uint32_t skipCode = maxvid32_code(SKIP, pixelsLeftInLine);
          numCodesWordIn--; numCodesWordOut++;
          assert(numCodesWordIn > 0);
          *maxvidCodes++ = skipCode;
          
          totalNumPixelsConverted += pixelsLeftInLine;
        }
        
        rowOffset = 0;
      }
      
      uint8_t num_to_skip = skip_code - 1;
      
      if (num_to_skip > 0) {
#ifdef DUMP_WHILE_DECODING
        fprintf(stdout, "skip %d pixels\n", num_to_skip);
#endif // DUMP_WHILE_DECODING
        
        // Advance the row ptr by skip pixels checking that it does
        // not skip past the end of the row.
        
        //        assert((rowPtr + num_to_skip) < rowPtrMax);          
        //        rowPtr += num_to_skip;
        
        assert((rowOffset + num_to_skip - 1) < rowMaxOffset);          
        rowOffset += num_to_skip;
        
        assert(num_to_skip != 0);
        uint32_t skipCode = maxvid32_code(SKIP, num_to_skip);
        numCodesWordIn--; numCodesWordOut++;
        assert(numCodesWordIn > 0);
        *maxvidCodes++ = skipCode;
        
        totalNumPixelsConverted += num_to_skip;
      }
      
      while (1) {
        // RLE code (signed)
        
        assert(bytesRemaining >= 1);
        int8_t rle_code = *samplePtr++;
        bytesRemaining--;
        
        if (rle_code == 0) {
          // There is another skip code ahead in the stream, continue with next skip code
#ifdef DUMP_WHILE_DECODING
          fprintf(stdout, "rle_code == 0x0 (0) found to indicate another skip code\n");
#endif // DUMP_WHILE_DECODING
          break;
        } else if (rle_code == -1) {
          // When a RLE line is finished decoding, increment the current line row ptr.
          // Note that multiple -1 codes can be used to skip multiple unchanged lines.
          
#ifdef DUMP_WHILE_DECODING
          fprintf(stdout, "rle_code == 0xFF (-1) found to indicate end of RLE line %d\n", current_line);
#endif // DUMP_WHILE_DECODING
          
          incr_current_line = 1;
          
          break;
        } else if (rle_code < -1) {
          // Read pixel value and repeat it -rle_code times in the frame buffer
          
          uint32_t numTimesToRepeat = -rle_code;
          
          // 24 bit pixels : RGB
          // write 32 bit pixels : ARGB
          
          assert(bytesRemaining >= 3);
          uint32_t pixel;
          READ_UINT24(pixel, samplePtr);
          bytesRemaining -= 3;
          
#ifdef DUMP_WHILE_DECODING
          fprintf(stdout, "repeat 24 bit pixel 0x%X %d times\n", pixel, numTimesToRepeat);
#endif // DUMP_WHILE_DECODING
          
          //assert((rowPtr + numTimesToRepeat - 1) < rowPtrMax);
          assert((rowOffset + numTimesToRepeat - 1) < rowMaxOffset);
          
          rowOffset += numTimesToRepeat;
                              
          // Repeated pixel is handled with common DUP op code
          // The "num" argument indicates the number of pixels to duplicate.
          
          uint32_t dupCode = maxvid32_code(DUP, numTimesToRepeat);
          numCodesWordIn--; numCodesWordOut++;
          assert(numCodesWordIn > 0);
          *maxvidCodes++ = dupCode;
          
          totalNumPixelsConverted += numTimesToRepeat;
          
          // One additional word appears after the DUP code (contains the pixel)
          
          numCodesWordIn--; numCodesWordOut++;
          assert(numCodesWordIn > 0);
          *maxvidCodes++ = pixel;
          
        } else {
          // Greater than 0, copy pixels from input to output stream
          assert(rle_code > 0);
          
          // 24 bit pixels : RGB
          // write 32 bit pixels : ARGB
          
          uint32_t numBytesToCopy = 3 * rle_code;
          
          assert(bytesRemaining >= numBytesToCopy);
          
          bytesRemaining -= numBytesToCopy;
          
          //assert((rowPtr + rle_code - 1) < rowPtrMax);
          assert((rowOffset + rle_code - 1) < rowMaxOffset);
          
          uint32_t numPixelsToWrite = rle_code;
          
          // Create maxvid op code, num indicates the pixel to write.
          // Each pixel takes up 1 word, so the num pixels and
          // num words match.
          
          uint32_t copyCode = maxvid32_code(COPY, numPixelsToWrite);
          numCodesWordIn--; numCodesWordOut++;
          assert(numCodesWordIn > 0);
          *maxvidCodes++ = copyCode;
          
          // write a word for each pixel
          
          for (int i = 0; i < numPixelsToWrite; i++) {
            uint32_t pixel;
            READ_UINT24(pixel, samplePtr);
            
#ifdef DUMP_WHILE_DECODING
            fprintf(stdout, "copy 24 bit pixel 0x%X to dest\n", pixel);
#endif // DUMP_WHILE_DECODING
            
            rowOffset++; // advance row index
            
            totalNumPixelsConverted++;
            
            numCodesWordIn--; numCodesWordOut++;
            assert(numCodesWordIn > 0);
            *maxvidCodes++ = pixel;
          }          
        }        
      }
    }
  }
  
  return 0;
}

// 32 bit pixels : ARGB pixels with straight alpha

static inline
uint32_t
convert_maxvid_rle_sample32(
                            const void* restrict sampleBuffer,
                            uint32_t sampleBufferSize,
                            uint32_t isKeyFrame,
                            uint32_t * restrict maxvidCodes,
                            uint32_t * restrict numCodesWords,
                            uint32_t frameBufferWidth,
                            uint32_t frameBufferHeight)
{
  assert(sampleBuffer);
  assert(sampleBufferSize > 0);
  //  assert(frameBuffer);
  
  uint32_t bytesRemaining = sampleBufferSize;
  
  //  uint16_t* restrict rowPtr = NULL;
  //  uint16_t* restrict rowPtrMax = NULL;
  
  uint32_t totalNumPixelsConverted = 0;
  uint32_t numCodesWordIn = *numCodesWords;
  uint32_t numCodesWordOut = 0;
  *numCodesWords = 0;
  
  // Optionally use passed in buffer that is known to be large enough to hold the sample.
  
  const char* restrict samplePtr = sampleBuffer;
  
  if (1) {
    // http://wiki.multimedia.cx/index.php?title=Apple_QuickTime_RLE
    //
    // sample size : 4 bytes
    // header : 2 bytes
    // optional : 8 bytes
    //  starting line at which to begin updating frame : 2 bytes
    //  unknown : 2 bytes
    //  the number of lines to update : 2 bytes
    //  unknown    
    // compressed lines : ?
    
    // Dump the bytes that remain at this point in the sample reading process.
    
#ifdef DUMP_WHILE_DECODING
    if (1) {
      fprintf(stdout, "sample bytes dump : bytesRemaining %d, sample length %d\n", bytesRemaining, sampleBufferSize);
      for (int i = 0; i < bytesRemaining; i++ ) {
        uint8_t b = *(samplePtr + i);
        fprintf(stdout, "0x%X ", b);
      }
      fprintf(stdout, "\n");
      
      uint32_t size = byte_read_be_uint32(samplePtr);
      uint32_t size_m24 = byte_read_be_uint32(samplePtr) & 0xFFFFFF;
      uint32_t flags = (byte_read_be_uint32(samplePtr) >> 24) & 0xFF;
      fprintf(stdout, "sample size : flags %d, size %d, size mask24 %d\n", flags, size, size_m24);
      for (int i = 0; i < 4; i++ ) {
        uint8_t b = *(samplePtr + i);
        fprintf(stdout, "0x%X ", b);
      }
      fprintf(stdout, "\n");
      
      uint32_t header = byte_read_be_uint16(samplePtr + 4);
      fprintf(stdout, "header %d\n", header);
      for (int i = 4; i < 6; i++ ) {
        uint8_t b = *(samplePtr + i);
        fprintf(stdout, "0x%X ", b);
      }
      fprintf(stdout, "\n");
      
      if (header == 0) {
        // No optional 8 bytes
        fprintf(stdout, "no optional line info\n");
      } else {
        fprintf(stdout, "optional line info\n");
        for (int i = 6; i < 6+8; i++ ) {
          uint8_t b = *(samplePtr + i);
          fprintf(stdout, "0x%X ", b);
        }
        fprintf(stdout, "\n");        
      }
      
      uint8_t skip_code = *(samplePtr + 6 + 8);
      fprintf(stdout, "skip code 0x%X = %d\n", skip_code, skip_code);
    }
#endif // DUMP_WHILE_DECODING
    
    // Skip sample size, this field looks like a 1 byte flags value and then a 24 bit length
    // value (size & 0xFFFFFF) results in a correct 24 bit length. The flag element seems to
    // be 0x1 when set. But, this field is undocumented and can be safely skipped because
    // the sample length is already known.
    
    assert(bytesRemaining >= 4);
    samplePtr += 4;
    bytesRemaining -= 4;
    
    assert(bytesRemaining >= 2);
    uint32_t header;
    READ_UINT16(header, samplePtr);
    bytesRemaining -= 2;
    
    assert(header == 0x0 || header == 0x0008);
    
    uint32_t starting_line, lines_to_update;
    
    if (header != 0) {
      // Frame delta
      
      assert(bytesRemaining >= 8);
      
      READ_UINT16(starting_line, samplePtr);
      bytesRemaining -= 2;
      
      // skip 2 unknown bytes
      samplePtr += 2;
      bytesRemaining -= 2;
      
      READ_UINT16(lines_to_update, samplePtr);
      bytesRemaining -= 2;
      
      // skip 2 unknown bytes
      samplePtr += 2;
      bytesRemaining -= 2;
    } else {
      // Keyframe
      
      starting_line = 0;
      lines_to_update = frameBufferHeight;
    }
    assert(lines_to_update > 0);
    
#ifdef DUMP_WHILE_DECODING
    if (isKeyFrame) {
      fprintf(stdout, "key frame!\n");
    } else {
      fprintf(stdout, "starting line %d\n", starting_line);
      fprintf(stdout, "lines to update %d\n", lines_to_update);
    }
#endif // DUMP_WHILE_DECODING
    
    // Get a pointer to the start of a row in the framebuffer based on the starting_line
    
    uint32_t current_line = starting_line;
    assert(current_line < frameBufferHeight);
    
    // FIXME: Add a test to this converter so that the total output number of pixels
    // either copied, skipped, or duped matches the expected number of pixels.
    
    // If starting line is not the first line, encode as skip pixels op.
    
    if (starting_line > 0) {
      uint32_t skipNumPixels = starting_line * frameBufferWidth;
      assert(skipNumPixels != 0);
      uint32_t m16_skipCode = maxvid32_code(SKIP, skipNumPixels);
      numCodesWordIn--; numCodesWordOut++;
      assert(numCodesWordIn > 0);
      *maxvidCodes++ = m16_skipCode;
      
      totalNumPixelsConverted += skipNumPixels;
    }
    
    //    rowPtr = frameBuffer + (current_line * frameBufferWidth);
    //    rowPtrMax = rowPtr + frameBufferWidth;
    
    uint32_t rowOffset = 0;
    uint32_t rowMaxOffset = frameBufferWidth;
    
    // Increment the input/output line after seeing a -1 skip byte
    
    uint32_t incr_current_line = 0;
    
    while (1) {
#ifdef DUMP_WHILE_DECODING
      if (1) {
        fprintf(stdout, "skip code bytes dump : bytesRemaining %d, sample length %d\n", bytesRemaining, sampleBufferSize);
        for (int i = 0; i < bytesRemaining; i++ ) {
          uint8_t b = *(samplePtr + i);
          fprintf(stdout, "0x%X ", b);
        }
        fprintf(stdout, "\n");
      }
#endif // DUMP_WHILE_DECODING
      
      // Skip code
      
      assert(bytesRemaining >= 1);
      uint8_t skip_code = *samplePtr++;
      bytesRemaining--;
      
      if (skip_code == 0) {
        // Done decoding all lines in this frame
        // a zero skip code should only be found at the end of the sample
        assert(bytesRemaining == 0);
        
        // Emit pixel skip operations up to the end of the frame buffer
        // if the delta data does not advance to the end. Use multiple
        // skip ops so we don't have to worry about passing a number
        // larger than the 16 bit max.
        
        uint32_t pixelsLeftInLine = (rowOffset == 0) ? 0 : (rowMaxOffset - rowOffset);
        
        if (pixelsLeftInLine > 0) {
          uint32_t num_to_skip = pixelsLeftInLine;
          
          uint32_t skipCode = maxvid32_code(SKIP, num_to_skip);
          numCodesWordIn--; numCodesWordOut++;
          assert(numCodesWordIn > 0);
          *maxvidCodes++ = skipCode;
          
          totalNumPixelsConverted += num_to_skip;
        }        
        
        uint32_t numLinesLeft = (frameBufferHeight - 1) - current_line;
        
        if (numLinesLeft > 0) {
          for (int i = 0; i < numLinesLeft; i++) {
            uint32_t num_to_skip = frameBufferWidth;
            
            uint32_t skipCode = maxvid32_code(SKIP, num_to_skip);
            numCodesWordIn--; numCodesWordOut++;
            assert(numCodesWordIn > 0);
            *maxvidCodes++ = skipCode;
            
            totalNumPixelsConverted += num_to_skip;            
          }
        }
        
        // In the tricky case where a line ends and then the whole delta ends
        // but there are no additional line deltas 
        
        assert(totalNumPixelsConverted == (frameBufferWidth * frameBufferHeight));
        
        uint32_t doneCode = maxvid32_code(DONE, 0x0);
        numCodesWordIn--; numCodesWordOut++;
        assert(numCodesWordIn > 0);
        *maxvidCodes++ = doneCode;
        
        *numCodesWords = numCodesWordOut;
        
        break;
      }
      
      // Increment the current line once we know that another line
      // will be written (skip code is non-zero). This is useful
      // here since we don't want the row pointer to ever point past
      // the number of valid rows.
      
      if (incr_current_line) {
        incr_current_line = 0;
        current_line++;
        
        assert(current_line < frameBufferHeight);
        
        //rowPtr = frameBuffer + (current_line * frameBufferWidth);
        //rowPtrMax = rowPtr + frameBufferWidth;
        
        uint32_t pixelsLeftInLine = (rowMaxOffset - rowOffset);
        
        if (pixelsLeftInLine > 0) {
          assert(pixelsLeftInLine != 0);
          uint32_t skipCode = maxvid32_code(SKIP, pixelsLeftInLine);
          numCodesWordIn--; numCodesWordOut++;
          assert(numCodesWordIn > 0);
          *maxvidCodes++ = skipCode;
          
          totalNumPixelsConverted += pixelsLeftInLine;
        }
        
        rowOffset = 0;
      }
      
      uint8_t num_to_skip = skip_code - 1;
      
      if (num_to_skip > 0) {
#ifdef DUMP_WHILE_DECODING
        fprintf(stdout, "skip %d pixels\n", num_to_skip);
#endif // DUMP_WHILE_DECODING
        
        // Advance the row ptr by skip pixels checking that it does
        // not skip past the end of the row.
        
        //        assert((rowPtr + num_to_skip) < rowPtrMax);          
        //        rowPtr += num_to_skip;
        
        assert((rowOffset + num_to_skip - 1) < rowMaxOffset);          
        rowOffset += num_to_skip;
        
        assert(num_to_skip != 0);
        uint32_t skipCode = maxvid32_code(SKIP, num_to_skip);
        numCodesWordIn--; numCodesWordOut++;
        assert(numCodesWordIn > 0);
        *maxvidCodes++ = skipCode;
        
        totalNumPixelsConverted += num_to_skip;
      }
      
      while (1) {
        // RLE code (signed)
        
        assert(bytesRemaining >= 1);
        int8_t rle_code = *samplePtr++;
        bytesRemaining--;
        
        if (rle_code == 0) {
          // There is another skip code ahead in the stream, continue with next skip code
#ifdef DUMP_WHILE_DECODING
          fprintf(stdout, "rle_code == 0x0 (0) found to indicate another skip code\n");
#endif // DUMP_WHILE_DECODING
          break;
        } else if (rle_code == -1) {
          // When a RLE line is finished decoding, increment the current line row ptr.
          // Note that multiple -1 codes can be used to skip multiple unchanged lines.
          
#ifdef DUMP_WHILE_DECODING
          fprintf(stdout, "rle_code == 0xFF (-1) found to indicate end of RLE line %d\n", current_line);
#endif // DUMP_WHILE_DECODING
          
          incr_current_line = 1;
          
          break;
        } else if (rle_code < -1) {
          // Read pixel value and repeat it -rle_code times in the frame buffer
          
          uint32_t numTimesToRepeat = -rle_code;
          
          // 32 bit pixels : ARGB
          
          assert(bytesRemaining >= 4);
          uint32_t pixel;
          READ_AND_PREMULTIPLY(pixel, samplePtr);
          bytesRemaining -= 4;
          
#ifdef DUMP_WHILE_DECODING
          fprintf(stdout, "repeat 32 bit pixel 0x%X %d times\n", pixel, numTimesToRepeat);
#endif // DUMP_WHILE_DECODING          
                    
          //assert((rowPtr + numTimesToRepeat - 1) < rowPtrMax);
          assert((rowOffset + numTimesToRepeat - 1) < rowMaxOffset);
          
          rowOffset += numTimesToRepeat;
          
          // Repeated pixel is handled with common DUP op code
          // The "num" argument indicates the number of pixels to duplicate.
          
          uint32_t dupCode = maxvid32_code(DUP, numTimesToRepeat);
          numCodesWordIn--; numCodesWordOut++;
          assert(numCodesWordIn > 0);
          *maxvidCodes++ = dupCode;
          
          totalNumPixelsConverted += numTimesToRepeat;
          
          // One additional word appears after the DUP code (contains the pixel)
          
          numCodesWordIn--; numCodesWordOut++;
          assert(numCodesWordIn > 0);
          *maxvidCodes++ = pixel;
          
        } else {
          // Greater than 0, copy pixels from input to output stream
          assert(rle_code > 0);
          
          // 32 bit pixels : ARGB
           
          uint32_t numBytesToCopy = 4 * rle_code;
          
          assert(bytesRemaining >= numBytesToCopy);
          
          bytesRemaining -= numBytesToCopy;
          
          //assert((rowPtr + rle_code - 1) < rowPtrMax);
          assert((rowOffset + rle_code - 1) < rowMaxOffset);
          
          uint32_t numPixelsToWrite = rle_code;
          
          // Create maxvid op code, num indicates the pixel to write.
          // Each pixel takes up 1 word, so the num pixels and
          // num words match.
          
          uint32_t copyCode = maxvid32_code(COPY, numPixelsToWrite);
          numCodesWordIn--; numCodesWordOut++;
          assert(numCodesWordIn > 0);
          *maxvidCodes++ = copyCode;
          
          // write a word for each pixel
          
          for (int i = 0; i < numPixelsToWrite; i++) {
            uint32_t pixel;
            READ_AND_PREMULTIPLY(pixel, samplePtr);
            
#ifdef DUMP_WHILE_DECODING
            fprintf(stdout, "copy 32 bit pixel 0x%X to dest\n", pixel);
#endif // DUMP_WHILE_DECODING            
            
            rowOffset++; // advance row index
            
            totalNumPixelsConverted++;
            
            numCodesWordIn--; numCodesWordOut++;
            assert(numCodesWordIn > 0);
            *maxvidCodes++ = pixel;
          }          
        }        
      }
    }
  }
  
  return 0;
}

// Convert a sample buffer to maxvid codes. The numCodesWords value contains
// the number of words available in maxvidCodes. The numCodesWords is
// written on function exit with the number of words actually written.

uint32_t
movdata_convert_maxvid_decode_rle_sample16(
                                            void *sampleBuffer,
                                            uint32_t sampleBufferSize,
                                            uint32_t isKeyframe,
                                            uint32_t * restrict maxvidCodes,
                                            uint32_t * restrict numCodesWords,
                                            uint32_t width,
                                            uint32_t height)                    
{
  return convert_maxvid_rle_sample16(sampleBuffer, sampleBufferSize, isKeyframe, maxvidCodes, numCodesWords, width, height);
}

uint32_t
movdata_convert_maxvid_decode_rle_sample24(
                                            void *sampleBuffer,
                                            uint32_t sampleBufferSize,
                                            uint32_t isKeyframe,
                                            uint32_t * restrict maxvidCodes,
                                            uint32_t * restrict numCodesWords,
                                            uint32_t width,
                                            uint32_t height)
{
  return convert_maxvid_rle_sample24(sampleBuffer, sampleBufferSize, isKeyframe, maxvidCodes, numCodesWords, width, height);
}

uint32_t
movdata_convert_maxvid_decode_rle_sample32(
                                           void *sampleBuffer,
                                           uint32_t sampleBufferSize,
                                           uint32_t isKeyframe,
                                           uint32_t * restrict maxvidCodes,
                                           uint32_t * restrict numCodesWords,
                                           uint32_t width,
                                           uint32_t height)
{
  init_alphaTables();
  return convert_maxvid_rle_sample32(sampleBuffer, sampleBufferSize, isKeyframe, maxvidCodes, numCodesWords, width, height);
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

// Convert a movdata frame to maxvid c4 codes and write to a file.

static
uint32_t
movdata_convert_and_write_maxvid_frame(
                       const void * restrict movSampleBuffer,
                       const uint32_t movSampleBufferNumBytes,
                       const uint32_t isKeyframe,
                       uint32_t **maxvidCodeBufferPtr, // in/out
                       uint32_t *maxvidCodeBufferNumBytesPtr, // in/out
                       AVMvidFileWriter *aVMvidFileWriter,
                       const uint32_t width,
                       const uint32_t height,
                       const uint32_t bpp,
                       const uint32_t adler) // non-zero if adler generation is enabled
{
  assert(movSampleBuffer != NULL);
  assert(movSampleBufferNumBytes > 0);
  assert(aVMvidFileWriter != nil);
  assert(width > 0);
  assert(height > 0);
    
  // Ensure that the code buffer is at least 10 times the size of the movdata buffer.
  // The code buffer is always in terms of whole words.

  uint32_t byteLength = movSampleBufferNumBytes * 10;
  byteLength += (byteLength % sizeof(uint32_t));
  assert(byteLength > 0);
  assert((byteLength % 4) == 0);
  
  uint32_t *maxvidCodeBuffer = *maxvidCodeBufferPtr;
  uint32_t maxvidCodeBufferNumBytesSize = *maxvidCodeBufferNumBytesPtr;
  
  if (maxvidCodeBufferNumBytesSize < byteLength) {
    if (maxvidCodeBuffer != NULL) {
      free(maxvidCodeBuffer);
    }
    maxvidCodeBuffer = malloc(byteLength);
    bzero(maxvidCodeBuffer, byteLength);
    maxvidCodeBufferNumBytesSize = byteLength;
    
    // Write new buffer pointer and size back to in/out pointers
    *maxvidCodeBufferPtr = maxvidCodeBuffer;
    *maxvidCodeBufferNumBytesPtr = maxvidCodeBufferNumBytesSize;
  }
  
  assert(maxvidCodeBuffer != NULL);
  assert(maxvidCodeBufferNumBytesSize > 0);
      
  uint32_t numMaxvidCodeWords = maxvidCodeBufferNumBytesSize / sizeof(uint32_t);
  
  uint32_t retcode;
  
  if (bpp == 16) {
    retcode = movdata_convert_maxvid_decode_rle_sample16((void*)movSampleBuffer, movSampleBufferNumBytes,
                                               isKeyframe,
                                               (void*)maxvidCodeBuffer, &numMaxvidCodeWords,
                                               width, height);
  } else if (bpp == 24) {
    retcode = movdata_convert_maxvid_decode_rle_sample24((void*)movSampleBuffer, movSampleBufferNumBytes,
                                               isKeyframe,
                                               (void*)maxvidCodeBuffer, &numMaxvidCodeWords,
                                               width, height);      
  } else if (bpp == 32) {
    retcode = movdata_convert_maxvid_decode_rle_sample32((void*)movSampleBuffer, movSampleBufferNumBytes,
                                               isKeyframe,
                                               (void*)maxvidCodeBuffer, &numMaxvidCodeWords,
                                               width, height);      
  } else {
    assert(0);
  }

  assert(retcode == 0);
  
  // On return, numCodeWords contains the number of words actually used.
  
  assert(numMaxvidCodeWords > 0);
  
  // Convert the generic maxvid codes to the optimized c4 encoding and append to the output file
  
  FILE *tmpfp = tmpfile();
  if (tmpfp == NULL) {
    assert(0);
  }
  
  if (bpp == 16) {
    retcode = maxvid_encode_c4_sample16(maxvidCodeBuffer, numMaxvidCodeWords, width * height, NULL, tmpfp, 0);
  } else if (bpp == 24 || bpp == 32) {
    retcode = maxvid_encode_c4_sample32(maxvidCodeBuffer, numMaxvidCodeWords, width * height, NULL, tmpfp, 0);
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
        
        BOOL worked = [aVMvidFileWriter writeDeltaframe:buffer bufferSize:filesize adler:adler];
        
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
  
  return retcode;
}

static inline
uint32_t
fwrite_word(FILE *fp, uint32_t word) {
  size_t size = fwrite(&word, sizeof(uint32_t), 1, fp);
  if (size != 1) {
    return MV_ERROR_CODE_WRITE_FAILED;
  }
  return 0;
}

static uint32_t
process_frames(MovData *movData, char *mappedMovData,
               uint32_t width, uint32_t height,
               uint32_t bpp,
               AVMvidFileWriter *aVMvidFileWriter,
               uint32_t genAdler)
{
  uint32_t retcode = 0;
  BOOL worked;

  assert(width > 0);
  assert(height > 0);

  void *frameBuffer = NULL;

  MovSample **frames = movData->frames;
  
  uint32_t *maxvidCodeBuffer = NULL;
  uint32_t maxvidCodeBufferNumBytes = 0;
  
  // totalNumFrames is the total count of frame in animation
  
  aVMvidFileWriter.totalNumFrames = movData->numFrames;
  assert(aVMvidFileWriter.totalNumFrames > 1);
  
  // frameDuration is the length in seconds of 1 frame
  
  aVMvidFileWriter.frameDuration = 1.0 / movData->fps;
  assert(aVMvidFileWriter.frameDuration > 0.0);
  
  // bpp is 16, 24, or 32 BPP depending on pixel format
  
  aVMvidFileWriter.bpp = bpp;
  
  // width x height
  
  aVMvidFileWriter.movieSize = CGSizeMake(width, height);
  
  // Open output file and write initial header data
  
  worked = [aVMvidFileWriter open];
  
  if (worked == FALSE) {
    retcode = MV_ERROR_CODE_WRITE_FAILED;
    goto RETCODE;
  }
  
  // Write 
    
  // There is always going to be at least 1 keyframe in a file, so allocate now
  // instead of in the loop
  
  uint16_t *frameBuffer16 = NULL;
  uint32_t *frameBuffer32 = NULL;
  uint32_t bitDepth = movData->bitDepth;
  
  int frameBufferNumBytes;
  if (bitDepth == 16) {
    frameBufferNumBytes = sizeof(uint16_t) * width * height;
    frameBuffer16 = valloc(frameBufferNumBytes);
    bzero(frameBuffer16, sizeof(frameBufferNumBytes));
    frameBuffer = frameBuffer16;
  } else if (bitDepth == 24 || bitDepth == 32) {
    frameBufferNumBytes = sizeof(uint32_t) * width * height;
    frameBuffer32 = valloc(frameBufferNumBytes);
    bzero(frameBuffer32, frameBufferNumBytes);
    frameBuffer = frameBuffer32;
  } else {
    assert(0);
  }
  
  // Loop over each frame and write contents of mov frames to mvid file
  
  for (int i = 0 ; i <  movData->numFrames; i++) {
    MovSample *frame = frames[i];

    // keyframe property is set for normal frame and no-op frame
    
    uint32_t isKeyFrame = movsample_iskeyframe(frame);
        
    //fprintf(stdout, "Frame %d [%d %d] : iskeyframe %d\n", i, frame->offset, movsample_length(frame), movsample_iskeyframe(frame));
    
    if ((i > 0) && (frame == frames[i-1])) {
      // This frame is a no-op, since it duplicates data from the previous frame.
      
      //fprintf(stdout, "Frame %d NOP\n", i);
      
      // Reading a no-op frame after a regular frame is a no-op. But, seeking to a no-op frame must start decoding
      // at the original file offset that appears before the no-op frame. The complication is that multiple no-op
      // frames can appear in a row, so deal with this by duplicating the offset and length of the previous frame
      // when the no-op case is detected.
      
      [aVMvidFileWriter writeNopFrame];
    } else {
      // The current frame is not a nop frame, it can be a keyframe or a delta frame
      
      // Get pointer to the start of the delta data in the mapped file
      
      char *mappedPtr = mappedMovData + frame->offset;
      uint32_t mappedNumBytes = movsample_length(frame);
                  
      if (isKeyFrame) {
        // A keyframe is a special case where a zero-copy optimization can be used.
        // Extract the movdata into a framebuffer and write the contents
        // of the framebuffer to the mvid file. Use the movdata module to extract
        // the framebuffer contents instead of converting to c4 codes and then
        // extracting so that this convert module works even when no code to decompress
        // c4 codes is available.
        
        uint32_t status = process_rle_sample(mappedMovData, movData, frame, frameBuffer);
        
        if (status) {
          retcode = status;
          goto RETCODE;
        }
                        
        worked = [aVMvidFileWriter writeKeyframe:frameBuffer bufferSize:frameBufferNumBytes];
        
        if (worked == FALSE) {
          retcode = MV_ERROR_CODE_WRITE_FAILED;
          goto RETCODE;
        }
      } else {
        // Convert frame of animation data to maxvid c4 encoding
        
        uint32_t adler = 0;
        
        if (genAdler) {
          // Apply the delta to the framebuffer and generate a new adler32 checksum
          
          uint32_t status = process_rle_sample(mappedMovData, movData, frame, frameBuffer);
          
          if (status) {
            retcode = status;
            goto RETCODE;
          }
          
          adler = maxvid_adler32(0, frameBuffer, frameBufferNumBytes);
          assert(adler != 0);
        }
        
        uint32_t status =    
        movdata_convert_and_write_maxvid_frame(mappedPtr, mappedNumBytes,
                               isKeyFrame,
                               &maxvidCodeBuffer,
                               &maxvidCodeBufferNumBytes,
                               aVMvidFileWriter,
                               width,
                               height,
                               bpp,
                               adler);
        if (status) {
          retcode = status;
          goto RETCODE;
        }
      }      
    }
  }

  // Rewrite the header data now that all mvid data has been written
  
  worked = [aVMvidFileWriter rewriteHeader];
  
  if (worked == FALSE) {
    retcode = MV_ERROR_CODE_WRITE_FAILED;
    goto RETCODE;
  }
     
  // Cleanup

RETCODE:
  if (maxvidCodeBuffer) {
    free(maxvidCodeBuffer);
  }
  if (frameBuffer) {
    free(frameBuffer);
  }
  
  return retcode;
}

// Util function to open a .mov file and init a MovData member.
// The caller will need to invoke movdata_free() to release the
// MovData member initialized in this function.

uint32_t
movdata_convert_open_file(
                          char *inMovPath,
                          uint32_t inMovDataNumBytes,
                          MovData *movData)
{
  // Open input .mov and read frame data
  
  movdata_init(movData);
  
  // FIXME: current impl of process_atoms() depends on passing a FILE* and reading
  // the data from a file pointer. If reading bytes from a stream, the entire file
  // might not be ready. And, in the case where the mdat appears before the header
  // info, then the file can't be processed until all the mov data has been extracted.
  // A better design might be able to examine a partial buffer of data to see if the
  // header is before the mdat (streaming enabled).
  
  FILE *movFile = fopen(inMovPath, "r");
  if (movFile == NULL) {
    return MV_ERROR_CODE_INVALID_FILENAME;
  }
  
  uint32_t result;
  
  result = process_atoms(movFile, movData, inMovDataNumBytes);
  if (result) {
    return MV_ERROR_CODE_INVALID_INPUT;
  }
  
  result = process_sample_tables(movFile, movData);
  if (result) {
    return MV_ERROR_CODE_INVALID_INPUT;
  }
  
  assert(movData->numFrames != 0);

  fclose(movFile);
  
  return 0;
}

uint32_t
movdata_convert_maxvid_file(
                            NSString *inMovPath,
                            char *inMovData,
                            uint32_t inMovDataNumBytes,
                            NSString *outMaxvidPath,
                            uint32_t genAdler)
{
  uint32_t retcode = 0;
  
  AVMvidFileWriter *aVMvidFileWriter = nil;
  aVMvidFileWriter = [AVMvidFileWriter aVMvidFileWriter];
  
  aVMvidFileWriter.mvidPath = outMaxvidPath;
  aVMvidFileWriter.genAdler = genAdler;
  
  // Open input .mov and read frame data
  
  MovData movData;
  movdata_convert_open_file((char*)[inMovPath UTF8String], inMovDataNumBytes, &movData);
  
  uint32_t width = movData.width;
  uint32_t height = movData.height;
  uint32_t bpp = movData.bitDepth;
  
  // Process each frame in the mov file, convert to maxvid frames
  
  retcode = process_frames(&movData, inMovData, width, height, bpp, aVMvidFileWriter, genAdler);
  
  movdata_free(&movData);
  
  return retcode;
}
