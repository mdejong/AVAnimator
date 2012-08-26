//
//  AVOfflineComposition.h
//  Created by Moses DeJong on 3/31/12.
//
//  License terms defined in License.txt.
//
// An offline composition creates a new movie file by combining existing
// clips into a single movie. Clips can be concatenated together to create
// a large clip. Clips can also be composed together, so that one clip
// is displayed over another. A clip with a full alpha channel can be used
// so that the alpha channel blends into the background. Input to this module
// is a PLIST file that contains specific info to identify each clip.
// The composition operation is executed in a background thread, a notification
// is posted when the composition operation has completed.

#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>

extern NSString * const AVOfflineCompositionCompletedNotification;
extern NSString * const AVOfflineCompositionFailedNotification;

@interface AVOfflineComposition : NSObject
{
@private
  NSString   *m_errorString;
  NSString   *m_source;
  NSString   *m_destination;
  NSArray    *m_compClips;
  float      m_compDuration;
  float      m_compFPS;
  float      m_compFrameDuration;
  NSUInteger m_numFrames;
  CGColorRef m_backgroundColor;
  CGSize     m_compSize;
}

@property (nonatomic, copy) NSString *destination;

+ (AVOfflineComposition*) aVOfflineComposition;

// Initiate a composition operation given info about the composition
// contained in the indicated dictionary.

- (void) compose:(NSDictionary*)compDict;

// Load plist file from a resource file with the given name

+ (id) readPlist:(NSString*)resFileName;

@end
