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
+ (void) testApp;
@end

@implementation AVAnimatorViewTests

+ (void) test24BPP:(UIWindow*)window
{
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
  
  CFDataRef pixelData = CGDataProviderCopyData(CGImageGetDataProvider(animatorView.image.CGImage));
  
  uint32_t pixel;
  int offset = 0;
  CFDataGetBytes(pixelData, CFRangeMake(offset, sizeof(pixel)), (UInt8*)&pixel );
  
  NSAssert(pixel == 0x0, @"pixel");
  
  return;
}

// Define a method named "testApp", it will be invoked dynamically from
// RegressionTest.m at runtime

+ (void) testApp {
	id appDelegate = [[UIApplication sharedApplication] delegate];	
	UIWindow *window = [appDelegate window];
	NSAssert(window, @"window");
  
  // Run each test case in the test class
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  [self test24BPP:window];
  [RegressionTests cleanupAfterTest];
  [pool drain];
  
	return;
}

@end
