//
//  AVResourceLoaderTests.m
//
//  Created by Moses DeJong on 4/22/11.
//
//  License terms defined in License.txt.

#import "RegressionTests.h"

#import "AVAnimatorLayer.h"
#include "AVAnimatorLayerPrivate.h"

#import "AVAnimatorMedia.h"
#import "AVAnimatorMediaPrivate.h"

#import "AVAppResourceLoader.h"

#import "AV7zAppResourceLoader.h"

#import "AVApng2MvidResourceLoader.h"
#import "AV7zApng2MvidResourceLoader.h"

#import "AVMvidFrameDecoder.h"

#import "AVFileUtil.h"

#import "AVAsset2MvidResourceLoader.h"

#import "AVGIF89A2MvidResourceLoader.h"

#import "AVFrame.h"

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

// Decompress .mvid.7z app resource to .mov in temp file and open.
// Then extract image data to make sure extraction was successful.

+ (void) test7zBlackBlue2x2_16BPP
{
	id appDelegate = [[UIApplication sharedApplication] delegate];	
	UIWindow *window = [appDelegate window];
	NSAssert(window, @"window");  
  
  NSString *archiveFilename = @"2x2_black_blue_16BPP.mvid.7z";
  NSString *entryFilename = @"2x2_black_blue_16BPP.mvid";  
  NSString *outPath = [AVFileUtil getTmpDirPath:entryFilename];
  
  // Create a plain AVAnimatorLayer without a movie controls and display
  // in portrait mode. This setup involves no containing views and
  // has no transforms applied to the AVAnimatorLayer.
  
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
  
  AVFrame *frameObj = avLayerObj.AVFrame;
  
  NSAssert(frameObj != nil, @"frame");
  NSAssert(frameObj.image != nil, @"image");
  
  NSAssert(media.prevFrame == nil, @"prev frame not set properly");
  
  // Double check that the contents field matches the core graphics image
  
  NSAssert(frameObj.image.CGImage != nil, @"CGImage is nil");
  NSAssert((id)frameObj.image.CGImage == viewLayer.contents, @"contents not set");
  
  return;
}

// Use AV7zAppResourceLoader class to decompress .mov.7z to .mov and compare
// the results to a known good result, also attached as a resource.

+ (void) testDecode7zCompareToResource
{
  NSString *archiveFilename = @"2x2_black_blue_16BPP.mvid.7z";
  NSString *entryFilename = @"2x2_black_blue_16BPP.mvid";
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
    
    uint32_t resByteLength = (uint32_t) [resMvidData length];
    uint32_t wroteByteLength = (uint32_t) [wroteMvidData length];
    
    // Extracted 2x2_black_blue_16BPP.mvid Size should be 12288 bytes
    
    BOOL sameLength = (resByteLength == wroteByteLength);
    NSAssert(sameLength, @"sameLength");
    BOOL same = [resMvidData isEqualToData:wroteMvidData];
    NSAssert(same, @"same");
  }
  
  return;
}

// Decompress a .mvid.7z file and convert the extracted .mvid to
// a known .mvid attached to the resources.

+ (void) testDecode7zMvidCompareToResource
{  
  NSString *archiveFilename = @"2x2_black_blue_16BPP.mvid.7z";
  NSString *entryFilename = @"2x2_black_blue_16BPP.mvid";
  NSString *outFilename = @"2x2_black_blue_16BPP.mvid";
  NSString *outPath = [AVFileUtil getTmpDirPath:outFilename];

  AV7zAppResourceLoader *resLoader = [AV7zAppResourceLoader aV7zAppResourceLoader];
  resLoader.archiveFilename = archiveFilename;
  resLoader.movieFilename = entryFilename;
  resLoader.outPath = outPath;

  // Make sure binary compare matches by forcing adler generation when debugging is off
  //resLoader.alwaysGenerateAdler = TRUE;
  
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
    
    uint32_t resByteLength   = (uint32_t) [resMvidData length];
    uint32_t wroteByteLength = (uint32_t) [wroteMvidData length];
    
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

// Decompress .mvid from .7z archive and then examine the pixel
// contents of the movie frames.

+ (void) test7zMvidBlackBlue2x2_16BPP
{
	id appDelegate = [[UIApplication sharedApplication] delegate];	
	UIWindow *window = [appDelegate window];
	NSAssert(window, @"window");  
  
  NSString *archiveFilename = @"2x2_black_blue_16BPP.mvid.7z";
  NSString *entryFilename = @"2x2_black_blue_16BPP.mvid";
  NSString *outFilename = @"2x2_black_blue_16BPP.mvid";
  
  NSString *outPath = [AVFileUtil getTmpDirPath:outFilename];
  
  // Create a plain AVAnimatorLayer without a movie controls and display
  // in portrait mode. This setup involves no containing views and
  // has no transforms applied to the AVAnimatorLayer.
  
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
  
  NSAssert(media.prevFrame == nil, @"prev frame not set properly");
  
  uint16_t pixel[4];
  
  AVFrame *frameObj = avLayerObj.AVFrame;
  
  NSAssert(frameObj.image != nil, @"image");
  
  // First frame is all black pixels
  
  [self getPixels16BPP:frameObj.image.CGImage
                offset:0
               nPixels:4
              pixelPtr:&pixel[0]];
  
  NSAssert(pixel[0] == 0x0, @"pixel");  
  NSAssert(pixel[1] == 0x0, @"pixel");  
  NSAssert(pixel[2] == 0x0, @"pixel");
  NSAssert(pixel[3] == 0x0, @"pixel");
  
  // Double check that the contents field matches the core graphics image
  
  NSAssert(frameObj.image.CGImage != nil, @"CGImage is nil");
  NSAssert((id)frameObj.image.CGImage == viewLayer.contents, @"contents not set");
  
  // Second frame is all blue pixels
  
  UIImage *frameBeforeImage = frameObj.image;
  
  [media showFrame:1];

  frameObj = avLayerObj.AVFrame;
  
  UIImage *frameAfterImage = frameObj.image;
  
  NSAssert(frameAfterImage != nil, @"frameAfterImage");
  NSAssert(frameBeforeImage != frameAfterImage, @"frameBeforeImage != frameAfterImage");
  
  [self getPixels16BPP:frameObj.image.CGImage
                offset:0
               nPixels:4
              pixelPtr:&pixel[0]];
  
  NSAssert(pixel[0] == 0x1F, @"pixel");  
  NSAssert(pixel[1] == 0x1F, @"pixel");  
  NSAssert(pixel[2] == 0x1F, @"pixel");  
  NSAssert(pixel[3] == 0x1F, @"pixel");
  
  // Double check that the contents field matches the core graphics image
  
  NSAssert(frameObj.image.CGImage != nil, @"CGImage is nil");
  NSAssert((id)frameObj.image.CGImage == viewLayer.contents, @"contents not set");  
  
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

  // Create a plain AVAnimatorLayer without a movie controls and display
  // in portrait mode. This setup involves no containing views and
  // has no transforms applied to the AVAnimatorLayer.
  
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
  
  NSAssert(media.prevFrame == nil, @"prev frame not set properly");
  
  uint32_t pixel[4];
  
  // First frame is all black pixels
  
  AVFrame *frameObj = avLayerObj.AVFrame;
  NSAssert(frameObj != nil, @"frame");
  NSAssert(frameObj.image != nil, @"image");
  
  [self getPixels32BPP:frameObj.image.CGImage
                offset:0
               nPixels:4
              pixelPtr:&pixel[0]];
  
  NSAssert(pixel[0] == ((0xFF << 24) | 0x0), @"pixel");  
  NSAssert(pixel[1] == ((0xFF << 24) | 0x0), @"pixel");  
  NSAssert(pixel[2] == ((0xFF << 24) | 0x0), @"pixel");  
  NSAssert(pixel[3] == ((0xFF << 24) | 0x0), @"pixel");
  
  // Double check that the contents field matches the core graphics image
  
  NSAssert(frameObj.image.CGImage != nil, @"CGImage is nil");
  NSAssert((id)frameObj.image.CGImage == viewLayer.contents, @"contents not set");
  
  // Second frame is all blue pixels
  
  UIImage *frameBeforeImage = frameObj.image;
  
  [media showFrame:1];

  frameObj = avLayerObj.AVFrame;
  UIImage *frameAfterImage = frameObj.image;
  
  NSAssert(frameAfterImage != nil, @"image");
  NSAssert(frameBeforeImage != frameAfterImage, @"image");
  
  [self getPixels32BPP:frameObj.image.CGImage
                offset:0
               nPixels:4
              pixelPtr:&pixel[0]];
  
  NSAssert(pixel[0] == ((0xFF << 24) | 0xFF), @"pixel");  
  NSAssert(pixel[1] == ((0xFF << 24) | 0xFF), @"pixel");  
  NSAssert(pixel[2] == ((0xFF << 24) | 0xFF), @"pixel");  
  NSAssert(pixel[3] == ((0xFF << 24) | 0xFF), @"pixel");
  
  // Double check that the contents field matches the core graphics image
  
  NSAssert(frameObj.image.CGImage != nil, @"CGImage is nil");
  NSAssert((id)frameObj.image.CGImage == viewLayer.contents, @"contents not set");
  
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
  
  // Create a plain AVAnimatorLayer without a movie controls and display
  // in portrait mode. This setup involves no containing views and
  // has no transforms applied to the AVAnimatorLayer.
  
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
  
  NSAssert(media.prevFrame == nil, @"prev frame not set properly");
  
  uint32_t pixel[4];
  
  // First frame is all black pixels
  
  AVFrame *frameObj = avLayerObj.AVFrame;
  
  NSAssert(frameObj.image != nil, @"image");
  
  [self getPixels32BPP:frameObj.image.CGImage
                offset:0
               nPixels:4
              pixelPtr:&pixel[0]];
  
  NSAssert(pixel[0] == ((0xFF << 24) | 0x0), @"pixel");  
  NSAssert(pixel[1] == ((0xFF << 24) | 0x0), @"pixel");  
  NSAssert(pixel[2] == ((0xFF << 24) | 0x0), @"pixel");  
  NSAssert(pixel[3] == ((0xFF << 24) | 0x0), @"pixel");
  
  // Double check that the contents field matches the core graphics image
  
  NSAssert(frameObj.image.CGImage != nil, @"CGImage is nil");
  NSAssert((id)frameObj.image.CGImage == viewLayer.contents, @"contents not set");
  
  // Second frame is all blue pixels
  
  UIImage *frameBeforeImage = frameObj.image;
  
  [media showFrame:1];

  frameObj = avLayerObj.AVFrame;
  
  UIImage *frameAfterImage = frameObj.image;
  
  NSAssert(frameAfterImage != nil, @"image");
  NSAssert(frameBeforeImage != frameAfterImage, @"image");
  
  [self getPixels32BPP:frameObj.image.CGImage
                offset:0
               nPixels:4
              pixelPtr:&pixel[0]];
  
  NSAssert(pixel[0] == ((0xFF << 24) | 0xFF), @"pixel");  
  NSAssert(pixel[1] == ((0xFF << 24) | 0xFF), @"pixel");  
  NSAssert(pixel[2] == ((0xFF << 24) | 0xFF), @"pixel");  
  NSAssert(pixel[3] == ((0xFF << 24) | 0xFF), @"pixel");
  
  // Double check that the contents field matches the core graphics image
  
  NSAssert(frameObj.image.CGImage != nil, @"CGImage is nil");
  NSAssert((id)frameObj.image.CGImage == viewLayer.contents, @"contents not set");
  
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
  
  // Create a plain AVAnimatorLayer without a movie controls and display
  // in portrait mode. This setup involves no containing views and
  // has no transforms applied to the AVAnimatorLayer.
  
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
  
  NSAssert(media.prevFrame == nil, @"prev frame not set properly");
  
  uint32_t pixel[4];
  
  // First frame is all black pixels
  
  AVFrame *frameObj = avLayerObj.AVFrame;
  NSAssert(frameObj != nil, @"frame");
  NSAssert(frameObj.image != nil, @"image");
  
  [self getPixels32BPP:frameObj.image.CGImage
                offset:0
               nPixels:4
              pixelPtr:&pixel[0]];
  
  NSAssert(pixel[0] == ((0xFF << 24) | 0x0), @"pixel");  
  NSAssert(pixel[1] == ((0xFF << 24) | 0x0), @"pixel");  
  NSAssert(pixel[2] == ((0xFF << 24) | 0x0), @"pixel");  
  NSAssert(pixel[3] == ((0xFF << 24) | 0x0), @"pixel");
  
  // Double check that the contents field matches the core graphics image
  
  NSAssert(frameObj.image.CGImage != nil, @"CGImage is nil");
  NSAssert((id)frameObj.image.CGImage == viewLayer.contents, @"contents not set");
  
  // Second frame is all transparent pixels
  
  UIImage *frameBeforeImage = frameObj.image;
  
  [media showFrame:1];
  
  frameObj = avLayerObj.AVFrame;
  
  UIImage *frameAfterImage = frameObj.image;
  
  NSAssert(frameAfterImage != nil, @"image");
  NSAssert(frameBeforeImage != frameAfterImage, @"image");
  
  [self getPixels32BPP:frameObj.image.CGImage
                offset:0
               nPixels:4
              pixelPtr:&pixel[0]];
  
  NSAssert(pixel[0] == 0, @"pixel");  
  NSAssert(pixel[1] == 0, @"pixel");  
  NSAssert(pixel[2] == 0, @"pixel");  
  NSAssert(pixel[3] == 0, @"pixel");
  
  // Double check that the contents field matches the core graphics image
  
  NSAssert(frameObj.image.CGImage != nil, @"CGImage is nil");
  NSAssert((id)frameObj.image.CGImage == viewLayer.contents, @"contents not set");
  
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
  
  // Create a plain AVAnimatorLayer without a movie controls and display
  // in portrait mode. This setup involves no containing views and
  // has no transforms applied to the AVAnimatorLayer.
  
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
  
  NSAssert(media.prevFrame == nil, @"prev frame not set properly");
  
  uint32_t pixel[4];
  
  // First frame is all black pixels
  
  AVFrame *frameObj = avLayerObj.AVFrame;
  NSAssert(frameObj.image != nil, @"image");
  
  [self getPixels32BPP:frameObj.image.CGImage
                offset:0
               nPixels:4
              pixelPtr:&pixel[0]];
  
  NSAssert(pixel[0] == ((0xFF << 24) | 0x0), @"pixel");  
  NSAssert(pixel[1] == ((0xFF << 24) | 0x0), @"pixel");  
  NSAssert(pixel[2] == ((0xFF << 24) | 0x0), @"pixel");  
  NSAssert(pixel[3] == ((0xFF << 24) | 0x0), @"pixel");
  
  // Double check that the contents field matches the core graphics image
  
  NSAssert(frameObj.image.CGImage != nil, @"CGImage is nil");
  NSAssert((id)frameObj.image.CGImage == viewLayer.contents, @"contents not set");
  
  // Second frame is all transparent pixels
  
  UIImage *frameBeforeImage = frameObj.image;
  
  [media showFrame:1];
  
  frameObj = avLayerObj.AVFrame;
  UIImage *frameAfterImage = frameObj.image;
  
  NSAssert(frameAfterImage != nil, @"image");
  NSAssert(frameBeforeImage != frameAfterImage, @"image");
  
  [self getPixels32BPP:frameObj.image.CGImage
                offset:0
               nPixels:4
              pixelPtr:&pixel[0]];
  
  NSAssert(pixel[0] == 0, @"pixel");  
  NSAssert(pixel[1] == 0, @"pixel");  
  NSAssert(pixel[2] == 0, @"pixel");  
  NSAssert(pixel[3] == 0, @"pixel");
  
  // Double check that the contents field matches the core graphics image
  
  NSAssert(frameObj.image.CGImage != nil, @"CGImage is nil");
  NSAssert((id)frameObj.image.CGImage == viewLayer.contents, @"contents not set");
  
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
  
  // Create a plain AVAnimatorLayer without a movie controls and display
  // in portrait mode. This setup involves no containing views and
  // has no transforms applied to the AVAnimatorLayer.
  
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
  
  NSAssert(media.prevFrame == nil, @"prev frame not set properly");
  
  uint32_t pixel[4];
  
  // First frame is all black pixels
  
  AVFrame *frameObj = avLayerObj.AVFrame;
  
  NSAssert(frameObj.image != nil, @"image");
  
  [self getPixels32BPP:frameObj.image.CGImage
                offset:0
               nPixels:4
              pixelPtr:&pixel[0]];
  
  NSAssert(pixel[0] == ((0xFF << 24) | 0x0), @"pixel");  
  NSAssert(pixel[1] == ((0xFF << 24) | 0x0), @"pixel");  
  NSAssert(pixel[2] == ((0xFF << 24) | 0x0), @"pixel");  
  NSAssert(pixel[3] == ((0xFF << 24) | 0x0), @"pixel");
  
  // Double check that the contents field matches the core graphics image
  
  NSAssert(frameObj.image.CGImage != nil, @"CGImage is nil");
  NSAssert((id)frameObj.image.CGImage == viewLayer.contents, @"contents not set");
  
  // Second frame is all transparent pixels
  
  UIImage *frameBeforeImage = frameObj.image;
  
  [media showFrame:1];
  
  frameObj = avLayerObj.AVFrame;
  UIImage *frameAfterImage = frameObj.image;
  
  NSAssert(frameAfterImage != nil, @"image");
  NSAssert(frameBeforeImage != frameAfterImage, @"image");
  
  [self getPixels32BPP:frameObj.image.CGImage
                offset:0
               nPixels:4
              pixelPtr:&pixel[0]];
  
  NSAssert(pixel[0] == ((0xFF << 24) | 0x0), @"pixel");  
  NSAssert(pixel[1] == ((0xFF << 24) | 0x0), @"pixel");
  NSAssert(pixel[2] == ((0xFF << 24) | 0xFF), @"pixel");  
  NSAssert(pixel[3] == ((0xFF << 24) | 0xFF), @"pixel");
  
  // Double check that the contents field matches the core graphics image
  
  NSAssert(frameObj.image.CGImage != nil, @"CGImage is nil");
  NSAssert((id)frameObj.image.CGImage == viewLayer.contents, @"contents not set");
  
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
  
  // Create a plain AVAnimatorLayer without a movie controls and display
  // in portrait mode. This setup involves no containing views and
  // has no transforms applied to the AVAnimatorLayer.
  
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
  
  NSAssert(media.prevFrame == nil, @"prev frame not set properly");
  
  uint32_t pixel[4];
  
  // First frame is all black pixels

  AVFrame *frameObj = avLayerObj.AVFrame;
  NSAssert(frameObj.image != nil, @"image");
  
  [self getPixels32BPP:frameObj.image.CGImage
                offset:0
               nPixels:4
              pixelPtr:&pixel[0]];
  
  NSAssert(pixel[0] == ((0xFF << 24) | 0x0), @"pixel");  
  NSAssert(pixel[1] == ((0xFF << 24) | 0x0), @"pixel");  
  NSAssert(pixel[2] == ((0xFF << 24) | 0x0), @"pixel");  
  NSAssert(pixel[3] == ((0xFF << 24) | 0x0), @"pixel");
  
  // Double check that the contents field matches the core graphics image
  
  NSAssert(frameObj.image.CGImage != nil, @"CGImage is nil");
  NSAssert((id)frameObj.image.CGImage == viewLayer.contents, @"contents not set");
  
  // Second frame is all black pixels, advancing to the second
  // frame is a no-op since no pixels changed as compared to
  // the first frame.

  UIImage *imageBefore;
  UIImage *imageAfter;
  
  imageBefore = frameObj.image;
  
  [media showFrame:1];
  
  frameObj = avLayerObj.AVFrame;
  imageAfter = frameObj.image;
  
  NSAssert(imageBefore == imageAfter, @"advancing to 2nd frame changed the image");  
  
  // Third frame is all blue pixels
  
  frameObj = avLayerObj.AVFrame;
  imageBefore = frameObj.image;
  
  [media showFrame:2];
  
  frameObj = avLayerObj.AVFrame;
  imageAfter = frameObj.image;
  
  NSAssert(imageAfter != nil, @"image");
  NSAssert(imageBefore != imageAfter, @"image");
  
  [self getPixels32BPP:frameObj.image.CGImage
                offset:0
               nPixels:4
              pixelPtr:&pixel[0]];
  
  NSAssert(pixel[0] == ((0xFF << 24) | 0xFF), @"pixel");  
  NSAssert(pixel[1] == ((0xFF << 24) | 0xFF), @"pixel");
  NSAssert(pixel[2] == ((0xFF << 24) | 0xFF), @"pixel");  
  NSAssert(pixel[3] == ((0xFF << 24) | 0xFF), @"pixel");
  
  // Double check that the contents field matches the core graphics image
  
  NSAssert(frameObj.image.CGImage != nil, @"CGImage is nil");
  NSAssert((id)frameObj.image.CGImage == viewLayer.contents, @"contents not set");  
  
  return;
}

// Decompress example where all pixels of 480x320 frame are the same. This test just makes sure that
// .mvid.7z to .mvid decoding is working.

+ (void) testDecodeFullScreenAllSame
{  
  NSString *archiveFilename = @"480x320_black_blue_16BPP.mvid.7z";
  NSString *entryFilename = @"480x320_black_blue_16BPP.mvid";
  NSString *outFilename = @"480x320_black_blue_16BPP.mvid";
  NSString *outPath = [AVFileUtil getTmpDirPath:outFilename];
  
  AV7zAppResourceLoader *resLoader = [AV7zAppResourceLoader aV7zAppResourceLoader];
  resLoader.archiveFilename = archiveFilename;
  resLoader.movieFilename = entryFilename;
  resLoader.outPath = outPath;
  
  // Make sure binary compare matches by forcing adler generation when debugging is off
  //resLoader.alwaysGenerateAdler = TRUE;
  
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
// a large skip value is included in the movie data. Previously, this tested the .mov to .mvid
// decoding logic, but now this is just a decompression loader test.

+ (void) testDecodeFullScreenBigSkip
{  
  NSString *archiveFilename = @"480x320_black_blue_1LD_16BPP.mvid.7z";
  NSString *entryFilename = @"480x320_black_blue_1LD_16BPP.mvid";
  NSString *outFilename = @"480x320_black_blue_1LD_16BPP.mvid";
  NSString *outPath = [AVFileUtil getTmpDirPath:outFilename];
  
  AV7zAppResourceLoader *resLoader = [AV7zAppResourceLoader aV7zAppResourceLoader];
  resLoader.archiveFilename = archiveFilename;
  resLoader.movieFilename = entryFilename;
  resLoader.outPath = outPath;
  
  // FIXME: this test and the one above could be converted into a "flatten frames"
  // test where .mvid is decompressed and then made into a flat .mvid file at runtime.
  
  // Make sure binary compare matches by forcing adler generation when debugging is off
  //resLoader.alwaysGenerateAdler = TRUE;
  
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
  NSString *archiveFilename = @"2x2_black_blue_16BPP.mvid.7z";
  NSString *entryFilename = @"2x2_black_blue_16BPP.mvid";
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
    NSAssert(wroteMvidData, @"could not map .mvid data");
    
    NSString *resPath = [AVFileUtil getResourcePath:entryFilename];
    NSData *resMvidData = [NSData dataWithContentsOfMappedFile:resPath];
    NSAssert(resMvidData, @"could not map .mvid data");
    
    uint32_t resByteLength   = (uint32_t) [resMvidData length];
    uint32_t wroteByteLength = (uint32_t) [wroteMvidData length];
    
    // Extracted 2x2_black_blue_16BPP.mvid Size should be 8204 bytes
    
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
  NSString *archiveFilename = @"2x2_black_blue_16BPP.mvid.7z";
  NSString *entryFilename = @"2x2_black_blue_16BPP.mvid";
  NSString *outFilename = @"2x2_black_blue_16BPP.mvid";
  NSString *outPath = [AVFileUtil getTmpDirPath:outFilename];
  
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
    // Compare generated mvid file data to identical data attached as a project resource
    
    NSData *wroteMvidData = [NSData dataWithContentsOfMappedFile:outPath];
    NSAssert(wroteMvidData, @"could not map .mvid data");
    
    NSString *resPath = [AVFileUtil getResourcePath:outFilename];
    NSData *resMvidData = [NSData dataWithContentsOfMappedFile:resPath];
    NSAssert(resMvidData, @"could not map .mvid data");
    
    uint32_t resByteLength   = (uint32_t) [resMvidData length];
    uint32_t wroteByteLength = (uint32_t) [wroteMvidData length];
    
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

// Load 16BPP 3x3 MVID at version 0, this movie contains 3 frames

+ (void) testDecode3x3At16BPPMov2MvidCompareToResource
{
  NSString *resFilename = @"3x3_bwd_ANI_16BPP.mvid";

  AVAppResourceLoader *resLoader = [AVAppResourceLoader aVAppResourceLoader];
  resLoader.movieFilename = resFilename;
    
  [resLoader load];
  
  BOOL worked = [RegressionTests waitUntilTrue:resLoader
                                      selector:@selector(isReady)
                                   maxWaitTime:1000.0];
  NSAssert(worked, @"worked");
  
  if (1) {    
    // Verify that the emitted .mvid file has a valid magic number
    
    NSArray *resourcePathsArr = [resLoader getResources];
    NSAssert([resourcePathsArr count] == 1, @"expected 1 resource paths");
    NSString *videoPath = [resourcePathsArr objectAtIndex:0];
    
    NSData *wroteMvidData = [NSData dataWithContentsOfMappedFile:videoPath];
    
    char *mvidBytes = (char*) [wroteMvidData bytes];
    
    MVFileHeader *mvFileHeaderPtr = (MVFileHeader*) mvidBytes;

    assert(mvFileHeaderPtr->bpp == 16);
    assert(mvFileHeaderPtr->numFrames == 3);
  }
  
  return;
}

// Load 24BPP 3x3 MVID at version 0, this movie contains 3 frames

+ (void) testDecode3x3At24BPPMov2MvidCompareToResource
{
  NSString *resFilename = @"3x3_bwd_ANI_24BPP.mvid";
  
  AVAppResourceLoader *resLoader = [AVAppResourceLoader aVAppResourceLoader];
  resLoader.movieFilename = resFilename;
  
  [resLoader load];
  
  BOOL worked = [RegressionTests waitUntilTrue:resLoader
                                      selector:@selector(isReady)
                                   maxWaitTime:1000.0];
  NSAssert(worked, @"worked");
  
  if (1) {
    // Verify that the emitted .mvid file has a valid magic number
    
    NSArray *resourcePathsArr = [resLoader getResources];
    NSAssert([resourcePathsArr count] == 1, @"expected 1 resource paths");
    NSString *videoPath = [resourcePathsArr objectAtIndex:0];
    
    NSData *wroteMvidData = [NSData dataWithContentsOfMappedFile:videoPath];
    
    char *mvidBytes = (char*) [wroteMvidData bytes];
    
    MVFileHeader *mvFileHeaderPtr = (MVFileHeader*) mvidBytes;
    
    assert(mvFileHeaderPtr->bpp == 24);
    assert(mvFileHeaderPtr->numFrames == 3);
  }
  
  return;
}

#ifdef AVANIMATOR_HAS_IMAGEIO_FRAMEWORK

// Convert 24BPP GIF89A animation to .mvid

+ (void) testDecodeBeakerGIF89A
{
  NSString *resFilename = @"Beaker.gif";
  NSString *outFilename = @"Beaker.mvid";
  NSString *outPath = [AVFileUtil getTmpDirPath:outFilename];
  
  [[NSFileManager defaultManager] removeItemAtPath:outPath error:nil];
  
  AVGIF89A2MvidResourceLoader *resLoader = [AVGIF89A2MvidResourceLoader aVGIF89A2MvidResourceLoader];
  resLoader.movieFilename = resFilename;
  resLoader.outPath = outPath;
  
  [resLoader load];
  
  BOOL worked = [RegressionTests waitUntilTrue:resLoader
                                      selector:@selector(isReady)
                                   maxWaitTime:1000.0];
  NSAssert(worked, @"worked");
  
  if (1) {
    // Verify that the emitted .mvid file has a valid magic number
    // and check the parsed properties from the GIF header.
    
    NSArray *resourcePathsArr = [resLoader getResources];
    NSAssert([resourcePathsArr count] == 1, @"expected 1 resource paths");
    NSString *videoPath = [resourcePathsArr objectAtIndex:0];
    
    NSData *wroteMvidData = [NSData dataWithContentsOfMappedFile:videoPath];
    
    char *mvidBytes = (char*) [wroteMvidData bytes];
    
    MVFileHeader *mvFileHeaderPtr = (MVFileHeader*) mvidBytes;
    
    assert(mvFileHeaderPtr->bpp == 24);
    assert(mvFileHeaderPtr->numFrames == 10);
    assert(mvFileHeaderPtr->width == 400);
    assert(mvFileHeaderPtr->height == 225);
    assert(((int)(1.0 / mvFileHeaderPtr->frameDuration)) == 25);
  }
  
  return;
}

// Convert 32BPP GIF89A animation to .mvid

+ (void) testDecodeSuperwalkGIF89A
{
  NSString *resFilename = @"superwalk.gif";
  NSString *outFilename = @"superwalk.mvid";
  NSString *outPath = [AVFileUtil getTmpDirPath:outFilename];
  
  [[NSFileManager defaultManager] removeItemAtPath:outPath error:nil];
  
  AVGIF89A2MvidResourceLoader *resLoader = [AVGIF89A2MvidResourceLoader aVGIF89A2MvidResourceLoader];
  resLoader.movieFilename = resFilename;
  resLoader.outPath = outPath;
  
  [resLoader load];
  
  BOOL worked = [RegressionTests waitUntilTrue:resLoader
                                      selector:@selector(isReady)
                                   maxWaitTime:1000.0];
  NSAssert(worked, @"worked");
  
  if (1) {
    // Verify that the emitted .mvid file has a valid magic number
    // and check the parsed properties from the GIF header.
    
    NSArray *resourcePathsArr = [resLoader getResources];
    NSAssert([resourcePathsArr count] == 1, @"expected 1 resource paths");
    NSString *videoPath = [resourcePathsArr objectAtIndex:0];
    
    NSData *wroteMvidData = [NSData dataWithContentsOfMappedFile:videoPath];
    
    char *mvidBytes = (char*) [wroteMvidData bytes];
    
    MVFileHeader *mvFileHeaderPtr = (MVFileHeader*) mvidBytes;
    
    assert(mvFileHeaderPtr->bpp == 32);
    assert(mvFileHeaderPtr->numFrames == 6);
    assert(mvFileHeaderPtr->width == 86);
    assert(mvFileHeaderPtr->height == 114);
    assert(((int)(1.0 / mvFileHeaderPtr->frameDuration)) == 7);
  }
  
  return;
}

#endif // AVANIMATOR_HAS_IMAGEIO_FRAMEWORK

@end
