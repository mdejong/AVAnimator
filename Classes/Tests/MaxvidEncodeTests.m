//
//  MaxvidEncodeTests.m
//
//  Created by Moses DeJong on 9/3/12.
//
//  Test for maxvid format encoding utility functions.
//  Test encoding to the generic maxvid encoding word codes,
//  these will be translated to c4 style encoding in a second step.
//  This logic is needed to verify the correctness of the skip,
//  dup, and copy op detection methods. These frame buffer diff
//  methods take two input buffers and perform a diff on the pixels
//  in the input buffers to construct a delta frame.

#import <Foundation/Foundation.h>

#import "RegressionTests.h"

#import "maxvid_encode.h"

#import "maxvid_decode.h"

static inline
uint32_t num_words_16bpp(uint32_t numPixels) {
  // Return the number of words required to contain
  // the given number of pixels.
  return (numPixels >> 1) + (numPixels & 0x1);
}

@interface MaxvidEncodeTests : NSObject {
}
@end

// Private API decl

@interface MaxvidEncodeTests ()

+ (NSString*) util_printMvidCodes16:(NSData*)codes;

+ (NSString*) util_printMvidCodes32:(NSData*)codes;

+ (NSString*) util_convertAndPrintC4Codes16:(NSData*)codes
                       frameBufferNumPixels:(NSUInteger)frameBufferNumPixels;

+ (NSString*) util_convertAndPrintC4Codes32:(NSData*)codes
                       frameBufferNumPixels:(NSUInteger)frameBufferNumPixels;

@end

// implementation

@implementation MaxvidEncodeTests

// Debug print method for 16 bit codes

+ (NSString*) util_printMvidCodes16:(NSData*)codes
{
  if (codes == nil) {
    return @"IDENTICAL";
  }
  
  NSMutableString *mStr = [NSMutableString string];
  
  int index = 0;
  int end = (int) ([codes length] / sizeof(uint32_t));
  uint32_t *ptr = (uint32_t *)codes.bytes;
  
  for ( ; index < end; ) {
    uint32_t inword = ptr[index];
    
    MV16_READ_OP_VAL_NUM(inword, opCode, val, num);
    
    if (opCode == SKIP) {
      [mStr appendFormat:@"SKIP %d ", num];
      index++;
    } else if (opCode == COPY) {
      [mStr appendFormat:@"COPY %d ", num];
      index++;
      
      // pixels are stored 2 in a word, padded to a
      // whole number of words.

      int numPixels = num;
      int numWords = num_words_16bpp(numPixels);
      
      for ( int count = numWords; count ; count-- ) {
        inword = ptr[index++];
        numPixels--;
        [mStr appendFormat:@"0x%X ", (inword & 0xFFFF)];
        if (numPixels > 0) {
          numPixels--;
          [mStr appendFormat:@"0x%X ", ((inword >> 16) & 0xFFFF)];
        }
      }
    } else if (opCode == DUP) {
      // DUP word contains the number and the next word contains the pixel
      index++;
      inword = ptr[index++];
      uint16_t pixel16 = (uint16_t)inword;      
      [mStr appendFormat:@"DUP %d 0x%X ", num, pixel16];
    } else if (opCode == DONE) {
      [mStr appendFormat:@"DONE"];
      index++;
    } else {
      assert(FALSE);
    }
  }
  assert(index == end);
  
  return [NSString stringWithString:mStr];
}

// Debug print method for 32 bit codes

+ (NSString*) util_printMvidCodes32:(NSData*)codes
{
  if (codes == nil) {
    return @"IDENTICAL";
  }
  
  NSMutableString *mStr = [NSMutableString string];
    
  int index = 0;
  int end = (int) ([codes length] / sizeof(uint32_t));
  uint32_t *ptr = (uint32_t *)codes.bytes;
  
  for ( ; index < end; ) {
    uint32_t inword = ptr[index];
    
    MV32_PARSE_OP_NUM_SKIP(inword, opCode, num, skip);
    
    if (opCode == SKIP) {
      [mStr appendFormat:@"SKIP %d ", num];
      index++;
    } else if (opCode == COPY) {
      [mStr appendFormat:@"COPY %d ", num];
      assert(skip == 0);
      
      index++;
      
      // foreach word in copy, write as hex!
      
      for ( int count = num; count ; count-- ) {
        inword = ptr[index];
        [mStr appendFormat:@"0x%X ", inword];
        index++;
      }
    } else if (opCode == DUP) {
      assert(skip == 0);
      
      // DUP is followed by a single word to indicate the dup pixel
      index++;
      inword = ptr[index];
      index++;
      
      [mStr appendFormat:@"DUP %d 0x%X ", num, inword];
    } else if (opCode == DONE) {
      [mStr appendFormat:@"DONE"];
      index++;
    } else {
      assert(FALSE);
    }
  }
  assert(index == end);
  
  return [NSString stringWithString:mStr];
}

// This method will convert generic 16BPP codes to m4 codes and print them.
// m4 codes are more complex than generic codes because multiple
// code elements can be condensed together.

+ (NSString*) util_convertAndPrintC4Codes16:(NSData*)codes
                       frameBufferNumPixels:(NSUInteger)frameBufferNumPixels
{
  if (codes == nil) {
    return @"IDENTICAL";
  }
  
  NSMutableData *mC4Data = [NSMutableData dataWithCapacity:frameBufferNumPixels];
  
  // Convert generic codes to m4 codes at 16BPP
  
  uint32_t *maxvidCodeBuffer = (uint32_t*)codes.bytes;
  uint32_t numMaxvidCodeWords = (uint32_t) (codes.length / sizeof(uint32_t));
  
  int retcode;
  retcode = maxvid_encode_c4_sample16(maxvidCodeBuffer, numMaxvidCodeWords, (uint32_t)frameBufferNumPixels, mC4Data, 0);
  assert(retcode == 0);
  
  // Format c4 codes as string entries
  
  NSMutableString *mStr = [NSMutableString string];
  
  int index = 0;
  int end = (int) ([mC4Data length] / sizeof(uint32_t));
  uint32_t *ptr = (uint32_t *)mC4Data.bytes;
  
  int frameBufferNumPixelsWritten = 0;
  
  for ( ; index < end; ) {
    uint32_t inword = ptr[index];
    
    MV16_READ_OP_VAL_NUM(inword, opCode, val, num);
    
    if (opCode == SKIP) {
      // Note that SKIP has a special binary layout such that the
      // entire skip value as a 30 bit unsigned number is exactly
      // the same as treating the word code as a 32 bit number.
      uint32_t skipNumPixels = inword;
      assert(skipNumPixels > 0);
      [mStr appendFormat:@"SKIP %d ", skipNumPixels];
      index++;
      frameBufferNumPixelsWritten += skipNumPixels;
    } else if (opCode == COPY) {
      [mStr appendFormat:@"COPY %d ", val];
      index++;
      
      // The first pixel value is implicitly stored in the
      // num slot in the COPY word when the 16BPP framebuffer
      // is half word aligned. This logic is an optimization
      // so that the next write can be in terms of a whole word.
      
      // FIXME: use frameBufferNumPixels to determine when num
      // pixels is odd.
      
      // not :       if ((numPixels % 2) != 0)
      
      int numPixels = val;
      
      if (((frameBufferNumPixelsWritten % 2) != 0) || (val == 1)) {
        assert(val > 0);
        [mStr appendFormat:@"0x%X ", num];
        numPixels -= 1;
        frameBufferNumPixelsWritten += 1;
      }
      
      // pixels are stored 2 in a word, padded to a
      // whole number of words.
      
      int numWords = num_words_16bpp(numPixels);
      
      for ( int count = numWords; count ; count-- ) {
        inword = ptr[index++];
        numPixels--;
        [mStr appendFormat:@"0x%X ", (inword & 0xFFFF)];
        frameBufferNumPixelsWritten += 1;
        if (numPixels > 0) {
          numPixels--;
          [mStr appendFormat:@"0x%X ", ((inword >> 16) & 0xFFFF)];
          frameBufferNumPixelsWritten += 1;
        }
      }
    } else if (opCode == DUP) {
      // DUP val contains the number and num contains the pixel
      index++;
      uint16_t pixel16 = (uint16_t)num;
      [mStr appendFormat:@"DUP %d 0x%X ", val, pixel16];
      frameBufferNumPixelsWritten += val;
    } else if (opCode == DONE) {
      [mStr appendFormat:@"DONE"];
      index++;
    } else {
      assert(FALSE);
    }
  }
  assert(index == end);
  assert(frameBufferNumPixelsWritten == frameBufferNumPixels);
  
  return [NSString stringWithString:mStr];
}

// This method will convert generic 32BPP codes to m4 codes and print them.
// m4 codes are more complex than generic codes because multiple
// code elements can be condensed together.

+ (NSString*) util_convertAndPrintC4Codes32:(NSData*)codes
                       frameBufferNumPixels:(NSUInteger)frameBufferNumPixels
{
  if (codes == nil) {
    return @"IDENTICAL";
  }
  
  // Convert generic codes to m4 codes at 32BPP
  
  NSMutableData *mC4Data = [NSMutableData dataWithCapacity:frameBufferNumPixels];
  
  uint32_t *maxvidCodeBuffer = (uint32_t*)codes.bytes;
  uint32_t numMaxvidCodeWords = (uint32_t) (codes.length / sizeof(uint32_t));
  
  int retcode;
  retcode = maxvid_encode_c4_sample32(maxvidCodeBuffer, numMaxvidCodeWords, (uint32_t)frameBufferNumPixels, mC4Data, 0);
  assert(retcode == 0);
  
  // Format c4 codes as string entries
  
  NSMutableString *mStr = [NSMutableString string];
  
  int index = 0;
  int end = (int) ([mC4Data length] / sizeof(uint32_t));
  uint32_t *ptr = (uint32_t *)mC4Data.bytes;
  
  for ( ; index < end; ) {
    uint32_t inword = ptr[index];
    
    MV32_PARSE_OP_NUM_SKIP(inword, opCode, num, skip);
    
    if (opCode == SKIP) {
      // For the 32 bit SKIP encoding, the 22 bit num field is
      // used to encode the num value. Note that the skip field
      // is always zero in this case.
      
      assert(num > 0);
      [mStr appendFormat:@"SKIP %d ", num];
      index++;
    } else if (opCode == COPY) {
      [mStr appendFormat:@"COPY %d ", num];
      
      index++;
      
      // foreach word in copy, write as hex!
      
      for ( int count = num; count ; count-- ) {
        inword = ptr[index];
        [mStr appendFormat:@"0x%X ", inword];
        index++;
      }
      
      if (skip > 0) {
        [mStr appendFormat:@"(SKIP %d) ", skip];
      }
    } else if (opCode == DUP) {
      // DUP is followed by a single word to indicate the dup pixel
      index++;
      inword = ptr[index];
      index++;
      
      [mStr appendFormat:@"DUP %d 0x%X ", num, inword];
      
      if (skip > 0) {
        [mStr appendFormat:@"(SKIP %d) ", skip];
      }
    } else if (opCode == DONE) {
      [mStr appendFormat:@"DONE"];
      index++;
      // Note that a c4 DONE code is always followed by a zero value, skip over it
      assert(ptr[index] == 0);
      index++;
    } else {
      assert(FALSE);
    }
  }
  assert(index == end);
  
  return [NSString stringWithString:mStr];
}

// This test case checks a 1x1 frame with identical 16bit pixel values.

+ (void) testEncode1x1IdenticalAt16BPP
{
  uint16_t prev[] = { 0x1 };
  uint16_t curr[] = { 0x1 };
  
  NSData *codes;
  NSString *results;
  
  codes = maxvid_encode_generic_delta_pixels16(prev, curr, sizeof(curr)/sizeof(uint16_t), 1, 1, NULL, 0);
  results = [self util_printMvidCodes16:codes];
  NSAssert([results isEqualToString:@"IDENTICAL"], @"isEqualToString");

  results = [self util_convertAndPrintC4Codes16:codes frameBufferNumPixels:sizeof(curr)/sizeof(uint16_t)];
  NSAssert([results isEqualToString:@"IDENTICAL"], @"isEqualToString");
  
  return;
}

// This test case checks a 1x1 frame with identical 32bit pixel values.

+ (void) testEncode1x1IdenticalAt32BPP
{
  uint32_t prev[] = { 0x1 };
  uint32_t curr[] = { 0x1 };
  
  NSData *codes;
  NSString *results;
  
  codes = maxvid_encode_generic_delta_pixels32(prev, curr, sizeof(curr)/sizeof(uint32_t), 1, 1, NULL, 0);
  results = [self util_printMvidCodes32:codes];
  NSAssert([results isEqualToString:@"IDENTICAL"], @"isEqualToString");
  
  results = [self util_convertAndPrintC4Codes32:codes frameBufferNumPixels:sizeof(curr)/sizeof(uint32_t)];
  NSAssert([results isEqualToString:@"IDENTICAL"], @"isEqualToString");

  return;
}

// This test case checks a 1x1 frame with different 32bit pixel values.

+ (void) testEncode1x1DifferentAt16BPP
{
  uint16_t prev[] = { 0x1 };
  uint16_t curr[] = { 0x2 };
  
  NSData *codes;
  NSString *results;
  
  codes = maxvid_encode_generic_delta_pixels16(prev, curr, sizeof(curr)/sizeof(uint16_t), 1, 1, NULL, 0);
  results = [self util_printMvidCodes16:codes];
  NSAssert([results isEqualToString:@"COPY 1 0x2 DONE"], @"isEqualToString");

  results = [self util_convertAndPrintC4Codes16:codes frameBufferNumPixels:sizeof(curr)/sizeof(uint16_t)];
  NSAssert([results isEqualToString:@"COPY 1 0x2 DONE"], @"isEqualToString");
  
  return;
}

// This test case checks a 1x1 frame with different 32bit pixel values.

+ (void) testEncode1x1DifferentAt32BPP
{
  uint32_t prev[] = { 0x1 };
  uint32_t curr[] = { 0x2 };
  
  NSData *codes;
  NSString *results;
  
  codes = maxvid_encode_generic_delta_pixels32(prev, curr, sizeof(curr)/sizeof(uint32_t), 1, 1, NULL, 0);
  results = [self util_printMvidCodes32:codes];
  NSAssert([results isEqualToString:@"COPY 1 0x2 DONE"], @"isEqualToString");
  
  results = [self util_convertAndPrintC4Codes32:codes frameBufferNumPixels:sizeof(curr)/sizeof(uint32_t)];
  NSAssert([results isEqualToString:@"COPY 1 0x2 DONE"], @"isEqualToString");
  
  return;
}

// Check that a SKIP is being emitted after a delta pixel

+ (void) testEncode2x1CopySkipAt16BPP
{
  uint16_t prev[] = { 0x1, 0x2 };
  uint16_t curr[] = { 0x3, 0x2 };
  
  NSData *codes;
  NSString *results;
  
  codes = maxvid_encode_generic_delta_pixels16(prev, curr, sizeof(curr)/sizeof(uint16_t), 2, 1, NULL, 0);
  results = [self util_printMvidCodes16:codes];
  NSAssert([results isEqualToString:@"COPY 1 0x3 SKIP 1 DONE"], @"isEqualToString");
 
  results = [self util_convertAndPrintC4Codes16:codes frameBufferNumPixels:sizeof(curr)/sizeof(uint16_t)];
  NSAssert([results isEqualToString:@"COPY 1 0x3 SKIP 1 DONE"], @"isEqualToString");
  
  return;
}

// Check that a SKIP is being emitted after a delta pixel

+ (void) testEncode2x1CopySkipAt32BPP
{
  uint32_t prev[] = { 0x1, 0x2 };
  uint32_t curr[] = { 0x3, 0x2 };
  
  NSData *codes;
  NSString *results;
  
  codes = maxvid_encode_generic_delta_pixels32(prev, curr, sizeof(curr)/sizeof(uint32_t), 2, 1, NULL, 0);
  results = [self util_printMvidCodes32:codes];
  NSAssert([results isEqualToString:@"COPY 1 0x3 SKIP 1 DONE"], @"isEqualToString");
  
  results = [self util_convertAndPrintC4Codes32:codes frameBufferNumPixels:sizeof(curr)/sizeof(uint32_t)];
  NSAssert([results isEqualToString:@"COPY 1 0x3 (SKIP 1) DONE"], @"isEqualToString");
  
  return;
}

// Check that a SKIP is being emitted before a delta pixel

+ (void) testEncode2x1SkipCopyAt16BPP
{
  uint16_t prev[] = { 0x2, 0x1 };
  uint16_t curr[] = { 0x2, 0x3 };
  
  NSData *codes;
  NSString *results;
  
  codes = maxvid_encode_generic_delta_pixels16(prev, curr, sizeof(curr)/sizeof(uint16_t), 2, 1, NULL, 0);
  results = [self util_printMvidCodes16:codes];
  NSAssert([results isEqualToString:@"SKIP 1 COPY 1 0x3 DONE"], @"isEqualToString");
  
  results = [self util_convertAndPrintC4Codes16:codes frameBufferNumPixels:sizeof(curr)/sizeof(uint16_t)];
  NSAssert([results isEqualToString:@"SKIP 1 COPY 1 0x3 DONE"], @"isEqualToString");
  
  return;
}

// Check that a SKIP is being emitted before a delta pixel

+ (void) testEncode2x1SkipCopyAt32BPP
{
  uint32_t prev[] = { 0x2, 0x1 };
  uint32_t curr[] = { 0x2, 0x3 };
  
  NSData *codes;
  NSString *results;
  
  codes = maxvid_encode_generic_delta_pixels32(prev, curr, sizeof(curr)/sizeof(uint32_t), 2, 1, NULL, 0);
  results = [self util_printMvidCodes32:codes];
  NSAssert([results isEqualToString:@"SKIP 1 COPY 1 0x3 DONE"], @"isEqualToString");
  
  results = [self util_convertAndPrintC4Codes32:codes frameBufferNumPixels:sizeof(curr)/sizeof(uint32_t)];
  NSAssert([results isEqualToString:@"SKIP 1 COPY 1 0x3 DONE"], @"isEqualToString");
  
  return;
}

// Emit a SKIP both before and after a COPY

+ (void) testEncode3x1SkipCopySkipAt16BPP
{
  uint16_t prev[] = { 0x2, 0x1, 0x4 };
  uint16_t curr[] = { 0x2, 0x3, 0x4 };
  
  NSData *codes;
  NSString *results;
  
  codes = maxvid_encode_generic_delta_pixels16(prev, curr, sizeof(curr)/sizeof(uint16_t), 3, 1, NULL, 0);
  results = [self util_printMvidCodes16:codes];
  NSAssert([results isEqualToString:@"SKIP 1 COPY 1 0x3 SKIP 1 DONE"], @"isEqualToString");
 
  results = [self util_convertAndPrintC4Codes16:codes frameBufferNumPixels:sizeof(curr)/sizeof(uint16_t)];
  NSAssert([results isEqualToString:@"SKIP 1 COPY 1 0x3 SKIP 1 DONE"], @"isEqualToString");
  
  return;
}

// Emit a SKIP both before and after a COPY

+ (void) testEncode3x1SkipCopySkipAt32BPP
{
  uint32_t prev[] = { 0x2, 0x1, 0x4 };
  uint32_t curr[] = { 0x2, 0x3, 0x4 };
  
  NSData *codes;
  NSString *results;
  
  codes = maxvid_encode_generic_delta_pixels32(prev, curr, sizeof(curr)/sizeof(uint32_t), 3, 1, NULL, 0);
  results = [self util_printMvidCodes32:codes];
  NSAssert([results isEqualToString:@"SKIP 1 COPY 1 0x3 SKIP 1 DONE"], @"isEqualToString");

  results = [self util_convertAndPrintC4Codes32:codes frameBufferNumPixels:sizeof(curr)/sizeof(uint32_t)];
  NSAssert([results isEqualToString:@"SKIP 1 COPY 1 0x3 (SKIP 1) DONE"], @"isEqualToString");
  
  return;
}

+ (void) testEncode3x1CopySkipCopyAt16BPP
{
  uint16_t prev[] = { 0x1, 0x2, 0x3 };
  uint16_t curr[] = { 0x4, 0x2, 0x5 };
  
  NSData *codes;
  NSString *results;
  
  codes = maxvid_encode_generic_delta_pixels16(prev, curr, sizeof(curr)/sizeof(uint16_t), 3, 1, NULL, 0);
  results = [self util_printMvidCodes16:codes];
  NSAssert([results isEqualToString:@"COPY 1 0x4 SKIP 1 COPY 1 0x5 DONE"], @"isEqualToString");
  
  results = [self util_convertAndPrintC4Codes16:codes frameBufferNumPixels:sizeof(curr)/sizeof(uint16_t)];
  NSAssert([results isEqualToString:@"COPY 1 0x4 SKIP 1 COPY 1 0x5 DONE"], @"isEqualToString");
  
  return;
}

+ (void) testEncode3x1CopySkipCopyAt32BPP
{
  uint32_t prev[] = { 0x1, 0x2, 0x3 };
  uint32_t curr[] = { 0x4, 0x2, 0x5 };
  
  NSData *codes;
  NSString *results;
  
  codes = maxvid_encode_generic_delta_pixels32(prev, curr, sizeof(curr)/sizeof(uint32_t), 3, 1, NULL, 0);
  results = [self util_printMvidCodes32:codes];
  NSAssert([results isEqualToString:@"COPY 1 0x4 SKIP 1 COPY 1 0x5 DONE"], @"isEqualToString");
  
  results = [self util_convertAndPrintC4Codes32:codes frameBufferNumPixels:sizeof(curr)/sizeof(uint32_t)];
  NSAssert([results isEqualToString:@"COPY 1 0x4 (SKIP 1) COPY 1 0x5 DONE"], @"isEqualToString");
  
  return;
}

// Two different COPY pixels in a run

+ (void) testEncode2x1CopyCopyAt16BPP
{
  uint16_t prev[] = { 0x1, 0x2 };
  uint16_t curr[] = { 0x3, 0x4 };
  
  NSData *codes;
  NSString *results;
  
  codes = maxvid_encode_generic_delta_pixels16(prev, curr, sizeof(curr)/sizeof(uint16_t), 2, 1, NULL, 0);
  results = [self util_printMvidCodes16:codes];
  NSAssert([results isEqualToString:@"COPY 2 0x3 0x4 DONE"], @"isEqualToString");
  
  results = [self util_convertAndPrintC4Codes16:codes frameBufferNumPixels:sizeof(curr)/sizeof(uint16_t)];
  NSAssert([results isEqualToString:@"COPY 2 0x3 0x4 DONE"], @"isEqualToString");
  
  return;
}

// Two different COPY pixels in a run

+ (void) testEncode2x1CopyCopyAt32BPP
{
  uint32_t prev[] = { 0x1, 0x2 };
  uint32_t curr[] = { 0x3, 0x4 };
  
  NSData *codes;
  NSString *results;
  
  codes = maxvid_encode_generic_delta_pixels32(prev, curr, sizeof(curr)/sizeof(uint32_t), 2, 1, NULL, 0);
  results = [self util_printMvidCodes32:codes];
  NSAssert([results isEqualToString:@"COPY 2 0x3 0x4 DONE"], @"isEqualToString");
  
  results = [self util_convertAndPrintC4Codes32:codes frameBufferNumPixels:sizeof(curr)/sizeof(uint32_t)];
  NSAssert([results isEqualToString:@"COPY 2 0x3 0x4 DONE"], @"isEqualToString");
  
  return;
}

// Three different COPY pixels in a run

+ (void) testEncode3x1CopyCopyCopyAt16BPP
{
  uint16_t prev[] = { 0x1, 0x2, 0x3 };
  uint16_t curr[] = { 0x4, 0x5, 0x6 };
  
  NSData *codes;
  NSString *results;
  
  codes = maxvid_encode_generic_delta_pixels16(prev, curr, sizeof(curr)/sizeof(uint16_t), 3, 1, NULL, 0);
  results = [self util_printMvidCodes16:codes];
  NSAssert([results isEqualToString:@"COPY 3 0x4 0x5 0x6 DONE"], @"isEqualToString");
  
  results = [self util_convertAndPrintC4Codes16:codes frameBufferNumPixels:sizeof(curr)/sizeof(uint16_t)];
  NSAssert([results isEqualToString:@"COPY 3 0x4 0x5 0x6 DONE"], @"isEqualToString");
  
  return;
}

// Three different COPY pixels in a run

+ (void) testEncode3x1CopyCopyCopyAt32BPP
{
  uint32_t prev[] = { 0x1, 0x2, 0x3 };
  uint32_t curr[] = { 0x4, 0x5, 0x6 };
  
  NSData *codes;
  NSString *results;
  
  codes = maxvid_encode_generic_delta_pixels32(prev, curr, sizeof(curr)/sizeof(uint32_t), 3, 1, NULL, 0);
  results = [self util_printMvidCodes32:codes];
  NSAssert([results isEqualToString:@"COPY 3 0x4 0x5 0x6 DONE"], @"isEqualToString");

  results = [self util_convertAndPrintC4Codes32:codes frameBufferNumPixels:sizeof(curr)/sizeof(uint32_t)];
  NSAssert([results isEqualToString:@"COPY 3 0x4 0x5 0x6 DONE"], @"isEqualToString");
  
  return;
}

// Two identical pixels in a run is a DUP

+ (void) testEncode2x1Dup2At16BPP
{
  uint16_t prev[] = { 0x1, 0x2 };
  uint16_t curr[] = { 0x3, 0x3 };
  
  NSData *codes;
  NSString *results;
  
  codes = maxvid_encode_generic_delta_pixels16(prev, curr, sizeof(curr)/sizeof(uint16_t), 2, 1, NULL, 0);
  results = [self util_printMvidCodes16:codes];
  NSAssert([results isEqualToString:@"DUP 2 0x3 DONE"], @"isEqualToString");
 
  results = [self util_convertAndPrintC4Codes16:codes frameBufferNumPixels:sizeof(curr)/sizeof(uint16_t)];
  NSAssert([results isEqualToString:@"DUP 2 0x3 DONE"], @"isEqualToString");
  
  return;
}

// Two identical pixels in a run is a DUP

+ (void) testEncode2x1Dup2At32BPP
{
  uint32_t prev[] = { 0x1, 0x2 };
  uint32_t curr[] = { 0x3, 0x3 };
  
  NSData *codes;
  NSString *results;
  
  codes = maxvid_encode_generic_delta_pixels32(prev, curr, sizeof(curr)/sizeof(uint32_t), 2, 1, NULL, 0);
  results = [self util_printMvidCodes32:codes];
  NSAssert([results isEqualToString:@"DUP 2 0x3 DONE"], @"isEqualToString");
  
  results = [self util_convertAndPrintC4Codes32:codes frameBufferNumPixels:sizeof(curr)/sizeof(uint32_t)];
  NSAssert([results isEqualToString:@"DUP 2 0x3 DONE"], @"isEqualToString");
  
  return;
}

// Two identical DUP pixels followed by a COPY

+ (void) testEncode3x1DupCopy2At16BPP
{
  uint16_t prev[] = { 0x1, 0x2, 0x3 };
  uint16_t curr[] = { 0x3, 0x3, 0x4 };
  
  NSData *codes;
  NSString *results;
  
  codes = maxvid_encode_generic_delta_pixels16(prev, curr, sizeof(curr)/sizeof(uint16_t), 3, 1, NULL, 0);
  results = [self util_printMvidCodes16:codes];
  NSAssert([results isEqualToString:@"DUP 2 0x3 COPY 1 0x4 DONE"], @"isEqualToString");
  
  results = [self util_convertAndPrintC4Codes16:codes frameBufferNumPixels:sizeof(curr)/sizeof(uint16_t)];
  NSAssert([results isEqualToString:@"DUP 2 0x3 COPY 1 0x4 DONE"], @"isEqualToString");
  
  return;
}

// Two identical DUP pixels followed by a COPY

+ (void) testEncode3x1DupCopy2At32BPP
{
  uint32_t prev[] = { 0x1, 0x2, 0x3 };
  uint32_t curr[] = { 0x3, 0x3, 0x4 };
  
  NSData *codes;
  NSString *results;
  
  codes = maxvid_encode_generic_delta_pixels32(prev, curr, sizeof(curr)/sizeof(uint32_t), 3, 1, NULL, 0);
  results = [self util_printMvidCodes32:codes];
  NSAssert([results isEqualToString:@"DUP 2 0x3 COPY 1 0x4 DONE"], @"isEqualToString");
  
  results = [self util_convertAndPrintC4Codes32:codes frameBufferNumPixels:sizeof(curr)/sizeof(uint32_t)];
  NSAssert([results isEqualToString:@"DUP 2 0x3 COPY 1 0x4 DONE"], @"isEqualToString");
  
  return;
}

// COPY followed by two identical DUP pixels

+ (void) testEncode3x1CopyDup2At16BPP
{
  uint16_t prev[] = { 0x1, 0x2, 0x3 };
  uint16_t curr[] = { 0x4, 0x5, 0x5 };
  
  NSData *codes;
  NSString *results;
  
  codes = maxvid_encode_generic_delta_pixels16(prev, curr, sizeof(curr)/sizeof(uint16_t), 3, 1, NULL, 0);
  results = [self util_printMvidCodes16:codes];
  NSAssert([results isEqualToString:@"COPY 1 0x4 DUP 2 0x5 DONE"], @"isEqualToString");
  
  results = [self util_convertAndPrintC4Codes16:codes frameBufferNumPixels:sizeof(curr)/sizeof(uint16_t)];
  NSAssert([results isEqualToString:@"COPY 1 0x4 DUP 2 0x5 DONE"], @"isEqualToString");
  
  return;
}

// COPY followed by two identical DUP pixels

+ (void) testEncode3x1CopyDup2At32BPP
{
  uint32_t prev[] = { 0x1, 0x2, 0x3 };
  uint32_t curr[] = { 0x4, 0x5, 0x5 };
  
  NSData *codes;
  NSString *results;
  
  codes = maxvid_encode_generic_delta_pixels32(prev, curr, sizeof(curr)/sizeof(uint32_t), 3, 1, NULL, 0);
  results = [self util_printMvidCodes32:codes];
  NSAssert([results isEqualToString:@"COPY 1 0x4 DUP 2 0x5 DONE"], @"isEqualToString");
  
  results = [self util_convertAndPrintC4Codes32:codes frameBufferNumPixels:sizeof(curr)/sizeof(uint32_t)];
  NSAssert([results isEqualToString:@"COPY 1 0x4 DUP 2 0x5 DONE"], @"isEqualToString");
  
  return;
}

// DUP COPY DUP in one pixel run

+ (void) testEncode5x1Dup2CopyDup2At16BPP
{
  uint16_t prev[] = { 0x1, 0x2, 0x3, 0x4, 0x5 };
  uint16_t curr[] = { 0x6, 0x6, 0x7, 0x8, 0x8 };
  
  NSData *codes;
  NSString *results;
  
  codes = maxvid_encode_generic_delta_pixels16(prev, curr, sizeof(curr)/sizeof(uint16_t), 5, 1, NULL, 0);
  results = [self util_printMvidCodes16:codes];
  NSAssert([results isEqualToString:@"DUP 2 0x6 COPY 1 0x7 DUP 2 0x8 DONE"], @"isEqualToString");
  
  results = [self util_convertAndPrintC4Codes16:codes frameBufferNumPixels:sizeof(curr)/sizeof(uint16_t)];
  NSAssert([results isEqualToString:@"DUP 2 0x6 COPY 1 0x7 DUP 2 0x8 DONE"], @"isEqualToString");
  
  return;
}

// DUP COPY DUP in one pixel run

+ (void) testEncode5x1Dup2CopyDup2At32BPP
{
  uint32_t prev[] = { 0x1, 0x2, 0x3, 0x4, 0x5 };
  uint32_t curr[] = { 0x6, 0x6, 0x7, 0x8, 0x8 };
  
  NSData *codes;
  NSString *results;
  
  codes = maxvid_encode_generic_delta_pixels32(prev, curr, sizeof(curr)/sizeof(uint32_t), 5, 1, NULL, 0);
  results = [self util_printMvidCodes32:codes];
  NSAssert([results isEqualToString:@"DUP 2 0x6 COPY 1 0x7 DUP 2 0x8 DONE"], @"isEqualToString");
  
  results = [self util_convertAndPrintC4Codes32:codes frameBufferNumPixels:sizeof(curr)/sizeof(uint32_t)];
  NSAssert([results isEqualToString:@"DUP 2 0x6 COPY 1 0x7 DUP 2 0x8 DONE"], @"isEqualToString");
  
  return;
}

// COPY DUP COPY in one pixel run

+ (void) testEncode4x1CopyDup2CopyAt16BPP
{
  uint16_t prev[] = { 0x1, 0x2, 0x3, 0x4 };
  uint16_t curr[] = { 0x5, 0x6, 0x6, 0x7 };
  
  NSData *codes;
  NSString *results;
  
  codes = maxvid_encode_generic_delta_pixels16(prev, curr, sizeof(curr)/sizeof(uint16_t), 4, 1, NULL, 0);
  results = [self util_printMvidCodes16:codes];
  NSAssert([results isEqualToString:@"COPY 1 0x5 DUP 2 0x6 COPY 1 0x7 DONE"], @"isEqualToString");
  
  results = [self util_convertAndPrintC4Codes16:codes frameBufferNumPixels:sizeof(curr)/sizeof(uint16_t)];
  NSAssert([results isEqualToString:@"COPY 1 0x5 DUP 2 0x6 COPY 1 0x7 DONE"], @"isEqualToString");
  
  return;
}

// COPY DUP COPY in one pixel run

+ (void) testEncode4x1CopyDup2CopyAt32BPP
{
  uint32_t prev[] = { 0x1, 0x2, 0x3, 0x4 };
  uint32_t curr[] = { 0x5, 0x6, 0x6, 0x7 };
  
  NSData *codes;
  NSString *results;
  
  codes = maxvid_encode_generic_delta_pixels32(prev, curr, sizeof(curr)/sizeof(uint32_t), 4, 1, NULL, 0);
  results = [self util_printMvidCodes32:codes];
  NSAssert([results isEqualToString:@"COPY 1 0x5 DUP 2 0x6 COPY 1 0x7 DONE"], @"isEqualToString");
  
  results = [self util_convertAndPrintC4Codes32:codes frameBufferNumPixels:sizeof(curr)/sizeof(uint32_t)];
  NSAssert([results isEqualToString:@"COPY 1 0x5 DUP 2 0x6 COPY 1 0x7 DONE"], @"isEqualToString");
  
  return;
}

// SKIP COPY SKIP SKIP

+ (void) testEncode4x1SkipCopySkip2At16BPP
{
  uint16_t prev[] = { 0x1, 0x2, 0x3, 0x3 };
  uint16_t curr[] = { 0x1, 0x3, 0x3, 0x3 };
  
  NSData *codes;
  NSString *results;
  
  codes = maxvid_encode_generic_delta_pixels16(prev, curr, sizeof(curr)/sizeof(uint16_t), 4, 1, NULL, 0);
  results = [self util_printMvidCodes16:codes];
  NSAssert([results isEqualToString:@"SKIP 1 COPY 1 0x3 SKIP 2 DONE"], @"isEqualToString");
  
  results = [self util_convertAndPrintC4Codes16:codes frameBufferNumPixels:sizeof(curr)/sizeof(uint16_t)];
  NSAssert([results isEqualToString:@"SKIP 1 COPY 1 0x3 SKIP 2 DONE"], @"isEqualToString");
  
  return;
}

// SKIP COPY SKIP SKIP

+ (void) testEncode4x1SkipCopySkip2At32BPP
{
  uint32_t prev[] = { 0x1, 0x2, 0x3, 0x3 };
  uint32_t curr[] = { 0x1, 0x3, 0x3, 0x3 };
  
  NSData *codes;
  NSString *results;
  
  codes = maxvid_encode_generic_delta_pixels32(prev, curr, sizeof(curr)/sizeof(uint32_t), 4, 1, NULL, 0);
  results = [self util_printMvidCodes32:codes];
  NSAssert([results isEqualToString:@"SKIP 1 COPY 1 0x3 SKIP 2 DONE"], @"isEqualToString");
  
  results = [self util_convertAndPrintC4Codes32:codes frameBufferNumPixels:sizeof(curr)/sizeof(uint32_t)];
  NSAssert([results isEqualToString:@"SKIP 1 COPY 1 0x3 (SKIP 2) DONE"], @"isEqualToString");
  
  return;
}

// COPY of all pixels in the buffer will be treated as a keyframe when non-NULL emitKeyframeAnyway
// argument is passed.

+ (void) testEncode4x1CopyAllChangedAt16BPP
{
  uint16_t prev[] = { 0x1, 0x2, 0x3, 0x4 };
  uint16_t curr[] = { 0x5, 0x6, 0x7, 0x8 };
  
  NSData *codes;
  
  BOOL emitKeyframeAnyway = FALSE;
  codes = maxvid_encode_generic_delta_pixels16(prev, curr, sizeof(curr)/sizeof(uint16_t), 4, 1, &emitKeyframeAnyway, 0);
  NSAssert(emitKeyframeAnyway == TRUE, @"emitKeyframeAnyway");
  NSAssert(codes == nil, @"codes");
  
  return;
}

// COPY of all pixels in the buffer will be treated as a keyframe when non-NULL emitKeyframeAnyway
// argument is passed.

+ (void) testEncode4x1CopyAllChangedAt32BPP
{
  uint32_t prev[] = { 0x1, 0x2, 0x3, 0x4 };
  uint32_t curr[] = { 0x5, 0x6, 0x7, 0x8 };
  
  NSData *codes;
  
  BOOL emitKeyframeAnyway = FALSE;
  codes = maxvid_encode_generic_delta_pixels32(prev, curr, sizeof(curr)/sizeof(uint32_t), 4, 1, &emitKeyframeAnyway, 0);
  NSAssert(emitKeyframeAnyway == TRUE, @"emitKeyframeAnyway");
  NSAssert(codes == nil, @"codes");
  
  return;
}

// Delta a very large buffer to generate a skip that is buffer length minus one. This
// will be processed as COPY and then a large SKIP, the SKIP value is so large that
// it can't be contained in one single 16 bit value.

+ (void) testEncodeLargeCopySkipAt16BPP
{
  int width = 480;
  int height = 320;
  int numBytes = width * height * sizeof(uint16_t);
  uint16_t *prev = (uint16_t *) malloc( numBytes );
  uint16_t *curr = (uint16_t *) malloc( numBytes );

  bzero(prev, numBytes);
  prev[0] = 0x1;
  bzero(curr, numBytes);
  curr[0] = 0x2;
  
  NSData *codes;
  NSString *results;
  
  codes = maxvid_encode_generic_delta_pixels16(prev, curr, numBytes/sizeof(uint16_t), width, height, NULL, 0);
  results = [self util_printMvidCodes16:codes];
  NSAssert([results isEqualToString:@"COPY 1 0x2 SKIP 65535 SKIP 65535 SKIP 22529 DONE"], @"isEqualToString");

  results = [self util_convertAndPrintC4Codes16:codes frameBufferNumPixels:numBytes/sizeof(uint16_t)];
  NSAssert([results isEqualToString:@"COPY 1 0x2 SKIP 153599 DONE"], @"isEqualToString");
  
  free(prev);
  free(curr);
  
  return;
}

+ (void) testEncodeLargeCopySkipAt32BPP
{
  int width = 480;
  int height = 320;
  int numBytes = width * height * sizeof(uint32_t);
  uint32_t *prev = (uint32_t *) malloc( numBytes );
  uint32_t *curr = (uint32_t *) malloc( numBytes );
  
  bzero(prev, numBytes);
  prev[0] = 0x1;
  bzero(curr, numBytes);
  curr[0] = 0x2;
  
  NSData *codes;
  NSString *results;
  
  codes = maxvid_encode_generic_delta_pixels32(prev, curr, numBytes/sizeof(uint32_t), width, height, NULL, 0);
  results = [self util_printMvidCodes32:codes];
  NSAssert([results isEqualToString:@"COPY 1 0x2 SKIP 65535 SKIP 65535 SKIP 22529 DONE"], @"isEqualToString");
  
  results = [self util_convertAndPrintC4Codes32:codes frameBufferNumPixels:numBytes/sizeof(uint32_t)];
  NSAssert([results isEqualToString:@"COPY 1 0x2 (SKIP 255) SKIP 153344 DONE"], @"isEqualToString");
  
  free(prev);
  free(curr);
  
  return;
}

// Delta a buffer where every single pixel is changed to the same other pixel, aka a large DUP.

+ (void) testEncodeLargeDupAt16BPP
{
  int width = 480;
  int height = 320;
  int numBytes = width * height * sizeof(uint16_t);
  uint16_t *prev = (uint16_t *) malloc( numBytes );
  uint16_t *curr = (uint16_t *) malloc( numBytes );
  
  bzero(prev, numBytes);  
  for (int i=0; i < (width * height); i++) {
    curr[i] = 0x1;
  }
  
  NSData *codes;
  NSString *results;
  
  codes = maxvid_encode_generic_delta_pixels16(prev, curr, numBytes/sizeof(uint16_t), width, height, NULL, 0);
  results = [self util_printMvidCodes16:codes];
  NSAssert([results isEqualToString:@"DUP 65535 0x1 DUP 65535 0x1 DUP 22530 0x1 DONE"], @"isEqualToString");

  // 14 bit max = 16383, 16383 * 9 + 6153 = 153600
  
  results = [self util_convertAndPrintC4Codes16:codes frameBufferNumPixels:numBytes/sizeof(uint16_t)];
  NSAssert([results isEqualToString:@"DUP 16383 0x1 DUP 16383 0x1 DUP 16383 0x1 DUP 16383 0x1 DUP 16383 0x1 DUP 16383 0x1 DUP 16383 0x1 DUP 16383 0x1 DUP 16383 0x1 DUP 6153 0x1 DONE"], @"isEqualToString");
  
  free(prev);
  free(curr);
  
  return;
}

// Delta a buffer where every single pixel is changed to the same other pixel, aka a large DUP.

+ (void) testEncodeLargeDupAt32BPP
{
  int width = 480;
  int height = 320;
  int numBytes = width * height * sizeof(uint32_t);
  uint32_t *prev = (uint32_t *) malloc( numBytes );
  uint32_t *curr = (uint32_t *) malloc( numBytes );
  
  bzero(prev, numBytes);  
  for (int i=0; i < width * height; i++) {
    curr[i] = 0x1;
  }
  
  NSData *codes;
  NSString *results;
  
  codes = maxvid_encode_generic_delta_pixels32(prev, curr, numBytes/sizeof(uint32_t), width, height, NULL, 0);
  results = [self util_printMvidCodes32:codes];
  NSAssert([results isEqualToString:@"DUP 65535 0x1 DUP 65535 0x1 DUP 22530 0x1 DONE"], @"isEqualToString");
  
  // A 32 bit c4 DUP code can contain a num up to a max of 22 bits
  
  results = [self util_convertAndPrintC4Codes32:codes frameBufferNumPixels:numBytes/sizeof(uint32_t)];
  NSAssert([results isEqualToString:@"DUP 153600 0x1 DONE"], @"isEqualToString");
  
  free(prev);
  free(curr);
  
  return;
}

// This test case checks the odd situation where the DUP is larger than the 14 bit max
// and the resulting next DUP would then be only 1 pixel (which is invalid).

+ (void) testEncodeReallyHugeDupTailingUnderTwoAt16BPP
{
  if (!TARGET_IPHONE_SIMULATOR) {
    // This test consumes all memory on the device and results in the app getting killed.
    return;
  }
  
  int width = 16383 + 1;
  int height = 1;
  int numBytes = width * height * sizeof(uint16_t);
  uint16_t *prev = (uint16_t *) malloc( numBytes );
  uint16_t *curr = (uint16_t *) malloc( numBytes );
  
  bzero(prev, numBytes);
  for (int i=0; i < (width * height); i++) {
    curr[i] = 0x1;
  }
  
  NSData *codes;
  NSString *results;
  
  codes = maxvid_encode_generic_delta_pixels16(prev, curr, numBytes/sizeof(uint16_t), width, height, NULL, 0);
  results = [self util_printMvidCodes16:codes];
  NSAssert([results isEqualToString:@"DUP 16384 0x1 DONE"], @"isEqualToString");
  
  // 14 bit max = 16383, so emit 16382 and then 2
  
  results = [self util_convertAndPrintC4Codes16:codes frameBufferNumPixels:numBytes/sizeof(uint16_t)];
  NSAssert([results isEqualToString:@"DUP 16382 0x1 DUP 2 0x1 DONE"], @"isEqualToString");
  
  free(prev);
  free(curr);
  
  return;
}

// This test case will push the limits of a 32 bit DUP code by allocating a buffer that is
// 1 pixel larger than the 22 bit dup count limit of 0x3FFFFF or 4194303 pixels.

+ (void) testEncodeReallyHugeDupTailingUnderTwoAt32BPP
{
  if (!TARGET_IPHONE_SIMULATOR) {
    // This test consumes all memory on the device and results in the app getting killed.
    return;
  }
  
  int width = (MV_MAX_22_BITS + 1);
  int height = 1;
  int numBytes = width * height * sizeof(uint32_t);
  uint32_t *prev = (uint32_t *) malloc( numBytes );
  uint32_t *curr = (uint32_t *) malloc( numBytes );
  
  bzero(prev, numBytes);
  for (int i=0; i < width * height; i++) {
    curr[i] = 0x1;
  }
  
  NSData *codes;
  NSString *results;
  
  codes = maxvid_encode_generic_delta_pixels32(prev, curr, numBytes/sizeof(uint32_t), width, height, NULL, 0);
  results = [self util_printMvidCodes32:codes];
  
  assert(((64 * MV_MAX_16_BITS) + 64) == (width * height));
  NSMutableString *expectedResult = [NSMutableString string];
  for (int dupi = 0; dupi < 64; dupi++) {
    [expectedResult appendFormat:@"DUP 65535 0x1 "];
  }
  [expectedResult appendFormat:@"DUP 64 0x1 "];
  [expectedResult appendFormat:@"DONE"];

  NSAssert([results isEqualToString:expectedResult], @"isEqualToString");
  
  // A 32 bit c4 DUP code can contain a num up to a max of 22 bits. In this specific case
  // splitting a DUP on the max bound would result in the following DUP only having one
  // pixel in the DUP. Instead, simply emit one fewer in the previous dup to avoid this issue.
  
  results = [self util_convertAndPrintC4Codes32:codes frameBufferNumPixels:numBytes/sizeof(uint32_t)];
  NSAssert([results isEqualToString:@"DUP 4194302 0x1 DUP 2 0x1 DONE"], @"isEqualToString");
  
  free(prev);
  free(curr);
  
  return;
}

// This test case will be over the 22 bit DUP limit by 2 pixels. This test is basically
// the same as the one above, except that the special case of not emitting the full
// 22 bits so that the trailing DUP is at least 2 is not hit by this test case.

+ (void) testEncodeReallyHugeDupTailingTwoAt32BPP
{
  if (!TARGET_IPHONE_SIMULATOR) {
    // This test consumes all memory on the device and results in the app getting killed.
    return;
  }
  
  int width = (MV_MAX_22_BITS + 1 + 1);
  int height = 1;
  int numBytes = width * height * sizeof(uint32_t);
  uint32_t *prev = (uint32_t *) malloc( numBytes );
  uint32_t *curr = (uint32_t *) malloc( numBytes );
  
  bzero(prev, numBytes);
  for (int i=0; i < width * height; i++) {
    curr[i] = 0x1;
  }
  
  NSData *codes;
  NSString *results;
  
  codes = maxvid_encode_generic_delta_pixels32(prev, curr, numBytes/sizeof(uint32_t), width, height, NULL, 0);
  results = [self util_printMvidCodes32:codes];
  
  assert(((64 * MV_MAX_16_BITS) + 65) == (width * height));
  NSMutableString *expectedResult = [NSMutableString string];
  for (int dupi = 0; dupi < 64; dupi++) {
    [expectedResult appendFormat:@"DUP 65535 0x1 "];
  }
  [expectedResult appendFormat:@"DUP 65 0x1 "];
  [expectedResult appendFormat:@"DONE"];
  
  NSAssert([results isEqualToString:expectedResult], @"isEqualToString");
  
  // A 32 bit c4 DUP code can contain a num up to a max of 22 bits. In this specific case
  // splitting a DUP on the max bound would result in the following DUP containing two
  // pixels, which is just fine.
  
  results = [self util_convertAndPrintC4Codes32:codes frameBufferNumPixels:numBytes/sizeof(uint32_t)];
  NSAssert([results isEqualToString:@"DUP 4194303 0x1 DUP 2 0x1 DONE"], @"isEqualToString");
  
  free(prev);
  free(curr);
  
  return;
}

// Delta a buffer where every single pixel is changed to some other pixel, aka a large COPY.

+ (void) testEncodeLargeCopyAt16BPP
{
  int width = 480;
  int height = 320;
  int numBytes = width * height * sizeof(uint16_t);
  uint16_t *prev = (uint16_t *) malloc( numBytes );
  uint16_t *curr = (uint16_t *) malloc( numBytes );
  
  // All pixels is prev buffer are 0, so take care to note emit a pixel with the
  // value zero in the curr buffer.
  
  bzero(prev, numBytes);
  
  // Note that the value range for 0 -> 153600 will overflow a 16bit pixel value
  for (int i=0; i < width * height; i++) {
    uint16_t pixelValue;
    if ((i % 3) == 0) {
      pixelValue = 0x1;
    } else if ((i % 3) == 1) {
      pixelValue = 0x2;
    } else if ((i % 3) == 2) {
      pixelValue = 0x3;
    } else {
      assert(0);
    }
    curr[i] = pixelValue;
  }
  
  NSData *codes;
  NSString *results;
  
  codes = maxvid_encode_generic_delta_pixels16(prev, curr, numBytes/sizeof(uint16_t), width, height, NULL, 0);
  results = [self util_printMvidCodes16:codes];
  
  // Generate a string like "COPY 65535 0x1 0x2 0x3 ... COPY 65535 ... COPY 22530 ... DONE"
  
  NSMutableString *mStr = [NSMutableString string];
  
  [mStr appendFormat:@"COPY %d ", 65535];
  for (int i=0; i < 65535 / 3; i++) {
    [mStr appendString:@"0x1 0x2 0x3 "];
  }
  [mStr appendFormat:@"COPY %d ", 65535];
  for (int i=0; i < 65535 / 3; i++) {
    [mStr appendString:@"0x1 0x2 0x3 "];
  }
  [mStr appendFormat:@"COPY %d ", 22530];
  for (int i=0; i < 22530 / 3; i++) {
    [mStr appendString:@"0x1 0x2 0x3 "];
  }
  
  [mStr appendString:@"DONE"];
  
  NSString *expected = [NSString stringWithString:mStr];
  
  NSAssert([results isEqualToString:expected], @"isEqualToString");
  
  // Generate c4 codes
  
  results = [self util_convertAndPrintC4Codes16:codes frameBufferNumPixels:numBytes/sizeof(uint16_t)];
  
  // 9 instances of : COPY 16383 0x1 0x2 0x3 ...
  // 1 instance of :  COPY 6153 0x1 0x2 0x3 ...
  
  assert((6153 + (16383 * 9)) == (width * height));
  
  [mStr setString:@""];
  
  for (int bigCopyi = 0; bigCopyi < 9; bigCopyi++) {
    [mStr appendFormat:@"COPY %d ", 16383];
    for (int i=0; i < 16383 / 3; i++) {
      [mStr appendString:@"0x1 0x2 0x3 "];
    }
  }
  
  [mStr appendFormat:@"COPY %d ", 6153];
  for (int i=0; i < 6153 / 3; i++) {
    [mStr appendString:@"0x1 0x2 0x3 "];
  }
  
  [mStr appendString:@"DONE"];
  
  NSAssert([results isEqualToString:mStr], @"isEqualToString");
  
  free(prev);
  free(curr);
  
  return;
}

// Delta a buffer where every single pixel is changed to some other pixel, aka a large COPY.

+ (void) testEncodeLargeCopyAt32BPP
{
  int width = 480;
  int height = 320;
  int numBytes = width * height * sizeof(uint32_t);
  uint32_t *prev = (uint32_t *) malloc( numBytes );
  uint32_t *curr = (uint32_t *) malloc( numBytes );
  
  // All pixels is prev buffer are 0, so take care to note emit a pixel with the
  // value zero in the curr buffer.
  
  bzero(prev, numBytes);
  
  for (int i=0; i < width * height; i++) {
    uint32_t pixelValue;
    if ((i % 3) == 0) {
      pixelValue = 0x1;
    } else if ((i % 3) == 1) {
      pixelValue = 0x2;
    } else if ((i % 3) == 2) {
      pixelValue = 0x3;
    } else {
      assert(0);
    }
    curr[i] = pixelValue;
  }
  
  NSData *codes;
  NSString *results;
  
  codes = maxvid_encode_generic_delta_pixels32(prev, curr, numBytes/sizeof(uint32_t), width, height, NULL, 0);
  results = [self util_printMvidCodes32:codes];
  
  // Generate a string like "COPY 65535 0x1 0x2 0x3 ... COPY 65535 ... COPY 22530 ... DONE"
  
  NSMutableString *mStr = [NSMutableString string];
  
  [mStr appendFormat:@"COPY %d ", 65535];
  for (int i=0; i < 65535 / 3; i++) {
    [mStr appendString:@"0x1 0x2 0x3 "];
  }
  [mStr appendFormat:@"COPY %d ", 65535];
  for (int i=0; i < 65535 / 3; i++) {
    [mStr appendString:@"0x1 0x2 0x3 "];
  }
  [mStr appendFormat:@"COPY %d ", 22530];
  for (int i=0; i < 22530 / 3; i++) {
    [mStr appendString:@"0x1 0x2 0x3 "];
  }
  
  [mStr appendString:@"DONE"];
  
  NSString *expected = [NSString stringWithString:mStr];
  
  NSAssert([results isEqualToString:expected], @"isEqualToString");
  
  // generate c4 codes
  
  results = [self util_convertAndPrintC4Codes32:codes frameBufferNumPixels:numBytes/sizeof(uint32_t)];
  
  [mStr setString:@""];
  
  [mStr appendFormat:@"COPY %d ", 153600];
  for (int i=0; i < 153600 / 3; i++) {
    [mStr appendString:@"0x1 0x2 0x3 "];
  }
  
  [mStr appendString:@"DONE"];
  
  NSAssert([results isEqualToString:mStr], @"isEqualToString");
  
  free(prev);
  free(curr);
  
  return;
}

// In this test case, a large 32 bit c4 DUP code is generated with a trailing SKIP
// pixel directly after the DUP code. The 32 bit c4 logic contains special logic
// that can fold a trailing SKIP op code into the previous DUP code. But, the
// DUP emitting logic must take care to only emit the skip at the end of a set of
// split DUP codes.

+ (void) testEncodeHugeDupThenSkipAt32BPP
{
  if (!TARGET_IPHONE_SIMULATOR) {
    // This test consumes all memory on the device and results in the app getting killed.
    return;
  }
  
  int width = (MV_MAX_22_BITS + 2 + 1);
  int height = 1;
  int numBytes = width * height * sizeof(uint32_t);
  uint32_t *prev = (uint32_t *) malloc( numBytes );
  uint32_t *curr = (uint32_t *) malloc( numBytes );
  
  bzero(prev, numBytes);
  for (int i=0; i < width * height; i++) {
    curr[i] = 0x1;
  }
  
  // Make the last pixel a SKIP
  curr[width * height - 1] = 0;
  
  NSData *codes;
  NSString *results;
  
  codes = maxvid_encode_generic_delta_pixels32(prev, curr, numBytes/sizeof(uint32_t), width, height, NULL, 0);
  results = [self util_printMvidCodes32:codes];
  
  assert(((64 * MV_MAX_16_BITS) + 65 + 1) == (width * height));
  NSMutableString *expectedResult = [NSMutableString string];
  for (int dupi = 0; dupi < 64; dupi++) {
    [expectedResult appendFormat:@"DUP 65535 0x1 "];
  }
  [expectedResult appendFormat:@"DUP 65 0x1 "];
  [expectedResult appendFormat:@"SKIP 1 "];
  [expectedResult appendFormat:@"DONE"];
  
  NSAssert([results isEqualToString:expectedResult], @"isEqualToString");
  
  // A 32 bit c4 DUP code can contain a num up to a max of 22 bits. In this case, a normal
  // DUP would split into max-1 and then 2. But, we expect the second DUP to contain the
  // implicit skip, not the first on in the split.
  
  results = [self util_convertAndPrintC4Codes32:codes frameBufferNumPixels:numBytes/sizeof(uint32_t)];
  NSAssert([results isEqualToString:@"DUP 4194303 0x1 DUP 2 0x1 (SKIP 1) DONE"], @"isEqualToString");
  
  free(prev);
  free(curr);
  
  return;
}

// In this test case a large COPY with a trailing SKIP code is generated. This test checks the same
// implicit skip at the end of a set of split codes logic as the DUP test above. Basically, a split
// COPY operation must emit the implicit skip with the last split COPY op code. This test also
// checks that emitting two COPY codes based on the same input generic COPY code works as expected.

+ (void) testEncodeHugeCopyThenSkipAt32BPP
{
  if (!TARGET_IPHONE_SIMULATOR) {
    // This test consumes all memory on the device and results in the app getting killed.
    return;
  }
  
  int width = (MV_MAX_22_BITS + 1 + 1);
  int height = 1;
  int numBytes = width * height * sizeof(uint32_t);
  uint32_t *prev = (uint32_t *) malloc( numBytes );
  uint32_t *curr = (uint32_t *) malloc( numBytes );
  
  // All pixels is prev buffer are 0, so take care to note emit a pixel with the
  // value zero in the curr buffer.
  
  bzero(prev, numBytes);
  
  for (int i=0; i < width * height; i++) {
    uint32_t pixelValue;
    if ((i % 3) == 0) {
      pixelValue = 0x1;
    } else if ((i % 3) == 1) {
      pixelValue = 0x2;
    } else if ((i % 3) == 2) {
      pixelValue = 0x3;
    } else {
      assert(0);
    }
    curr[i] = pixelValue;
  }
  
  // The last pixel is reset so that it becomes a trailing SKIP
  curr[(width * height) - 1] = 0;
  
  NSData *codes;
  NSString *results;
  
  codes = maxvid_encode_generic_delta_pixels32(prev, curr, numBytes/sizeof(uint32_t), width, height, NULL, 0);
  results = [self util_printMvidCodes32:codes];
  
  NSMutableString *mStr = [NSMutableString string];
  
  for (int copyi = 0; copyi < 64; copyi++) {
    [mStr appendFormat:@"COPY %d ", 65535];
    for (int i=0; i < 65535 / 3; i++) {
      [mStr appendString:@"0x1 0x2 0x3 "];
    }
  }
  
  [mStr appendFormat:@"COPY %d ", 64];
  for (int i=0; i < 64 / 3; i++) {
    [mStr appendString:@"0x1 0x2 0x3 "];
  }

  [mStr appendString:@"0x1 "];
  
  [mStr appendString:@"SKIP 1 "];
  
  [mStr appendString:@"DONE"];
  
  NSString *expected = [NSString stringWithString:mStr];
  
  NSAssert([results isEqualToString:expected], @"isEqualToString");
  
  // generate c4 codes, note that the massive 22 bit size of the number of pixels to copy
  // means that many generic codes are condensed down to 1 big one and then an extra one.
  
  results = [self util_convertAndPrintC4Codes32:codes frameBufferNumPixels:numBytes/sizeof(uint32_t)];
  
  [mStr setString:@""];
  
  [mStr appendFormat:@"COPY %d ", 4194303];
  for (int i=0; i < 4194303 / 3; i++) {
    [mStr appendString:@"0x1 0x2 0x3 "];
  }

  // The trailing SKIP should be applied to the second emitted code
  
  [mStr appendFormat:@"COPY 1 0x1 (SKIP 1) "];
  
  [mStr appendString:@"DONE"];
  
  NSAssert([results isEqualToString:mStr], @"isEqualToString");
 
  free(prev);
  free(curr);
  
  return;
}

@end
