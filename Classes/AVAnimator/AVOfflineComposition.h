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
// is posted when the composition operation has completed. The output of a comp
// is always 24BPP, any alpha pixels are blended over the background color.

// COMP SETTINGS:
//   "ABOUT" string description of the comp
//   "Source" string name of plist file, used in error reporting
//   "Destination" string name of output .mvid file in tmp dir (if not fully qualified)
//   "CompDurationSeconds" float length of comp
//   "CompFramesPerSecond" float FPS
//   "CompWidth" int width of the whole comp
//   "CompHeight" int height of the whole comp
//   "CompBackgroundColor" string #RRGGBB value indicating a color (defaults to black)
//   "CompScale" optional int to indicate scale, either 1, 2, or 0 for screen scale (defaults to 1)
//   "Font" optional string name of iOS font (defaults to system font)
//   "FontSize" optional int font size (defaults to 14)
//   "FontColor" optional string #RRGGBB value indicating a color (defaults to black)
//   "DeleteTmpFiles" optional boolean to indicate if decode tmp files are deleted (defaults to TRUE)
//   "HighQualityInterpolation" optional boolean to indicate if a movie/image to be resized/scaled during
//     a render operation should use the 2x slow high quality interpolation mode. (defaults to FALSE).
//
// CLIP SETTINGS:
//   "ClipSource" string name of H264 or MVID file, image name for "image", literal text for "text" type
//   "ClipType" string type ("mvid", "h264", "image", "text")
//   "ClipX" int X coordinate of clip where 0,0 is in upper left corner of comp
//   "ClipY" int Y coordinate of clip where 0,0 is in upper left corner of comp
//   "ClipWidth" int width of the rectangular bounding box for the clip
//   "ClipHeight" int height of the rectangular bounding box for the clip
//   "ClipStartSeconds" float time in seconds when clip starts
//   "ClipEndSeconds" float time in second when clip ends
//   "ClipScaleFramePerSecond" optional boolean indicates that clip FPS should be scaled
//   "Font" optional string name of iOS font
//   "FontSize" optional int font size
//   "FontColor" optional string #RRGGBB value indicating a color

// For a "Font", indicate the name of an iOS font from one of the support font names:
// http://daringfireball.net/misc/2007/07/iphone-osx-fonts.pdf

#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>

extern NSString * const AVOfflineCompositionCompletedNotification;
extern NSString * const AVOfflineCompositionFailedNotification;

@class MutableAttrString;

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
  NSString   *m_defaultFont;
  NSUInteger m_defaultFontSize;
  CGColorRef m_defaultFontColor;
  NSUInteger m_compScale;
  BOOL       m_deleteTmpFiles;
  BOOL       m_highQualityInterpolation;
  // These next members act only as pointers to objects, the lifetime of
  // these two resources is not managed by holding ref counts.
  MutableAttrString *m_mAttrString;
  CGContextRef m_bitmapContext;
  CGRect     m_renderBounds;
}

@property (nonatomic, copy) NSString *destination;

// The error string indicates additional information and is set in the case
// where AVOfflineCompositionFailedNotification is delivered.

@property (nonatomic, copy) NSString *errorString;

+ (AVOfflineComposition*) aVOfflineComposition;

// Initiate a composition operation given info about the composition
// contained in the indicated dictionary.

- (void) compose:(NSDictionary*)compDict;

// Load plist file from a resource file with the given name

+ (id) readPlist:(NSString*)resFileName;

@end
