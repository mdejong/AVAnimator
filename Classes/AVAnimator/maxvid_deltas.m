// maxvid_deltas module
//
//  License terms defined in License.txt.
//

#import "maxvid_deltas.h"

#import "AVMvidFileWriter.h"

#if MV_ENABLE_DELTAS

// inline impl of 32BPP delta operation where each component byte is
// treated as a uint8_t. Overflow and underflow are bound to 0 -> 255
// for each component in the pixel.

static
inline
uint32_t delta_pixel(uint32_t newValue, uint32_t prevValue)
{
  uint32_t deltaPixel;
  
  //deltaPixel = newValue - prevValue;
  
  uint8_t newValueAlpha = (newValue >> 24) & 0xFF;
  uint8_t newValueRed = (newValue >> 16) & 0xFF;
  uint8_t newValueGreen = (newValue >> 8) & 0xFF;
  uint8_t newValueBlue = (newValue >> 0) & 0xFF;
  
  uint8_t prevValueAlpha = (prevValue >> 24) & 0xFF;
  uint8_t prevValueRed = (prevValue >> 16) & 0xFF;
  uint8_t prevValueGreen = (prevValue >> 8) & 0xFF;
  uint8_t prevValueBlue = (prevValue >> 0) & 0xFF;
  
  uint8_t deltaValueAlpha = newValueAlpha - prevValueAlpha;
  uint8_t deltaValueRed = newValueRed - prevValueRed;
  uint8_t deltaValueGreen = newValueGreen - prevValueGreen;
  uint8_t deltaValueBlue = newValueBlue - prevValueBlue;
  
  deltaPixel = (deltaValueAlpha << 24) | (deltaValueRed << 16)
  | (deltaValueGreen << 8) | deltaValueBlue;
  
  return deltaPixel;
}

// Invert the previous delta operation by adding component values

static
inline
uint32_t undelta_pixel(uint32_t newValue, uint32_t prevValue)
{
  uint32_t undeltaPixel;
  
  //deltaPixel = newValue + prevValue;
  
  uint8_t newValueAlpha = (newValue >> 24) & 0xFF;
  uint8_t newValueRed = (newValue >> 16) & 0xFF;
  uint8_t newValueGreen = (newValue >> 8) & 0xFF;
  uint8_t newValueBlue = (newValue >> 0) & 0xFF;
  
  uint8_t prevValueAlpha = (prevValue >> 24) & 0xFF;
  uint8_t prevValueRed = (prevValue >> 16) & 0xFF;
  uint8_t prevValueGreen = (prevValue >> 8) & 0xFF;
  uint8_t prevValueBlue = (prevValue >> 0) & 0xFF;
  
  uint8_t deltaValueAlpha = newValueAlpha + prevValueAlpha;
  uint8_t deltaValueRed = newValueRed + prevValueRed;
  uint8_t deltaValueGreen = newValueGreen + prevValueGreen;
  uint8_t deltaValueBlue = newValueBlue + prevValueBlue;
  
  undeltaPixel = (deltaValueAlpha << 24) | (deltaValueRed << 16)
  | (deltaValueGreen << 8) | deltaValueBlue;
  
  return undeltaPixel;
}

// Rewrite generic maxvid delta pixel values to a more compact
// format as compared to the regular pixels. This rewrite logic
// is executed before the generic codes are passed through the
// c4 emitter logic. The simplified codes are easier to work with.

BOOL
maxvid_deltas_compress(NSData *maxvidInData,
                       NSMutableData *maxvidOutData,
                       void *inputBuffer,
                       uint32_t inputBufferNumBytes,
                       NSUInteger frameBufferNumPixels,
                       uint32_t processAsBPP)
{
  assert(maxvidInData);
  assert([maxvidInData length] > 0);
  assert(maxvidOutData);
  assert(inputBuffer);
  assert(inputBufferNumBytes > 0);
  assert(frameBufferNumPixels > 0);
  
  if (MV_DELTAS_SUBTRACT_PIXELS == 0) {
    // nop
    [maxvidOutData appendData:maxvidInData];
    return TRUE;
  }
  
  // Loop over each generic code in the buffer and convert COPY codes to COPYD codes
  // which indicate a COPY but with a pixel value delta that will be applied when
  // decoded.
  
  assert((inputBufferNumBytes % 4) == 0);
  const int numWords = [maxvidInData length] / 4;
  
  assert(processAsBPP == 32); // FIXME: add 16bpp later ?
  
  // This is the pixel value of the "last pixel". Note that this value is reset to
  // black at the start of each frame to make sure it is possible to decode a
  // frame without depending on decoding of the previous frame at this point.
  
  uint32_t lastPixel = 0x0;
  
  int wordi = 0;
  
#define LOG_PIXEL_DELTAS 0
  
  while (wordi < numWords) {
    NSRange wordRange;
    wordRange.location = wordi * 4;
    wordRange.length = 4;
    uint32_t inWord;
    [maxvidInData getBytes:&inWord range:wordRange];
    
    // The "SKIP", and "DONE" codes are simply copied to the output
    // The "DUP", "COPY" codes are converted to relative values
    
    MV32_PARSE_OP_NUM_SKIP(inWord, opCode, num, skip);
    
    if (LOG_PIXEL_DELTAS) {
      char *codePtr = "";
      if (opCode == SKIP) {
        codePtr = "SKIP";
      } else if (opCode == DUP) {
        codePtr = "DUP";
      } else if (opCode == COPY) {
        codePtr = "COPY";
      } else if (opCode == DONE) {
        codePtr = "DONE";
      }
      
      NSLog(@"wordi %d, op %s, num %d, skip %d", wordi, codePtr, num, skip);
    }
    
    if (opCode == SKIP) {
      // A SKIP code is 1 word
      [maxvidOutData appendBytes:&inWord length:sizeof(uint32_t)];
      wordi++;
    } else if (opCode == DUP) {
      // A DUP code consists of 2 words
      [maxvidOutData appendBytes:&inWord length:sizeof(uint32_t)];
      wordi += 1;
      wordRange.location = wordi * 4;
      [maxvidInData getBytes:&inWord range:wordRange];
      
      // Adjust the DUP pixel value to be an offset as compared to the previous pixel
      
      if (LOG_PIXEL_DELTAS) {
        NSLog(@"DUPI  0x%.8X", inWord);
        NSLog(@"LASTP 0x%.8X", lastPixel);
      }
      
      uint32_t deltaPixel = delta_pixel(inWord, lastPixel);
      lastPixel = inWord;
      [maxvidOutData appendBytes:&deltaPixel length:sizeof(uint32_t)];
      wordi += 1;
      
      if (LOG_PIXEL_DELTAS) {
        NSLog(@"DUPO  0x%.8X", deltaPixel);
      }
    } else if (opCode == DONE) {
      // A DONE code is a single word
      [maxvidOutData appendBytes:&inWord length:sizeof(uint32_t)];
      wordi++;
    } else if (opCode == COPY) {
      // A COPY code is 1 word, it is followed by N actual word values.
      
      [maxvidOutData appendBytes:&inWord length:sizeof(uint32_t)];
      wordi += 1;
      
      uint32_t newMax = wordi + num;
      assert(newMax < numWords);
      
      while (wordi < newMax) {
        wordRange.location = wordi * 4;
        [maxvidInData getBytes:&inWord range:wordRange];
        
        if (LOG_PIXEL_DELTAS) {
          NSLog(@"COPYI 0x%.8X", inWord);
          NSLog(@"LASTP 0x%.8X", lastPixel);
        }
        
        uint32_t deltaPixel = delta_pixel(inWord, lastPixel);
        
        if (LOG_PIXEL_DELTAS) {
          NSLog(@"COPYO 0x%.8X", deltaPixel);
        }
        
        if (LOG_PIXEL_DELTAS && 0) {
          // Undo the operation by adding the adjusted value to the previous
          // pixel value and printing the result.
          
          uint32_t reversed = undelta_pixel(deltaPixel, lastPixel);
          NSLog(@"REVR  0x%.8X", reversed);
        }
        
        lastPixel = inWord;
        [maxvidOutData appendBytes:&deltaPixel length:sizeof(uint32_t)];
        wordi += 1;
      }
    } else {
      // Any other code means something has gone very wrong because a valid
      // code cannot be found.
      
      assert(0);
      return FALSE;
    }
  }
  
  // Verify that all input words were consumed
  assert(wordi == numWords);
  
  // FIXME: this will no longer be valid once word codes are modified
  assert([maxvidInData length] == [maxvidOutData length]);
  
  return TRUE;
}

// Rewrite generic maxvid delta codes to "pixel delta" codes where each
// pixel data element is a delta as compared to the previous pixel.
// Currently, this method assumes that the input and the output size
// are exactly the same and that no codes are changed into other codes.

uint32_t
maxvid_deltas_decompress16(uint32_t *inputBuffer32, uint32_t *outputBuffer32, uint32_t inputBuffer32NumWords)
{
  if (MV_DELTAS_SUBTRACT_PIXELS == 0) {
    memcpy(outputBuffer32, inputBuffer32, inputBuffer32NumWords * 4);
    return 0;
  }
  
  // FIXME: impl 16
  
  return 0;
}

uint32_t
maxvid_deltas_decompress32(uint32_t *inputBuffer32, uint32_t *outputBuffer32, uint32_t inputBuffer32NumWords)
{
  if (MV_DELTAS_SUBTRACT_PIXELS == 0) {
    memcpy(outputBuffer32, inputBuffer32, inputBuffer32NumWords * 4);
    return 0;
  }
  
  uint32_t lastPixel = 0x0;
  
  int wordi = 0;
  
  while (wordi < inputBuffer32NumWords) {
    uint32_t inWord = *inputBuffer32++;
    
    // The "SKIP", and "DONE" codes are simply copied to the output
    // The "DUP", "COPY" codes are converted to relative values
    
    MV32_PARSE_OP_NUM_SKIP(inWord, opCode, num, skip);
    
    if (LOG_PIXEL_DELTAS) {
      char *codePtr = "";
      if (opCode == SKIP) {
        codePtr = "SKIP";
      } else if (opCode == DUP) {
        codePtr = "DUP";
      } else if (opCode == COPY) {
        codePtr = "COPY";
      } else if (opCode == DONE) {
        codePtr = "DONE";
      }
      
      NSLog(@"wordi %d, op %s, num %d, skip %d", wordi, codePtr, num, skip);
    }
    
    if (opCode == SKIP) {
      // A SKIP code is 1 word and can be copied as-is.
      *outputBuffer32++ = inWord;
      wordi += 1;
    } else if (opCode == DUP) {
      // A DUP code is 2 words, the code word can be copied as is
      *outputBuffer32++ = inWord;
      
      wordi += 1;
      
      inWord = *inputBuffer32++;
      
      // Adjust the DUP pixel value to be an offset as compared to the previous pixel
      
      if (LOG_PIXEL_DELTAS) {
        NSLog(@"DUPI  0x%.8X", inWord);
        NSLog(@"LASTP 0x%.8X", lastPixel);
      }
      
      uint32_t undeltaPixel = undelta_pixel(inWord, lastPixel);
      lastPixel = undeltaPixel;
      *outputBuffer32++ = undeltaPixel;
      wordi += 1;
      
      if (LOG_PIXEL_DELTAS) {
        NSLog(@"DUPO  0x%.8X", undeltaPixel);
      }
    } else if (opCode == DONE) {
      // A DONE code is a single word, it can be copied as-is
      *outputBuffer32++ = inWord;
      wordi += 1;
      
      // Note that there is always a trailing zero word after
      // the DONE code in a 32BPP stream. Verify the trailing zero
      // and then emit it.
      
      inWord = *inputBuffer32++;
      assert(inWord == 0);
      *outputBuffer32++ = inWord;
      
      break;
    } else if (opCode == COPY) {
      // A COPY code is 1 word, it is followed by N actual word values.
      
      *outputBuffer32++ = inWord;
      wordi += 1;
      
      uint32_t newMax = wordi + num;
      assert(newMax < inputBuffer32NumWords);
      
      while (wordi < newMax) {
        inWord = *inputBuffer32++;
        
        if (LOG_PIXEL_DELTAS) {
          NSLog(@"COPYI 0x%.8X", inWord);
          NSLog(@"LASTP 0x%.8X", lastPixel);
        }
        
        uint32_t undeltaPixel = undelta_pixel(inWord, lastPixel);
        
        if (LOG_PIXEL_DELTAS) {
          NSLog(@"COPYO 0x%.8X", undeltaPixel);
        }
        
        lastPixel = undeltaPixel;
        *outputBuffer32++ = undeltaPixel;
        wordi += 1;
      }
    } else {
      // Any other code means something has gone very wrong because a valid
      // code cannot be found.
      
      assert(0);
      return 1;
    }
  }
  
  // Verify that the last code in both buffers is a DONE code
  
  {
    uint32_t lastInWord = *(inputBuffer32 - 2);
    uint32_t lastOutWord = *(outputBuffer32 - 2);
    
    assert(lastInWord == lastOutWord);
    
    MV32_PARSE_OP_NUM_SKIP(lastInWord, opCode, num, skip);
    
    assert(opCode == DONE);
  }
  
  return 0;
}

#endif // MV_ENABLE_DELTAS

