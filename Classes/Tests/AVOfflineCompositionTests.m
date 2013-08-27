//
//  AVOfflineCompositionTests.m
//
//  Created by Moses DeJong on 3/31/12.
//
// Regression tests for offline composition operation module.
// This module combines video clips into a single movie.

#import <Foundation/Foundation.h>

#import "RegressionTests.h"

#import "AVAnimatorMedia.h"
#import "AVAnimatorMediaPrivate.h"

#import "AVAppResourceLoader.h"

#import "AV7zAppResourceLoader.h"

#import "AVMvidFrameDecoder.h"

#import "AVFileUtil.h"

#import "AVOfflineComposition.h"

#import "AVFrame.h"

#define MAX_WAIT_TIME 10.0

// Private API

@interface AVOfflineComposition ()

// Read a plist from a resource file. Either a NSDictionary or NSArray

+ (id) readPlist:(NSString*)resFileName;

- (BOOL) parseToplevelProperties:(NSDictionary*)compDict;

- (void) notifyCompositionCompleted;

- (void) notifyCompositionFailed;

- (NSString*) backgroundColorStr;

- (BOOL) composeFrames;

@property (nonatomic, copy) NSString *source;

@property (nonatomic, copy) NSArray *compClips;

@property (nonatomic, assign) float compDuration;

@property (nonatomic, assign) float compFPS;

@property (nonatomic, assign) NSUInteger numFrames;

@property (nonatomic, assign) CGSize compSize;

@end

// Util class

@interface AVOfflineCompositionNotificationUtil : NSObject {
  BOOL m_wasFailedNotificationDelivered;
  BOOL m_wasSuccessNotificationDelivered;
}

@property (nonatomic, assign) BOOL wasFailedNotificationDelivered;
@property (nonatomic, assign) BOOL wasSuccessNotificationDelivered;

+ (AVOfflineCompositionNotificationUtil*) aVOfflineCompositionNotificationUtil;

- (void) setupNotification:(AVOfflineComposition*)composition;

@end

// This utility object will register to receive a AVOfflineCompositionCompletedNotification and set
// a boolean flag to indicate if the notification is delivered.

@implementation AVOfflineCompositionNotificationUtil

@synthesize wasFailedNotificationDelivered = m_wasFailedNotificationDelivered;
@synthesize wasSuccessNotificationDelivered = m_wasSuccessNotificationDelivered;

+ (AVOfflineCompositionNotificationUtil*) aVOfflineCompositionNotificationUtil
{
  AVOfflineCompositionNotificationUtil *obj = [[AVOfflineCompositionNotificationUtil alloc] init];
  return [obj autorelease];
}

- (void) dealloc {
  [[NSNotificationCenter defaultCenter] removeObserver:self];
  [super dealloc];
}

- (void) setupNotification:(AVOfflineComposition*)composition
{
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(finishedLoadNotification:) 
                                               name:AVOfflineCompositionCompletedNotification
                                             object:composition];
  
  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(failedToLoadNotification:) 
                                               name:AVOfflineCompositionFailedNotification
                                             object:composition];  
}

- (void) finishedLoadNotification:(NSNotification*)notification
{
  NSAssert(self.wasSuccessNotificationDelivered == FALSE, @"not default state when notification received");
  NSAssert(self.wasFailedNotificationDelivered == FALSE, @"not default state when notification received");
  self.wasSuccessNotificationDelivered = TRUE;
}

- (void) failedToLoadNotification:(NSNotification*)notification
{
  NSAssert(self.wasSuccessNotificationDelivered == FALSE, @"not default state when notification received");
  NSAssert(self.wasFailedNotificationDelivered == FALSE, @"not default state when notification received");
  self.wasFailedNotificationDelivered = TRUE;
}

@end // setupNotification

// class AVOfflineCompositionTests

@interface AVOfflineCompositionTests : NSObject {
}
@end

@implementation AVOfflineCompositionTests

// This utility method will dump each frame as a PNG

+ (void) dumpEachFrameUtil:(AVMvidFrameDecoder*)frameDecoder
{
  BOOL worked;
  
  // Dump each Frame 
  
  if (TRUE) {
    
    worked = [frameDecoder allocateDecodeResources];
    NSAssert(worked, @"allocateDecodeResources");
    
    for (NSUInteger frameIndex = 0; frameIndex < frameDecoder.numFrames; frameIndex++) {
      NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
      NSLog(@"render frame %d", frameIndex);
      AVFrame *frame = [frameDecoder advanceToFrame:frameIndex];
      UIImage *img = frame.image;
      NSAssert(img, @"frame image is nil");
      
      // Write image as PNG
      
      NSString *tmpDir = NSTemporaryDirectory();
      
      NSString *tmpPNGPath = [tmpDir stringByAppendingFormat:@"Frame%d.png", (frameIndex + 1)];
      
      NSData *data = [NSData dataWithData:UIImagePNGRepresentation(img)];
      [data writeToFile:tmpPNGPath atomically:YES];
      NSLog(@"wrote %@", tmpPNGPath);
      [pool drain];
    }
    
  }

}

// This test cases creates a composition that is 2 frames long, the total duration is 1.0 seconds
// and the movie will consist of just a blue background at 2x2 pixels.

+ (void) testCompose2FrameBlueBackground
{
  NSString *resFilename;
  
  resFilename = @"AVOfflineCompositionTwoFrameBlueBackgroundTest.plist";
  
  NSDictionary *plistDict = (NSDictionary*) [AVOfflineComposition readPlist:resFilename];
  
  AVOfflineComposition *comp = [AVOfflineComposition aVOfflineComposition];
  
  AVOfflineCompositionNotificationUtil *notificationUtil = [AVOfflineCompositionNotificationUtil aVOfflineCompositionNotificationUtil];

  [notificationUtil setupNotification:comp];
  
  [comp compose:plistDict];
  
  // Wait until comp operation either works or fails
  
  BOOL worked = [RegressionTests waitUntilTrue:notificationUtil
                                      selector:@selector(wasSuccessNotificationDelivered)
                                   maxWaitTime:MAX_WAIT_TIME];
  NSAssert(worked, @"worked");

  // Verify that the correct properties were parsed from the plist

  NSAssert([comp.source isEqualToString:resFilename], @"source");

  NSString *tmpDir = NSTemporaryDirectory();
  NSString *tmpPath = [tmpDir stringByAppendingString:@"AVOfflineCompositionTwoFrameBlueBackgroundTest.mvid"];
  
  NSAssert([comp.destination isEqualToString:tmpPath], @"source");
  
  NSAssert(comp.compDuration == 1.0f, @"compDuration");

  NSAssert(comp.compFPS == 2.0f, @"compFPS");

  NSAssert(comp.numFrames == 2, @"numFrames");
  
  // BG color
  
  NSString *bgColor = [comp backgroundColorStr];
  
  NSAssert([bgColor isEqualToString:@"#0000FFFF"], @"background color");

  // width x height
  
  NSAssert(CGSizeEqualToSize(comp.compSize, CGSizeMake(2,2)), @"size");
  
  // Open .mvid file and verify header info
  
  AVMvidFrameDecoder *frameDecoder = [AVMvidFrameDecoder aVMvidFrameDecoder];
  
  worked = [frameDecoder openForReading:comp.destination];
	NSAssert(worked, @"frameDecoder openForReading failed");
  
  NSAssert(frameDecoder.frameDuration == 0.5, @"frameDuration");
  NSAssert(frameDecoder.numFrames == 2, @"numFrames");
  
  // Dump each Frame 
  
  if (TRUE) {
    [self dumpEachFrameUtil:frameDecoder];
  }
    
  return;
}

// This test cases creates a composition that is 2 frames long. The composition contains
// 2 frames from the indicated clip. Each frame in the clip completely covers all pixels
// in the comp buffer. The result is that the comp movie is an exact copy of the original
// clip.

+ (void) testCompose2FrameBlueBlackCopy
{
  NSString *resFilename;
  
  resFilename = @"AVOfflineCompositionTwoFrameBlackBlueMovieTest.plist";
  
  NSDictionary *plistDict = (NSDictionary*) [AVOfflineComposition readPlist:resFilename];
  
  AVOfflineComposition *comp = [AVOfflineComposition aVOfflineComposition];
  
  AVOfflineCompositionNotificationUtil *notificationUtil = [AVOfflineCompositionNotificationUtil aVOfflineCompositionNotificationUtil];
  
  [notificationUtil setupNotification:comp];
  
  [comp compose:plistDict];
  
  // Wait until comp operation either works or fails
  
  BOOL worked = [RegressionTests waitUntilTrue:notificationUtil
                                      selector:@selector(wasSuccessNotificationDelivered)
                                   maxWaitTime:MAX_WAIT_TIME];
  NSAssert(worked, @"worked");
  
  // Verify that the correct properties were parsed from the plist
  
  NSAssert([comp.source isEqualToString:resFilename], @"source");
  
  NSString *tmpDir = NSTemporaryDirectory();
  NSString *tmpPath = [tmpDir stringByAppendingString:@"AVOfflineCompositionTwoFrameBlackBlueMovieTest.mvid"];
  
  NSAssert([comp.destination isEqualToString:tmpPath], @"source");
  
  NSAssert(comp.compDuration == 2.0f, @"compDuration");
  
  NSAssert(comp.compFPS == 1.0f, @"compFPS");
  
  NSAssert(comp.numFrames == 2, @"numFrames");
  
  // BG color is black (the default)
  
  NSString *bgColor = [comp backgroundColorStr];
  
  NSAssert([bgColor isEqualToString:@"#000000FF"], @"background color");
  
  // width x height
  
  NSAssert(CGSizeEqualToSize(comp.compSize, CGSizeMake(2,2)), @"size");
  
  // Open .mvid file and verify header info
  
  AVMvidFrameDecoder *frameDecoder = [AVMvidFrameDecoder aVMvidFrameDecoder];
  
  worked = [frameDecoder openForReading:comp.destination];
	NSAssert(worked, @"frameDecoder openForReading failed");
  
  NSAssert(frameDecoder.frameDuration == 1.0, @"frameDuration");
  NSAssert(frameDecoder.numFrames == 2, @"numFrames");
  
  // Dump each Frame 
  
  if (TRUE) {
    [self dumpEachFrameUtil:frameDecoder];
  }
  
  return;
}

// This test cases creates a composition that is 4 frames long at 1 FPS.
// The movie contained in the clip is normally 1 FPS for 2 frames, but the
// plist set the special ClipScaleFramePerSecond flag so that the effective
// frame rate of the clip is adjusted to 2 FPS. The clip is in effect "strected"
// so that it displays for 4 seconds instead of 2. This logic is different than
// the default behavior of simply showing the final frame after the normal
// clip end time has elapsed in terms of the frmerate defined in the clip mvid.

+ (void) testCompose2FrameBlueBlackCopyScaleFramerate
{
  NSString *resFilename;
  
  resFilename = @"AVOfflineCompositionTwoFrameBlackBlueScaleMovieTest.plist";
  
  NSDictionary *plistDict = (NSDictionary*) [AVOfflineComposition readPlist:resFilename];
  NSAssert(plistDict, @"plistDict");
  
  AVOfflineComposition *comp = [AVOfflineComposition aVOfflineComposition];
  
  AVOfflineCompositionNotificationUtil *notificationUtil = [AVOfflineCompositionNotificationUtil aVOfflineCompositionNotificationUtil];
  
  [notificationUtil setupNotification:comp];
  
  [comp compose:plistDict];
  
  // Wait until comp operation either works or fails
  
  BOOL worked = [RegressionTests waitUntilTrue:notificationUtil
                                      selector:@selector(wasSuccessNotificationDelivered)
                                   maxWaitTime:MAX_WAIT_TIME];
  NSAssert(worked, @"worked");
  
  // Verify that the correct properties were parsed from the plist
  
  NSAssert([comp.source isEqualToString:resFilename], @"source");
  
  NSString *tmpDir = NSTemporaryDirectory();
  NSString *tmpPath = [tmpDir stringByAppendingString:@"AVOfflineCompositionTwoFrameBlackBlueScaleMovieTest.mvid"];
  
  NSAssert([comp.destination isEqualToString:tmpPath], @"source");
  
  NSAssert(comp.compDuration == 4.0f, @"compDuration");
  
  NSAssert(comp.compFPS == 1.0f, @"compFPS");
  
  NSAssert(comp.numFrames == 4, @"numFrames");
  
  // BG color is black (the default)
  
  NSString *bgColor = [comp backgroundColorStr];
  
  NSAssert([bgColor isEqualToString:@"#000000FF"], @"background color");
  
  // width x height
  
  NSAssert(CGSizeEqualToSize(comp.compSize, CGSizeMake(2,2)), @"size");
  
  // Open .mvid file and verify header info
  
  AVMvidFrameDecoder *frameDecoder = [AVMvidFrameDecoder aVMvidFrameDecoder];
  
  worked = [frameDecoder openForReading:comp.destination];
	NSAssert(worked, @"frameDecoder openForReading failed");
  
  NSAssert(frameDecoder.frameDuration == 1.0, @"frameDuration");
  NSAssert(frameDecoder.numFrames == 4, @"numFrames");
  
  // Dump each Frame 
  
  if (TRUE) {
    [self dumpEachFrameUtil:frameDecoder];
  }
  
  return;
}

// This test case includes 2 frames encoded at 15 FPS with the H264 codec. For nontrivial
// video data that does not inclue an alpha channel, the H264 codec compressed video data
// quite significantly.

+ (void) testCompose2FrameH264BlackBlueCopy
{
  NSString *resFilename;
  
  resFilename = @"AVOfflineComposition32x32BlackBlueTest.plist";
  
  NSDictionary *plistDict = (NSDictionary*) [AVOfflineComposition readPlist:resFilename];
  
  AVOfflineComposition *comp = [AVOfflineComposition aVOfflineComposition];
  
  AVOfflineCompositionNotificationUtil *notificationUtil = [AVOfflineCompositionNotificationUtil aVOfflineCompositionNotificationUtil];
  
  [notificationUtil setupNotification:comp];
  
  [comp compose:plistDict];
  
  // Wait until comp operation either works or fails
  
  BOOL worked = [RegressionTests waitUntilTrue:notificationUtil
                                      selector:@selector(wasSuccessNotificationDelivered)
                                   maxWaitTime:MAX_WAIT_TIME];
  NSAssert(worked, @"worked");
  
  // Verify that the correct properties were parsed from the plist
  
  NSAssert([comp.source isEqualToString:resFilename], @"source");
  
  NSString *tmpDir = NSTemporaryDirectory();
  NSString *tmpPath = [tmpDir stringByAppendingString:@"AVOfflineComposition32x32BlackBlueTest.mvid"];
  
  NSAssert([comp.destination isEqualToString:tmpPath], @"source");
  
  NSAssert(comp.compDuration == 0.13f, @"compDuration");
  
  NSAssert(comp.compFPS == 15.0f, @"compFPS");
  
  NSAssert(comp.numFrames == 2, @"numFrames");
  
  // BG color is black (the default)
  
  NSString *bgColor = [comp backgroundColorStr];
  
  NSAssert([bgColor isEqualToString:@"#000000FF"], @"background color");
  
  // width x height
  
  NSAssert(CGSizeEqualToSize(comp.compSize, CGSizeMake(32,32)), @"size");
  
  // Open .mvid file and verify header info
  
  AVMvidFrameDecoder *frameDecoder = [AVMvidFrameDecoder aVMvidFrameDecoder];
  
  worked = [frameDecoder openForReading:comp.destination];
	NSAssert(worked, @"frameDecoder openForReading failed");
  
  //NSAssert(frameDecoder.frameDuration == 0.66, @"frameDuration");
  NSAssert(frameDecoder.numFrames == 2, @"numFrames");
  
  // Dump each Frame 
  
  if (TRUE) {
    [self dumpEachFrameUtil:frameDecoder];
  }
  
  return;
}

// This test case includes 2 frames that contain static images. This come is trivial
// in that it just pastes one image as the background and then resizes another image
// and pastes it in the middle of the first at frame 2. This logic is testing the
// static image frame loading logic, it checks the resources, then the tmp dir, then
// in the bundle with a generic name that could be expanded with a @2x.png suffix.

+ (void) testCompose2FrameStaticImageTest
{
  NSString *resFilename;
  
  resFilename = @"AVOfflineCompositionTwoFrameStaticImageTest.plist";
  
  NSDictionary *plistDict = (NSDictionary*) [AVOfflineComposition readPlist:resFilename];
  
  AVOfflineComposition *comp = [AVOfflineComposition aVOfflineComposition];
  
  AVOfflineCompositionNotificationUtil *notificationUtil = [AVOfflineCompositionNotificationUtil aVOfflineCompositionNotificationUtil];
  
  [notificationUtil setupNotification:comp];
  
  [comp compose:plistDict];
  
  // Wait until comp operation either works or fails
  
  BOOL worked = [RegressionTests waitUntilTrue:notificationUtil
                                      selector:@selector(wasSuccessNotificationDelivered)
                                   maxWaitTime:MAX_WAIT_TIME];
  NSAssert(worked, @"worked");
  
  // Verify that the correct properties were parsed from the plist
  
  NSAssert([comp.source isEqualToString:resFilename], @"source");
  
  NSString *tmpDir = NSTemporaryDirectory();
  NSString *tmpPath = [tmpDir stringByAppendingString:@"AVOfflineCompositionTwoFrameStaticImageTest.mvid"];
  
  NSAssert([comp.destination isEqualToString:tmpPath], @"source");
  
  NSAssert(comp.compDuration == 2.0f, @"compDuration");
  
  NSAssert(comp.compFPS == 1.0f, @"compFPS");
  
  NSAssert(comp.numFrames == 2, @"numFrames");
    
  // width x height
  
  NSAssert(CGSizeEqualToSize(comp.compSize, CGSizeMake(256,256)), @"size");
  
  // Open .mvid file and verify header info
  
  AVMvidFrameDecoder *frameDecoder = [AVMvidFrameDecoder aVMvidFrameDecoder];
  
  worked = [frameDecoder openForReading:comp.destination];
	NSAssert(worked, @"frameDecoder openForReading failed");
  
  NSAssert(frameDecoder.frameDuration == 1, @"frameDuration");
  NSAssert(frameDecoder.numFrames == 2, @"numFrames");
  
  // Dump each Frame
  
  if (FALSE) {
    [self dumpEachFrameUtil:frameDecoder];
  }
  
  return;
}

// This test case creates a 2 frame animation with a background color and a text
// string rendered over the background image only in the second frame.

+ (void) testCompose2FrameStaticImageAndTextTest
{
  NSString *resFilename;
  
  resFilename = @"AVOfflineCompositionTwoFrameStaticImageAndTextTest.plist";
  
  NSDictionary *plistDict = (NSDictionary*) [AVOfflineComposition readPlist:resFilename];
  
  AVOfflineComposition *comp = [AVOfflineComposition aVOfflineComposition];
  
  AVOfflineCompositionNotificationUtil *notificationUtil = [AVOfflineCompositionNotificationUtil aVOfflineCompositionNotificationUtil];
  
  [notificationUtil setupNotification:comp];
  
  [comp compose:plistDict];
  
  // Wait until comp operation either works or fails
  
  BOOL worked = [RegressionTests waitUntilTrue:notificationUtil
                                      selector:@selector(wasSuccessNotificationDelivered)
                                   maxWaitTime:MAX_WAIT_TIME];
  NSAssert(worked, @"worked");
  
  // Verify that the correct properties were parsed from the plist
  
  NSAssert([comp.source isEqualToString:resFilename], @"source");
  
  NSString *tmpDir = NSTemporaryDirectory();
  NSString *tmpPath = [tmpDir stringByAppendingString:@"AVOfflineCompositionTwoFrameStaticImageAndTextTest.mvid"];
  
  NSAssert([comp.destination isEqualToString:tmpPath], @"source");
  
  NSAssert(comp.compDuration == 2.0f, @"compDuration");
  
  NSAssert(comp.compFPS == 1.0f, @"compFPS");
  
  NSAssert(comp.numFrames == 2, @"numFrames");
  
  // width x height
  
  NSAssert(CGSizeEqualToSize(comp.compSize, CGSizeMake(256,256)), @"size");
  
  // Open .mvid file and verify header info
  
  AVMvidFrameDecoder *frameDecoder = [AVMvidFrameDecoder aVMvidFrameDecoder];
  
  worked = [frameDecoder openForReading:comp.destination];
	NSAssert(worked, @"frameDecoder openForReading failed");
  
  NSAssert(frameDecoder.frameDuration == 1, @"frameDuration");
  NSAssert(frameDecoder.numFrames == 2, @"numFrames");
  
  // Dump each Frame
  
  if (FALSE) {
    [self dumpEachFrameUtil:frameDecoder];
  }
  
  return;
}

// This text case checks comp font settings and clip specific font settings.

+ (void) testCompose2FrameStaticImageAndTwoTextTest
{
  NSString *resFilename;
  
  resFilename = @"AVOfflineCompositionTwoFrameStaticImageAndTwoTextTest.plist";
  
  NSDictionary *plistDict = (NSDictionary*) [AVOfflineComposition readPlist:resFilename];
  
  AVOfflineComposition *comp = [AVOfflineComposition aVOfflineComposition];
  
  AVOfflineCompositionNotificationUtil *notificationUtil = [AVOfflineCompositionNotificationUtil aVOfflineCompositionNotificationUtil];
  
  [notificationUtil setupNotification:comp];
  
  [comp compose:plistDict];
  
  // Wait until comp operation either works or fails
  
  BOOL worked = [RegressionTests waitUntilTrue:notificationUtil
                                      selector:@selector(wasSuccessNotificationDelivered)
                                   maxWaitTime:MAX_WAIT_TIME];
  NSAssert(worked, @"worked");
  
  // Verify that the correct properties were parsed from the plist
  
  NSAssert([comp.source isEqualToString:resFilename], @"source");
  
  NSString *tmpDir = NSTemporaryDirectory();
  NSString *tmpPath = [tmpDir stringByAppendingString:@"AVOfflineCompositionTwoFrameStaticImageAndTwoTextTest.mvid"];
  
  NSAssert([comp.destination isEqualToString:tmpPath], @"source");
  
  NSAssert(comp.compDuration == 2.0f, @"compDuration");
  
  NSAssert(comp.compFPS == 1.0f, @"compFPS");
  
  NSAssert(comp.numFrames == 2, @"numFrames");
  
  // width x height
  
  NSAssert(CGSizeEqualToSize(comp.compSize, CGSizeMake(256,256)), @"size");
  
  // Open .mvid file and verify header info
  
  AVMvidFrameDecoder *frameDecoder = [AVMvidFrameDecoder aVMvidFrameDecoder];
  
  worked = [frameDecoder openForReading:comp.destination];
	NSAssert(worked, @"frameDecoder openForReading failed");
  
  NSAssert(frameDecoder.frameDuration == 1, @"frameDuration");
  NSAssert(frameDecoder.numFrames == 2, @"numFrames");
  
  // Dump each Frame
  
  if (FALSE) {
    [self dumpEachFrameUtil:frameDecoder];
  }
  
  return;
}

// This test case the may text frames render logic with one single render operation.

+ (void) testManyTextFieldsOneRender
{
  NSString *resFilename;
  
  resFilename = @"AVOfflineCompositionManyTextFields.plist";
  
  NSDictionary *plistDict = (NSDictionary*) [AVOfflineComposition readPlist:resFilename];
  
  AVOfflineComposition *comp = [AVOfflineComposition aVOfflineComposition];
  
  AVOfflineCompositionNotificationUtil *notificationUtil = [AVOfflineCompositionNotificationUtil aVOfflineCompositionNotificationUtil];
  
  [notificationUtil setupNotification:comp];
  
  [comp compose:plistDict];
  
  // Wait until comp operation either works or fails
  
  BOOL worked = [RegressionTests waitUntilTrue:notificationUtil
                                      selector:@selector(wasSuccessNotificationDelivered)
                                   maxWaitTime:MAX_WAIT_TIME * 5];
  NSAssert(worked, @"worked");
  
  // Verify that the correct properties were parsed from the plist
  
  NSAssert([comp.source isEqualToString:resFilename], @"source");
  
  NSString *tmpDir = NSTemporaryDirectory();
  NSString *tmpPath = [tmpDir stringByAppendingString:@"AVOfflineCompositionManyTextFields.mvid"];
  
  NSAssert([comp.destination isEqualToString:tmpPath], @"source");
  
  NSAssert(comp.compDuration == 10.0f, @"compDuration");
  
  NSAssert(comp.compFPS == 30.0f, @"compFPS");
  
  NSAssert(comp.numFrames == 300, @"numFrames");
  
  // width x height
  
  NSAssert(CGSizeEqualToSize(comp.compSize, CGSizeMake(256,256)), @"size");
  
  // Open .mvid file and verify header info
  
  AVMvidFrameDecoder *frameDecoder = [AVMvidFrameDecoder aVMvidFrameDecoder];
  
  worked = [frameDecoder openForReading:comp.destination];
	NSAssert(worked, @"frameDecoder openForReading failed");
  
  NSAssert(frameDecoder.frameDuration == 1.0f/30.0f, @"frameDuration");
  NSAssert(frameDecoder.numFrames == 300, @"numFrames");
  
  // Dump each Frame
  
  if (FALSE) {
    [self dumpEachFrameUtil:frameDecoder];
  }
  
  // Delete output file

  worked = [[NSFileManager defaultManager] removeItemAtPath:frameDecoder.filePath error:nil];
  NSAssert(worked, @"could not remove tmp file");
  
  return;
}

// This test case attempts to reproduce a text render crash in CoreText
// that could happen when text rendering is done on a secondary thread.
// The workaround that renders CoreText with calls back into the main
// thread should avoid this crash.

+ (void) testManyTextFieldsRenderedConcurrently
{
#define NUM_TIMES 1
//#define NUM_TIMES 10
  
  for (int outerRenderLoops=0; outerRenderLoops < NUM_TIMES; outerRenderLoops++) @autoreleasepool {
  
  NSMutableArray *mNotificationUtilObjects = [NSMutableArray array];
  NSMutableArray *mTmpPaths = [NSMutableArray array];

//#define NUM_COMPS 2
#define NUM_COMPS 10
    
  for (int i=0; i < NUM_COMPS; i++) {
    NSString *resFilename;
    
    resFilename = @"AVOfflineCompositionManyTextFields.plist";
    
    NSDictionary *original_plistDict = (NSDictionary*) [AVOfflineComposition readPlist:resFilename];
    
    // Each render operation runs in a secondary thread and each must render into
    // a different output file to avoid writing over each other.
    
    NSMutableDictionary *mplistDict = [NSMutableDictionary dictionaryWithDictionary:original_plistDict];
    
    NSString *tmpPath = [AVFileUtil generateUniqueTmpPath];
    
    [mplistDict setObject:tmpPath forKey:@"Destination"];
    
    AVOfflineComposition *comp = [AVOfflineComposition aVOfflineComposition];
    
    AVOfflineCompositionNotificationUtil *notificationUtil = [AVOfflineCompositionNotificationUtil aVOfflineCompositionNotificationUtil];
    
    [notificationUtil setupNotification:comp];
    
    // Kick off secondary thread that does the text rendering and composition
    [comp compose:mplistDict];
    
    [mNotificationUtilObjects addObject:notificationUtil];
    [mTmpPaths addObject:tmpPath];
  }
  
  NSLog(@"waiting until render threads are completed");
  
  // Now wait for each operation to be done, 1 at a time
  
  for (int i=0; i < NUM_COMPS; i++) {
    AVOfflineCompositionNotificationUtil *notificationUtil = [mNotificationUtilObjects objectAtIndex:i];
    
    // Wait until comp operation either works or fails
    
    BOOL worked = [RegressionTests waitUntilTrue:notificationUtil
                                        selector:@selector(wasSuccessNotificationDelivered)
                                     maxWaitTime:MAX_WAIT_TIME * 20];
    NSAssert(worked, @"worked");
  }
  
  NSLog(@"done render threads");

  // Now wait for each operation to be done, 1 at a time
  
  for (int i=0; i < NUM_COMPS; i++) {
    NSString *tmpPath = [mTmpPaths objectAtIndex:i];
    
    // Delete rendered comp file
    
    BOOL worked;
    NSError *error;
    NSError **errorPtr = &error;
    worked = [[NSFileManager defaultManager] removeItemAtPath:tmpPath error:errorPtr];
    if (!worked) {
      NSAssert(worked, @"could not remove tmp file: %@", *errorPtr);
    }
  }
 
  } // outer render loops, pop autorelease pool
    
  return;
}

// Render a 256 x 256 comp at 2x scale, the result is a 512 x 512 comp

+ (void) testCompose2xComp
{
  NSString *resFilename;
  
  resFilename = @"AVOfflineComposition2xScale.plist";
  
  NSDictionary *plistDict = (NSDictionary*) [AVOfflineComposition readPlist:resFilename];
  
  AVOfflineComposition *comp = [AVOfflineComposition aVOfflineComposition];
  
  AVOfflineCompositionNotificationUtil *notificationUtil = [AVOfflineCompositionNotificationUtil aVOfflineCompositionNotificationUtil];
  
  [notificationUtil setupNotification:comp];
  
  [comp compose:plistDict];
  
  // Wait until comp operation either works or fails
  
  BOOL worked = [RegressionTests waitUntilTrue:notificationUtil
                                      selector:@selector(wasSuccessNotificationDelivered)
                                   maxWaitTime:MAX_WAIT_TIME];
  NSAssert(worked, @"worked");
  
  // Verify that the correct properties were parsed from the plist
  
  NSAssert([comp.source isEqualToString:resFilename], @"source");
  
  NSString *tmpDir = NSTemporaryDirectory();
  NSString *tmpPath = [tmpDir stringByAppendingString:@"AVOfflineComposition2xScale.mvid"];
  
  NSAssert([comp.destination isEqualToString:tmpPath], @"source");
  
  NSAssert(comp.compDuration == 10.0f, @"compDuration");
  
  NSAssert(comp.compFPS == 10.0f, @"compFPS");
  
  NSAssert(comp.numFrames == 100, @"numFrames");
  
  // width x height (does not include 2x scale)
  
  NSAssert(CGSizeEqualToSize(comp.compSize, CGSizeMake(256,256)), @"size");
  
  // Open .mvid file and verify header info
  
  AVMvidFrameDecoder *frameDecoder = [AVMvidFrameDecoder aVMvidFrameDecoder];
  
  worked = [frameDecoder openForReading:comp.destination];
	NSAssert(worked, @"frameDecoder openForReading failed");
  
  NSAssert(frameDecoder.numFrames == 100, @"numFrames");

  // The size of the actual rendered movie is 512 x 512
  
  NSAssert(frameDecoder.width == 512, @"width");
  NSAssert(frameDecoder.height == 512, @"height");
  
  // Dump each Frame
  
  if (FALSE) {
    [self dumpEachFrameUtil:frameDecoder];
  }
  
  // Delete output file
  
  worked = [[NSFileManager defaultManager] removeItemAtPath:frameDecoder.filePath error:nil];
  NSAssert(worked, @"could not remove tmp file");
  
  return;
}

@end // AVOfflineCompositionTests
