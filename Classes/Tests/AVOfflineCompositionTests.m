//
//  AVOfflineCompositionTests.m
//
//  Created by Moses DeJong on 3/31/12.
//
// Regression tests for offline composition operation module.
// This module combines video clips into a single movie.

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

#import "AVOfflineComposition.h"

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

@property (nonatomic, copy) NSString *errorString;

@property (nonatomic, copy) NSString *source;

@property (nonatomic, copy) NSString *destination;

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

  NSAssert([comp.source isEqualToString:@"AVOfflineCompositionTwoFrameBlueBackgroundTest.plist"], @"source");

  NSString *tmpDir = NSTemporaryDirectory();
  NSString *tmpPath = [tmpDir stringByAppendingString:@"AVOfflineCompositionTwoFrameBlueBackgroundTest.mvid"];
  
  NSAssert([comp.destination isEqualToString:tmpPath], @"source");
  
  NSAssert(comp.compDuration == 1.0f, @"compDuration");

  NSAssert(comp.compFPS == 2.0f, @"compFPS");

  NSAssert(comp.numFrames == 2, @"numFrames");
  
  NSAssert(comp.compClips == nil, @"compClips");
  
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
    
    worked = [frameDecoder allocateDecodeResources];
    NSAssert(worked, @"allocateDecodeResources");
    
    for (NSUInteger frame = 0; frame < frameDecoder.numFrames; frame++) {
      UIImage *img = [frameDecoder advanceToFrame:frame];
      
      // Write image as PNG
      
      NSString *tmpPNGPath = [tmpDir stringByAppendingFormat:@"Frame%d.png", (frame + 1)];
      
      NSData *data = [NSData dataWithData:UIImagePNGRepresentation(img)];
      [data writeToFile:tmpPNGPath atomically:YES];
      NSLog(@"wrote %@", tmpPNGPath);
    }
    
  }
    
  return;
}

// FIXME: provide plist that does not have correct parameters and test for failed notification

@end // AVOfflineCompositionTests
