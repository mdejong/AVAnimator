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


@implementation MaxvidEncodeTests

// Debug print method

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
      
      // foreach work in copy, write as hex!
      
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

// This test case checks a 1x1 frame with identical pixel values.

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

// This test case checks a 1x1 frame with different pixel values.

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

@end
