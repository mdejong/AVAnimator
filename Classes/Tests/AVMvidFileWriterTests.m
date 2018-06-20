//
//  AVMvidFileWriterTests.m
//
//  Created by Moses DeJong on 2/24/16.
//
// Test AVMvidFileWriter object which write a MVID to the disk.

#import <Foundation/Foundation.h>

#import "RegressionTests.h"

#import "AVAnimatorView.h"
#include "AVAnimatorViewPrivate.h"

#import "AVAnimatorLayer.h"
#include "AVAnimatorLayerPrivate.h"

#import "AVAnimatorMedia.h"
#import "AVAnimatorMediaPrivate.h"

#import "AVAppResourceLoader.h"

#import "AV7zAppResourceLoader.h"

#import "AVMvidFrameDecoder.h"

#import "AVFileUtil.h"

#import "AVFrame.h"

#import "AVMvidFileWriter.h"

#import "AVStreamEncodeDecode.h"

@interface AVMvidFileWriterTests : NSObject {
}
@end

// class AVAnimatorMediaTests

@implementation AVMvidFileWriterTests

// This test case will create a media object and attempt to load video data from a file that exists
// but contains no data. It is not possible to create a loader for a file that does not even exist.

+ (void) testWrite3x1At24BPP_V2
{
	id appDelegate = [[UIApplication sharedApplication] delegate];	
	UIWindow *window = [appDelegate window];
	NSAssert(window, @"window");
  
  BOOL worked;
  
  // Get tmp dir path and create an empty file with the .mvid extension
  
  NSString *tmpFilename = @"Vid3x1At24BPP.mvid";
  NSString *tmpDir = NSTemporaryDirectory();
  NSString *tmpPath = [tmpDir stringByAppendingPathComponent:tmpFilename];
  
  AVMvidFileWriter *avMvidFileWriter = [AVMvidFileWriter aVMvidFileWriter];
  
  avMvidFileWriter.mvidPath = tmpPath;
  
  avMvidFileWriter.bpp = 24;
  
  avMvidFileWriter.frameDuration = 1.0 / 10;
  avMvidFileWriter.totalNumFrames = (int) 2;
  
  avMvidFileWriter.genAdler = TRUE;
  
  avMvidFileWriter.movieSize = CGSizeMake(3, 1);
  
  uint32_t keyframe1Data[] = { 0xFF000000, 0xFF000000, 0xFF000000 };
  
  worked = [avMvidFileWriter open];
  
  NSAssert(worked, @"error: Could not open .mvid output file \"%@\"", avMvidFileWriter.mvidPath);
  
  [avMvidFileWriter writeKeyframe:(char*)&keyframe1Data[0] bufferSize:sizeof(keyframe1Data)];

  worked = [avMvidFileWriter rewriteHeader];

  NSAssert(worked, @"error: Could not write .mvid output file \"%@\"", avMvidFileWriter.mvidPath);
  
  [avMvidFileWriter close];
  
  // Open file that was just written as inspect it
  
  FILE *fp = fopen((char*)[tmpPath UTF8String], "rb");
  
  uint32_t isValid = maxvid_file_is_valid(fp);
  
  fclose(fp);
  
  NSAssert(isValid, @"isValid");
  
  NSData *fileAsData = [NSData dataWithContentsOfFile:tmpPath];
  
  NSAssert(fileAsData, @"read file as data");
  
  char *fileData = (char*)fileAsData.bytes;
  int numBytes = (int)fileAsData.length;
  
  maxvid_file_map_verify(fileData);
  
  NSAssert(numBytes == 32768, @"numBytes");
  
  MVFileHeader *fileHeaderPtr = (MVFileHeader*) fileData;
  
  uint8_t version = maxvid_file_version(fileHeaderPtr);
  
  NSAssert(version == 2, @"version");
  
  NSAssert(maxvid_file_is_all_keyframes(fileHeaderPtr), @"maxvid_file_is_all_keyframes");
  
  // Frame offset and size are in terms of bytes
  
  void *framesPtr = (void *) (fileData + sizeof(MVFileHeader));
  
  MVFrame* frame = maxvid_file_frame(framesPtr, 0);
  
  NSAssert(maxvid_frame_offset(frame) == (4*4096), @"maxvid_frame_offset");
  
  NSAssert(maxvid_frame_length(frame) == 12, @"maxvid_frame_length");
  
  [[NSFileManager defaultManager] removeItemAtPath:tmpPath error:nil];
  
  return;
}

// This test case will create a media object and attempt to load video data from a file that exists
// but contains no data. It is not possible to create a loader for a file that does not even exist.

+ (void) testWrite3x1At24BPP_V3
{
  id appDelegate = [[UIApplication sharedApplication] delegate];
  UIWindow *window = [appDelegate window];
  NSAssert(window, @"window");
  
  BOOL worked;
  
  // Get tmp dir path and create an empty file with the .mvid extension
  
  NSString *tmpFilename = @"Vid3x1At24BPP.mvid";
  NSString *tmpDir = NSTemporaryDirectory();
  NSString *tmpPath = [tmpDir stringByAppendingPathComponent:tmpFilename];
  
  AVMvidFileWriter *avMvidFileWriter = [AVMvidFileWriter aVMvidFileWriter];
  
  avMvidFileWriter.mvidPath = tmpPath;
  
  avMvidFileWriter.bpp = 24;
  
  avMvidFileWriter.frameDuration = 1.0 / 10;
  avMvidFileWriter.totalNumFrames = (int) 2;
  
  avMvidFileWriter.genAdler = TRUE;
  
  avMvidFileWriter.genV3 = TRUE;
  
  avMvidFileWriter.movieSize = CGSizeMake(3, 1);
  
  uint32_t keyframe1Data[] = { 0xFF000000, 0xFF000000, 0xFF000000 };
  
  worked = [avMvidFileWriter open];
  
  NSAssert(worked, @"error: Could not open .mvid output file \"%@\"", avMvidFileWriter.mvidPath);
  
  [avMvidFileWriter writeKeyframe:(char*)&keyframe1Data[0] bufferSize:sizeof(keyframe1Data)];
  
  worked = [avMvidFileWriter rewriteHeader];
  
  NSAssert(worked, @"error: Could not write .mvid output file \"%@\"", avMvidFileWriter.mvidPath);
  
  [avMvidFileWriter close];
  
  // Open file that was just written as inspect it
  
  FILE *fp = fopen((char*)[tmpPath UTF8String], "rb");
  
  uint32_t isValid = maxvid_file_is_valid(fp);
  
  fclose(fp);
  
  NSAssert(isValid, @"isValid");
  
  NSData *fileAsData = [NSData dataWithContentsOfFile:tmpPath];
  
  NSAssert(fileAsData, @"read file as data");
  
  char *fileData = (char*)fileAsData.bytes;
  int numBytes = (int)fileAsData.length;
  
  maxvid_file_map_verify(fileData);
  
  NSAssert(numBytes == 32768, @"numBytes");
  
  MVFileHeader *fileHeaderPtr = (MVFileHeader*) fileData;
  
  uint8_t version = maxvid_file_version(fileHeaderPtr);
  
  NSAssert(version == 3, @"version");
  
  NSAssert(maxvid_file_is_all_keyframes(fileHeaderPtr), @"maxvid_file_is_all_keyframes");
  
  // Frame offset should be 1, frame size should be zero
  
  void *framesPtr = (void *) (fileData + sizeof(MVFileHeader));
  
  MVV3Frame* frame = maxvid_v3_file_frame(framesPtr, 0);
  
  NSAssert(maxvid_v3_frame_offset(frame) == 16384, @"maxvid_frame_offset");
  
  NSAssert(maxvid_v3_frame_length(frame) == 12, @"maxvid_frame_length");
  
  [[NSFileManager defaultManager] removeItemAtPath:tmpPath error:nil];
  
  return;
}

// This test case will create a media object and attempt to load video data from a file that exists
// but contains no data. It is not possible to create a loader for a file that does not even exist.

+ (void) testWrite3x1At16BPP_V3
{
  id appDelegate = [[UIApplication sharedApplication] delegate];
  UIWindow *window = [appDelegate window];
  NSAssert(window, @"window");
  
  BOOL worked;
  
  // Get tmp dir path and create an empty file with the .mvid extension
  
  NSString *tmpFilename = @"Vid3x1At16BPP.mvid";
  NSString *tmpDir = NSTemporaryDirectory();
  NSString *tmpPath = [tmpDir stringByAppendingPathComponent:tmpFilename];
  
  AVMvidFileWriter *avMvidFileWriter = [AVMvidFileWriter aVMvidFileWriter];
  
  avMvidFileWriter.mvidPath = tmpPath;
  
  avMvidFileWriter.bpp = 16;
  
  avMvidFileWriter.frameDuration = 1.0 / 10;
  avMvidFileWriter.totalNumFrames = (int) 2;
  
  avMvidFileWriter.genAdler = TRUE;
  
  avMvidFileWriter.genV3 = TRUE;
  
  avMvidFileWriter.movieSize = CGSizeMake(3, 1);
  
  uint16_t keyframe1Data[] = { 0xFFFF, 0xFFFF, 0xFFFF, 0x0000 }; // 16 bits of padding
  
  worked = [avMvidFileWriter open];
  
  NSAssert(worked, @"error: Could not open .mvid output file \"%@\"", avMvidFileWriter.mvidPath);
  
  [avMvidFileWriter writeKeyframe:(char*)&keyframe1Data[0] bufferSize:sizeof(keyframe1Data)];
  
  worked = [avMvidFileWriter rewriteHeader];
  
  NSAssert(worked, @"error: Could not write .mvid output file \"%@\"", avMvidFileWriter.mvidPath);
  
  [avMvidFileWriter close];
  
  // Open file that was just written as inspect it
  
  FILE *fp = fopen((char*)[tmpPath UTF8String], "rb");
  
  uint32_t isValid = maxvid_file_is_valid(fp);
  
  fclose(fp);
  
  NSAssert(isValid, @"isValid");
  
  NSData *fileAsData = [NSData dataWithContentsOfFile:tmpPath];
  
  NSAssert(fileAsData, @"read file as data");
  
  char *fileData = (char*)fileAsData.bytes;
  int numBytes = (int)fileAsData.length;
  
  maxvid_file_map_verify(fileData);
  
  NSAssert(numBytes == 32768, @"numBytes");
  
  MVFileHeader *fileHeaderPtr = (MVFileHeader*) fileData;
  
  uint8_t version = maxvid_file_version(fileHeaderPtr);
  
  NSAssert(version == 3, @"version");
  
  NSAssert(maxvid_file_is_all_keyframes(fileHeaderPtr), @"maxvid_file_is_all_keyframes");
  
  // Frame offset should be 1, frame size should be zero
  
  void *framesPtr = (MVFrame *) (fileData + sizeof(MVFileHeader));
  
  MVV3Frame* frame = maxvid_v3_file_frame(framesPtr, 0);
  
  NSAssert(maxvid_v3_frame_offset(frame) == 16384, @"maxvid_frame_offset");
  
  NSAssert(maxvid_v3_frame_length(frame) == 8, @"maxvid_frame_length");
  
  [[NSFileManager defaultManager] removeItemAtPath:tmpPath error:nil];
  
  return;
}

// With a special flag, the file writer can emit BGRA pixels as BGR data that is further
// compressed with a from of lz compression. Check that writing bytes and decoding them
// works as expected.

+ (void) testAVStreamEncodeDecode1
{
  uint32_t pixels[] = {
    0xFF000000,
    0xFF010101,
    0xFF020202,
    0xFF030303,
    0xFF040404,
    0xFF050505,
    0xFF060606,
    0xFF070707,
    0xFF080808,
    0xFF090909,
    0xFF0A0A0A,
    0xFF0B0B0B,
    0xFF0C0C0C,
    0xFF0D0D0D,
  };
  
  NSData *pixelData = [NSData dataWithBytes:pixels length:sizeof(pixels)];
  NSMutableData *mEncodedData = [NSMutableData data];

  int bpp = 24;
  
  // Note that the compression method is self checking
  
  BOOL worked = [AVStreamEncodeDecode streamDeltaAndCompress:pixelData
                                   encodedData:mEncodedData
                                           bpp:bpp
                                     algorithm:COMPRESSION_LZ4];
  
  NSAssert(worked == TRUE, @"worked");

  return;
}

+ (void) testAVStreamEncodeDecode2
{
  uint32_t pixels[] = {
    0xFF000000,
    0xFF010101,
    0xFF020202,
    0xFF030303,
    0xFF040404,
    0xFF050505,
    0xFF060606,
    0xFF070707,
    0xFF080808,
    0xFF090909,
    0xFF0A0A0A,
    0xFF0B0B0B,
    0xFF0C0C0C,
    0xFF0D0D0D,
    0xFF0E0E0E,
    0xFF0F0F0F,
  };
  
  NSData *pixelData = [NSData dataWithBytes:pixels length:sizeof(pixels)];
  NSMutableData *mEncodedData = [NSMutableData data];
  
  int bpp = 24;
  
  // Note that the compression method is self checking
  
  BOOL worked = [AVStreamEncodeDecode streamDeltaAndCompress:pixelData
                                   encodedData:mEncodedData
                                           bpp:bpp
                                     algorithm:COMPRESSION_LZ4];
  
  NSAssert(worked == TRUE, @"worked");
  
  return;
}

// Test with a series of input pixel buffer sizes that repeat
// an input pattern of (0 -> 15) values stores as pixels.

+ (void) testAVStreamEncodeDecode3
{
  uint32_t pixels[] = {
    0xFF000000,
    0xFF010101,
    0xFF020202,
    0xFF030303,
    0xFF040404,
    0xFF050505,
    0xFF060606,
    0xFF070707,
    0xFF080808,
    0xFF090909,
    0xFF0A0A0A,
    0xFF0B0B0B,
    0xFF0C0C0C,
    0xFF0D0D0D,
    0xFF0E0E0E,
    0xFF0F0F0F,
  };
  
  for (int i = 0; i < 128; i++) @autoreleasepool {
    NSMutableData *mPixelData = [NSMutableData data];

    int numPixelsOutput = 16 + i;
    
    [mPixelData setLength:numPixelsOutput*sizeof(uint32_t)];
    
    uint32_t *mPixelPtr = (uint32_t *) mPixelData.mutableBytes;
    
    for (int pi = 0; pi < numPixelsOutput; pi++) {
      int piMod = pi % 16;
      uint32_t pixel = pixels[piMod];
      mPixelPtr[pi] = pixel;
    }
    
    NSMutableData *mEncodedData = [NSMutableData data];
    
    int bpp = 24;
    
    // Note that the compression method is self checking
    
    BOOL worked = [AVStreamEncodeDecode streamDeltaAndCompress:mPixelData
                                     encodedData:mEncodedData
                                             bpp:bpp
                                       algorithm:COMPRESSION_LZ4];
    
    NSAssert(worked == TRUE, @"worked");
  }
  
  return;
}

// Test a large number of very large buffers

+ (void) testAVStreamEncodeDecode4
{
  uint32_t pixels[] = {
    0xFF000000,
    0xFF010101,
    0xFF020202,
    0xFF030303,
    0xFF040404,
    0xFF050505,
    0xFF060606,
    0xFF070707,
    0xFF080808,
    0xFF090909,
    0xFF0A0A0A,
    0xFF0B0B0B,
    0xFF0C0C0C,
    0xFF0D0D0D,
    0xFF0E0E0E,
    0xFF0F0F0F,
  };
  
  for (int i = 1024; i < (1024 * 10); i++) @autoreleasepool {
    NSMutableData *mPixelData = [NSMutableData data];
    
    int numPixelsOutput = 16 + i;
    
    [mPixelData setLength:numPixelsOutput*sizeof(uint32_t)];
    
    uint32_t *mPixelPtr = (uint32_t *) mPixelData.mutableBytes;
    
    for (int pi = 0; pi < numPixelsOutput; pi++) {
      int piMod = pi % 16;
      uint32_t pixel = pixels[piMod];
      mPixelPtr[pi] = pixel;
    }
    
    NSMutableData *mEncodedData = [NSMutableData data];
    
    int bpp = 24;
    
    // Note that the compression method is self checking
    
    BOOL worked = [AVStreamEncodeDecode streamDeltaAndCompress:mPixelData
                                     encodedData:mEncodedData
                                             bpp:bpp
                                       algorithm:COMPRESSION_LZ4];
    
    NSAssert(worked == TRUE, @"worked");
  }
  
  return;
}

+ (void) testAVStreamEncodeDecode5
{
  uint32_t pixels[] = {
    0xFF000000,
    0xFF010101,
    0xFF000000,
    0xFF000000,
    0xFF020202,
    0xFF000000,
    0xFF000000,
    0xFF000000,
    0xFF030303,
    0xFF000000,
    0xFF000000,
    0xFF000000,
    0xFF000000,
    0xFF000000,
    0xFF000000,
    0xFF0F0F0F,
  };
  
  for (int i = 0; i < 1024; i++) @autoreleasepool {
    NSMutableData *mPixelData = [NSMutableData data];
    
    int numPixelsOutput = 16 + i;
    
    [mPixelData setLength:numPixelsOutput*sizeof(uint32_t)];
    
    uint32_t *mPixelPtr = (uint32_t *) mPixelData.mutableBytes;
    
    for (int pi = 0; pi < numPixelsOutput; pi++) {
      int piMod = pi % 16;
      uint32_t pixel = pixels[piMod];
      mPixelPtr[pi] = pixel;
    }
    
    NSMutableData *mEncodedData = [NSMutableData data];
    
    int bpp = 24;
    
    // Note that the compression method is self checking
    
    BOOL worked = [AVStreamEncodeDecode streamDeltaAndCompress:mPixelData
                                     encodedData:mEncodedData
                                             bpp:bpp
                                       algorithm:COMPRESSION_LZ4];
    
    NSAssert(worked == TRUE, @"worked");
  }
  
  return;
}

// Util method will fail if passed 24 BPP but one of the input pixels
// actually contains an alpha channel value other than 0x00 or 0xFF

+ (void) testAVStreamEncodeDecode6
{
  uint32_t pixels[] = {
    0xFF000000,
    0x01010101
  };
  
  NSData *pixelData = [NSData dataWithBytes:pixels length:sizeof(pixels)];
  NSMutableData *mEncodedData = [NSMutableData data];
  
  int bpp = 24;
  
  // Note that the compression method is self checking
  
  BOOL worked = [AVStreamEncodeDecode streamDeltaAndCompress:pixelData
                                   encodedData:mEncodedData
                                           bpp:bpp
                                     algorithm:COMPRESSION_LZ4];
  
  NSAssert(worked == FALSE, @"!worked");
  
  return;
}

@end // AVAnimatorMediaTests
