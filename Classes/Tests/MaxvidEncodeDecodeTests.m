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


@end
