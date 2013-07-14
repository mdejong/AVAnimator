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

@end
