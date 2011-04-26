/*
 *  AVResourceLoaderTests.m
 *
 *  Created by Moses DeJong on 4/22/11.
 *  Copyright 2011 __MyCompanyName__. All rights reserved.
 *
 */

#import "RegressionTests.h"

#import "AVAnimatorLayer.h"
#include "AVAnimatorLayerPrivate.h"

#import "AVAnimatorMedia.h"
#import "AVAnimatorMediaPrivate.h"

#import "AVAppResourceLoader.h"
#import "AVQTAnimationFrameDecoder.h"

#import "AV7zAppResourceLoader.h"
#import "AV7zQT2MvidResourceLoader.h"

#import "AVMvidFrameDecoder.h"

#import "AVFileUtil.h"

@interface AVResourceLoaderTests : NSObject {}
@end

// The methods named test* will be automatically invoked by the RegressionTests harness.

@implementation AVResourceLoaderTests

// Get a pixel value from an image

+ (void) getPixels16BPP:(CGImageRef)image
                 offset:(int)offset
                nPixels:(int)nPixels
               pixelPtr:(void*)pixelPtr
{
  // Query pixel data at a specific pixel offset
  
  CFDataRef pixelData = CGDataProviderCopyData(CGImageGetDataProvider(image));  
  CFDataGetBytes(pixelData, CFRangeMake(offset, sizeof(uint16_t) * nPixels), (UInt8*)pixelPtr);
  CFRelease(pixelData);
}

// Decompress .mov.7z app resource to .mov in temp file and open.
// Then extract image data to make sure extraction was successful.

+ (void) test7zBlackBlue2x2_16BPP
{
	id appDelegate = [[UIApplication sharedApplication] delegate];	
	UIWindow *window = [appDelegate window];
	NSAssert(window, @"window");  
  
  NSString *archiveFilename = @"2x2_black_blue_16BPP.mov.7z";
  NSString *entryFilename = @"2x2_black_blue_16BPP.mov";  
  NSString *outPath = [AVFileUtil getTmpDirPath:entryFilename];
  
  // Create a plain AVAnimatorView without a movie controls and display
  // in portrait mode. This setup involves no containing views and
  // has no transforms applied to the AVAnimatorView.
  
  CGRect frame = CGRectMake(0, 0, 2, 2);
  UIView *view = [[[UIView alloc] initWithFrame:frame] autorelease];
  CALayer *viewLayer = view.layer;
  
  AVAnimatorLayer *avLayerObj = [AVAnimatorLayer aVAnimatorLayer:viewLayer];
  
  // Create Media object and link it to the animatorView
  
  AVAnimatorMedia *media = [AVAnimatorMedia aVAnimatorMedia];
  [avLayerObj attachMedia:media];
  
  // Create loader that will decompress a movie from a 7zip archive attached
  // as an application resource.
  
	AV7zAppResourceLoader *resLoader = [AV7zAppResourceLoader aV7zAppResourceLoader];
  resLoader.archiveFilename = archiveFilename;
  resLoader.movieFilename = entryFilename;
  resLoader.outPath = outPath;
	media.resourceLoader = resLoader;
  
  // If the decode mov path exists currently, delete it so that this test case always
  // decodes the .mov from the .7z compressed Resource.

  if ([AVFileUtil fileExists:outPath]) {
    BOOL worked = [[NSFileManager defaultManager] removeItemAtPath:outPath error:nil];
    NSAssert(worked, @"could not remove existing file with same name as tmp dir");
  }
  
  // Create decoder that will generate frames from Quicktime Animation encoded data
  
  AVQTAnimationFrameDecoder *frameDecoder = [AVQTAnimationFrameDecoder aVQTAnimationFrameDecoder];
	media.frameDecoder = frameDecoder;
  
  media.animatorFrameDuration = 1.0;
  
  [window addSubview:view];
  
  [media prepareToAnimate];
  
  BOOL worked = [RegressionTests waitUntilTrue:media
                                      selector:@selector(isReadyToAnimate)
                                   maxWaitTime:10.0];
  NSAssert(worked, @"worked");
  
  NSAssert(media.state == READY, @"isReadyToAnimate");
  
  // At this point, initial keyframe should be displayed
  
  NSAssert([frameDecoder hasAlphaChannel] == FALSE, @"hasAlphaChannel");
  
  NSAssert(media.currentFrame == 0, @"currentFrame");
  
  NSAssert(avLayerObj.image != nil, @"image");
  
  NSAssert(media.prevFrame == nil, @"prev frame not set properly");
  
  uint16_t pixel[4];
  
  // First frame is all black pixels
  
  [self getPixels16BPP:avLayerObj.image.CGImage
                offset:0
               nPixels:4
              pixelPtr:&pixel[0]];
  
  NSAssert(pixel[0] == 0x0, @"pixel");  
  NSAssert(pixel[1] == 0x0, @"pixel");  
  NSAssert(pixel[2] == 0x0, @"pixel");  
  NSAssert(pixel[3] == 0x0, @"pixel");
  
  // Double check that the contents field matches the core graphics image
  
  NSAssert(avLayerObj.image.CGImage != nil, @"CGImage is nil");
  NSAssert((id)avLayerObj.image.CGImage == viewLayer.contents, @"contents not set");
  
  // Second frame is all blue pixels
  
  UIImage *frameBefore = avLayerObj.image;
  
  [media showFrame:1];
  
  UIImage *frameAfter = avLayerObj.image;
  
  NSAssert(frameAfter != nil, @"image");
  NSAssert(frameBefore != frameAfter, @"image");
  
  [self getPixels16BPP:avLayerObj.image.CGImage
                offset:0
               nPixels:4
              pixelPtr:&pixel[0]];
  
  NSAssert(pixel[0] == 0x1F, @"pixel");  
  NSAssert(pixel[1] == 0x1F, @"pixel");  
  NSAssert(pixel[2] == 0x1F, @"pixel");  
  NSAssert(pixel[3] == 0x1F, @"pixel");
  
  // Double check that the contents field matches the core graphics image
  
  NSAssert(avLayerObj.image.CGImage != nil, @"CGImage is nil");
  NSAssert((id)avLayerObj.image.CGImage == viewLayer.contents, @"contents not set");  
  
  return;
}

// Use AV7zAppResourceLoader class to decompress .mov.7z to .mov and compare
// the results to a known good result, also attached as a resource.

+ (void) testDecode7zCompareToResource
{
  NSString *archiveFilename = @"2x2_black_blue_16BPP.mov.7z";
  NSString *entryFilename = @"2x2_black_blue_16BPP.mov";
  NSString *outPath = [AVFileUtil getTmpDirPath:entryFilename];
  
  AV7zAppResourceLoader *resLoader = [AV7zAppResourceLoader aV7zAppResourceLoader];
  resLoader.archiveFilename = archiveFilename;
  resLoader.movieFilename = entryFilename;
  resLoader.outPath = outPath;
  
  // If the decode mov path exists currently, delete it so that this test case always
  // decodes the .mov from the .7z compressed Resource.
  
  if ([AVFileUtil fileExists:outPath]) {
    BOOL worked = [[NSFileManager defaultManager] removeItemAtPath:outPath error:nil];
    NSAssert(worked, @"could not remove existing file with same name as tmp dir");
  }  
  
  [resLoader load];
  
  BOOL worked = [RegressionTests waitUntilTrue:resLoader
                                      selector:@selector(isReady)
                                   maxWaitTime:10.0];
  NSAssert(worked, @"worked");  
  
  NSLog(@"Wrote : %@", outPath);
  
  if (1) {
    // Compare extracted file data to identical data attached as a project resource
    
    NSData *wroteMvidData = [NSData dataWithContentsOfMappedFile:outPath];
    NSAssert(wroteMvidData, @"could not map .mov data");
    
    NSString *resPath = [AVFileUtil getResourcePath:entryFilename];
    NSData *resMvidData = [NSData dataWithContentsOfMappedFile:resPath];
    NSAssert(resMvidData, @"could not map .mov data");
    
    uint32_t resByteLength = [resMvidData length];
    uint32_t wroteByteLength = [wroteMvidData length];
    
    // Extracted 2x2_black_blue_16BPP.mov Size should be 839 bytes
    
    BOOL sameLength = (resByteLength == wroteByteLength);
    NSAssert(sameLength, @"sameLength");
    BOOL same = [resMvidData isEqualToData:wroteMvidData];
    NSAssert(same, @"same");
  }
  
  return;
}

// Decompress a .mov.7z file and convert the .mov data to .mvid

+ (void) testDecode7zMvidCompareToResource
{  
  NSString *archiveFilename = @"2x2_black_blue_16BPP.mov.7z";
  NSString *entryFilename = @"2x2_black_blue_16BPP.mov";
  NSString *outFilename = @"2x2_black_blue_16BPP.mvid";
  NSString *outPath = [AVFileUtil getTmpDirPath:outFilename];

  AV7zQT2MvidResourceLoader *resLoader = [AV7zQT2MvidResourceLoader aV7zQT2MvidResourceLoader];
  resLoader.archiveFilename = archiveFilename;
  resLoader.movieFilename = entryFilename;
  resLoader.outPath = outPath;
  
  // If the decode mov path exists currently, delete it so that this test case always
  // decodes the .mov from the .7z compressed Resource.
  
  if ([AVFileUtil fileExists:outPath]) {
    BOOL worked = [[NSFileManager defaultManager] removeItemAtPath:outPath error:nil];
    NSAssert(worked, @"could not remove existing file with same name as tmp dir");
  }  
  
  [resLoader load];
  
  BOOL worked = [RegressionTests waitUntilTrue:resLoader
                                      selector:@selector(isReady)
                                   maxWaitTime:10.0];
  NSAssert(worked, @"worked");  
  
  NSLog(@"Wrote : %@", outPath);
  
  if (1) {
    // Compare extracted file data to identical data attached as a project resource
    
    NSData *wroteMvidData = [NSData dataWithContentsOfMappedFile:outPath];
    NSAssert(wroteMvidData, @"could not map .mov data");
    
    NSString *resPath = [AVFileUtil getResourcePath:outFilename];
    NSData *resMvidData = [NSData dataWithContentsOfMappedFile:resPath];
    NSAssert(resMvidData, @"could not map .mov data");
    
    uint32_t resByteLength = [resMvidData length];
    uint32_t wroteByteLength = [wroteMvidData length];
    
    // Converted 2x2_black_blue_16BPP.mvid should be 12288 bytes
    
    BOOL sameLength = (resByteLength == wroteByteLength);
    NSAssert(sameLength, @"sameLength");
    BOOL same = [resMvidData isEqualToData:wroteMvidData];
    NSAssert(same, @"same");
    
    // Verify that the emitted .mvid file has a valid magic number
    
    char *mvidBytes = (char*) [wroteMvidData bytes];
    
    MVFile *mvFilePtr = maxvid_file_map_open(mvidBytes);
    
    assert(mvFilePtr->header.numFrames == 2);
    
    maxvid_file_map_close(mvFilePtr);
  }
  
  return;
}

+ (void) test7zMvidBlackBlue2x2_16BPP
{
	id appDelegate = [[UIApplication sharedApplication] delegate];	
	UIWindow *window = [appDelegate window];
	NSAssert(window, @"window");  
  
  NSString *archiveFilename = @"2x2_black_blue_16BPP.mov.7z";
  NSString *entryFilename = @"2x2_black_blue_16BPP.mov";
  NSString *outFilename = @"2x2_black_blue_16BPP.mvid";
  
  NSString *outPath = [AVFileUtil getTmpDirPath:outFilename];
  
  // Create a plain AVAnimatorView without a movie controls and display
  // in portrait mode. This setup involves no containing views and
  // has no transforms applied to the AVAnimatorView.
  
  CGRect frame = CGRectMake(0, 0, 2, 2);
  UIView *view = [[[UIView alloc] initWithFrame:frame] autorelease];
  CALayer *viewLayer = view.layer;
  
  AVAnimatorLayer *avLayerObj = [AVAnimatorLayer aVAnimatorLayer:viewLayer];
  
  // Create Media object and link it to the animatorView
  
  AVAnimatorMedia *media = [AVAnimatorMedia aVAnimatorMedia];
  [avLayerObj attachMedia:media];
  
  // Create loader that will decompress a movie from a 7zip archive attached
  // as an application resource.
  
	AV7zQT2MvidResourceLoader *resLoader = [AV7zQT2MvidResourceLoader aV7zQT2MvidResourceLoader];
  resLoader.archiveFilename = archiveFilename;
  resLoader.movieFilename = entryFilename;
  resLoader.outPath = outPath;
	media.resourceLoader = resLoader;
  
  // If the decode mov path exists currently, delete it so that this test case always
  // decodes the .mov from the .7z compressed Resource.
  
  if ([AVFileUtil fileExists:outPath]) {
    BOOL worked = [[NSFileManager defaultManager] removeItemAtPath:outPath error:nil];
    NSAssert(worked, @"could not remove existing file with same name as tmp dir");
  }
  
  NSAssert(![resLoader isReady], @"not ready yet");
  
  // Create decoder that will generate frames from Quicktime Animation encoded data
  
  AVMvidFrameDecoder *frameDecoder = [AVMvidFrameDecoder aVMvidFrameDecoder];
	media.frameDecoder = frameDecoder;
  
  media.animatorFrameDuration = 1.0;
  
  [window addSubview:view];
  
  [media prepareToAnimate];
  
  BOOL worked = [RegressionTests waitUntilTrue:media
                                      selector:@selector(isReadyToAnimate)
                                   maxWaitTime:10.0];
  NSAssert(worked, @"worked");
  
  NSAssert(media.state == READY, @"isReadyToAnimate");
  
  // At this point, initial keyframe should be displayed
  
  NSAssert([frameDecoder hasAlphaChannel] == FALSE, @"hasAlphaChannel");
  
  NSAssert(media.currentFrame == 0, @"currentFrame");
  
  NSAssert(avLayerObj.image != nil, @"image");
  
  NSAssert(media.prevFrame == nil, @"prev frame not set properly");
  
  uint16_t pixel[4];
  
  // First frame is all black pixels
  
  [self getPixels16BPP:avLayerObj.image.CGImage
                offset:0
               nPixels:4
              pixelPtr:&pixel[0]];
  
  NSAssert(pixel[0] == 0x0, @"pixel");  
  NSAssert(pixel[1] == 0x0, @"pixel");  
  NSAssert(pixel[2] == 0x0, @"pixel");  
  NSAssert(pixel[3] == 0x0, @"pixel");
  
  // Double check that the contents field matches the core graphics image
  
  NSAssert(avLayerObj.image.CGImage != nil, @"CGImage is nil");
  NSAssert((id)avLayerObj.image.CGImage == viewLayer.contents, @"contents not set");
  
  // Second frame is all blue pixels
  
  UIImage *frameBefore = avLayerObj.image;
  
  [media showFrame:1];
  
  UIImage *frameAfter = avLayerObj.image;
  
  NSAssert(frameAfter != nil, @"image");
  NSAssert(frameBefore != frameAfter, @"image");
  
  [self getPixels16BPP:avLayerObj.image.CGImage
                offset:0
               nPixels:4
              pixelPtr:&pixel[0]];
  
  NSAssert(pixel[0] == 0x1F, @"pixel");  
  NSAssert(pixel[1] == 0x1F, @"pixel");  
  NSAssert(pixel[2] == 0x1F, @"pixel");  
  NSAssert(pixel[3] == 0x1F, @"pixel");
  
  // Double check that the contents field matches the core graphics image
  
  NSAssert(avLayerObj.image.CGImage != nil, @"CGImage is nil");
  NSAssert((id)avLayerObj.image.CGImage == viewLayer.contents, @"contents not set");  
  
  return;
}

@end
