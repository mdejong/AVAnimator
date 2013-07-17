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


@interface MaxvidEncodeTests : NSObject {
}
@end

@interface MaxvidEncodeTests ()

+ (NSString*) util_printMvidCodes16:(NSData*)codes;

+ (NSString*) util_printMvidCodes32:(NSData*)codes;

+ (NSString*) util_convertAndPrintC4Codes16:(NSData*)codes
                       frameBufferNumPixels:(NSUInteger)frameBufferNumPixels;

+ (NSString*) util_convertAndPrintC4Codes32:(NSData*)codes
                       frameBufferNumPixels:(NSUInteger)frameBufferNumPixels;

@end

@interface MaxvidEncodeDecodeTests : NSObject {
}
@end


// implementation

@implementation MaxvidEncodeDecodeTests

// The next couple of tests will encode simple pixel data as mvid codes and then decode
// the generated codes into a second buffer. This logic is a basic sanity check of the
// encoder and decoder logic.

// This method will convert generic 16BPP codes to m4 codes and return the result
// is a NSData.

+ (NSMutableData*) util_convertToC4Codes16:(NSData*)codes
                      frameBufferNumPixels:(NSUInteger)frameBufferNumPixels
{
  if (codes == nil) {
    return nil;
  }
  
  NSMutableData *mC4Data = [NSMutableData dataWithCapacity:frameBufferNumPixels];
  
  // Convert generic codes to m4 codes at 16BPP
  
  uint32_t *maxvidCodeBuffer = (uint32_t*)codes.bytes;
  uint32_t numMaxvidCodeWords = codes.length / sizeof(uint32_t);
  
  int retcode;
  retcode = maxvid_encode_c4_sample16(maxvidCodeBuffer, numMaxvidCodeWords, frameBufferNumPixels, mC4Data, 0);
  assert(retcode == 0);
  
  return mC4Data;
}

// This method will convert generic 32BPP codes to m4 codes and return the result
// is a NSData.

+ (NSData*) util_convertToC4Codes32:(NSData*)codes
               frameBufferNumPixels:(NSUInteger)frameBufferNumPixels
{
  if (codes == nil) {
    return nil;
  }
  
  // Convert generic codes to m4 codes at 32BPP
  
  NSMutableData *mC4Data = [NSMutableData dataWithCapacity:frameBufferNumPixels];
  
  uint32_t *maxvidCodeBuffer = (uint32_t*)codes.bytes;
  uint32_t numMaxvidCodeWords = codes.length / sizeof(uint32_t);
  
  int retcode;
  retcode = maxvid_encode_c4_sample32(maxvidCodeBuffer, numMaxvidCodeWords, frameBufferNumPixels, mC4Data, 0);
  assert(retcode == 0);
  
  return mC4Data;
}

// This test checks the special case of an optimized DUP 2 for 16BPP

+ (void) testEncodeAndDecodeDupTwo16BPP
{
  uint16_t prev[] = { 0x1, 0x2 };
  uint16_t curr[] = { 0x3, 0x3 };
  int width = 2;
  int height = 1;
  
  NSData *codes;
  NSString *results;
  
  codes = maxvid_encode_generic_delta_pixels16(prev, curr, sizeof(curr)/sizeof(uint16_t), width, height, NULL);
  results = [MaxvidEncodeTests util_printMvidCodes16:codes];
  NSAssert([results isEqualToString:@"DUP 2 0x3 DONE"], @"isEqualToString");

  // convert generic codes to c4 codes
  
  uint32_t frameBufferSize = width * height;
  
  NSData *c4Codes = [self util_convertToC4Codes16:codes frameBufferNumPixels:frameBufferSize];
  
  uint32_t *inputBuffer32 = (uint32_t*) c4Codes.bytes;
  uint32_t inputBuffer32NumWords = c4Codes.length / sizeof(uint32_t);

  // allocate framebuffer to decode into
  
  uint16_t *frameBuffer16 = valloc(4096);
  memset(frameBuffer16, 0, 4096);

  // invoke decoder
  
  uint32_t result =
  maxvid_decode_c4_sample16(frameBuffer16, inputBuffer32, inputBuffer32NumWords, frameBufferSize);

  NSAssert(result == 0, @"result");
  NSAssert(frameBuffer16[0] == 0x3, @"index 0");
  NSAssert(frameBuffer16[1] == 0x3, @"index 1");
  
  free(frameBuffer16);
  return;
}

// This test checks the special case of an optimized DUP 2 for 16BPP
// on a framebuffer that is not word aligned.

+ (void) testEncodeAndDecodeDupTwoNotWordAligned16BPP
{
  uint16_t prev[] = { 0x1, 0x2, 0x3 };
  uint16_t curr[] = { 0x1, 0x4, 0x4 };
  int width = 3;
  int height = 1;
  
  NSData *codes;
  NSString *results;
  
  codes = maxvid_encode_generic_delta_pixels16(prev, curr, sizeof(curr)/sizeof(uint16_t), width, height, NULL);
  results = [MaxvidEncodeTests util_printMvidCodes16:codes];
  NSAssert([results isEqualToString:@"SKIP 1 DUP 2 0x4 DONE"], @"isEqualToString");
  
  // convert generic codes to c4 codes
  
  uint32_t frameBufferSize = width * height;
  
  NSData *c4Codes = [self util_convertToC4Codes16:codes frameBufferNumPixels:frameBufferSize];
  
  uint32_t *inputBuffer32 = (uint32_t*) c4Codes.bytes;
  uint32_t inputBuffer32NumWords = c4Codes.length / sizeof(uint32_t);
  
  // allocate framebuffer to decode into
  
  uint16_t *frameBuffer16 = valloc(4096);
  memset(frameBuffer16, 0, 4096);
  
  frameBuffer16[0] = 0x1;
  
  // invoke decoder
  
  uint32_t result =
  maxvid_decode_c4_sample16(frameBuffer16, inputBuffer32, inputBuffer32NumWords, frameBufferSize);
  
  NSAssert(result == 0, @"result");
  NSAssert(frameBuffer16[0] == 0x1, @"index 0");
  NSAssert(frameBuffer16[1] == 0x4, @"index 2");
  NSAssert(frameBuffer16[2] == 0x4, @"index 3");
  
  free(frameBuffer16);
  return;
}

+ (void) testEncodeAndDecodeDupTwo32BPP
{
  uint32_t prev[] = { 0x1, 0x2 };
  uint32_t curr[] = { 0x3, 0x3 };
  int width = 2;
  int height = 1;
  
  NSData *codes;
  NSString *results;
  
  codes = maxvid_encode_generic_delta_pixels32(prev, curr, sizeof(curr)/sizeof(uint16_t), width, height, NULL);
  results = [MaxvidEncodeTests util_printMvidCodes32:codes];
  NSAssert([results isEqualToString:@"DUP 2 0x3 DONE"], @"isEqualToString");
  
  // convert generic codes to c4 codes
  
  uint32_t frameBufferSize = width * height;
  
  NSData *c4Codes = [self util_convertToC4Codes32:codes frameBufferNumPixels:frameBufferSize];
  
  uint32_t *inputBuffer32 = (uint32_t*) c4Codes.bytes;
  uint32_t inputBuffer32NumWords = c4Codes.length / sizeof(uint32_t);
  
  // allocate framebuffer to decode into
  
  uint32_t *frameBuffer32 = valloc(4096);
  memset(frameBuffer32, 0, 4096);
  
  // invoke decoder
  
  uint32_t result =
  maxvid_decode_c4_sample32(frameBuffer32, inputBuffer32, inputBuffer32NumWords, frameBufferSize);
  
  NSAssert(result == 0, @"result");
  NSAssert(frameBuffer32[0] == 0x3, @"index 0");
  NSAssert(frameBuffer32[1] == 0x3, @"index 1");
  
  free(frameBuffer32);
  return;
}

+ (void) testEncodeAndDecodeCopyOne16BPP
{
  uint16_t prev[] = { 0x1 };
  uint16_t curr[] = { 0x3 };
  int width = 1;
  int height = 1;
  
  NSData *codes;
  NSString *results;
  
  codes = maxvid_encode_generic_delta_pixels16(prev, curr, sizeof(curr)/sizeof(uint16_t), width, height, NULL);
  results = [MaxvidEncodeTests util_printMvidCodes16:codes];
  NSAssert([results isEqualToString:@"COPY 1 0x3 DONE"], @"isEqualToString");
  
  // convert generic codes to c4 codes
  
  uint32_t frameBufferSize = width * height;
  
  NSData *c4Codes = [self util_convertToC4Codes16:codes frameBufferNumPixels:frameBufferSize];
  
  uint32_t *inputBuffer32 = (uint32_t*) c4Codes.bytes;
  uint32_t inputBuffer32NumWords = c4Codes.length / sizeof(uint32_t);
  
  // allocate framebuffer to decode into
  
  uint16_t *frameBuffer16 = valloc(4096);
  memset(frameBuffer16, 0, 4096);
  
  // invoke decoder
  
  uint32_t result =
  maxvid_decode_c4_sample16(frameBuffer16, inputBuffer32, inputBuffer32NumWords, frameBufferSize);
  
  NSAssert(result == 0, @"result");
  NSAssert(frameBuffer16[0] == 0x3, @"index 0");
  
  free(frameBuffer16);
  return;
}

+ (void) testEncodeAndDecodeCopyOne32BPP
{
  uint32_t prev[] = { 0x1 };
  uint32_t curr[] = { 0x3 };
  int width = 1;
  int height = 1;
  
  NSData *codes;
  NSString *results;
  
  codes = maxvid_encode_generic_delta_pixels32(prev, curr, sizeof(curr)/sizeof(uint32_t), width, height, NULL);
  results = [MaxvidEncodeTests util_printMvidCodes32:codes];
  NSAssert([results isEqualToString:@"COPY 1 0x3 DONE"], @"isEqualToString");
  
  // convert generic codes to c4 codes
  
  uint32_t frameBufferSize = width * height;
  
  NSData *c4Codes = [self util_convertToC4Codes32:codes frameBufferNumPixels:frameBufferSize];
  
  uint32_t *inputBuffer32 = (uint32_t*) c4Codes.bytes;
  uint32_t inputBuffer32NumWords = c4Codes.length / sizeof(uint32_t);
  
  // allocate framebuffer to decode into
  
  uint32_t *frameBuffer32 = valloc(4096);
  memset(frameBuffer32, 0, 4096);
  
  // invoke decoder
  
  uint32_t result =
  maxvid_decode_c4_sample32(frameBuffer32, inputBuffer32, inputBuffer32NumWords, frameBufferSize);
  
  NSAssert(result == 0, @"result");
  NSAssert(frameBuffer32[0] == 0x3, @"index 0");
  
  free(frameBuffer32);
  return;
}

// This test encodes all the small DUP operations (those with 6 words aka 12 pixels or fewer)
// 13 pixels is still 6 words + 1 more pixel.

+ (void) testEncodeAndDecodeSmallDup16BPP
{
  const int width = 90;
  const int height = 1;

  uint16_t prev[width * height];
  uint16_t curr[width * height];
  
  NSData *codes;
  NSString *results;
  
  // Treat all previous pixels as zero
  memset(&prev[0], 0, sizeof(prev));
  assert(prev[0] == 0);
  
  int offset, val, num;
  
  offset = 0;
  
  // DUP 2
  val = 0x2;
  num = 2;
  for (int i=0; i<num; i++) {
    curr[offset++] = val;
  }
  // DUP 3
  val = 0x3;
  num = 3;
  for (int i=0; i<num; i++) {
    curr[offset++] = val;
  }
  // DUP 4
  val = 0x4;
  num = 4;
  for (int i=0; i<num; i++) {
    curr[offset++] = val;
  }
  // DUP 5
  val = 0x5;
  num = 5;
  for (int i=0; i<num; i++) {
    curr[offset++] = val;
  }
  // DUP 6
  val = 0x6;
  num = 6;
  for (int i=0; i<num; i++) {
    curr[offset++] = val;
  }
  // DUP 7
  val = 0x7;
  num = 7;
  for (int i=0; i<num; i++) {
    curr[offset++] = val;
  }
  // DUP 8
  val = 0x8;
  num = 8;
  for (int i=0; i<num; i++) {
    curr[offset++] = val;
  }
  // DUP 9
  val = 0x9;
  num = 9;
  for (int i=0; i<num; i++) {
    curr[offset++] = val;
  }
  // DUP 10
  val = 0xA;
  num = 10;
  for (int i=0; i<num; i++) {
    curr[offset++] = val;
  }
  // DUP 11
  val = 0xB;
  num = 11;
  for (int i=0; i<num; i++) {
    curr[offset++] = val;
  }
  // DUP 12
  val = 0xC;
  num = 12;
  for (int i=0; i<num; i++) {
    curr[offset++] = val;
  }
  // DUP 13
  val = 0xD;
  num = 13;
  for (int i=0; i<num; i++) {
    curr[offset++] = val;
  }
  
  codes = maxvid_encode_generic_delta_pixels16(prev, curr, sizeof(curr)/sizeof(uint16_t), width, height, NULL);
  results = [MaxvidEncodeTests util_printMvidCodes16:codes];
  NSAssert([results isEqualToString:@"DUP 2 0x2 DUP 3 0x3 DUP 4 0x4 DUP 5 0x5 DUP 6 0x6 DUP 7 0x7 DUP 8 0x8 DUP 9 0x9 DUP 10 0xA DUP 11 0xB DUP 12 0xC DUP 13 0xD DONE"], @"isEqualToString");
  
  // convert generic codes to c4 codes
  
  uint32_t frameBufferSize = width * height;
  
  NSData *c4Codes = [self util_convertToC4Codes16:codes frameBufferNumPixels:frameBufferSize];
  
  uint32_t *inputBuffer32 = (uint32_t*) c4Codes.bytes;
  uint32_t inputBuffer32NumWords = c4Codes.length / sizeof(uint32_t);
  
  // allocate framebuffer to decode into
  
  uint16_t *frameBuffer16 = valloc(4096);
  memset(frameBuffer16, 0, 4096);
  
  // invoke decoder
  
  uint32_t result =
  maxvid_decode_c4_sample16(frameBuffer16, inputBuffer32, inputBuffer32NumWords, frameBufferSize);
  
  NSAssert(result == 0, @"result");
  
  NSAssert(memcmp(curr, frameBuffer16, sizeof(curr)) == 0, @"memcmp");
  
  free(frameBuffer16);
  return;
}

// In 32BPP mode, 2 to 6 pixels are considered a small DUP

+ (void) testEncodeAndDecodeSmallDup32BPP
{
  const int width = 20;
  const int height = 1;
  
  uint32_t prev[width * height];
  uint32_t curr[width * height];
  
  // Treat all previous pixels as zero
  memset(&prev[0], 0, sizeof(prev));
  assert(prev[0] == 0);
  
  int offset, val, num;
  
  offset = 0;
  
  // DUP 2
  val = 0x2;
  num = 2;
  for (int i=0; i<num; i++) {
    curr[offset++] = val;
  }
  // DUP 3
  val = 0x3;
  num = 3;
  for (int i=0; i<num; i++) {
    curr[offset++] = val;
  }
  // DUP 4
  val = 0x4;
  num = 4;
  for (int i=0; i<num; i++) {
    curr[offset++] = val;
  }
  // DUP 5
  val = 0x5;
  num = 5;
  for (int i=0; i<num; i++) {
    curr[offset++] = val;
  }
  // DUP 6
  val = 0x6;
  num = 6;
  for (int i=0; i<num; i++) {
    curr[offset++] = val;
  }
  
  NSData *codes;
  NSString *results;
  
  codes = maxvid_encode_generic_delta_pixels32(prev, curr, sizeof(curr)/sizeof(uint16_t), width, height, NULL);
  results = [MaxvidEncodeTests util_printMvidCodes32:codes];
  NSAssert([results isEqualToString:@"DUP 2 0x2 DUP 3 0x3 DUP 4 0x4 DUP 5 0x5 DUP 6 0x6 DONE"], @"isEqualToString");
  
  // convert generic codes to c4 codes
  
  uint32_t frameBufferSize = width * height;
  
  NSData *c4Codes = [self util_convertToC4Codes32:codes frameBufferNumPixels:frameBufferSize];
  
  uint32_t *inputBuffer32 = (uint32_t*) c4Codes.bytes;
  uint32_t inputBuffer32NumWords = c4Codes.length / sizeof(uint32_t);
  
  // allocate framebuffer to decode into
  
  uint32_t *frameBuffer32 = valloc(4096);
  memset(frameBuffer32, 0, 4096);
  
  // invoke decoder
  
  uint32_t result =
  maxvid_decode_c4_sample32(frameBuffer32, inputBuffer32, inputBuffer32NumWords, frameBufferSize);
  
  NSAssert(result == 0, @"result");
  
  NSAssert(memcmp(curr, frameBuffer32, sizeof(curr)) == 0, @"memcmp");
  
  free(frameBuffer32);
  return;
}

// Normally, 14 pixels would be 7 words that that would be considered a large DUP.
// But in this tricky special case, the 16BPP framebuffer is not word aligned and the
// result is that one halfword is written before the DUP test. That brings the
// total remaining pixels down to 13 which is processed with the small DUP logic.

+ (void) testEncodeAndDecodeBigMinusOneSmallDup16BPP
{
  const int width = 15;
  const int height = 1;
  
  uint16_t prev[width * height];
  uint16_t curr[width * height];
  
  NSData *codes;
  NSString *results;
  
  // Treat all previous pixels as zero
  memset(&prev[0], 0, sizeof(prev));
  assert(prev[0] == 0);
  
  int offset, val, num;
  
  offset = 0;
  
  // SKIP 1
  curr[offset++] =0;
  
  // DUP 14
  val = 0xE;
  num = 14;
  for (int i=0; i<num; i++) {
    curr[offset++] = val;
  }
  
  codes = maxvid_encode_generic_delta_pixels16(prev, curr, sizeof(curr)/sizeof(uint16_t), width, height, NULL);
  results = [MaxvidEncodeTests util_printMvidCodes16:codes];
  NSAssert([results isEqualToString:@"SKIP 1 DUP 14 0xE DONE"], @"isEqualToString");
  
  // convert generic codes to c4 codes
  
  uint32_t frameBufferSize = width * height;
  
  NSData *c4Codes = [self util_convertToC4Codes16:codes frameBufferNumPixels:frameBufferSize];
  
  uint32_t *inputBuffer32 = (uint32_t*) c4Codes.bytes;
  uint32_t inputBuffer32NumWords = c4Codes.length / sizeof(uint32_t);
  
  // allocate framebuffer to decode into
  
  uint16_t *frameBuffer16 = valloc(4096);
  memset(frameBuffer16, 0, 4096);
  
  // invoke decoder
  
  uint32_t result =
  maxvid_decode_c4_sample16(frameBuffer16, inputBuffer32, inputBuffer32NumWords, frameBufferSize);
  
  NSAssert(result == 0, @"result");
  
  NSAssert(memcmp(curr, frameBuffer16, sizeof(curr)) == 0, @"memcmp");
  
  free(frameBuffer16);
  return;
}

// This test encodes 16BPP DUP runs starting at the big size min of 14 pixels (7 words)
// and then ending once a round of 8 words would get copied (14 + 16 = 30)

+ (void) testEncodeAndDecodeBigDup16BPP
{
  const int width = 374;
  const int height = 1;
  
  uint16_t prev[width * height];
  uint16_t curr[width * height];
  
  NSData *codes;
  NSString *results;
  
  // Treat all previous pixels as zero
  memset(&prev[0], 0, sizeof(prev));
  assert(prev[0] == 0);
  
  int offset, val, num;
  
  offset = 0;
  
  // DUP 14
  val = 0xE;
  num = 14;
  for (int i=0; i<num; i++) {
    curr[offset++] = val;
  }
  // DUP 15
  val = 0xF;
  num = 15;
  for (int i=0; i<num; i++) {
    curr[offset++] = val;
  }
  // DUP 16
  val = 0x10;
  num = 16;
  for (int i=0; i<num; i++) {
    curr[offset++] = val;
  }
  // DUP 17
  val = 0x11;
  num = 17;
  for (int i=0; i<num; i++) {
    curr[offset++] = val;
  }
  // DUP 18
  val = 0x12;
  num = 18;
  for (int i=0; i<num; i++) {
    curr[offset++] = val;
  }
  // DUP 19
  val = 0x13;
  num = 19;
  for (int i=0; i<num; i++) {
    curr[offset++] = val;
  }
  // DUP 20
  val = 0x14;
  num = 20;
  for (int i=0; i<num; i++) {
    curr[offset++] = val;
  }
  // DUP 21
  val = 0x15;
  num = 21;
  for (int i=0; i<num; i++) {
    curr[offset++] = val;
  }
  // DUP 22
  val = 0x16;
  num = 22;
  for (int i=0; i<num; i++) {
    curr[offset++] = val;
  }
  // DUP 23
  val = 0x17;
  num = 23;
  for (int i=0; i<num; i++) {
    curr[offset++] = val;
  }
  // DUP 24
  val = 0x18;
  num = 24;
  for (int i=0; i<num; i++) {
    curr[offset++] = val;
  }
  // DUP 25
  val = 0x19;
  num = 25;
  for (int i=0; i<num; i++) {
    curr[offset++] = val;
  }
  // DUP 26
  val = 0x1A;
  num = 26;
  for (int i=0; i<num; i++) {
    curr[offset++] = val;
  }
  // DUP 27
  val = 0x1B;
  num = 27;
  for (int i=0; i<num; i++) {
    curr[offset++] = val;
  }
  // DUP 28
  val = 0x1C;
  num = 28;
  for (int i=0; i<num; i++) {
    curr[offset++] = val;
  }
  // DUP 29
  val = 0x1D;
  num = 29;
  for (int i=0; i<num; i++) {
    curr[offset++] = val;
  }
  // DUP 30
  val = 0x1E;
  num = 30;
  for (int i=0; i<num; i++) {
    curr[offset++] = val;
  }
  
  codes = maxvid_encode_generic_delta_pixels16(prev, curr, sizeof(curr)/sizeof(uint16_t), width, height, NULL);
  results = [MaxvidEncodeTests util_printMvidCodes16:codes];
  NSAssert([results isEqualToString:@"DUP 14 0xE DUP 15 0xF DUP 16 0x10 DUP 17 0x11 DUP 18 0x12 DUP 19 0x13 DUP 20 0x14 DUP 21 0x15 DUP 22 0x16 DUP 23 0x17 DUP 24 0x18 DUP 25 0x19 DUP 26 0x1A DUP 27 0x1B DUP 28 0x1C DUP 29 0x1D DUP 30 0x1E DONE"], @"isEqualToString");
  
  // convert generic codes to c4 codes
  
  uint32_t frameBufferSize = width * height;
  
  NSData *c4Codes = [self util_convertToC4Codes16:codes frameBufferNumPixels:frameBufferSize];
  
  uint32_t *inputBuffer32 = (uint32_t*) c4Codes.bytes;
  uint32_t inputBuffer32NumWords = c4Codes.length / sizeof(uint32_t);
  
  // allocate framebuffer to decode into
  
  uint16_t *frameBuffer16 = valloc(4096);
  memset(frameBuffer16, 0, 4096);
  
  // invoke decoder
  
  uint32_t result =
  maxvid_decode_c4_sample16(frameBuffer16, inputBuffer32, inputBuffer32NumWords, frameBufferSize);
  
  NSAssert(result == 0, @"result");
  
  NSAssert(memcmp(curr, frameBuffer16, sizeof(curr)) == 0, @"memcmp");
  
  free(frameBuffer16);
  return;
}

// This test encodes 32BPP DUP runs starting at the big size min of 7 words
// until 7 + 8 = 15 words are duplicated.

+ (void) testEncodeAndDecodeBigDup32BPP
{
  const int width = 99;
  const int height = 1;
  
  uint32_t prev[width * height];
  uint32_t curr[width * height];
  
  // Treat all previous pixels as zero
  memset(&prev[0], 0, sizeof(prev));
  assert(prev[0] == 0);
  
  int offset, val, num;
  
  offset = 0;
  
  // DUP 7
  val = 0x7;
  num = 7;
  for (int i=0; i<num; i++) {
    curr[offset++] = val;
  }
  // DUP 8
  val = 0x8;
  num = 8;
  for (int i=0; i<num; i++) {
    curr[offset++] = val;
  }
  // DUP 9
  val = 0x9;
  num = 9;
  for (int i=0; i<num; i++) {
    curr[offset++] = val;
  }
  // DUP 10
  val = 0xA;
  num = 10;
  for (int i=0; i<num; i++) {
    curr[offset++] = val;
  }
  // DUP 11
  val = 0xB;
  num = 11;
  for (int i=0; i<num; i++) {
    curr[offset++] = val;
  }
  // DUP 12
  val = 0xC;
  num = 12;
  for (int i=0; i<num; i++) {
    curr[offset++] = val;
  }
  // DUP 13
  val = 0xD;
  num = 13;
  for (int i=0; i<num; i++) {
    curr[offset++] = val;
  }
  // DUP 14
  val = 0xE;
  num = 14;
  for (int i=0; i<num; i++) {
    curr[offset++] = val;
  }
  // DUP 15
  val = 0xF;
  num = 15;
  for (int i=0; i<num; i++) {
    curr[offset++] = val;
  }
  
  NSData *codes;
  NSString *results;
  
  codes = maxvid_encode_generic_delta_pixels32(prev, curr, sizeof(curr)/sizeof(uint16_t), width, height, NULL);
  results = [MaxvidEncodeTests util_printMvidCodes32:codes];
  NSAssert([results isEqualToString:@"DUP 7 0x7 DUP 8 0x8 DUP 9 0x9 DUP 10 0xA DUP 11 0xB DUP 12 0xC DUP 13 0xD DUP 14 0xE DUP 15 0xF DONE"], @"isEqualToString");
  
  // convert generic codes to c4 codes
  
  uint32_t frameBufferSize = width * height;
  
  NSData *c4Codes = [self util_convertToC4Codes32:codes frameBufferNumPixels:frameBufferSize];
  
  uint32_t *inputBuffer32 = (uint32_t*) c4Codes.bytes;
  uint32_t inputBuffer32NumWords = c4Codes.length / sizeof(uint32_t);
  
  // allocate framebuffer to decode into
  
  uint32_t *frameBuffer32 = valloc(4096);
  memset(frameBuffer32, 0, 4096);
  
  // invoke decoder
  
  uint32_t result =
  maxvid_decode_c4_sample32(frameBuffer32, inputBuffer32, inputBuffer32NumWords, frameBufferSize);
  
  NSAssert(result == 0, @"result");
  
  NSAssert(memcmp(curr, frameBuffer32, sizeof(curr)) == 0, @"memcmp");
  
  free(frameBuffer32);
  return;
}

// This test encodes all the small COPY operations at 16BPP (A big COPY is 16 or more pixels)
// so a COPY convers 2 to 15 pixels with one more pixel possibly consumed to align to 32 bits.

// COPYBIG 16 : if (numPixels >= (8*2))

+ (void) testEncodeAndDecodeSmallCopy16BPP
{
  const int width = 256;
  const int height = 1;
  
  uint16_t prev[width * height];
  uint16_t curr[width * height];
  
  NSData *codes;
  NSString *results;
  
  // Treat all previous pixels as zero
  memset(&prev[0], 0, sizeof(prev));
  assert(prev[0] == 0);

  // Treat all (skipped) pixels as zero
  memset(&curr[0], 0, sizeof(prev));
  assert(curr[0] == 0);
  
  int offset, val, num;
  
  offset = 0;

  // COPY 2 0x2 0x1 SKIP 1
  val = 0x2;
  num = 2;
  for (int i=0; i<num; i++) {
    curr[offset++] = val - i;
    //NSLog(@"curr[%d] = %d", (offset - 1), curr[(offset - 1)]);
  }
  offset += 1;
  // COPY 3 0x3 0x2 0x1 SKIP 1
  val = 0x3;
  num = 3;
  for (int i=0; i<num; i++) {
    curr[offset++] = val - i;
    //NSLog(@"curr[%d] = %d", (offset - 1), curr[(offset - 1)]);
  }
  offset += 1;
  // COPY 4 0x4 0x3 0x2 0x1 SKIP 1
  val = 0x4;
  num = 4;
  for (int i=0; i<num; i++) {
    curr[offset++] = val - i;
    //NSLog(@"curr[%d] = %d", (offset - 1), curr[(offset - 1)]);
  }
  offset += 1;
  // COPY 5 ...
  val = 0x5;
  num = 5;
  for (int i=0; i<num; i++) {
    curr[offset++] = val - i;
    //NSLog(@"curr[%d] = %d", (offset - 1), curr[(offset - 1)]);
  }
  offset += 1;
  // COPY 6
  val = 0x6;
  num = 6;
  for (int i=0; i<num; i++) {
    curr[offset++] = val - i;
  }
  offset += 1;
  // COPY 7
  val = 0x7;
  num = 7;
  for (int i=0; i<num; i++) {
    curr[offset++] = val - i;
  }
  offset += 1;
  // COPY 8
  val = 0x8;
  num = 8;
  for (int i=0; i<num; i++) {
    curr[offset++] = val - i;
  }
  offset += 1;
  // COPY 9
  val = 0x9;
  num = 9;
  for (int i=0; i<num; i++) {
    curr[offset++] = val - i;
  }
  offset += 1;
  // COPY 10
  val = 0xA;
  num = 10;
  for (int i=0; i<num; i++) {
    curr[offset++] = val - i;
  }
  offset += 1;
  // COPY 11
  val = 0xB;
  num = 11;
  for (int i=0; i<num; i++) {
    curr[offset++] = val - i;
  }
  offset += 1;
  // COPY 12
  val = 0xC;
  num = 12;
  for (int i=0; i<num; i++) {
    curr[offset++] = val - i;
  }
  offset += 1;
  // COPY 13
  val = 0xD;
  num = 13;
  for (int i=0; i<num; i++) {
    curr[offset++] = val - i;
  }
  offset += 1;
  // COPY 14
  val = 0xE;
  num = 14;
  for (int i=0; i<num; i++) {
    curr[offset++] = val - i;
  }
  offset += 1;
  // COPY 15
  val = 0xF;
  num = 15;
  for (int i=0; i<num; i++) {
    curr[offset++] = val - i;
    //NSLog(@"curr[%d] = %d", (offset - 1), curr[(offset - 1)]);
  }
  offset += 1;
    
  //NSLog(@"last offset after first loop %d", (offset - 1));

  // COPY 5 ...
  val = 0x5;
  num = 5;
  for (int i=0; i<num; i++) {
    curr[offset++] = val - i;
    //NSLog(@"curr[%d] = %d", (offset - 1), curr[(offset - 1)]);
  }
  offset += 1;
  // COPY 6
  val = 0x6;
  num = 6;
  for (int i=0; i<num; i++) {
    curr[offset++] = val - i;
    //NSLog(@"curr[%d] = %d", (offset - 1), curr[(offset - 1)]);
  }
  offset += 1;
  // COPY 7
  val = 0x7;
  num = 7;
  for (int i=0; i<num; i++) {
    curr[offset++] = val - i;
    //NSLog(@"curr[%d] = %d", (offset - 1), curr[(offset - 1)]);
  }
  offset += 1;
  // COPY 8
  val = 0x8;
  num = 8;
  for (int i=0; i<num; i++) {
    curr[offset++] = val - i;
    //NSLog(@"curr[%d] = %d", (offset - 1), curr[(offset - 1)]);
  }
  offset += 1;
  // COPY 9
  val = 0x9;
  num = 9;
  for (int i=0; i<num; i++) {
    curr[offset++] = val - i;
    //NSLog(@"curr[%d] = %d", (offset - 1), curr[(offset - 1)]);
  }
  offset += 1;
  // COPY 10
  val = 0xA;
  num = 10;
  for (int i=0; i<num; i++) {
    curr[offset++] = val - i;
    //NSLog(@"curr[%d] = %d", (offset - 1), curr[(offset - 1)]);
  }
  offset += 1;
  // COPY 11
  val = 0xB;
  num = 11;
  for (int i=0; i<num; i++) {
    curr[offset++] = val - i;
    //NSLog(@"curr[%d] = %d", (offset - 1), curr[(offset - 1)]);
  }
  offset += 1;
  // COPY 12
  val = 0xC;
  num = 12;
  for (int i=0; i<num; i++) {
    curr[offset++] = val - i;
    //NSLog(@"curr[%d] = %d", (offset - 1), curr[(offset - 1)]);
  }
  offset += 1;
  // COPY 13
  val = 0xD;
  num = 13;
  for (int i=0; i<num; i++) {
    curr[offset++] = val - i;
    //NSLog(@"curr[%d] = %d", (offset - 1), curr[(offset - 1)]);
  }
  offset += 1;
  // COPY 14
  val = 0xE;
  num = 14;
  for (int i=0; i<num; i++) {
    curr[offset++] = val - i;
    //NSLog(@"curr[%d] = %d", (offset - 1), curr[(offset - 1)]);
  }
  offset += 1;
  // COPY 15
  val = 0xF;
  num = 15;
  for (int i=0; i<num; i++) {
    curr[offset++] = val - i;
    //NSLog(@"curr[%d] = %d", (offset - 1), curr[(offset - 1)]);
  }
  offset += 1;
  
  // Add 1 more COPY 2
  
  curr[offset++] = 0x2;
  //NSLog(@"curr[%d] = %d", (offset - 1), curr[(offset - 1)]);
  curr[offset++] = 0x1;
  //NSLog(@"curr[%d] = %d", (offset - 1), curr[(offset - 1)]);
  
  assert(offset == 256);
    
  codes = maxvid_encode_generic_delta_pixels16(prev, curr, sizeof(curr)/sizeof(uint16_t), width, height, NULL);
  results = [MaxvidEncodeTests util_printMvidCodes16:codes];
  NSAssert([results isEqualToString:@"COPY 2 0x2 0x1 SKIP 1 COPY 3 0x3 0x2 0x1 SKIP 1 COPY 4 0x4 0x3 0x2 0x1 SKIP 1 COPY 5 0x5 0x4 0x3 0x2 0x1 SKIP 1 COPY 6 0x6 0x5 0x4 0x3 0x2 0x1 SKIP 1 COPY 7 0x7 0x6 0x5 0x4 0x3 0x2 0x1 SKIP 1 COPY 8 0x8 0x7 0x6 0x5 0x4 0x3 0x2 0x1 SKIP 1 COPY 9 0x9 0x8 0x7 0x6 0x5 0x4 0x3 0x2 0x1 SKIP 1 COPY 10 0xA 0x9 0x8 0x7 0x6 0x5 0x4 0x3 0x2 0x1 SKIP 1 COPY 11 0xB 0xA 0x9 0x8 0x7 0x6 0x5 0x4 0x3 0x2 0x1 SKIP 1 COPY 12 0xC 0xB 0xA 0x9 0x8 0x7 0x6 0x5 0x4 0x3 0x2 0x1 SKIP 1 COPY 13 0xD 0xC 0xB 0xA 0x9 0x8 0x7 0x6 0x5 0x4 0x3 0x2 0x1 SKIP 1 COPY 14 0xE 0xD 0xC 0xB 0xA 0x9 0x8 0x7 0x6 0x5 0x4 0x3 0x2 0x1 SKIP 1 COPY 15 0xF 0xE 0xD 0xC 0xB 0xA 0x9 0x8 0x7 0x6 0x5 0x4 0x3 0x2 0x1 SKIP 1 COPY 5 0x5 0x4 0x3 0x2 0x1 SKIP 1 COPY 6 0x6 0x5 0x4 0x3 0x2 0x1 SKIP 1 COPY 7 0x7 0x6 0x5 0x4 0x3 0x2 0x1 SKIP 1 COPY 8 0x8 0x7 0x6 0x5 0x4 0x3 0x2 0x1 SKIP 1 COPY 9 0x9 0x8 0x7 0x6 0x5 0x4 0x3 0x2 0x1 SKIP 1 COPY 10 0xA 0x9 0x8 0x7 0x6 0x5 0x4 0x3 0x2 0x1 SKIP 1 COPY 11 0xB 0xA 0x9 0x8 0x7 0x6 0x5 0x4 0x3 0x2 0x1 SKIP 1 COPY 12 0xC 0xB 0xA 0x9 0x8 0x7 0x6 0x5 0x4 0x3 0x2 0x1 SKIP 1 COPY 13 0xD 0xC 0xB 0xA 0x9 0x8 0x7 0x6 0x5 0x4 0x3 0x2 0x1 SKIP 1 COPY 14 0xE 0xD 0xC 0xB 0xA 0x9 0x8 0x7 0x6 0x5 0x4 0x3 0x2 0x1 SKIP 1 COPY 15 0xF 0xE 0xD 0xC 0xB 0xA 0x9 0x8 0x7 0x6 0x5 0x4 0x3 0x2 0x1 SKIP 1 COPY 2 0x2 0x1 DONE"], @"isEqualToString");
  
  // convert generic codes to c4 codes
  
  uint32_t frameBufferSize = width * height;
  
  NSData *c4Codes = [self util_convertToC4Codes16:codes frameBufferNumPixels:frameBufferSize];
  
  uint32_t *inputBuffer32 = (uint32_t*) c4Codes.bytes;
  uint32_t inputBuffer32NumWords = c4Codes.length / sizeof(uint32_t);
  
  // allocate framebuffer to decode into
  
  uint16_t *frameBuffer16 = valloc(4096);
  memset(frameBuffer16, 0, 4096);
  
  // invoke decoder
  
  uint32_t result =
  maxvid_decode_c4_sample16(frameBuffer16, inputBuffer32, inputBuffer32NumWords, frameBufferSize);
  
  NSAssert(result == 0, @"result");
  
  NSAssert(memcmp(curr, frameBuffer16, sizeof(curr)) == 0, @"memcmp");
  
  free(frameBuffer16);
  return;
}

// Normally, 16 pixels would be a big copy of 8 words, but when the framebuffer is not word
// aligned then a one pixel is consumed to align it. The result is a 16 pixel COPY that is
// handled by writing 7 words and with a half word write before hand.

+ (void) testEncodeAndDecodeBigCopyMinusOne16BPP
{
  const int width = 17;
  const int height = 1;
  
  uint16_t prev[width * height];
  uint16_t curr[width * height];
  
  NSData *codes;
  NSString *results;
  
  // Treat all previous pixels as zero
  memset(&prev[0], 0, sizeof(prev));
  assert(prev[0] == 0);
  
  // Treat all (skipped) pixels as zero
  memset(&curr[0], 0, sizeof(prev));
  assert(curr[0] == 0);
  
  int offset, val, num;
  
  offset = 0;
  
  offset += 1;
  
  // COPY 16
  val = 0x10;
  num = 16;
  for (int i=0; i<num; i++) {
    curr[offset++] = val - i;
    //NSLog(@"curr[%d] = %d", (offset - 1), curr[(offset - 1)]);
  }
  
  //NSLog(@"last offset after first loop %d", (offset - 1));
  
  assert(offset == 17);
  
  codes = maxvid_encode_generic_delta_pixels16(prev, curr, sizeof(curr)/sizeof(uint16_t), width, height, NULL);
  results = [MaxvidEncodeTests util_printMvidCodes16:codes];
  NSAssert([results isEqualToString:@"SKIP 1 COPY 16 0x10 0xF 0xE 0xD 0xC 0xB 0xA 0x9 0x8 0x7 0x6 0x5 0x4 0x3 0x2 0x1 DONE"], @"isEqualToString");
  
  // convert generic codes to c4 codes
  
  uint32_t frameBufferSize = width * height;
  
  NSData *c4Codes = [self util_convertToC4Codes16:codes frameBufferNumPixels:frameBufferSize];
  
  uint32_t *inputBuffer32 = (uint32_t*) c4Codes.bytes;
  uint32_t inputBuffer32NumWords = c4Codes.length / sizeof(uint32_t);
  
  // allocate framebuffer to decode into
  
  uint16_t *frameBuffer16 = valloc(4096);
  memset(frameBuffer16, 0, 4096);
  
  // invoke decoder
  
  uint32_t result =
  maxvid_decode_c4_sample16(frameBuffer16, inputBuffer32, inputBuffer32NumWords, frameBufferSize);
  
  NSAssert(result == 0, @"result");
  
  NSAssert(memcmp(curr, frameBuffer16, sizeof(curr)) == 0, @"memcmp");
  
  free(frameBuffer16);
  return;
}

// This test encodes all the small COPY operations at 32BPP (a big copy is 8 pixels/words or more)

+ (void) testEncodeAndDecodeSmallCopy32BPP
{
  const int width = 32;
  const int height = 1;
  
  uint32_t prev[width * height];
  uint32_t curr[width * height];
  
  NSData *codes;
  NSString *results;
  
  // Treat all previous pixels as zero
  memset(&prev[0], 0, sizeof(prev));
  assert(prev[0] == 0);
  
  // Treat all (skipped) pixels as zero
  memset(&curr[0], 0, sizeof(prev));
  assert(curr[0] == 0);
  
  int offset, val, num;
  
  offset = 0;
  
  // COPY 2 0x2 0x1 SKIP 1
  val = 0x2;
  num = 2;
  for (int i=0; i<num; i++) {
    curr[offset++] = val - i;
    //NSLog(@"curr[%d] = %d", (offset - 1), curr[(offset - 1)]);
  }
  offset += 1;
  // COPY 3 0x3 0x2 0x1 SKIP 1
  val = 0x3;
  num = 3;
  for (int i=0; i<num; i++) {
    curr[offset++] = val - i;
    //NSLog(@"curr[%d] = %d", (offset - 1), curr[(offset - 1)]);
  }
  offset += 1;
  // COPY 4 0x4 0x3 0x2 0x1 SKIP 1
  val = 0x4;
  num = 4;
  for (int i=0; i<num; i++) {
    curr[offset++] = val - i;
    //NSLog(@"curr[%d] = %d", (offset - 1), curr[(offset - 1)]);
  }
  offset += 1;
  // COPY 5 ...
  val = 0x5;
  num = 5;
  for (int i=0; i<num; i++) {
    curr[offset++] = val - i;
    //NSLog(@"curr[%d] = %d", (offset - 1), curr[(offset - 1)]);
  }
  offset += 1;
  // COPY 6
  val = 0x6;
  num = 6;
  for (int i=0; i<num; i++) {
    curr[offset++] = val - i;
    //NSLog(@"curr[%d] = %d", (offset - 1), curr[(offset - 1)]);
  }
  offset += 1;
  // COPY 7
  val = 0x7;
  num = 7;
  for (int i=0; i<num; i++) {
    curr[offset++] = val - i;
    //NSLog(@"curr[%d] = %d", (offset - 1), curr[(offset - 1)]);
  }
  
  assert(offset == 32);
  
  codes = maxvid_encode_generic_delta_pixels32(prev, curr, sizeof(curr)/sizeof(uint32_t), width, height, NULL);
  results = [MaxvidEncodeTests util_printMvidCodes32:codes];
  NSAssert([results isEqualToString:@"COPY 2 0x2 0x1 SKIP 1 COPY 3 0x3 0x2 0x1 SKIP 1 COPY 4 0x4 0x3 0x2 0x1 SKIP 1 COPY 5 0x5 0x4 0x3 0x2 0x1 SKIP 1 COPY 6 0x6 0x5 0x4 0x3 0x2 0x1 SKIP 1 COPY 7 0x7 0x6 0x5 0x4 0x3 0x2 0x1 DONE"], @"isEqualToString");
  
  // convert generic codes to c4 codes
  
  uint32_t frameBufferSize = width * height;
  
  NSData *c4Codes = [self util_convertToC4Codes32:codes frameBufferNumPixels:frameBufferSize];
  
  uint32_t *inputBuffer32 = (uint32_t*) c4Codes.bytes;
  uint32_t inputBuffer32NumWords = c4Codes.length / sizeof(uint32_t);
  
  // allocate framebuffer to decode into
  
  uint32_t *frameBuffer32 = valloc(4096);
  memset(frameBuffer32, 0, 4096);
  
  // invoke decoder
  
  uint32_t result =
  maxvid_decode_c4_sample32(frameBuffer32, inputBuffer32, inputBuffer32NumWords, frameBufferSize);
  
  NSAssert(result == 0, @"result");
  
  NSAssert(memcmp(curr, frameBuffer32, sizeof(curr)) == 0, @"memcmp");
  
  free(frameBuffer32);
  return;
}

// A big copy should be 8 words or more, but a single pixel can be consumed before the 8 word
// test, so that the small copy logic is still invoked for an 8 word copy. Test this special
// case in this method.

+ (void) testEncodeAndDecodeBigCopyMinusOne32BPP
{
  const int width = 8;
  const int height = 1;
  
  uint32_t prev[width * height];
  uint32_t curr[width * height];
  
  NSData *codes;
  NSString *results;
  
  // Treat all previous pixels as zero
  memset(&prev[0], 0, sizeof(prev));
  assert(prev[0] == 0);
  
  // Treat all (skipped) pixels as zero
  memset(&curr[0], 0, sizeof(prev));
  assert(curr[0] == 0);
  
  int offset, val, num;
  
  offset = 0;
  
  // COPY 8 ...
  val = 0x8;
  num = 8;
  for (int i=0; i<num; i++) {
    curr[offset++] = val - i;
    //NSLog(@"curr[%d] = %d", (offset - 1), curr[(offset - 1)]);
  }
  
  //NSLog(@"last offset after first loop %d", (offset - 1));
  
  assert(offset == 8);
  
  codes = maxvid_encode_generic_delta_pixels32(prev, curr, sizeof(curr)/sizeof(uint32_t), width, height, NULL);
  results = [MaxvidEncodeTests util_printMvidCodes32:codes];
  NSAssert([results isEqualToString:@"COPY 8 0x8 0x7 0x6 0x5 0x4 0x3 0x2 0x1 DONE"], @"isEqualToString");
  
  // convert generic codes to c4 codes
  
  uint32_t frameBufferSize = width * height;
  
  NSData *c4Codes = [self util_convertToC4Codes32:codes frameBufferNumPixels:frameBufferSize];
  
  uint32_t *inputBuffer32 = (uint32_t*) c4Codes.bytes;
  uint32_t inputBuffer32NumWords = c4Codes.length / sizeof(uint32_t);
  
  // allocate framebuffer to decode into
  
  uint32_t *frameBuffer32 = valloc(4096);
  memset(frameBuffer32, 0, 4096);
  
  // invoke decoder
  
  uint32_t result =
  maxvid_decode_c4_sample32(frameBuffer32, inputBuffer32, inputBuffer32NumWords, frameBufferSize);
  
  NSAssert(result == 0, @"result");
  
  NSAssert(memcmp(curr, frameBuffer32, sizeof(curr)) == 0, @"memcmp");
  
  free(frameBuffer32);
  return;
}

// 16BPP COPYBIG should cover 16 to 32 pixels (8 to 16 words). This test encodes all
// the big copy operations starting from 8 words up until 8+8 to ensure that all
// the emit after the 8 word loop options are handled.

// COPYBIG 16 : if (numPixels >= (8*2))

+ (void) testEncodeAndDecodeBigCopy16BPP
{
  const int width = 512;
  const int height = 1;
  
  uint16_t prev[width * height];
  uint16_t curr[width * height];
  
  NSData *codes;
  NSString *results;
  
  // Treat all previous pixels as zero
  memset(&prev[0], 0, sizeof(prev));
  assert(prev[0] == 0);
  
  // Treat all (skipped) pixels as zero
  memset(&curr[0], 0, sizeof(prev));
  assert(curr[0] == 0);
  
  int offset, val, num;
  
  offset = 0;

  // Loop from 16 to 32 pixels, each pixel value counts down to 1
  
  for (int pixelNum = 16; pixelNum < 32; pixelNum++) {
    // COPY 8 0x8 0x7 ... 0x1 SKIP 1
    val = pixelNum;
    num = pixelNum;
    for (int i=0; i<num; i++) {
      curr[offset++] = val - i;
      //NSLog(@"curr[%d] = %d", (offset - 1), curr[(offset - 1)]);
    }
    offset += 1;
  }
  
  //NSLog(@"last offset after first loop %d", (offset - 1));

  for (int pixelNum = 16; pixelNum < 22; pixelNum++) {
    // COPY 8 0x8 0x7 ... 0x1 SKIP 1
    val = pixelNum;
    num = pixelNum;
    for (int i=0; i<num; i++) {
      curr[offset++] = val - i;
      //NSLog(@"curr[%d] = %d", (offset - 1), curr[(offset - 1)]);
    }
    offset += 1;
  }

  //NSLog(@"last offset after second loop %d", (offset - 1));
  
  // SKIP 3 ...
  offset += 3;
    
  assert(offset == 512);
  
  codes = maxvid_encode_generic_delta_pixels16(prev, curr, sizeof(curr)/sizeof(uint16_t), width, height, NULL);
  results = [MaxvidEncodeTests util_printMvidCodes16:codes];
  NSAssert([results isEqualToString:@"COPY 16 0x10 0xF 0xE 0xD 0xC 0xB 0xA 0x9 0x8 0x7 0x6 0x5 0x4 0x3 0x2 0x1 SKIP 1 COPY 17 0x11 0x10 0xF 0xE 0xD 0xC 0xB 0xA 0x9 0x8 0x7 0x6 0x5 0x4 0x3 0x2 0x1 SKIP 1 COPY 18 0x12 0x11 0x10 0xF 0xE 0xD 0xC 0xB 0xA 0x9 0x8 0x7 0x6 0x5 0x4 0x3 0x2 0x1 SKIP 1 COPY 19 0x13 0x12 0x11 0x10 0xF 0xE 0xD 0xC 0xB 0xA 0x9 0x8 0x7 0x6 0x5 0x4 0x3 0x2 0x1 SKIP 1 COPY 20 0x14 0x13 0x12 0x11 0x10 0xF 0xE 0xD 0xC 0xB 0xA 0x9 0x8 0x7 0x6 0x5 0x4 0x3 0x2 0x1 SKIP 1 COPY 21 0x15 0x14 0x13 0x12 0x11 0x10 0xF 0xE 0xD 0xC 0xB 0xA 0x9 0x8 0x7 0x6 0x5 0x4 0x3 0x2 0x1 SKIP 1 COPY 22 0x16 0x15 0x14 0x13 0x12 0x11 0x10 0xF 0xE 0xD 0xC 0xB 0xA 0x9 0x8 0x7 0x6 0x5 0x4 0x3 0x2 0x1 SKIP 1 COPY 23 0x17 0x16 0x15 0x14 0x13 0x12 0x11 0x10 0xF 0xE 0xD 0xC 0xB 0xA 0x9 0x8 0x7 0x6 0x5 0x4 0x3 0x2 0x1 SKIP 1 COPY 24 0x18 0x17 0x16 0x15 0x14 0x13 0x12 0x11 0x10 0xF 0xE 0xD 0xC 0xB 0xA 0x9 0x8 0x7 0x6 0x5 0x4 0x3 0x2 0x1 SKIP 1 COPY 25 0x19 0x18 0x17 0x16 0x15 0x14 0x13 0x12 0x11 0x10 0xF 0xE 0xD 0xC 0xB 0xA 0x9 0x8 0x7 0x6 0x5 0x4 0x3 0x2 0x1 SKIP 1 COPY 26 0x1A 0x19 0x18 0x17 0x16 0x15 0x14 0x13 0x12 0x11 0x10 0xF 0xE 0xD 0xC 0xB 0xA 0x9 0x8 0x7 0x6 0x5 0x4 0x3 0x2 0x1 SKIP 1 COPY 27 0x1B 0x1A 0x19 0x18 0x17 0x16 0x15 0x14 0x13 0x12 0x11 0x10 0xF 0xE 0xD 0xC 0xB 0xA 0x9 0x8 0x7 0x6 0x5 0x4 0x3 0x2 0x1 SKIP 1 COPY 28 0x1C 0x1B 0x1A 0x19 0x18 0x17 0x16 0x15 0x14 0x13 0x12 0x11 0x10 0xF 0xE 0xD 0xC 0xB 0xA 0x9 0x8 0x7 0x6 0x5 0x4 0x3 0x2 0x1 SKIP 1 COPY 29 0x1D 0x1C 0x1B 0x1A 0x19 0x18 0x17 0x16 0x15 0x14 0x13 0x12 0x11 0x10 0xF 0xE 0xD 0xC 0xB 0xA 0x9 0x8 0x7 0x6 0x5 0x4 0x3 0x2 0x1 SKIP 1 COPY 30 0x1E 0x1D 0x1C 0x1B 0x1A 0x19 0x18 0x17 0x16 0x15 0x14 0x13 0x12 0x11 0x10 0xF 0xE 0xD 0xC 0xB 0xA 0x9 0x8 0x7 0x6 0x5 0x4 0x3 0x2 0x1 SKIP 1 COPY 31 0x1F 0x1E 0x1D 0x1C 0x1B 0x1A 0x19 0x18 0x17 0x16 0x15 0x14 0x13 0x12 0x11 0x10 0xF 0xE 0xD 0xC 0xB 0xA 0x9 0x8 0x7 0x6 0x5 0x4 0x3 0x2 0x1 SKIP 1 COPY 16 0x10 0xF 0xE 0xD 0xC 0xB 0xA 0x9 0x8 0x7 0x6 0x5 0x4 0x3 0x2 0x1 SKIP 1 COPY 17 0x11 0x10 0xF 0xE 0xD 0xC 0xB 0xA 0x9 0x8 0x7 0x6 0x5 0x4 0x3 0x2 0x1 SKIP 1 COPY 18 0x12 0x11 0x10 0xF 0xE 0xD 0xC 0xB 0xA 0x9 0x8 0x7 0x6 0x5 0x4 0x3 0x2 0x1 SKIP 1 COPY 19 0x13 0x12 0x11 0x10 0xF 0xE 0xD 0xC 0xB 0xA 0x9 0x8 0x7 0x6 0x5 0x4 0x3 0x2 0x1 SKIP 1 COPY 20 0x14 0x13 0x12 0x11 0x10 0xF 0xE 0xD 0xC 0xB 0xA 0x9 0x8 0x7 0x6 0x5 0x4 0x3 0x2 0x1 SKIP 1 COPY 21 0x15 0x14 0x13 0x12 0x11 0x10 0xF 0xE 0xD 0xC 0xB 0xA 0x9 0x8 0x7 0x6 0x5 0x4 0x3 0x2 0x1 SKIP 4 DONE"], @"isEqualToString");
  
  // convert generic codes to c4 codes
  
  uint32_t frameBufferSize = width * height;
  
  NSData *c4Codes = [self util_convertToC4Codes16:codes frameBufferNumPixels:frameBufferSize];
  
  uint32_t *inputBuffer32 = (uint32_t*) c4Codes.bytes;
  uint32_t inputBuffer32NumWords = c4Codes.length / sizeof(uint32_t);
  
  // allocate framebuffer to decode into
  
  uint16_t *frameBuffer16 = valloc(4096);
  memset(frameBuffer16, 0, 4096);
  
  // invoke decoder
  
  uint32_t result =
  maxvid_decode_c4_sample16(frameBuffer16, inputBuffer32, inputBuffer32NumWords, frameBufferSize);
  
  NSAssert(result == 0, @"result");
  
  NSAssert(memcmp(curr, frameBuffer16, sizeof(curr)) == 0, @"memcmp");
  
  free(frameBuffer16);
  return;
}

// 32BPP COPYBIG should cover 9 to 17 pixels.

+ (void) testEncodeAndDecodeBigCopy32BPP
{
  const int width = 128;
  const int height = 1;
  
  uint32_t prev[width * height];
  uint32_t curr[width * height];
  
  NSData *codes;
  NSString *results;
  
  // Treat all previous pixels as zero
  memset(&prev[0], 0, sizeof(prev));
  assert(prev[0] == 0);
  
  // Treat all (skipped) pixels as zero
  memset(&curr[0], 0, sizeof(prev));
  assert(curr[0] == 0);
  
  int offset, val, num;
  
  offset = 0;
  
  // Loop from 9 to 17 pixels, each pixel value counts down to 1
  
  for (int pixelNum = 9; pixelNum < 18; pixelNum++) {
    // COPY 8 0x8 0x7 ... 0x1 SKIP 1
    val = pixelNum;
    num = pixelNum;
    for (int i=0; i<num; i++) {
      curr[offset++] = val - i;
      //NSLog(@"curr[%d] = %d", (offset - 1), curr[(offset - 1)]);
    }
    offset += 1;
  }
  
  //NSLog(@"offset after first loop %d", offset);
  
  // COPY 2 ...
  val = 2;
  num = 2;
  for (int i=0; i<num; i++) {
    curr[offset++] = val - i;
    //NSLog(@"curr[%d] = %d", (offset - 1), curr[(offset - 1)]);
  }
  
  assert(offset == 128);
  
  codes = maxvid_encode_generic_delta_pixels32(prev, curr, sizeof(curr)/sizeof(uint32_t), width, height, NULL);
  results = [MaxvidEncodeTests util_printMvidCodes32:codes];
  NSAssert([results isEqualToString:@"COPY 9 0x9 0x8 0x7 0x6 0x5 0x4 0x3 0x2 0x1 SKIP 1 COPY 10 0xA 0x9 0x8 0x7 0x6 0x5 0x4 0x3 0x2 0x1 SKIP 1 COPY 11 0xB 0xA 0x9 0x8 0x7 0x6 0x5 0x4 0x3 0x2 0x1 SKIP 1 COPY 12 0xC 0xB 0xA 0x9 0x8 0x7 0x6 0x5 0x4 0x3 0x2 0x1 SKIP 1 COPY 13 0xD 0xC 0xB 0xA 0x9 0x8 0x7 0x6 0x5 0x4 0x3 0x2 0x1 SKIP 1 COPY 14 0xE 0xD 0xC 0xB 0xA 0x9 0x8 0x7 0x6 0x5 0x4 0x3 0x2 0x1 SKIP 1 COPY 15 0xF 0xE 0xD 0xC 0xB 0xA 0x9 0x8 0x7 0x6 0x5 0x4 0x3 0x2 0x1 SKIP 1 COPY 16 0x10 0xF 0xE 0xD 0xC 0xB 0xA 0x9 0x8 0x7 0x6 0x5 0x4 0x3 0x2 0x1 SKIP 1 COPY 17 0x11 0x10 0xF 0xE 0xD 0xC 0xB 0xA 0x9 0x8 0x7 0x6 0x5 0x4 0x3 0x2 0x1 SKIP 1 COPY 2 0x2 0x1 DONE"], @"isEqualToString");
  
  // convert generic codes to c4 codes
  
  uint32_t frameBufferSize = width * height;
  
  NSData *c4Codes = [self util_convertToC4Codes32:codes frameBufferNumPixels:frameBufferSize];
  
  uint32_t *inputBuffer32 = (uint32_t*) c4Codes.bytes;
  uint32_t inputBuffer32NumWords = c4Codes.length / sizeof(uint32_t);
  
  // allocate framebuffer to decode into
  
  uint32_t *frameBuffer32 = valloc(4096);
  memset(frameBuffer32, 0, 4096);
  
  // invoke decoder
  
  uint32_t result =
  maxvid_decode_c4_sample32(frameBuffer32, inputBuffer32, inputBuffer32NumWords, frameBufferSize);
  
  NSAssert(result == 0, @"result");
  
  NSAssert(memcmp(curr, frameBuffer32, sizeof(curr)) == 0, @"memcmp");
  
  free(frameBuffer32);
  return;
}


@end
