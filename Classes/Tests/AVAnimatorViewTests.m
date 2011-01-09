//
//  AVAnimatorViewTests.m
//  QTFileParserApp
//
//  Created by Moses DeJong on 1/8/11.
//

#import "RegressionTests.h"

#import "AVAnimatorView.h"
#include "AVAnimatorViewPrivate.h"

#import "AVAppResourceLoader.h"
#import "AVQTAnimationFrameDecoder.h"

@interface AVAnimatorViewTests : NSObject {}
@end

@implementation AVAnimatorViewTests

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

+ (void) test16BPP
{
	id appDelegate = [[UIApplication sharedApplication] delegate];	
	UIWindow *window = [appDelegate window];
	NSAssert(window, @"window");  
  
  NSString *resourceName = @"Bounce_16BPP_15FPS.mov";
  
  // Create a plain AVAnimatorView without a movie controls and display
  // in portrait mode. This setup involves no containing views and
  // has no transforms applied to the AVAnimatorView.
  
  CGRect frame = CGRectMake(0, 0, 480, 320);
  AVAnimatorView *animatorView = [AVAnimatorView aVAnimatorViewWithFrame:frame];  
  animatorView.animatorOrientation = UIImageOrientationLeft;
  
  // Create loader that will read a movie file from app resources.
  
	AVAppResourceLoader *resLoader = [AVAppResourceLoader aVAppResourceLoader];
  resLoader.movieFilename = resourceName;
	animatorView.resourceLoader = resLoader;
  
  // Create decoder that will generate frames from Quicktime Animation encoded data
  
  AVQTAnimationFrameDecoder *frameDecoder = [AVQTAnimationFrameDecoder aVQTAnimationFrameDecoder];
	animatorView.frameDecoder = frameDecoder;
  
  animatorView.animatorFrameDuration = 1.0;
  
  NSAssert(animatorView.renderSize.width == 0.0, @"renderSize.width");
  NSAssert(animatorView.renderSize.height == 0.0, @"renderSize.height");
  
  [window addSubview:animatorView];
  
  // Check that adding the animator to the window invoked loadViewImpl
  
  NSAssert(animatorView.renderSize.width == 480.0, @"renderSize.width");
  NSAssert(animatorView.renderSize.height == 320.0, @"renderSize.height");
  
  /*
   // No transform should be defined, but default transform depends on
   // the platform because iOS has a translate and negate transform by default.
   CATransform3D transform = animatorView.layer.transform;
   UIView *defaultView = [[[UIView alloc] initWithFrame:frame] autorelease];
   CATransform3D defaultTransform = defaultView.layer.transform;
   
   //  NSAssert(CATransform3DIsIdentity(transform), @"not identity transform");
   NSAssert(CATransform3DEqualToTransform(transform, defaultTransform), @"not default transform");
   */
  
  // Wait until initial keyframe of data is loaded.
  
  NSAssert(animatorView.isReadyToAnimate == FALSE, @"isReadyToAnimate");
  
  [animatorView prepareToAnimate];
  
  BOOL worked = [RegressionTests waitUntilTrue:animatorView
                                      selector:@selector(isReadyToAnimate)
                                   maxWaitTime:10.0];
  NSAssert(worked, @"worked");
  
  NSAssert(animatorView.state == READY, @"isReadyToAnimate");
  
  // At this point, initial keyframe should be displayed
  
  NSAssert(animatorView.currentFrame == 0, @"currentFrame");
  
  NSAssert(animatorView.image != nil, @"image");
  
  // Query pixel data at a specific pixel offset
  
  uint16_t pixel;
  
  [self getPixels16BPP:animatorView.image.CGImage
                offset:0
               nPixels:1
              pixelPtr:&pixel];
  
  NSAssert(pixel == 0x0, @"pixel");
  
  NSDate *maxDate = [NSDate dateWithTimeIntervalSinceNow:5.0];
  [[NSRunLoop currentRunLoop] runUntilDate:maxDate];
  
  return;
}

// Each test case method is invoked by the RegressionTests harness.

+ (void) test24BPP
{
	id appDelegate = [[UIApplication sharedApplication] delegate];	
	UIWindow *window = [appDelegate window];
	NSAssert(window, @"window");  
  
  NSString *resourceName = @"Bounce_24BPP_15FPS.mov";
  
  // Create a plain AVAnimatorView without a movie controls and display
  // in portrait mode. This setup involves no containing views and
  // has no transforms applied to the AVAnimatorView.
  
  CGRect frame = CGRectMake(0, 0, 480, 320);
  AVAnimatorView *animatorView = [AVAnimatorView aVAnimatorViewWithFrame:frame];  
  animatorView.animatorOrientation = UIImageOrientationLeft;
  
  // Create loader that will read a movie file from app resources.
  
	AVAppResourceLoader *resLoader = [AVAppResourceLoader aVAppResourceLoader];
  resLoader.movieFilename = resourceName;
	animatorView.resourceLoader = resLoader;
  
  // Create decoder that will generate frames from Quicktime Animation encoded data
  
  AVQTAnimationFrameDecoder *frameDecoder = [AVQTAnimationFrameDecoder aVQTAnimationFrameDecoder];
	animatorView.frameDecoder = frameDecoder;
  
  animatorView.animatorFrameDuration = 1.0;
  
  NSAssert(animatorView.renderSize.width == 0.0, @"renderSize.width");
  NSAssert(animatorView.renderSize.height == 0.0, @"renderSize.height");
  
  [window addSubview:animatorView];
    
  // Check that adding the animator to the window invoked loadViewImpl
  
  NSAssert(animatorView.renderSize.width == 480.0, @"renderSize.width");
  NSAssert(animatorView.renderSize.height == 320.0, @"renderSize.height");
  
  /*
  // No transform should be defined, but default transform depends on
  // the platform because iOS has a translate and negate transform by default.
  CATransform3D transform = animatorView.layer.transform;
  UIView *defaultView = [[[UIView alloc] initWithFrame:frame] autorelease];
  CATransform3D defaultTransform = defaultView.layer.transform;

//  NSAssert(CATransform3DIsIdentity(transform), @"not identity transform");
  NSAssert(CATransform3DEqualToTransform(transform, defaultTransform), @"not default transform");
  */
  
  // Wait until initial keyframe of data is loaded.

  NSAssert(animatorView.isReadyToAnimate == FALSE, @"isReadyToAnimate");
  
  [animatorView prepareToAnimate];
  
  BOOL worked = [RegressionTests waitUntilTrue:animatorView
                                      selector:@selector(isReadyToAnimate)
                                   maxWaitTime:10.0];
  NSAssert(worked, @"worked");
  
  NSAssert(animatorView.state == READY, @"isReadyToAnimate");
  
  // At this point, initial keyframe should be displayed

  NSAssert(animatorView.currentFrame == 0, @"currentFrame");

  NSAssert(animatorView.image != nil, @"image");
  
  // Query pixel data at a specific pixel offset
  
  uint32_t pixel;

  [self getPixels32BPP:animatorView.image.CGImage
                offset:0
               nPixels:1
              pixelPtr:&pixel];
  
  NSAssert(pixel == 0x0, @"pixel");
  
  NSDate *maxDate = [NSDate dateWithTimeIntervalSinceNow:5.0];
  [[NSRunLoop currentRunLoop] runUntilDate:maxDate];
  
  return;
}

+ (void) testBlackBlue2x2_16BPP
{
	id appDelegate = [[UIApplication sharedApplication] delegate];	
	UIWindow *window = [appDelegate window];
	NSAssert(window, @"window");  
  
  NSString *resourceName = @"2x2_black_blue_16BPP.mov";
  
  // Create a plain AVAnimatorView without a movie controls and display
  // in portrait mode. This setup involves no containing views and
  // has no transforms applied to the AVAnimatorView.
  
  CGRect frame = CGRectMake(0, 0, 2, 2);
  AVAnimatorView *animatorView = [AVAnimatorView aVAnimatorViewWithFrame:frame];  
  animatorView.animatorOrientation = UIImageOrientationLeft;
  
  // Create loader that will read a movie file from app resources.
  
	AVAppResourceLoader *resLoader = [AVAppResourceLoader aVAppResourceLoader];
  resLoader.movieFilename = resourceName;
	animatorView.resourceLoader = resLoader;
  
  // Create decoder that will generate frames from Quicktime Animation encoded data
  
  AVQTAnimationFrameDecoder *frameDecoder = [AVQTAnimationFrameDecoder aVQTAnimationFrameDecoder];
	animatorView.frameDecoder = frameDecoder;
  
  animatorView.animatorFrameDuration = 1.0;
  
  NSAssert(animatorView.renderSize.width == 0.0, @"renderSize.width");
  NSAssert(animatorView.renderSize.height == 0.0, @"renderSize.height");
  
  [window addSubview:animatorView];
  
  // Check that adding the animator to the window invoked loadViewImpl
  
  NSAssert(animatorView.renderSize.width == 2.0, @"renderSize.width");
  NSAssert(animatorView.renderSize.height == 2.0, @"renderSize.height");
    
  [animatorView prepareToAnimate];
  
  BOOL worked = [RegressionTests waitUntilTrue:animatorView
                                      selector:@selector(isReadyToAnimate)
                                   maxWaitTime:10.0];
  NSAssert(worked, @"worked");
  
  NSAssert(animatorView.state == READY, @"isReadyToAnimate");
  
  // At this point, initial keyframe should be displayed
  
  NSAssert([frameDecoder hasAlphaChannel] == FALSE, @"hasAlphaChannel");
  
  NSAssert(animatorView.currentFrame == 0, @"currentFrame");
  
  NSAssert(animatorView.image != nil, @"image");
  
  uint16_t pixel[4];

  // First frame is all black pixels
  
  [self getPixels16BPP:animatorView.image.CGImage
                offset:0
               nPixels:4
              pixelPtr:&pixel[0]];
  
  NSAssert(pixel[0] == 0x0, @"pixel");  
  NSAssert(pixel[1] == 0x0, @"pixel");  
  NSAssert(pixel[2] == 0x0, @"pixel");  
  NSAssert(pixel[3] == 0x0, @"pixel");
  
  // Second frame is all blue pixels
    
  [animatorView showFrame:1];

  [self getPixels16BPP:animatorView.image.CGImage
                offset:0
               nPixels:4
              pixelPtr:&pixel[0]];
  
  NSAssert(pixel[0] == 0x1F, @"pixel");  
  NSAssert(pixel[1] == 0x1F, @"pixel");  
  NSAssert(pixel[2] == 0x1F, @"pixel");  
  NSAssert(pixel[3] == 0x1F, @"pixel");  
  
  return;
}

+ (void) testBlackBlue2x2_24BPP
{
	id appDelegate = [[UIApplication sharedApplication] delegate];	
	UIWindow *window = [appDelegate window];
	NSAssert(window, @"window");  
  
  NSString *resourceName = @"2x2_black_blue_24BPP.mov";
  
  // Create a plain AVAnimatorView without a movie controls and display
  // in portrait mode. This setup involves no containing views and
  // has no transforms applied to the AVAnimatorView.
  
  CGRect frame = CGRectMake(0, 0, 2, 2);
  AVAnimatorView *animatorView = [AVAnimatorView aVAnimatorViewWithFrame:frame];  
  animatorView.animatorOrientation = UIImageOrientationLeft;
  
  // Create loader that will read a movie file from app resources.
  
	AVAppResourceLoader *resLoader = [AVAppResourceLoader aVAppResourceLoader];
  resLoader.movieFilename = resourceName;
	animatorView.resourceLoader = resLoader;
  
  // Create decoder that will generate frames from Quicktime Animation encoded data
  
  AVQTAnimationFrameDecoder *frameDecoder = [AVQTAnimationFrameDecoder aVQTAnimationFrameDecoder];
	animatorView.frameDecoder = frameDecoder;
  
  animatorView.animatorFrameDuration = 1.0;
  
  NSAssert(animatorView.renderSize.width == 0.0, @"renderSize.width");
  NSAssert(animatorView.renderSize.height == 0.0, @"renderSize.height");
  
  [window addSubview:animatorView];
  
  // Check that adding the animator to the window invoked loadViewImpl
  
  NSAssert(animatorView.renderSize.width == 2.0, @"renderSize.width");
  NSAssert(animatorView.renderSize.height == 2.0, @"renderSize.height");
  
  [animatorView prepareToAnimate];
  
  BOOL worked = [RegressionTests waitUntilTrue:animatorView
                                      selector:@selector(isReadyToAnimate)
                                   maxWaitTime:10.0];
  NSAssert(worked, @"worked");
  
  NSAssert(animatorView.state == READY, @"isReadyToAnimate");
  
  // At this point, initial keyframe should be displayed
  
  NSAssert([frameDecoder hasAlphaChannel] == FALSE, @"hasAlphaChannel");
  
  NSAssert(animatorView.currentFrame == 0, @"currentFrame");
  
  NSAssert(animatorView.image != nil, @"image");
  
  uint32_t pixel[4];
  
  // First frame is all black pixels
  
  [self getPixels32BPP:animatorView.image.CGImage
                offset:0
               nPixels:4
              pixelPtr:&pixel[0]];
  
  NSAssert(pixel[0] == 0x0, @"pixel");  
  NSAssert(pixel[1] == 0x0, @"pixel");  
  NSAssert(pixel[2] == 0x0, @"pixel");  
  NSAssert(pixel[3] == 0x0, @"pixel");
  
  // Second frame is all blue pixels
  
  [animatorView showFrame:1];
  
  [self getPixels32BPP:animatorView.image.CGImage
                offset:0
               nPixels:4
              pixelPtr:&pixel[0]];
  
  NSAssert(pixel[0] == 0x000000FF, @"pixel");  
  NSAssert(pixel[1] == 0x000000FF, @"pixel");  
  NSAssert(pixel[2] == 0x000000FF, @"pixel");  
  NSAssert(pixel[3] == 0x000000FF, @"pixel");  
  
  return;
}

+ (void) testBlackBlue2x2_32BPP
{
	id appDelegate = [[UIApplication sharedApplication] delegate];	
	UIWindow *window = [appDelegate window];
	NSAssert(window, @"window");  
  
  NSString *resourceName = @"2x2_black_blue_32BPP.mov";
  
  // Create a plain AVAnimatorView without a movie controls and display
  // in portrait mode. This setup involves no containing views and
  // has no transforms applied to the AVAnimatorView.
  
  CGRect frame = CGRectMake(0, 0, 2, 2);
  AVAnimatorView *animatorView = [AVAnimatorView aVAnimatorViewWithFrame:frame];  
  animatorView.animatorOrientation = UIImageOrientationLeft;
  
  // Create loader that will read a movie file from app resources.
  
	AVAppResourceLoader *resLoader = [AVAppResourceLoader aVAppResourceLoader];
  resLoader.movieFilename = resourceName;
	animatorView.resourceLoader = resLoader;
  
  // Create decoder that will generate frames from Quicktime Animation encoded data
  
  AVQTAnimationFrameDecoder *frameDecoder = [AVQTAnimationFrameDecoder aVQTAnimationFrameDecoder];
	animatorView.frameDecoder = frameDecoder;
  
  animatorView.animatorFrameDuration = 1.0;
  
  NSAssert(animatorView.renderSize.width == 0.0, @"renderSize.width");
  NSAssert(animatorView.renderSize.height == 0.0, @"renderSize.height");
  
  [window addSubview:animatorView];
  
  // Check that adding the animator to the window invoked loadViewImpl
  
  NSAssert(animatorView.renderSize.width == 2.0, @"renderSize.width");
  NSAssert(animatorView.renderSize.height == 2.0, @"renderSize.height");
  
  [animatorView prepareToAnimate];
  
  BOOL worked = [RegressionTests waitUntilTrue:animatorView
                                      selector:@selector(isReadyToAnimate)
                                   maxWaitTime:10.0];
  NSAssert(worked, @"worked");
  
  NSAssert(animatorView.state == READY, @"isReadyToAnimate");
  
  // At this point, initial keyframe should be displayed
  
  NSAssert([frameDecoder hasAlphaChannel] == TRUE, @"hasAlphaChannel");
  
  NSAssert(animatorView.currentFrame == 0, @"currentFrame");
  
  NSAssert(animatorView.image != nil, @"image");
  
  uint32_t pixel[4];
  
  // First frame is all black pixels
  
  [self getPixels32BPP:animatorView.image.CGImage
                offset:0
               nPixels:4
              pixelPtr:&pixel[0]];
  
  NSAssert(pixel[0] == 0xFF000000, @"pixel");  
  NSAssert(pixel[1] == 0xFF000000, @"pixel");  
  NSAssert(pixel[2] == 0xFF000000, @"pixel");  
  NSAssert(pixel[3] == 0xFF000000, @"pixel");
  
  // Second frame is all blue pixels
  
  [animatorView showFrame:1];
  
  [self getPixels32BPP:animatorView.image.CGImage
                offset:0
               nPixels:4
              pixelPtr:&pixel[0]];
  
  NSAssert(pixel[0] == 0xFF0000FF, @"pixel");  
  NSAssert(pixel[1] == 0xFF0000FF, @"pixel");  
  NSAssert(pixel[2] == 0xFF0000FF, @"pixel");  
  NSAssert(pixel[3] == 0xFF0000FF, @"pixel");  
  
  return;
}

@end
