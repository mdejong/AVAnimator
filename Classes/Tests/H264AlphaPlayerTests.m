//
//  H264AlphaPlayerTests.m
//
//  Created by Mo DeJong on 3/16/16.

#import <Foundation/Foundation.h>

#import "RegressionTests.h"

#import "AVAnimatorH264AlphaPlayer.h"

@interface AVAnimatorH264AlphaPlayer ()

+ (uint32_t) timeIntervalToFrameOffset:(CFTimeInterval)elapsed
                                   fps:(CFTimeInterval)fps;

@end

@interface H264AlphaPlayerTests : NSObject

@end

@implementation H264AlphaPlayerTests

// Test measurement of frame offset based on elapsed time

- (void)testFrameTime1 {
  CFTimeInterval elapsed = 0.0;
  CFTimeInterval fps = 2.0;
  uint32_t frameOffset;
  
  frameOffset = [AVAnimatorH264AlphaPlayer timeIntervalToFrameOffset:elapsed fps:fps];
  
  NSAssert(frameOffset == 1, @"");
}

- (void)testFrameTime2 {
  CFTimeInterval elapsed = 0.1;
  CFTimeInterval fps = 2.0;
  uint32_t frameOffset;
  
  frameOffset = [AVAnimatorH264AlphaPlayer timeIntervalToFrameOffset:elapsed fps:fps];
  
  NSAssert(frameOffset == 1, @"");
}

- (void)testFrameTime3 {
  CFTimeInterval elapsed = 0.49;
  CFTimeInterval fps = 2.0;
  uint32_t frameOffset;
  
  frameOffset = [AVAnimatorH264AlphaPlayer timeIntervalToFrameOffset:elapsed fps:fps];
  
  NSAssert(frameOffset == 1, @"");
}

- (void)testFrameTime4 {
  CFTimeInterval elapsed = 0.50;
  CFTimeInterval fps = 2.0;
  uint32_t frameOffset;
  
  frameOffset = [AVAnimatorH264AlphaPlayer timeIntervalToFrameOffset:elapsed fps:fps];
  
  NSAssert(frameOffset == 1, @"");
}

- (void)testFrameTime5 {
  CFTimeInterval elapsed = 0.51;
  CFTimeInterval fps = 2.0;
  uint32_t frameOffset;
  
  frameOffset = [AVAnimatorH264AlphaPlayer timeIntervalToFrameOffset:elapsed fps:fps];
  
  NSAssert(frameOffset == 1, @"");
}

- (void)testFrameTime6 {
  CFTimeInterval elapsed = 0.6;
  CFTimeInterval fps = 2.0;
  uint32_t frameOffset;
  
  frameOffset = [AVAnimatorH264AlphaPlayer timeIntervalToFrameOffset:elapsed fps:fps];
  NSAssert(frameOffset == 1, @"");
}

// Rounds up to frame 2 at this point

- (void)testFrameTime7 {
  CFTimeInterval elapsed = 0.75;
  CFTimeInterval fps = 2.0;
  uint32_t frameOffset;
  
  frameOffset = [AVAnimatorH264AlphaPlayer timeIntervalToFrameOffset:elapsed fps:fps];
  NSAssert(frameOffset == 2, @"");
}

@end
