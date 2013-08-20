//
//  AVAnimatorOpenGLViewTests
//
//  Created by Moses DeJong on 8/19/13.
//
//  License terms defined in License.txt.

#import "RegressionTests.h"

#import "AVAnimatorOpenGLView.h"
#include "AVAnimatorOpenGLViewPrivate.h"

#import "AVAnimatorMedia.h"
#import "AVAnimatorMediaPrivate.h"

#import "AVAppResourceLoader.h"

#import "AVAssetFrameDecoder.h"

#import "AVFileUtil.h"

@interface AVAnimatorOpenGLViewTests : NSObject {}
@end

// The methods named test* will be automatically invoked by the RegressionTests harness.

@implementation AVAnimatorOpenGLViewTests

// This test checks the implementation of the attachMedia method
// in the AVAnimatorOpenGLViewTests class. Only a single media item can be
// attached to a rendering view at a time, and only an attached
// media element has resources like allocated framebuffers.

+ (void) testAttachDetachMedia
{
	id appDelegate = [[UIApplication sharedApplication] delegate];	
	UIWindow *window = [appDelegate window];
	NSAssert(window, @"window");  
  
  NSString *resourceName = @"32x32_black_blue_h264.mov";
  
  NSString *resPath;
  resPath = [AVFileUtil getResourcePath:resourceName];
  
  // Create a plain AVAnimatorView without a movie controls and display
  // in portrait mode. This setup involves no containing views and
  // has no transforms applied to the AVAnimatorView.
  
  CGRect frame = CGRectMake(0, 0, 200, 200);
  AVAnimatorOpenGLView *animatorView = [AVAnimatorOpenGLView aVAnimatorOpenGLViewWithFrame:frame];
  
  [animatorView attachMedia:nil];
  
  NSAssert(animatorView.media == nil, @"media");
  
  // Create Media object and link it to the animatorView
  
  AVAnimatorMedia *media = [AVAnimatorMedia aVAnimatorMedia];
  
  NSAssert(media, @"media");
  NSAssert(media.currentFrame == -1, @"currentFrame");
  
  // Create loader and frame decoder that will read from h.264 app asset
  
  AVAppResourceLoader *resLoader = [AVAppResourceLoader aVAppResourceLoader];
  resLoader.movieFilename = resPath;
  
  AVAssetFrameDecoder *frameDecoder = [AVAssetFrameDecoder aVAssetFrameDecoder];
  frameDecoder.produceCoreVideoPixelBuffers = TRUE;
  
  media.resourceLoader = resLoader;
	media.frameDecoder = frameDecoder;
    
  [window addSubview:animatorView];
  
  [media prepareToAnimate];
  
  BOOL worked = [RegressionTests waitUntilTrue:media
                                      selector:@selector(isReadyToAnimate)
                                   maxWaitTime:10.0];
  NSAssert(worked, @"worked");
  
  // The media was not attached on load, so currentFrame is still -1
  
  NSAssert(media.currentFrame == -1, @"currentFrame");  
  
  // The media is now ready, attaching will display the first keyframe.
  
  [animatorView attachMedia:media];
  
  NSAssert(animatorView.media == media, @"media");
  
  NSAssert(media.currentFrame == 0, @"currentFrame");
  
  [animatorView attachMedia:nil];
  
  NSAssert(animatorView.media == nil, @"media");

  // Detach from renderer implicity invoked stopAnimator
  
  NSAssert(media.currentFrame == -1, @"currentFrame");
  
  // FIXME: should work this way
  
  // Note that detaching from the renderer made a copy of the CoreVideo pixel
  // buffer, but it is not the one delivered by mediaserverd. Instead, that
  // data was copied into a duplicate CoreVideo pixel buffer so that the
  // copy backed by an OpenGL texture is no longer used.
  
  return;
}

@end
