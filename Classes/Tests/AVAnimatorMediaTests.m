//
//  AVAnimatorMediaTests.m
//
//  Created by Moses DeJong on 11/22/11.
//
// Test media object. A media object pulls frames from a decoder
// and handles the details of mapping audio time to media frames.

#import <Foundation/Foundation.h>

#import "RegressionTests.h"

#import "AVAnimatorView.h"
#include "AVAnimatorViewPrivate.h"

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

@interface AVAnimatorMediaTests : NSObject {
}
@end

// Util class

@interface NotificationUtil : NSObject {
  BOOL m_wasLoadFailedDelivered;
}

@property (nonatomic, assign) BOOL wasLoadFailedDelivered;

+ (NotificationUtil*) notificationUtil;

- (void) setupNotification:(AVAnimatorMedia*)media;

@end

// This utility object will register to receive a AVAnimatorFailedToLoadNotification and set
// a boolean flag to indicate if the notification is delivered.

@implementation NotificationUtil

@synthesize wasLoadFailedDelivered = m_wasLoadFailedDelivered;

+ (NotificationUtil*) notificationUtil
{
  NotificationUtil *obj = [[NotificationUtil alloc] init];
  return [obj autorelease];
}

- (void) dealloc {
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  [super dealloc];
}

- (void) setupNotification:(AVAnimatorMedia*)media
{  
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(failedToLoadNotification:) 
                                               name:AVAnimatorFailedToLoadNotification
                                             object:media];  
}

- (void) failedToLoadNotification:(NSNotification*)notification
{
  self.wasLoadFailedDelivered = TRUE;
}

@end // setupNotification

// class AVAnimatorMediaTests

@implementation AVAnimatorMediaTests

// This test case will create a media object and attempt to load video data from a file that exists
// but contains no data. It is not possible to create a loader for a file that does not even exist.

+ (void) testFailOnLoadEmptyMvidFile
{
	id appDelegate = [[UIApplication sharedApplication] delegate];	
	UIWindow *window = [appDelegate window];
	NSAssert(window, @"window");
  
  // Get tmp dir path and create an empty file with the .mvid extension
  
  NSString *tmpFilename = @"Empty.mvid";
  NSString *tmpDir = NSTemporaryDirectory();
  NSString *tmpPath = [tmpDir stringByAppendingPathComponent:tmpFilename];
  
  [[NSData data] writeToFile:tmpPath options:NSDataWritingAtomic error:nil];
      
  // Create Media object
  
  AVAnimatorMedia *media = [AVAnimatorMedia aVAnimatorMedia];
  
  // Create loader that will attempt to read the empty path from the filesystem
  
	AVAppResourceLoader *resLoader = [AVAppResourceLoader aVAppResourceLoader];
  resLoader.movieFilename = tmpPath;
	media.resourceLoader = resLoader;
  
  // Create decoder that will generate frames from Quicktime Animation encoded data
  
  AVMvidFrameDecoder *frameDecoder = [AVMvidFrameDecoder aVMvidFrameDecoder];
	media.frameDecoder = frameDecoder;
  
  media.animatorFrameDuration = 1.0;
  
  // Attach object that will receive a notification if delivered
  
  NotificationUtil *nUtil = [NotificationUtil notificationUtil];
  [nUtil setupNotification:media];
  
  // Prepare to animate, this should fail in async callback
  
  NSAssert(media.isReadyToAnimate == FALSE, @"isReadyToAnimate");
    
  [media prepareToAnimate];
  
  // Wait for a moment to see if media object becomes ready to play, this should fail
  // because the resource could not be loaded from the file.
  
  BOOL worked = [RegressionTests waitUntilTrue:media
                                      selector:@selector(isReadyToAnimate)
                                   maxWaitTime:0.1];
  NSAssert(worked == FALSE, @"!worked");
  
  // The result of attempting to load an empty .mvid file is a media object in the FAILED state
  
  NSAssert(media.state == FAILED, @"media.state");

  NSAssert(nUtil.wasLoadFailedDelivered == TRUE, @"wasLoadFailedDelivered");
  
  return;
}

// Test logic related to loading a mvid resource, but in this case the media
// object is not attached to a rendering view. The result is that loading will
// finish with a successful state. If this same setup were used and the media
// was already attached to a window, loading would fail because a
// memory map failure would have been simulated.

+ (void) testLoadingMvidSuccessWhenNotAttachedToRenderer
{
	id appDelegate = [[UIApplication sharedApplication] delegate];	
	UIWindow *window = [appDelegate window];
	NSAssert(window, @"window");
  
  NSString *resourceName = @"2x2_black_blue_16BPP.mvid";
  
  // Create Media object
  
  AVAnimatorMedia *media = [AVAnimatorMedia aVAnimatorMedia];
  
  // Create loader that will load the mvid from the filesystem
  
	AVAppResourceLoader *resLoader = [AVAppResourceLoader aVAppResourceLoader];
  resLoader.movieFilename = resourceName;
	media.resourceLoader = resLoader;
  
  // Create decoder that will generate frames from mvid encoded data
  
  AVMvidFrameDecoder *frameDecoder = [AVMvidFrameDecoder aVMvidFrameDecoder];
	media.frameDecoder = frameDecoder;
  
  // Indicate that mapping the file memory should fail, but this will not
  // effect the loading logic since the media is not attached to a renderer.
  
  frameDecoder.simulateMemoryMapFailure = TRUE;
  
  media.animatorFrameDuration = 1.0;
  
  // Attach object that will receive a notification if delivered
  
  NotificationUtil *nUtil = [NotificationUtil notificationUtil];
  [nUtil setupNotification:media];
  
  // Prepare to animate, this should fail in async callback
  
  NSAssert(media.isReadyToAnimate == FALSE, @"isReadyToAnimate");
  
  [media prepareToAnimate];
  
  // Wait for a moment to see if media object is loaded successfully.
  
  BOOL worked = [RegressionTests waitUntilTrue:media
                                      selector:@selector(isReadyToAnimate)
                                   maxWaitTime:0.5];
  NSAssert(worked, @"worked");
    
  NSAssert(media.state == READY, @"media.state");
  
  NSAssert(nUtil.wasLoadFailedDelivered == FALSE, @"wasLoadFailedDelivered");
  
  return;
}

// This test case is like the one above, except that the media object is
// attached to a renderer, so the simulated memory map will cause a failure
// of the media object during the load phase.

+ (void) testMvidFailOnMappingFileWhenAttachedToRenderer
{
	id appDelegate = [[UIApplication sharedApplication] delegate];	
	UIWindow *window = [appDelegate window];
	NSAssert(window, @"window");
  
  NSString *resourceName = @"2x2_black_blue_16BPP.mvid";
  
  // Create view that would be the render destination for the media
  
  CGRect frame = CGRectMake(0, 0, 480, 320);
  AVAnimatorView *animatorView = [AVAnimatorView aVAnimatorViewWithFrame:frame];
  
  // Add the view to the containing window and visit the event loop so that the
  // window system setup is complete.
  
  [window addSubview:animatorView];
  NSAssert(animatorView.window != nil, @"not added to window");
  
  // Create Media object
  
  AVAnimatorMedia *media = [AVAnimatorMedia aVAnimatorMedia];
  [animatorView attachMedia:media];
  NSAssert(media.renderer == animatorView, @"media.renderer");
  NSAssert(media == animatorView.media, @"renderer.media");
  
  // Create loader that will attempt to read the phone path from the filesystem
  
	AVAppResourceLoader *resLoader = [AVAppResourceLoader aVAppResourceLoader];
  resLoader.movieFilename = resourceName;
	media.resourceLoader = resLoader;
  
  // Create decoder that will generate frames from Quicktime Animation encoded data
  
  AVMvidFrameDecoder *frameDecoder = [AVMvidFrameDecoder aVMvidFrameDecoder];
	media.frameDecoder = frameDecoder;
  
  frameDecoder.simulateMemoryMapFailure = TRUE;
  
  media.animatorFrameDuration = 1.0;
  
  // Attach object that will receive a notification if delivered
  
  NotificationUtil *nUtil = [NotificationUtil notificationUtil];
  [nUtil setupNotification:media];
  
  // Prepare to animate, this should fail in async callback
  
  NSAssert(media.isReadyToAnimate == FALSE, @"isReadyToAnimate");
  
  [media prepareToAnimate];
  
  // Wait for a moment to see if media object was loaded. Note that the
  // isReadyToAnimate is TRUE when loading works. In this case, attaching
  // the media to the view did not work, but that is not the same thing
  // as failing to load.
  
  BOOL worked = [RegressionTests waitUntilTrue:media
                                      selector:@selector(isReadyToAnimate)
                                   maxWaitTime:0.5];
  NSAssert(worked == FALSE, @"!worked");
  
  // The result of attempting to load an empty .mvid file is a media object in the FAILED state
  
  NSAssert(media.state == FAILED, @"media.state");
  
  NSAssert(nUtil.wasLoadFailedDelivered == TRUE, @"wasLoadFailedDelivered");
  
  // When the media could not be attached to the view properly as part of the load
  // process, both references in the media and the view are set to nil.
  
  NSAssert(animatorView.media == nil, @"animatorView still connected to media");
  NSAssert(media.renderer == nil, @"media still connected to animatorView");
  
  return;
}

// In this test case, loading of the media works as expected. The media
// is not attached to a view at load time. Then, the media is attached
// to a specific view, this attach operation should fail immediatly.

+ (void) testLoadingMvidAttachFailedAfterSuccessfulLoad
{
	id appDelegate = [[UIApplication sharedApplication] delegate];	
	UIWindow *window = [appDelegate window];
	NSAssert(window, @"window");
  
  NSString *resourceName = @"2x2_black_blue_16BPP.mvid";
  
  // Create Media object
  
  AVAnimatorMedia *media = [AVAnimatorMedia aVAnimatorMedia];
  
  // Create loader that will load the mvid from the filesystem
  
	AVAppResourceLoader *resLoader = [AVAppResourceLoader aVAppResourceLoader];
  resLoader.movieFilename = resourceName;
	media.resourceLoader = resLoader;
  
  // Create decoder that will generate frames from mvid encoded data
  
  AVMvidFrameDecoder *frameDecoder = [AVMvidFrameDecoder aVMvidFrameDecoder];
	media.frameDecoder = frameDecoder;
  
  // Indicate that mapping the file memory should fail, but this will not
  // effect the loading logic since the media is not attached to a renderer.
  
  frameDecoder.simulateMemoryMapFailure = TRUE;
  
  media.animatorFrameDuration = 1.0;
  
  // Attach object that will receive a notification if delivered
  
  NotificationUtil *nUtil = [NotificationUtil notificationUtil];
  [nUtil setupNotification:media];
  
  // Prepare to animate, this should fail in async callback
  
  NSAssert(media.isReadyToAnimate == FALSE, @"isReadyToAnimate");
  
  [media prepareToAnimate];
  
  // Wait for a moment to see if media object is loaded successfully.
  
  BOOL worked = [RegressionTests waitUntilTrue:media
                                      selector:@selector(isReadyToAnimate)
                                   maxWaitTime:0.5];
  NSAssert(worked, @"worked");
  
  NSAssert(media.state == READY, @"media.state");
  
  NSAssert(nUtil.wasLoadFailedDelivered == FALSE, @"wasLoadFailedDelivered");
  
  // Create a view that the media will be attached to
  
  CGRect frame = CGRectMake(0, 0, 480, 320);
  AVAnimatorView *animatorView = [AVAnimatorView aVAnimatorViewWithFrame:frame];
  
  // Add the view to the containing window and visit the event loop so that the
  // window system setup is complete.
  
  [window addSubview:animatorView];
  NSAssert(animatorView.window != nil, @"not added to window");

  // Attach the media to the view, this will fail because the simulated
  // memory map flag is set in the frame decoder.
  
  NSAssert(animatorView.media == nil, @"media ref msut be nil");
  NSAssert(media.renderer == nil, @"renderer ref must be nil");
  
  [animatorView attachMedia:media];
  
  NSAssert(animatorView.media == nil, @"animatorView still connected to media");
  NSAssert(media.renderer == nil, @"media still connected to animatorView");
  
  NSAssert(nUtil.wasLoadFailedDelivered == FALSE, @"wasLoadFailedDelivered");
  
  // Now check that the attach will work if the simulated mmap failure goes away
  
  frameDecoder.simulateMemoryMapFailure = FALSE;
  
  [animatorView attachMedia:media];
  
  NSAssert(animatorView.media == media, @"animatorView.media");
  NSAssert(media.renderer == animatorView, @"media.renderer");

  return;
}

// In this test case a media object will fail to load. Later a view renderer
// will be attached, but this attach should fail because the media is in a FAIL state.
// of the media object during the load phase. This test case also invokes media
// APIs to make sure they no-op when in the FAILED state.

+ (void) testMvidFailOnAttachAfterFailToLoad
{
	id appDelegate = [[UIApplication sharedApplication] delegate];	
	UIWindow *window = [appDelegate window];
	NSAssert(window, @"window");
  
  NSString *resourceName = @"2x2_black_blue_16BPP.mvid";
  
  // Create view that would be the render destination for the media
  
  CGRect frame = CGRectMake(0, 0, 480, 320);
  AVAnimatorView *animatorView = [AVAnimatorView aVAnimatorViewWithFrame:frame];
  
  // Add the view to the containing window and visit the event loop so that the
  // window system setup is complete.
  
  [window addSubview:animatorView];
  NSAssert(animatorView.window != nil, @"not added to window");
  
  // Create Media object
  
  AVAnimatorMedia *media = [AVAnimatorMedia aVAnimatorMedia];
  [animatorView attachMedia:media];
  NSAssert(media.renderer == animatorView, @"media.renderer");
  NSAssert(media == animatorView.media, @"renderer.media");
  
  // Create loader that will attempt to read the phone path from the filesystem
  
	AVAppResourceLoader *resLoader = [AVAppResourceLoader aVAppResourceLoader];
  resLoader.movieFilename = resourceName;
	media.resourceLoader = resLoader;
  
  // Create decoder that will generate frames from Quicktime Animation encoded data
  
  AVMvidFrameDecoder *frameDecoder = [AVMvidFrameDecoder aVMvidFrameDecoder];
	media.frameDecoder = frameDecoder;
  
  frameDecoder.simulateMemoryMapFailure = TRUE;
  
  media.animatorFrameDuration = 1.0;
  
  // Attach object that will receive a notification if delivered
  
  NotificationUtil *nUtil = [NotificationUtil notificationUtil];
  [nUtil setupNotification:media];
  
  // Prepare to animate, this should fail in async callback
  
  NSAssert(media.isReadyToAnimate == FALSE, @"isReadyToAnimate");
  
  [media prepareToAnimate];
  
  // Wait for a moment to see if media object was loaded. Note that the
  // isReadyToAnimate is TRUE when loading works. In this case, attaching
  // the media to the view did not work, but that is not the same thing
  // as failing to load.
  
  BOOL worked = [RegressionTests waitUntilTrue:media
                                      selector:@selector(isReadyToAnimate)
                                   maxWaitTime:0.5];
  NSAssert(worked == FALSE, @"!worked");
  
  // The result of attempting to load an empty .mvid file is a media object in the FAILED state
  
  NSAssert(media.state == FAILED, @"media.state");
  
  NSAssert(nUtil.wasLoadFailedDelivered == TRUE, @"wasLoadFailedDelivered");
    
  NSAssert(animatorView.media == nil, @"animatorView still connected to media");
  NSAssert(media.renderer == nil, @"media still connected to animatorView");
  
  // Clearing the map fail flag should put things back into a working state.
  // But, because the media failed to load, it can't be used via an attach.
  
  frameDecoder.simulateMemoryMapFailure = FALSE;
  
  [animatorView attachMedia:media];
  
  NSAssert(animatorView.media == nil, @"animatorView still connected to media");
  NSAssert(media.renderer == nil, @"media still connected to animatorView");

  // Invoking start or stop on a media object in the FAILED state is a no-op.
  
  NSAssert(media.state == FAILED, @"media.state");  
  
  [media startAnimator];
  
  NSAssert(media.state == FAILED, @"media.state");

  [media stopAnimator];

  NSAssert(media.state == FAILED, @"media.state");

  [media pause];
  
  NSAssert(media.state == FAILED, @"media.state");

  [media unpause];
  
  NSAssert(media.state == FAILED, @"media.state");

  [media rewind];
  
  NSAssert(media.state == FAILED, @"media.state");
  
  // Invoking prepareToAnimate in the FAILED state is a no-op

  [media prepareToAnimate];
  
  NSAssert(media.state == FAILED, @"media.state");
  
  return;
}

// This test case checks the implementation of AVAnimatorView and how
// it holds a ref to the media object. A view must hold a ref to the
// media so that the media can be detached properly in the dealloc case.

+ (void) testMediaAndAVAnimatorViewRefCounts
{
	id appDelegate = [[UIApplication sharedApplication] delegate];	
	UIWindow *window = [appDelegate window];
	NSAssert(window, @"window");
  
  NSString *resourceName = @"2x2_black_blue_16BPP.mvid";
  
  // Create view that would be the render destination for the media
  
  CGRect frame = CGRectMake(0, 0, 480, 320);
  AVAnimatorView *animatorView = [AVAnimatorView aVAnimatorViewWithFrame:frame];
  
  // Add the view to the containing window and visit the event loop so that the
  // window system setup is complete.
  
  [window addSubview:animatorView];
  NSAssert(animatorView.window != nil, @"not added to window");
  
  // Create Media object
  
  AVAnimatorMedia *media = [AVAnimatorMedia aVAnimatorMedia];
  
  // Create loader that will attempt to read the phone path from the filesystem
  
	AVAppResourceLoader *resLoader = [AVAppResourceLoader aVAppResourceLoader];
  resLoader.movieFilename = resourceName;
	media.resourceLoader = resLoader;
  
  // Create decoder that will generate frames from Quicktime Animation encoded data
  
  AVMvidFrameDecoder *frameDecoder = [AVMvidFrameDecoder aVMvidFrameDecoder];
	media.frameDecoder = frameDecoder;
  
  media.animatorFrameDuration = 1.0;
    
  [media prepareToAnimate];
  
  // Wait for a moment to see if media object was loaded. Note that the
  // isReadyToAnimate is TRUE when loading works. In this case, attaching
  // the media to the view did not work, but that is not the same thing
  // as failing to load.
  
  BOOL worked = [RegressionTests waitUntilTrue:media
                                      selector:@selector(isReadyToAnimate)
                                   maxWaitTime:0.5];
  NSAssert(worked, @"worked");
  
  // The media should have been loaded, it would not have been attached to the view
  // at this point.
  
  NSAssert(media.state == READY, @"media.state");
  
  NSAssert(animatorView.media == nil, @"animatorView connected to media");
  NSAssert(media.renderer == nil, @"media connected to animatorView");
  
  int viewRefCountBefore = [animatorView retainCount];
  int mediaRefCountBefore = [media retainCount];
  
  [animatorView attachMedia:media];
  
  NSAssert(animatorView.media == media, @"animatorView not connected to media");
  NSAssert(media.renderer == animatorView, @"media not connected to animatorView");

  int viewRefCountAfter = [animatorView retainCount];
  int mediaRefCountAfter = [media retainCount];

  // The AVAnimatorView holds a ref to the media in the view
  
  NSAssert(viewRefCountBefore == viewRefCountAfter, @"view ref count was incremented by attach");
  NSAssert((mediaRefCountBefore + 1) == mediaRefCountAfter, @"media ref count was not incremented by attach");

  // Detaching the media should drop the ref count
  
  [animatorView attachMedia:nil];
  
  viewRefCountAfter = [animatorView retainCount];
  mediaRefCountAfter = [media retainCount];

  NSAssert(viewRefCountBefore == viewRefCountAfter, @"view ref count was incremented by attach");
  NSAssert(mediaRefCountBefore == mediaRefCountAfter, @"media ref count was not incremented by attach");
  
  // Now reattach and let the cleanup happen in the auto release pool logic, should not leak
  
  [animatorView attachMedia:media];
  
  return;
}

// This test case checks the implementation of AVAnimatorLayer and how
// it holds a ref to the media object. A view must hold a ref to the
// media so that the media can be detached properly in the dealloc case.

+ (void) testMediaAndAVAnimatorLayerRefCounts
{
	id appDelegate = [[UIApplication sharedApplication] delegate];	
	UIWindow *window = [appDelegate window];
	NSAssert(window, @"window");
  
  NSString *resourceName = @"2x2_black_blue_16BPP.mvid";
  
  // Create view that would be the render destination for the media
  
  CGRect frame = CGRectMake(0, 0, 480, 320);  
  UIView *view = [[[UIView alloc] initWithFrame:frame] autorelease];
  CALayer *viewLayer = view.layer;
  
  AVAnimatorLayer *avLayerObj = [AVAnimatorLayer aVAnimatorLayer:viewLayer];
  NSAssert(avLayerObj, @"avLayerObj");
  
  [window addSubview:view];

  NSAssert(view.window != nil, @"not added to window");
  
  // Create Media object
  
  AVAnimatorMedia *media = [AVAnimatorMedia aVAnimatorMedia];
  
  // Create loader that will attempt to read the phone path from the filesystem
  
	AVAppResourceLoader *resLoader = [AVAppResourceLoader aVAppResourceLoader];
  resLoader.movieFilename = resourceName;
	media.resourceLoader = resLoader;
  
  // Create decoder that will generate frames from Quicktime Animation encoded data
  
  AVMvidFrameDecoder *frameDecoder = [AVMvidFrameDecoder aVMvidFrameDecoder];
	media.frameDecoder = frameDecoder;
  
  media.animatorFrameDuration = 1.0;
  
  [media prepareToAnimate];
  
  // Wait for a moment to see if media object was loaded. Note that the
  // isReadyToAnimate is TRUE when loading works. In this case, attaching
  // the media to the view did not work, but that is not the same thing
  // as failing to load.
  
  BOOL worked = [RegressionTests waitUntilTrue:media
                                      selector:@selector(isReadyToAnimate)
                                   maxWaitTime:0.5];
  NSAssert(worked, @"worked");
  
  // The media should have been loaded, it would not have been attached to the view
  // at this point.
  
  NSAssert(media.state == READY, @"media.state");
  
  NSAssert(avLayerObj.media == nil, @"animatorView connected to media");
  NSAssert(media.renderer == nil, @"media connected to animatorView");
  
  int viewRefCountBefore = [avLayerObj retainCount];
  int mediaRefCountBefore = [media retainCount];
  
  [avLayerObj attachMedia:media];
  
  NSAssert(avLayerObj.media == media, @"animatorView not connected to media");
  NSAssert(media.renderer == avLayerObj, @"media not connected to animatorView");
  
  int viewRefCountAfter = [avLayerObj retainCount];
  int mediaRefCountAfter = [media retainCount];
  
  // The AVAnimatorLayer holds a ref to the media in the view
  
  NSAssert(viewRefCountBefore == viewRefCountAfter, @"view ref count was incremented by attach");
  NSAssert((mediaRefCountBefore + 1) == mediaRefCountAfter, @"media ref count was not incremented by attach");
  
  // Detaching the media should drop the ref count
  
  [avLayerObj attachMedia:nil];
  
  viewRefCountAfter = [avLayerObj retainCount];
  mediaRefCountAfter = [media retainCount];
  
  NSAssert(viewRefCountBefore == viewRefCountAfter, @"view ref count was incremented by attach");
  NSAssert(mediaRefCountBefore == mediaRefCountAfter, @"media ref count was not incremented by attach");
  
  // Now reattach and let the cleanup happen in the auto release pool logic, should not leak
  
  [avLayerObj attachMedia:media];
  
  return;
}

// FIXME:
// Load media and attach to view, then deallocate the view by dropping all refs.
// This should detach from the media object.

@end // AVAnimatorMediaTests
