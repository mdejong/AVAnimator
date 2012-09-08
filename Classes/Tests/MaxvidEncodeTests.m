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

@implementation MaxvidEncodeTests

// Debug print method for 16 bit codes

+ (NSString*) util_printMvidCodes16:(NSData*)codes
{
  if (codes == nil) {
    return @"IDENTICAL";
  }
  
  NSMutableString *mStr = [NSMutableString string];
  
  int index = 0;
  int end = [codes length] / sizeof(uint32_t);
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
  int end = [codes length] / sizeof(uint32_t);
  uint32_t *ptr = (uint32_t *)codes.bytes;
  
  for ( ; index < end; ) {
    uint32_t inword = ptr[index];
    
    MV32_PARSE_OP_NUM_SKIP(inword, opCode, num, skip);
    
    if (opCode == SKIP) {
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
    } else if (opCode == DUP) {
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

// This test case checks a 1x1 frame with identical 16bit pixel values.

+ (void) testEncode1x1IdenticalAt16BPP
{
  uint16_t prev[] = { 0x1 };
  uint16_t curr[] = { 0x1 };
  
  NSData *codes;
  NSString *results;
  
  codes = maxvid_encode_generic_delta_pixels16(prev, curr, sizeof(curr)/sizeof(uint16_t), 1, 1);
  results = [self util_printMvidCodes16:codes];
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
  
  codes = maxvid_encode_generic_delta_pixels32(prev, curr, sizeof(curr)/sizeof(uint32_t), 1, 1);
  results = [self util_printMvidCodes32:codes];
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
  
  codes = maxvid_encode_generic_delta_pixels16(prev, curr, sizeof(curr)/sizeof(uint16_t), 1, 1);
  results = [self util_printMvidCodes16:codes];
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
  
  codes = maxvid_encode_generic_delta_pixels32(prev, curr, sizeof(curr)/sizeof(uint32_t), 1, 1);
  results = [self util_printMvidCodes32:codes];
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
  
  codes = maxvid_encode_generic_delta_pixels16(prev, curr, sizeof(curr)/sizeof(uint16_t), 2, 1);
  results = [self util_printMvidCodes16:codes];
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
  
  codes = maxvid_encode_generic_delta_pixels32(prev, curr, sizeof(curr)/sizeof(uint32_t), 2, 1);
  results = [self util_printMvidCodes32:codes];
  NSAssert([results isEqualToString:@"COPY 1 0x3 SKIP 1 DONE"], @"isEqualToString");
  
  return;
}

// Check that a SKIP is being emitted before a delta pixel

+ (void) testEncode2x1SkipCopyAt16BPP
{
  uint16_t prev[] = { 0x2, 0x1 };
  uint16_t curr[] = { 0x2, 0x3 };
  
  NSData *codes;
  NSString *results;
  
  codes = maxvid_encode_generic_delta_pixels16(prev, curr, sizeof(curr)/sizeof(uint16_t), 2, 1);
  results = [self util_printMvidCodes16:codes];
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
  
  codes = maxvid_encode_generic_delta_pixels32(prev, curr, sizeof(curr)/sizeof(uint32_t), 2, 1);
  results = [self util_printMvidCodes32:codes];
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
  
  codes = maxvid_encode_generic_delta_pixels16(prev, curr, sizeof(curr)/sizeof(uint16_t), 3, 1);
  results = [self util_printMvidCodes16:codes];
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
  
  codes = maxvid_encode_generic_delta_pixels32(prev, curr, sizeof(curr)/sizeof(uint32_t), 3, 1);
  results = [self util_printMvidCodes32:codes];
  NSAssert([results isEqualToString:@"SKIP 1 COPY 1 0x3 SKIP 1 DONE"], @"isEqualToString");
  
  return;
}

+ (void) testEncode3x1CopySkipCopyAt16BPP
{
  uint16_t prev[] = { 0x1, 0x2, 0x3 };
  uint16_t curr[] = { 0x4, 0x2, 0x5 };
  
  NSData *codes;
  NSString *results;
  
  codes = maxvid_encode_generic_delta_pixels16(prev, curr, sizeof(curr)/sizeof(uint16_t), 3, 1);
  results = [self util_printMvidCodes16:codes];
  NSAssert([results isEqualToString:@"COPY 1 0x4 SKIP 1 COPY 1 0x5 DONE"], @"isEqualToString");
  
  return;
}

+ (void) testEncode3x1CopySkipCopyAt32BPP
{
  uint32_t prev[] = { 0x1, 0x2, 0x3 };
  uint32_t curr[] = { 0x4, 0x2, 0x5 };
  
  NSData *codes;
  NSString *results;
  
  codes = maxvid_encode_generic_delta_pixels32(prev, curr, sizeof(curr)/sizeof(uint32_t), 3, 1);
  results = [self util_printMvidCodes32:codes];
  NSAssert([results isEqualToString:@"COPY 1 0x4 SKIP 1 COPY 1 0x5 DONE"], @"isEqualToString");
  
  return;
}

// Two different COPY pixels in a run

+ (void) testEncode2x1CopyCopyAt16BPP
{
  uint16_t prev[] = { 0x1, 0x2 };
  uint16_t curr[] = { 0x3, 0x4 };
  
  NSData *codes;
  NSString *results;
  
  codes = maxvid_encode_generic_delta_pixels16(prev, curr, sizeof(curr)/sizeof(uint16_t), 2, 1);
  results = [self util_printMvidCodes16:codes];
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
  
  codes = maxvid_encode_generic_delta_pixels32(prev, curr, sizeof(curr)/sizeof(uint32_t), 2, 1);
  results = [self util_printMvidCodes32:codes];
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
  
  codes = maxvid_encode_generic_delta_pixels16(prev, curr, sizeof(curr)/sizeof(uint16_t), 3, 1);
  results = [self util_printMvidCodes16:codes];
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
  
  codes = maxvid_encode_generic_delta_pixels32(prev, curr, sizeof(curr)/sizeof(uint32_t), 3, 1);
  results = [self util_printMvidCodes32:codes];
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
  
  codes = maxvid_encode_generic_delta_pixels16(prev, curr, sizeof(curr)/sizeof(uint16_t), 2, 1);
  results = [self util_printMvidCodes16:codes];
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
  
  codes = maxvid_encode_generic_delta_pixels32(prev, curr, sizeof(curr)/sizeof(uint32_t), 2, 1);
  results = [self util_printMvidCodes32:codes];
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
  
  codes = maxvid_encode_generic_delta_pixels16(prev, curr, sizeof(curr)/sizeof(uint16_t), 3, 1);
  results = [self util_printMvidCodes16:codes];
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
  
  codes = maxvid_encode_generic_delta_pixels32(prev, curr, sizeof(curr)/sizeof(uint32_t), 3, 1);
  results = [self util_printMvidCodes32:codes];
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
  
  codes = maxvid_encode_generic_delta_pixels16(prev, curr, sizeof(curr)/sizeof(uint16_t), 3, 1);
  results = [self util_printMvidCodes16:codes];
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
  
  codes = maxvid_encode_generic_delta_pixels32(prev, curr, sizeof(curr)/sizeof(uint32_t), 3, 1);
  results = [self util_printMvidCodes32:codes];
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
  
  codes = maxvid_encode_generic_delta_pixels16(prev, curr, sizeof(curr)/sizeof(uint16_t), 5, 1);
  results = [self util_printMvidCodes16:codes];
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
  
  codes = maxvid_encode_generic_delta_pixels32(prev, curr, sizeof(curr)/sizeof(uint32_t), 5, 1);
  results = [self util_printMvidCodes32:codes];
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
  
  codes = maxvid_encode_generic_delta_pixels16(prev, curr, sizeof(curr)/sizeof(uint16_t), 4, 1);
  results = [self util_printMvidCodes16:codes];
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
  
  codes = maxvid_encode_generic_delta_pixels32(prev, curr, sizeof(curr)/sizeof(uint32_t), 4, 1);
  results = [self util_printMvidCodes32:codes];
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
  
  codes = maxvid_encode_generic_delta_pixels16(prev, curr, sizeof(curr)/sizeof(uint16_t), 4, 1);
  results = [self util_printMvidCodes16:codes];
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
  
  codes = maxvid_encode_generic_delta_pixels32(prev, curr, sizeof(curr)/sizeof(uint32_t), 4, 1);
  results = [self util_printMvidCodes32:codes];
  NSAssert([results isEqualToString:@"SKIP 1 COPY 1 0x3 SKIP 2 DONE"], @"isEqualToString");
  
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
  
  codes = maxvid_encode_generic_delta_pixels16(prev, curr, numBytes/sizeof(uint16_t), width, height);
  results = [self util_printMvidCodes16:codes];
  NSAssert([results isEqualToString:@"COPY 1 0x2 SKIP 65535 SKIP 65535 SKIP 22529 DONE"], @"isEqualToString");

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
  
  codes = maxvid_encode_generic_delta_pixels32(prev, curr, numBytes/sizeof(uint32_t), width, height);
  results = [self util_printMvidCodes32:codes];
  NSAssert([results isEqualToString:@"COPY 1 0x2 SKIP 65535 SKIP 65535 SKIP 22529 DONE"], @"isEqualToString");
  
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
  
  codes = maxvid_encode_generic_delta_pixels16(prev, curr, numBytes/sizeof(uint16_t), width, height);
  results = [self util_printMvidCodes16:codes];
  NSAssert([results isEqualToString:@"DUP 65535 0x1 DUP 65535 0x1 DUP 22530 0x1 DONE"], @"isEqualToString");
  
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
  
  codes = maxvid_encode_generic_delta_pixels32(prev, curr, numBytes/sizeof(uint32_t), width, height);
  results = [self util_printMvidCodes32:codes];
  NSAssert([results isEqualToString:@"DUP 65535 0x1 DUP 65535 0x1 DUP 22530 0x1 DONE"], @"isEqualToString");
  
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
  
  // Note that the value range for 0 -> 153600 will overflow the 16bit pixel value
  for (int i=0; i < width * height; i++) {
    uint16_t pixelValue;
    if ((i % 3) == 0) {
      pixelValue = 0x1;
    } else if ((i % 3) == 1) {
      pixelValue = 0x2;
    } else if ((i % 3) == 2) {
      pixelValue = 0x3;
    }
    curr[i] = pixelValue;
  }
  
  NSData *codes;
  NSString *results;
  
  codes = maxvid_encode_generic_delta_pixels16(prev, curr, numBytes/sizeof(uint16_t), width, height);
  results = [self util_printMvidCodes16:codes];
  
  // Generate a string like "COPY 65535 0x1 0x2 0x3 ... COPY 65535 ... COPY 65535 ... DONE"
  
  
  
  // We can't simply write 
  
  NSAssert([results isEqualToString:@"COPY 65535 0x1 DUP 65535 0x1 DUP 22530 0x1 DONE"], @"isEqualToString");
  
  free(prev);
  free(curr);
  
  return;
}

// FIXME:



@end
