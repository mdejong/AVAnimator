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

#import "AVApng2MvidResourceLoader.h"
#import "AV7zApng2MvidResourceLoader.h"

#import "AVMvidFrameDecoder.h"

#import "AVFileUtil.h"

#import "AVAssetReaderConvertMaxvid.h"

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

+ (void) getPixels32BPP:(CGImageRef)image
                 offset:(int)offset
                nPixels:(int)nPixels
               pixelPtr:(void*)pixelPtr
{
  // Query pixel data at a specific pixel offset
  
  CFDataRef pixelData = CGDataProviderCopyData(CGImageGetDataProvider(image));
  CFDataGetBytes(pixelData, CFRangeMake(offset, sizeof(uint32_t) * nPixels), (UInt8*)pixelPtr);
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

  // Make sure binary compare matches by forcing adler generation when debugging is off
  resLoader.alwaysGenerateAdler = TRUE;
  
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
    // Compare generated mvid file data to identical data attached as a project resource
    
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
    
    MVFileHeader *mvFileHeaderPtr = (MVFileHeader*) mvidBytes;
    
    assert(mvFileHeaderPtr->numFrames == 2);
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

// Convert a .apng file attached as a project resource. This test converts
// to .mvid format and then converts from the optimized .mvid to CoreGraphics images.
// Decoding a .apng file downloaded from the network would be the same as this
// except the loader would read from the filesystem instead of the resources.

+ (void) testApngBlackBlue2x2_24BPP
{
	id appDelegate = [[UIApplication sharedApplication] delegate];	
	UIWindow *window = [appDelegate window];
	NSAssert(window, @"window");  
  
  NSString *resFilename = @"2x2_black_blue_24BPP.apng";
  NSString *outFilename = @"2x2_black_blue_24BPP.mvid";
  NSString *outPath = [AVFileUtil getTmpDirPath:outFilename];
  
  // If the converted mov path exists currently, delete it so that this test case always converts.
  
  if ([AVFileUtil fileExists:outPath]) {
    BOOL worked = [[NSFileManager defaultManager] removeItemAtPath:outPath error:nil];
    NSAssert(worked, @"could not remove existing file with same name as tmp dir");
  }

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
  
  AVApng2MvidResourceLoader *resLoader = [AVApng2MvidResourceLoader aVApng2MvidResourceLoader];
  resLoader.movieFilename = resFilename;
  resLoader.outPath = outPath;
	media.resourceLoader = resLoader;
    
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
  
  uint32_t pixel[4];
  
  // First frame is all black pixels
  
  [self getPixels32BPP:avLayerObj.image.CGImage
                offset:0
               nPixels:4
              pixelPtr:&pixel[0]];
  
  NSAssert(pixel[0] == ((0xFF << 24) | 0x0), @"pixel");  
  NSAssert(pixel[1] == ((0xFF << 24) | 0x0), @"pixel");  
  NSAssert(pixel[2] == ((0xFF << 24) | 0x0), @"pixel");  
  NSAssert(pixel[3] == ((0xFF << 24) | 0x0), @"pixel");
  
  // Double check that the contents field matches the core graphics image
  
  NSAssert(avLayerObj.image.CGImage != nil, @"CGImage is nil");
  NSAssert((id)avLayerObj.image.CGImage == viewLayer.contents, @"contents not set");
  
  // Second frame is all blue pixels
  
  UIImage *frameBefore = avLayerObj.image;
  
  [media showFrame:1];
  
  UIImage *frameAfter = avLayerObj.image;
  
  NSAssert(frameAfter != nil, @"image");
  NSAssert(frameBefore != frameAfter, @"image");
  
  [self getPixels32BPP:avLayerObj.image.CGImage
                offset:0
               nPixels:4
              pixelPtr:&pixel[0]];
  
  NSAssert(pixel[0] == ((0xFF << 24) | 0xFF), @"pixel");  
  NSAssert(pixel[1] == ((0xFF << 24) | 0xFF), @"pixel");  
  NSAssert(pixel[2] == ((0xFF << 24) | 0xFF), @"pixel");  
  NSAssert(pixel[3] == ((0xFF << 24) | 0xFF), @"pixel");
  
  // Double check that the contents field matches the core graphics image
  
  NSAssert(avLayerObj.image.CGImage != nil, @"CGImage is nil");
  NSAssert((id)avLayerObj.image.CGImage == viewLayer.contents, @"contents not set");  
  
  return;
}

// Decompress and convert a .apng file in a 7zip archive. This approach offers
// the maximum compression for animations that have simmilar data from one frame
// to the next. This approach also offert the maximum performance because it
// uses zero copy keyframes only. The only downside is that the generated .mvid
// files are very large.

+ (void) test7zApngBlackBlue2x2_24BPP
{
	id appDelegate = [[UIApplication sharedApplication] delegate];	
	UIWindow *window = [appDelegate window];
	NSAssert(window, @"window");
  
  NSString *archiveFilename = @"2x2_black_blue_24BPP_opt_nc.apng.7z";
  NSString *entryFilename = @"2x2_black_blue_24BPP_opt_nc.apng";
  NSString *outFilename = @"2x2_black_blue_24BPP_opt_nc.mvid";
  NSString *outPath = [AVFileUtil getTmpDirPath:outFilename];
  
  // If the converted mov path exists currently, delete it so that this test case always converts.
  
  if ([AVFileUtil fileExists:outPath]) {
    BOOL worked = [[NSFileManager defaultManager] removeItemAtPath:outPath error:nil];
    NSAssert(worked, @"could not remove existing file with same name as tmp dir");
  }
  
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
  
  AV7zApng2MvidResourceLoader *resLoader = [AV7zApng2MvidResourceLoader aV7zApng2MvidResourceLoader];
  resLoader.archiveFilename = archiveFilename;
  resLoader.movieFilename = entryFilename;
  resLoader.outPath = outPath;
	media.resourceLoader = resLoader;
  
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
  
  uint32_t pixel[4];
  
  // First frame is all black pixels
  
  [self getPixels32BPP:avLayerObj.image.CGImage
                offset:0
               nPixels:4
              pixelPtr:&pixel[0]];
  
  NSAssert(pixel[0] == ((0xFF << 24) | 0x0), @"pixel");  
  NSAssert(pixel[1] == ((0xFF << 24) | 0x0), @"pixel");  
  NSAssert(pixel[2] == ((0xFF << 24) | 0x0), @"pixel");  
  NSAssert(pixel[3] == ((0xFF << 24) | 0x0), @"pixel");
  
  // Double check that the contents field matches the core graphics image
  
  NSAssert(avLayerObj.image.CGImage != nil, @"CGImage is nil");
  NSAssert((id)avLayerObj.image.CGImage == viewLayer.contents, @"contents not set");
  
  // Second frame is all blue pixels
  
  UIImage *frameBefore = avLayerObj.image;
  
  [media showFrame:1];
  
  UIImage *frameAfter = avLayerObj.image;
  
  NSAssert(frameAfter != nil, @"image");
  NSAssert(frameBefore != frameAfter, @"image");
  
  [self getPixels32BPP:avLayerObj.image.CGImage
                offset:0
               nPixels:4
              pixelPtr:&pixel[0]];
  
  NSAssert(pixel[0] == ((0xFF << 24) | 0xFF), @"pixel");  
  NSAssert(pixel[1] == ((0xFF << 24) | 0xFF), @"pixel");  
  NSAssert(pixel[2] == ((0xFF << 24) | 0xFF), @"pixel");  
  NSAssert(pixel[3] == ((0xFF << 24) | 0xFF), @"pixel");
  
  // Double check that the contents field matches the core graphics image
  
  NSAssert(avLayerObj.image.CGImage != nil, @"CGImage is nil");
  NSAssert((id)avLayerObj.image.CGImage == viewLayer.contents, @"contents not set");  
  
  return;
}

// Convert an APNG that contains 32 bit pixels with an alpha channel.
// This animation contains 2 frame, the first is all black. The
// second frame is all transparent pixels.

+ (void) testApng2x2AlphaReveal_32BPP
{
	id appDelegate = [[UIApplication sharedApplication] delegate];	
	UIWindow *window = [appDelegate window];
	NSAssert(window, @"window");  
  
  NSString *resFilename = @"2x2_alpha_reveal_32BPP.apng";
  NSString *outFilename = @"2x2_alpha_reveal_32BPP.mvid";
  NSString *outPath = [AVFileUtil getTmpDirPath:outFilename];
  
  // If the converted mov path exists currently, delete it so that this test case always converts.
  
  if ([AVFileUtil fileExists:outPath]) {
    BOOL worked = [[NSFileManager defaultManager] removeItemAtPath:outPath error:nil];
    NSAssert(worked, @"could not remove existing file with same name as tmp dir");
  }
  
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
  
  AVApng2MvidResourceLoader *resLoader = [AVApng2MvidResourceLoader aVApng2MvidResourceLoader];
  resLoader.movieFilename = resFilename;
  resLoader.outPath = outPath;
	media.resourceLoader = resLoader;
  
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
  
  // The mvid file should have the 32BPP flag set
  
  NSAssert([frameDecoder hasAlphaChannel] == TRUE, @"hasAlphaChannel");
  
  NSAssert(media.currentFrame == 0, @"currentFrame");
  
  NSAssert(avLayerObj.image != nil, @"image");
  
  NSAssert(media.prevFrame == nil, @"prev frame not set properly");
  
  uint32_t pixel[4];
  
  // First frame is all black pixels
  
  [self getPixels32BPP:avLayerObj.image.CGImage
                offset:0
               nPixels:4
              pixelPtr:&pixel[0]];
  
  NSAssert(pixel[0] == ((0xFF << 24) | 0x0), @"pixel");  
  NSAssert(pixel[1] == ((0xFF << 24) | 0x0), @"pixel");  
  NSAssert(pixel[2] == ((0xFF << 24) | 0x0), @"pixel");  
  NSAssert(pixel[3] == ((0xFF << 24) | 0x0), @"pixel");
  
  // Double check that the contents field matches the core graphics image
  
  NSAssert(avLayerObj.image.CGImage != nil, @"CGImage is nil");
  NSAssert((id)avLayerObj.image.CGImage == viewLayer.contents, @"contents not set");
  
  // Second frame is all transparent pixels
  
  UIImage *frameBefore = avLayerObj.image;
  
  [media showFrame:1];
  
  UIImage *frameAfter = avLayerObj.image;
  
  NSAssert(frameAfter != nil, @"image");
  NSAssert(frameBefore != frameAfter, @"image");
  
  [self getPixels32BPP:avLayerObj.image.CGImage
                offset:0
               nPixels:4
              pixelPtr:&pixel[0]];
  
  NSAssert(pixel[0] == 0, @"pixel");  
  NSAssert(pixel[1] == 0, @"pixel");  
  NSAssert(pixel[2] == 0, @"pixel");  
  NSAssert(pixel[3] == 0, @"pixel");
  
  // Double check that the contents field matches the core graphics image
  
  NSAssert(avLayerObj.image.CGImage != nil, @"CGImage is nil");
  NSAssert((id)avLayerObj.image.CGImage == viewLayer.contents, @"contents not set");  
  
  return;
}

// Same alpha reveal test as above, but this time the pixels are stored
// in a 256 palette with transparent pixels in the palette. This logic
// test the png8 parsing logic, as well as logic in the translation to
// mvid format which checks for 32BPP pixels. In this case, the transparent
// pixels are not discovered until the second frame, so the initial frame
// is seen as 24BPP, but the mvid header is written as 32BPP after all
// frames have been processed.

+ (void) testApng2x2AlphaReveal_Palette
{
	id appDelegate = [[UIApplication sharedApplication] delegate];	
	UIWindow *window = [appDelegate window];
	NSAssert(window, @"window");  
  
  NSString *resFilename = @"2x2_alpha_reveal_palette.apng";
  NSString *outFilename = @"2x2_alpha_reveal_palette.mvid";
  NSString *outPath = [AVFileUtil getTmpDirPath:outFilename];
  
  // If the converted mov path exists currently, delete it so that this test case always converts.
  
  if ([AVFileUtil fileExists:outPath]) {
    BOOL worked = [[NSFileManager defaultManager] removeItemAtPath:outPath error:nil];
    NSAssert(worked, @"could not remove existing file with same name as tmp dir");
  }
  
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
  
  AVApng2MvidResourceLoader *resLoader = [AVApng2MvidResourceLoader aVApng2MvidResourceLoader];
  resLoader.movieFilename = resFilename;
  resLoader.outPath = outPath;
	media.resourceLoader = resLoader;
  
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
  
  // The mvid file should have the 32BPP flag set
  
  NSAssert([frameDecoder hasAlphaChannel] == TRUE, @"hasAlphaChannel");
  
  NSAssert(media.currentFrame == 0, @"currentFrame");
  
  NSAssert(avLayerObj.image != nil, @"image");
  
  NSAssert(media.prevFrame == nil, @"prev frame not set properly");
  
  uint32_t pixel[4];
  
  // First frame is all black pixels
  
  [self getPixels32BPP:avLayerObj.image.CGImage
                offset:0
               nPixels:4
              pixelPtr:&pixel[0]];
  
  NSAssert(pixel[0] == ((0xFF << 24) | 0x0), @"pixel");  
  NSAssert(pixel[1] == ((0xFF << 24) | 0x0), @"pixel");  
  NSAssert(pixel[2] == ((0xFF << 24) | 0x0), @"pixel");  
  NSAssert(pixel[3] == ((0xFF << 24) | 0x0), @"pixel");
  
  // Double check that the contents field matches the core graphics image
  
  NSAssert(avLayerObj.image.CGImage != nil, @"CGImage is nil");
  NSAssert((id)avLayerObj.image.CGImage == viewLayer.contents, @"contents not set");
  
  // Second frame is all transparent pixels
  
  UIImage *frameBefore = avLayerObj.image;
  
  [media showFrame:1];
  
  UIImage *frameAfter = avLayerObj.image;
  
  NSAssert(frameAfter != nil, @"image");
  NSAssert(frameBefore != frameAfter, @"image");
  
  [self getPixels32BPP:avLayerObj.image.CGImage
                offset:0
               nPixels:4
              pixelPtr:&pixel[0]];
  
  NSAssert(pixel[0] == 0, @"pixel");  
  NSAssert(pixel[1] == 0, @"pixel");  
  NSAssert(pixel[2] == 0, @"pixel");  
  NSAssert(pixel[3] == 0, @"pixel");
  
  // Double check that the contents field matches the core graphics image
  
  NSAssert(avLayerObj.image.CGImage != nil, @"CGImage is nil");
  NSAssert((id)avLayerObj.image.CGImage == viewLayer.contents, @"contents not set");  
  
  return;
}

// This test case reads an APNG that makes use of a palette that has no alpha.
// The second frame contains a delta that writes over the second row of black
// pixels with blue. This test case checks the optimized delta frames are being
// processed correctly by the libapng logic. A minimal delta will typically use
// alpha table values, but the actual generated image does not make use of
// an alpha channel. By checking that the generated .mvid file uses 24BPP pixels,
// this test verifies that the 24 vs 32 BPP pixel detection logic is working properly.

+ (void) testApng2x2BlackBlue1LD_Palette
{
	id appDelegate = [[UIApplication sharedApplication] delegate];	
	UIWindow *window = [appDelegate window];
	NSAssert(window, @"window");  
  
  NSString *resFilename = @"2x2_black_blue_1LD_opt.apng";
  NSString *outFilename = @"2x2_black_blue_1LD_opt.mvid";
  NSString *outPath = [AVFileUtil getTmpDirPath:outFilename];
  
  // If the converted mov path exists currently, delete it so that this test case always converts.
  
  if ([AVFileUtil fileExists:outPath]) {
    BOOL worked = [[NSFileManager defaultManager] removeItemAtPath:outPath error:nil];
    NSAssert(worked, @"could not remove existing file with same name as tmp dir");
  }
  
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
  
  AVApng2MvidResourceLoader *resLoader = [AVApng2MvidResourceLoader aVApng2MvidResourceLoader];
  resLoader.movieFilename = resFilename;
  resLoader.outPath = outPath;
	media.resourceLoader = resLoader;
  
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
  
  // The mvid file should have the 24BPP flag set
  
  NSAssert([frameDecoder hasAlphaChannel] == FALSE, @"hasAlphaChannel");
  
  NSAssert(media.currentFrame == 0, @"currentFrame");
  
  NSAssert(avLayerObj.image != nil, @"image");
  
  NSAssert(media.prevFrame == nil, @"prev frame not set properly");
  
  uint32_t pixel[4];
  
  // First frame is all black pixels
  
  [self getPixels32BPP:avLayerObj.image.CGImage
                offset:0
               nPixels:4
              pixelPtr:&pixel[0]];
  
  NSAssert(pixel[0] == ((0xFF << 24) | 0x0), @"pixel");  
  NSAssert(pixel[1] == ((0xFF << 24) | 0x0), @"pixel");  
  NSAssert(pixel[2] == ((0xFF << 24) | 0x0), @"pixel");  
  NSAssert(pixel[3] == ((0xFF << 24) | 0x0), @"pixel");
  
  // Double check that the contents field matches the core graphics image
  
  NSAssert(avLayerObj.image.CGImage != nil, @"CGImage is nil");
  NSAssert((id)avLayerObj.image.CGImage == viewLayer.contents, @"contents not set");
  
  // Second frame is all transparent pixels
  
  UIImage *frameBefore = avLayerObj.image;
  
  [media showFrame:1];
  
  UIImage *frameAfter = avLayerObj.image;
  
  NSAssert(frameAfter != nil, @"image");
  NSAssert(frameBefore != frameAfter, @"image");
  
  [self getPixels32BPP:avLayerObj.image.CGImage
                offset:0
               nPixels:4
              pixelPtr:&pixel[0]];
  
  NSAssert(pixel[0] == ((0xFF << 24) | 0x0), @"pixel");  
  NSAssert(pixel[1] == ((0xFF << 24) | 0x0), @"pixel");
  NSAssert(pixel[2] == ((0xFF << 24) | 0xFF), @"pixel");  
  NSAssert(pixel[3] == ((0xFF << 24) | 0xFF), @"pixel");
  
  // Double check that the contents field matches the core graphics image
  
  NSAssert(avLayerObj.image.CGImage != nil, @"CGImage is nil");
  NSAssert((id)avLayerObj.image.CGImage == viewLayer.contents, @"contents not set");  
  
  return;
}

// Test NOP frame detection in the APNG decoder. The second frame in this animation is a NOP.

+ (void) testNopFrameAPNG
{
	id appDelegate = [[UIApplication sharedApplication] delegate];	
	UIWindow *window = [appDelegate window];
	NSAssert(window, @"window");  
  
  NSString *resFilename = @"2x2_nop.apng";
  NSString *outFilename = @"2x2_nop.mvid";
  NSString *outPath = [AVFileUtil getTmpDirPath:outFilename];
  
  // If the converted mov path exists currently, delete it so that this test case always converts.
  
  if ([AVFileUtil fileExists:outPath]) {
    BOOL worked = [[NSFileManager defaultManager] removeItemAtPath:outPath error:nil];
    NSAssert(worked, @"could not remove existing file with same name as tmp dir");
  }
  
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
  
  AVApng2MvidResourceLoader *resLoader = [AVApng2MvidResourceLoader aVApng2MvidResourceLoader];
  resLoader.movieFilename = resFilename;
  resLoader.outPath = outPath;
	media.resourceLoader = resLoader;
  
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
  
  // The mvid file should have the 24BPP flag set
  
  NSAssert([frameDecoder hasAlphaChannel] == FALSE, @"hasAlphaChannel");
  
  NSAssert(media.currentFrame == 0, @"currentFrame");
  
  NSAssert(avLayerObj.image != nil, @"image");
  
  NSAssert(media.prevFrame == nil, @"prev frame not set properly");
  
  uint32_t pixel[4];
  
  // First frame is all black pixels
  
  [self getPixels32BPP:avLayerObj.image.CGImage
                offset:0
               nPixels:4
              pixelPtr:&pixel[0]];
  
  NSAssert(pixel[0] == ((0xFF << 24) | 0x0), @"pixel");  
  NSAssert(pixel[1] == ((0xFF << 24) | 0x0), @"pixel");  
  NSAssert(pixel[2] == ((0xFF << 24) | 0x0), @"pixel");  
  NSAssert(pixel[3] == ((0xFF << 24) | 0x0), @"pixel");
  
  // Double check that the contents field matches the core graphics image
  
  NSAssert(avLayerObj.image.CGImage != nil, @"CGImage is nil");
  NSAssert((id)avLayerObj.image.CGImage == viewLayer.contents, @"contents not set");
  
  // Second frame is all black pixels, advancing to the second
  // frame is a no-op since no pixels changed as compared to
  // the first frame.
  
  UIImage *imageBefore = avLayerObj.image;
  
  [media showFrame:1];
  
  UIImage *imageAfter = avLayerObj.image;
  
  NSAssert(imageBefore == imageAfter, @"advancing to 2nd frame changed the image");  
  
  // Third frame is all blue pixels
  
  UIImage *frameBefore = avLayerObj.image;
  
  [media showFrame:2];
  
  UIImage *frameAfter = avLayerObj.image;
  
  NSAssert(frameAfter != nil, @"image");
  NSAssert(frameBefore != frameAfter, @"image");
  
  [self getPixels32BPP:avLayerObj.image.CGImage
                offset:0
               nPixels:4
              pixelPtr:&pixel[0]];
  
  NSAssert(pixel[0] == ((0xFF << 24) | 0xFF), @"pixel");  
  NSAssert(pixel[1] == ((0xFF << 24) | 0xFF), @"pixel");
  NSAssert(pixel[2] == ((0xFF << 24) | 0xFF), @"pixel");  
  NSAssert(pixel[3] == ((0xFF << 24) | 0xFF), @"pixel");
  
  // Double check that the contents field matches the core graphics image
  
  NSAssert(avLayerObj.image.CGImage != nil, @"CGImage is nil");
  NSAssert((id)avLayerObj.image.CGImage == viewLayer.contents, @"contents not set");  
  
  return;
}

// Decompress example where all pixels of 480x320 frame are the same, first all black, then all blue.
// This basically checks to make sure that a run of 72 pages of pixels does not exceed 17 bit value limits.

+ (void) testDecodeFullScreenAllSame
{  
  NSString *archiveFilename = @"480x320_black_blue_16BPP.mov.7z";
  NSString *entryFilename = @"480x320_black_blue_16BPP.mov";
  NSString *outFilename = @"480x320_black_blue_16BPP.mvid";
  NSString *outPath = [AVFileUtil getTmpDirPath:outFilename];
  
  AV7zQT2MvidResourceLoader *resLoader = [AV7zQT2MvidResourceLoader aV7zQT2MvidResourceLoader];
  resLoader.archiveFilename = archiveFilename;
  resLoader.movieFilename = entryFilename;
  resLoader.outPath = outPath;
  
  // Make sure binary compare matches by forcing adler generation when debugging is off
  resLoader.alwaysGenerateAdler = TRUE;
  
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
  
  return;
}

// Decompress example like above, except that many pixels in the 480x320 buffer are the same, so
// a large skip value would be generated. This logic tests the 16 bit value range for skip
// num pixels in the .mov to .mvid convert logic.

+ (void) testDecodeFullScreenBigSkip
{  
  NSString *archiveFilename = @"480x320_black_blue_1LD_16BPP.mov.7z";
  NSString *entryFilename = @"480x320_black_blue_1LD_16BPP.mov";
  NSString *outFilename = @"480x320_black_blue_1LD_16BPP.mvid";
  NSString *outPath = [AVFileUtil getTmpDirPath:outFilename];
  
  AV7zQT2MvidResourceLoader *resLoader = [AV7zQT2MvidResourceLoader aV7zQT2MvidResourceLoader];
  resLoader.archiveFilename = archiveFilename;
  resLoader.movieFilename = entryFilename;
  resLoader.outPath = outPath;
  
  // Make sure binary compare matches by forcing adler generation when debugging is off
  resLoader.alwaysGenerateAdler = TRUE;
  
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
  
  return;
}

// This test case makes use of a pair of AV7zAppResourceLoader that both
// try to load the same resource. This represents a race condition because
// both loaders start out at the same time and the resource file does
// not exist at that time. The race condition will not actually cause
// a failure at runtime because an atomic write is used when saving the
// file, but it will result in non-optional runtime CPU and memory usage.
// Address this race condition by setting the serialLoading flag such
// that only one decode operation is done at a time. When executed
// with serialLoading, the second loading operation will be a no-op
// because it will test the isReady flag before kicking off a decode.

+ (void) testDecode7zCompareToResourceOneAtATime
{
  NSString *archiveFilename = @"2x2_black_blue_16BPP.mov.7z";
  NSString *entryFilename = @"2x2_black_blue_16BPP.mov";
  NSString *outPath = [AVFileUtil getTmpDirPath:entryFilename];
  
  AV7zAppResourceLoader *resLoader1 = [AV7zAppResourceLoader aV7zAppResourceLoader];
  resLoader1.archiveFilename = archiveFilename;
  resLoader1.movieFilename = entryFilename;
  resLoader1.outPath = outPath;
  resLoader1.serialLoading = TRUE;

  AV7zAppResourceLoader *resLoader2 = [AV7zAppResourceLoader aV7zAppResourceLoader];
  resLoader2.archiveFilename = archiveFilename;
  resLoader2.movieFilename = entryFilename;
  resLoader2.outPath = outPath;
  resLoader2.serialLoading = TRUE;
  
  // If the decode mov path exists currently, delete it so that this test case always
  // decodes the .mov from the .7z compressed Resource.
  
  if ([AVFileUtil fileExists:outPath]) {
    BOOL worked = [[NSFileManager defaultManager] removeItemAtPath:outPath error:nil];
    NSAssert(worked, @"could not remove existing file with same name as tmp dir");
  }
  
  // With the serial loading flag set, these two threads should execute one at a time
  // and the result is that only 1 since decode operation is done. The second loader
  // would attempt to load the same resource as the first loader, so that second
  // loading job can be skipped.
  
  [resLoader1 load];
  [resLoader2 load];
  
  BOOL worked = [RegressionTests waitUntilTrue:resLoader2
                                      selector:@selector(isReady)
                                   maxWaitTime:10.0];
  NSAssert(worked, @"worked");

  // Wait a couple of seconds so that we are sure both secondary threads have actually
  // stopped running. The isReady test returns TRUE as soon as the first serial loader
  // has finished writing.
  
  NSDate *maxDate = [NSDate dateWithTimeIntervalSinceNow:2.0];
  [[NSRunLoop currentRunLoop] runUntilDate:maxDate];
  
  NSAssert(resLoader1.isReady, @"isReady");
  NSAssert(resLoader2.isReady, @"isReady");
  
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

// This test case makes use of a pair of AV7zQT2MvidResourceLoader that both
// try to load the same resource. This represents a race condition because
// both loaders start out at the same time and the resource file does
// not exist at that time. The race condition will not actually cause
// a failure at runtime because an atomic write is used when saving the
// file, but it will result in non-optional runtime CPU and memory usage.
// Address this race condition by setting the serialLoading flag such
// that only one decode operation is done at a time. When executed
// with serialLoading, the second loading operation will be a no-op
// because it will test the isReady flag before kicking off a decode.

+ (void) testDecode7zMvidCompareToResourceOneAtATime
{  
  NSString *archiveFilename = @"2x2_black_blue_16BPP.mov.7z";
  NSString *entryFilename = @"2x2_black_blue_16BPP.mov";
  NSString *outFilename = @"2x2_black_blue_16BPP.mvid";
  NSString *outPath = [AVFileUtil getTmpDirPath:outFilename];
  
  AV7zQT2MvidResourceLoader *resLoader1 = [AV7zQT2MvidResourceLoader aV7zQT2MvidResourceLoader];
  resLoader1.archiveFilename = archiveFilename;
  resLoader1.movieFilename = entryFilename;
  resLoader1.outPath = outPath;
  // Make sure binary compare matches by forcing adler generation when debugging is off
  resLoader1.alwaysGenerateAdler = TRUE;
  
  resLoader1.serialLoading = TRUE;

  AV7zQT2MvidResourceLoader *resLoader2 = [AV7zQT2MvidResourceLoader aV7zQT2MvidResourceLoader];
  resLoader2.archiveFilename = archiveFilename;
  resLoader2.movieFilename = entryFilename;
  resLoader2.outPath = outPath;
  // Make sure binary compare matches by forcing adler generation when debugging is off
  resLoader2.alwaysGenerateAdler = TRUE;
  
  resLoader2.serialLoading = TRUE;
  
  // If the decode mov path exists currently, delete it so that this test case always
  // decodes the .mov from the .7z compressed Resource.
  
  if ([AVFileUtil fileExists:outPath]) {
    BOOL worked = [[NSFileManager defaultManager] removeItemAtPath:outPath error:nil];
    NSAssert(worked, @"could not remove existing file with same name as tmp dir");
  }  
  
  // With the serial loading flag set, these two threads should execute one at a time
  // and the result is that only 1 since decode operation is done. The second loader
  // would attempt to load the same resource as the first loader, so that second
  // loading job can be skipped.
  
  [resLoader1 load];
  [resLoader2 load];
  
  BOOL worked = [RegressionTests waitUntilTrue:resLoader2
                                      selector:@selector(isReady)
                                   maxWaitTime:10.0];
  NSAssert(worked, @"worked");  
  
  // Wait a couple of seconds so that we are sure both secondary threads have actually
  // stopped running. The isReady test returns TRUE as soon as the first serial loader
  // has finished writing.
  
  NSDate *maxDate = [NSDate dateWithTimeIntervalSinceNow:2.0];
  [[NSRunLoop currentRunLoop] runUntilDate:maxDate];
  
  NSAssert(resLoader1.isReady, @"isReady");
  NSAssert(resLoader2.isReady, @"isReady");
  
  if (1) {
    // Compare generated mvid file data to identical data attached as a project resource
    
    NSData *wroteMvidData = [NSData dataWithContentsOfMappedFile:outPath];
    NSAssert(wroteMvidData, @"could not map .mvid data");
    
    NSString *resPath = [AVFileUtil getResourcePath:outFilename];
    NSData *resMvidData = [NSData dataWithContentsOfMappedFile:resPath];
    NSAssert(resMvidData, @"could not map .mvid data");
    
    uint32_t resByteLength = [resMvidData length];
    uint32_t wroteByteLength = [wroteMvidData length];
    
    // Converted 2x2_black_blue_16BPP.mvid should be 12288 bytes
    
    BOOL sameLength = (resByteLength == wroteByteLength);
    NSAssert(sameLength, @"sameLength");
    BOOL same = [resMvidData isEqualToData:wroteMvidData];
    NSAssert(same, @"same");
    
    // Verify that the emitted .mvid file has a valid magic number
    
    char *mvidBytes = (char*) [wroteMvidData bytes];
    
    MVFileHeader *mvFileHeaderPtr = (MVFileHeader*) mvidBytes;
    
    assert(mvFileHeaderPtr->numFrames == 2);
  }
  
  return;
}

// This test case makes use of a pair of AVApng2MvidResourceLoader that both
// try to load the same resource. This represents a race condition because
// both loaders start out at the same time and the resource file does
// not exist at that time. The race condition will not actually cause
// a failure at runtime because an atomic write is used when saving the
// file, but it will result in non-optional runtime CPU and memory usage.
// Address this race condition by setting the serialLoading flag such
// that only one decode operation is done at a time. When executed
// with serialLoading, the second loading operation will be a no-op
// because it will test the isReady flag before kicking off a decode.

+ (void) testDecodeAPNG2MvidCompareToResourceOneAtATime
{
  NSString *resFilename = @"2x2_black_blue_24BPP.apng";
  NSString *outFilename = @"2x2_black_blue_24BPP.mvid";
  NSString *outPath = [AVFileUtil getTmpDirPath:outFilename];
  
  AVApng2MvidResourceLoader *resLoader1 = [AVApng2MvidResourceLoader aVApng2MvidResourceLoader];
  resLoader1.movieFilename = resFilename;
  resLoader1.outPath = outPath;
  // Make sure binary compare matches by forcing adler generation when debugging is off
  resLoader1.alwaysGenerateAdler = TRUE;
  
  resLoader1.serialLoading = TRUE;
  
  AVApng2MvidResourceLoader *resLoader2 = [AVApng2MvidResourceLoader aVApng2MvidResourceLoader];
  resLoader2.movieFilename = resFilename;
  resLoader2.outPath = outPath;
  // Make sure binary compare matches by forcing adler generation when debugging is off
  resLoader2.alwaysGenerateAdler = TRUE;
  
  resLoader2.serialLoading = TRUE;
  
  // If the decode mov path exists currently, delete it so that this test case always
  // writes a new file.
  
  if ([AVFileUtil fileExists:outPath]) {
    BOOL worked = [[NSFileManager defaultManager] removeItemAtPath:outPath error:nil];
    NSAssert(worked, @"could not remove existing file with same name as tmp dir");
  }  
  
  // With the serial loading flag set, these two threads should execute one at a time
  // and the result is that only 1 since decode operation is done. The second loader
  // would attempt to load the same resource as the first loader, so that second
  // loading job can be skipped.
  
  [resLoader1 load];
  [resLoader2 load];
  
  BOOL worked = [RegressionTests waitUntilTrue:resLoader2
                                      selector:@selector(isReady)
                                   maxWaitTime:10.0];
  NSAssert(worked, @"worked");  
  
  // Wait a couple of seconds so that we are sure both secondary threads have actually
  // stopped running. The isReady test returns TRUE as soon as the first serial loader
  // has finished writing.
  
  NSDate *maxDate = [NSDate dateWithTimeIntervalSinceNow:2.0];
  [[NSRunLoop currentRunLoop] runUntilDate:maxDate];
  
  NSAssert(resLoader1.isReady, @"isReady");
  NSAssert(resLoader2.isReady, @"isReady");
  
  if (1) {
    // Compare generated mvid file data to identical data attached as a project resource
    
    NSData *wroteMvidData = [NSData dataWithContentsOfMappedFile:outPath];
    NSAssert(wroteMvidData, @"could not map .mvid data");
    
    NSAssert([wroteMvidData length] == 12288, @"length mismatch");
    
    // Verify that the emitted .mvid file has a valid magic number
    
    char *mvidBytes = (char*) [wroteMvidData bytes];
    
    MVFileHeader *mvFileHeaderPtr = (MVFileHeader*) mvidBytes;
    
    assert(mvFileHeaderPtr->numFrames == 2);
  }
  
  return;
}

// This test case makes use of a pair of AV7zApng2MvidResourceLoader that both
// try to load the same resource. This represents a race condition because
// both loaders start out at the same time and the resource file does
// not exist at that time. The race condition will not actually cause
// a failure at runtime because an atomic write is used when saving the
// file, but it will result in non-optional runtime CPU and memory usage.
// Address this race condition by setting the serialLoading flag such
// that only one decode operation is done at a time. When executed
// with serialLoading, the second loading operation will be a no-op
// because it will test the isReady flag before kicking off a decode.

+ (void) testDecode7zAPNG2MvidCompareToResourceOneAtATime
{
  NSString *archiveFilename = @"2x2_black_blue_24BPP_opt_nc.apng.7z";
  NSString *entryFilename = @"2x2_black_blue_24BPP_opt_nc.apng";
  NSString *outFilename = @"2x2_black_blue_24BPP_opt_nc.mvid";
  NSString *outPath = [AVFileUtil getTmpDirPath:outFilename];
  
  AV7zApng2MvidResourceLoader *resLoader1 = [AV7zApng2MvidResourceLoader aV7zApng2MvidResourceLoader];
  resLoader1.archiveFilename = archiveFilename;
  resLoader1.movieFilename = entryFilename;
  resLoader1.outPath = outPath;

  // Make sure binary compare matches by forcing adler generation when debugging is off
  resLoader1.alwaysGenerateAdler = TRUE;
  
  resLoader1.serialLoading = TRUE;
  
  AV7zApng2MvidResourceLoader *resLoader2 = [AV7zApng2MvidResourceLoader aV7zApng2MvidResourceLoader];
  resLoader2.archiveFilename = archiveFilename;
  resLoader2.movieFilename = entryFilename;
  resLoader2.outPath = outPath;
  
  // Make sure binary compare matches by forcing adler generation when debugging is off
  resLoader2.alwaysGenerateAdler = TRUE;
  
  resLoader2.serialLoading = TRUE;
  
  // If the decode mov path exists currently, delete it so that this test case always
  // writes a new file.
  
  if ([AVFileUtil fileExists:outPath]) {
    BOOL worked = [[NSFileManager defaultManager] removeItemAtPath:outPath error:nil];
    NSAssert(worked, @"could not remove existing file with same name as tmp dir");
  }  
  
  // With the serial loading flag set, these two threads should execute one at a time
  // and the result is that only 1 since decode operation is done. The second loader
  // would attempt to load the same resource as the first loader, so that second
  // loading job can be skipped.
  
  [resLoader1 load];
  [resLoader2 load];
  
  BOOL worked = [RegressionTests waitUntilTrue:resLoader2
                                      selector:@selector(isReady)
                                   maxWaitTime:10.0];
  NSAssert(worked, @"worked");  
  
  // Wait a couple of seconds so that we are sure both secondary threads have actually
  // stopped running. The isReady test returns TRUE as soon as the first serial loader
  // has finished writing.
  
  NSDate *maxDate = [NSDate dateWithTimeIntervalSinceNow:2.0];
  [[NSRunLoop currentRunLoop] runUntilDate:maxDate];
  
  NSAssert(resLoader1.isReady, @"isReady");
  NSAssert(resLoader2.isReady, @"isReady");
  
  if (1) {
    // Compare generated mvid file data to identical data attached as a project resource
    
    NSData *wroteMvidData = [NSData dataWithContentsOfMappedFile:outPath];
    NSAssert(wroteMvidData, @"could not map .mvid data");
    
    NSAssert([wroteMvidData length] == 12288, @"length mismatch");
    
    // Verify that the emitted .mvid file has a valid magic number
    
    char *mvidBytes = (char*) [wroteMvidData bytes];
    
    MVFileHeader *mvFileHeaderPtr = (MVFileHeader*) mvidBytes;
    
    assert(mvFileHeaderPtr->numFrames == 2);
  }
  
  return;
}

// This test case deals with decoding H.264 video as an MVID
// Available in iOS 4.1 and later.

#if defined(HAS_AVASSET_READER_CONVERT_MAXVID)

// Read video data from a single track (only one video track is supported anyway)

+ (void) testDecodeH264WithTrackReader
{
  NSString *resourceName = @"32x32_black_blue_h264.mov";
  NSString *resPath = [AVFileUtil getResourcePath:resourceName];
  NSURL *fileURL = [NSURL fileURLWithPath:resPath];
  
  NSString *tmpFilename = @"32x32_black_blue_h264.mvid";
  NSString *tmpPath = [AVFileUtil getTmpDirPath:tmpFilename];
  
  AVAssetReaderConvertMaxvid *obj = [AVAssetReaderConvertMaxvid aVAssetReaderConvertMaxvid];
  obj.assetURL = fileURL;
  obj.mvidPath = tmpPath;
  
  BOOL worked = [obj decodeAssetURL];
  NSAssert(worked, @"decodeAssetURL");
  
  if (TRUE) {
    NSData *wroteMvidData = [NSData dataWithContentsOfMappedFile:tmpPath];
    NSAssert(wroteMvidData, @"could not map .mvid data");
    
    NSAssert([wroteMvidData length] == 20480, @"length mismatch");
    
    // Verify that the emitted .mvid file has a valid magic number
    
    char *mvidBytes = (char*) [wroteMvidData bytes];
    
    MVFileHeader *mvFileHeaderPtr = (MVFileHeader*) mvidBytes;
    
    assert(mvFileHeaderPtr->numFrames == 2);
  }
  
  return;
}

#endif // HAS_AVASSET_READER_CONVERT_MAXVID

@end
