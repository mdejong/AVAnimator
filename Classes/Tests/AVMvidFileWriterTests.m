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
  
  MVFrame *framesPtr = (MVFrame *) (fileData + sizeof(MVFileHeader));
  
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
  
  avMvidFileWriter.genV3PageOffsetBlocks = TRUE;
  
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
  
  MVFrame *framesPtr = (MVFrame *) (fileData + sizeof(MVFileHeader));
  
  MVFrame* frame = maxvid_file_frame(framesPtr, 0);
  
  NSAssert(maxvid_frame_offset(frame) == 1, @"maxvid_frame_offset");
  
  NSAssert(maxvid_frame_length(frame) == 0, @"maxvid_frame_length");
  
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
  
  avMvidFileWriter.genV3PageOffsetBlocks = TRUE;
  
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
  
  MVFrame *framesPtr = (MVFrame *) (fileData + sizeof(MVFileHeader));
  
  MVFrame* frame = maxvid_file_frame(framesPtr, 0);
  
  NSAssert(maxvid_frame_offset(frame) == 1, @"maxvid_frame_offset");
  
  NSAssert(maxvid_frame_length(frame) == 0, @"maxvid_frame_length");
  
  [[NSFileManager defaultManager] removeItemAtPath:tmpPath error:nil];
  
  return;
}

@end // AVAnimatorMediaTests
