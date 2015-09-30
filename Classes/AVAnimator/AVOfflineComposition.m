//
//  AVOfflineComposition.m
//  Created by Moses DeJong on 3/31/12.
//
//  License terms defined in License.txt.

#import "AVOfflineComposition.h"

#if __has_feature(objc_arc)
#else
#import "AutoPropertyRelease.h"
#endif // objc_arc

#import "CGFrameBuffer.h"

#import "AVMvidFileWriter.h"

#import "AVFrame.h"

#import "AVMvidFrameDecoder.h"

#import <QuartzCore/QuartzCore.h>

#import "AVAssetReaderConvertMaxvid.h"

#import "AVFileUtil.h"

#import "MutableAttrString.h"

//#if defined(DEBUG)
//# define LOGGING
//#endif // DEBUG

// Notification name constants

NSString * const AVOfflineCompositionCompletedNotification = @"AVOfflineCompositionCompletedNotification";

NSString * const AVOfflineCompositionFailedNotification = @"AVOfflineCompositionFailedNotification";

static
int screenScale = 0;

typedef enum
{
  AVOfflineCompositionClipTypeMvid = 0,
  AVOfflineCompositionClipTypeH264,
  AVOfflineCompositionClipTypeImage,
  AVOfflineCompositionClipTypeText,
} AVOfflineCompositionClipType;

// Util object, one is created for each clip to be rendered in the composition

@interface AVOfflineCompositionClip : NSObject
{
  NSString   *m_clipSource;
  UIImage    *m_image;
  AVMvidFrameDecoder *m_mvidFrameDecoder;
@public
  AVOfflineCompositionClipType clipType;
  NSInteger clipX;
  NSInteger clipY;
  NSInteger clipWidth;
  NSInteger clipHeight;
  float     clipStartSeconds;
  float     clipEndSeconds;
  float     clipFrameDuration;
  NSInteger clipNumFrames;
  
  NSString   *m_font;
  NSUInteger m_fontSize;
  CGColorRef m_fontColor;
}

@property (nonatomic, copy) NSString *clipSource;

@property (nonatomic, retain) UIImage *image;

@property (nonatomic, retain) AVMvidFrameDecoder *mvidFrameDecoder;

@property (nonatomic, copy) NSString *font;

+ (AVOfflineCompositionClip*) aVOfflineCompositionClip;

@end

// Private API

@interface AVOfflineComposition ()

// Read a plist from a resource file. Either a NSDictionary or NSArray

+ (id) readPlist:(NSString*)resFileName;

- (BOOL) parseToplevelProperties:(NSDictionary*)compDict;

- (BOOL) parseClipProperties:(NSDictionary*)compDict;

- (void) notifyCompositionCompleted;

- (void) notifyCompositionFailed;

- (NSString*) backgroundColorStr;

- (BOOL) composeFrames;

- (void) queryScreenScale;

- (BOOL) composeClips:(NSUInteger)frame
        bitmapContext:(CGContextRef)bitmapContext;

@property (nonatomic, copy) NSString *source;

@property (nonatomic, copy) NSArray *compClips;

@property (nonatomic, assign) float compDuration;

@property (nonatomic, assign) float compFPS;

@property (nonatomic, assign) float compFrameDuration;

@property (nonatomic, assign) NSUInteger numFrames;

@property (nonatomic, assign) CGSize compSize;

@property (nonatomic, copy) NSString *defaultFont;

@property (nonatomic, assign) NSUInteger defaultFontSize;

@property (nonatomic, assign) NSUInteger compScale;

@end

// Implementation of AVOfflineComposition

@implementation AVOfflineComposition

@synthesize errorString = m_errorString;

@synthesize source = m_source;

@synthesize destination = m_destination;

@synthesize compClips = m_compClips;

@synthesize compDuration = m_compDuration;

@synthesize numFrames = m_numFrames;

@synthesize compFPS = m_compFPS;

@synthesize compFrameDuration = m_compFrameDuration;

@synthesize compSize = m_compSize;

@synthesize defaultFont = m_defaultFont;

@synthesize defaultFontSize = m_defaultFontSize;

@synthesize compScale = m_compScale;

// Constructor

+ (AVOfflineComposition*) aVOfflineComposition
{
  AVOfflineComposition *obj = [[AVOfflineComposition alloc] init];
#if __has_feature(objc_arc)
  return obj;
#else
  return [obj autorelease];
#endif // objc_arc
}

- (void) dealloc
{
  if (self->m_backgroundColor) {
    CGColorRelease(self->m_backgroundColor);
  }
  if (self->m_defaultFontColor) {
    CGColorRelease(self->m_defaultFontColor);
  }
#if __has_feature(objc_arc)
#else
  [AutoPropertyRelease releaseProperties:self thisClass:AVOfflineComposition.class];
  [super dealloc];
#endif // objc_arc
}

// Initiate a composition operation given info about the composition
// contained in the indicated dictionary.

- (void) compose:(NSDictionary*)compDict
{
  if (screenScale == 0) {
    // Init static variable the first time compose is invoke
    
    if ([NSThread isMainThread]) {
      [self queryScreenScale];
    } else {
      [self performSelectorOnMainThread: @selector(queryScreenScale) withObject:nil waitUntilDone:YES];
    }
  }
  
  NSAssert(compDict, @"compDict must not be nil");
  [NSThread detachNewThreadSelector:@selector(composeInSecondaryThread:) toTarget:self withObject:compDict];
}

// Execute a compose operation in a background thread. This is a thread entry point, so
// create a pool and release it on exit.

- (void) composeInSecondaryThread:(NSDictionary*)compDict
{
  @autoreleasepool {
  
  BOOL worked;
  
  NSAssert(compDict, @"compDict must not be nil");

  NSAssert([NSThread isMainThread] == FALSE, @"isMainThread");

#ifdef LOGGING
    NSLog(@"parsing properties %p", self);
#endif
    
  @autoreleasepool {
    worked = [self parseToplevelProperties:compDict];
  }
    
  if (worked) {
#ifdef LOGGING
    NSLog(@"starting comp %p", self);
#endif
    worked = [self composeFrames];
#ifdef LOGGING
    NSLog(@"finished comp %p", self);
#endif
  }

  if (worked) {
    // Deliver success notification
#ifdef LOGGING
    NSLog(@"notifyCompositionCompleted %p", self);
#endif
    [self notifyCompositionCompleted];
  } else {
#ifdef LOGGING
    NSLog(@"notifyCompositionFailed %p", self);
#endif
    [self notifyCompositionFailed];
  }
  
  }
  return;
}

+ (id) readPlist:(NSString*)resFileName
{
  NSData *plistData;  
  NSString *error = nil;
  NSPropertyListFormat format;  
  id plist;
  
  NSString *resPath = [[NSBundle mainBundle] pathForResource:resFileName ofType:@""];  
  plistData = [NSData dataWithContentsOfFile:resPath];   
  
  plist = [NSPropertyListSerialization propertyListFromData:plistData mutabilityOption:NSPropertyListImmutable format:&format errorDescription:&error];
  if (!plist) {
    NSLog(@"Error reading plist from file '%s', error = '%s'", [resFileName UTF8String], [error UTF8String]);
#if __has_feature(objc_arc)
#else
    [error release];
#endif // objc_arc
  }
  return plist;  
}

- (CGColorRef) createCGColor:(CGFloat)red
                       green:(CGFloat)green
                        blue:(CGFloat)blue
                       alpha:(CGFloat)alpha
CF_RETURNS_RETAINED
{
  // FIXME: should this be RGB or sRGB colorspace?
  CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
  CGFloat components[4] = {red, green, blue, alpha};
  CGColorRef cgColor = CGColorCreate(colorSpace, components);
  CGColorSpaceRelease(colorSpace);
  return cgColor;
}

- (CGColorRef) createColorWithHexString:(NSString*)stringToConvert
CF_RETURNS_RETAINED
{
  NSScanner *scanner = [NSScanner scannerWithString:stringToConvert];
  unsigned hex;
  if (![scanner scanHexInt:&hex]) return NULL;
  int r = (hex >> 16) & 0xFF;
  int g = (hex >> 8) & 0xFF;
  int b = (hex) & 0xFF;
  
  CGFloat redPercentage = r / 255.0f;
  CGFloat greenPercentage = g / 255.0f;
  CGFloat bluePercentage = b / 255.0f;
  CGFloat alphaPercentage = 1.0f;
  
  return [self createCGColor:redPercentage green:greenPercentage blue:bluePercentage alpha:alphaPercentage];
}

// Return the parsed core graphics color as a "#RRGGBBAA" string value

+ (NSString*) cgColorToString:(CGColorRef)cgColorRef
{
  const CGFloat *components = CGColorGetComponents(cgColorRef);
  int red = (int)(components[0] * 255);
  int green = (int)(components[1] * 255);
  int blue = (int)(components[2] * 255);
  int alpha = (int)(components[3] * 255);
  return [NSString stringWithFormat:@"#%0.2X%0.2X%0.2X%0.2X", red, green, blue, alpha];
}

- (NSString*) backgroundColorStr
{
  return [self.class cgColorToString:self->m_backgroundColor];
}

// Parse color from a string specification, must be "#RRGGBB" or "#RRGGBBAA"

- (CGColorRef) createParsedCGColor:(NSString*)colorSpec
CF_RETURNS_RETAINED
{
  int len = (int) [colorSpec length];
  if (len != 7 && len != 9) {
    self.errorString = @"CompBackgroundColor invalid";
    return NULL;
  }
  
  char c = (char) [colorSpec characterAtIndex:0];
  
  if (c != '#') {
    self.errorString = @"CompBackgroundColor invalid : must begin with #";
    return NULL;
  }
  
  NSString *stringNoPound = [colorSpec substringFromIndex:1];
  
  CGColorRef colorRef = [self createColorWithHexString:stringNoPound];
  
  if (colorRef == NULL) {
    self.errorString = @"CompBackgroundColor invalid";
    return NULL;
  }
  
  return colorRef;  
}

// Parse expected properties defined in the plist file and store them as properties of the
// composition object.

- (BOOL) parseToplevelProperties:(NSDictionary*)compDict
{
  self.errorString = nil;
  
  // Source is an optional string to indicate the plist data was parsed from
  
  self.source = [compDict objectForKey:@"Source"];
  
  // Destination is the output file name

  NSString *destination = [compDict objectForKey:@"Destination"];
  
  if (destination == nil) {
    self.errorString = @"Destination not found";
    return FALSE;
  }

  if ([destination length] == 0) {
    self.errorString = @"Destination invalid";
    return FALSE;
  }
  
  if ([destination characterAtIndex:0] == '/') {
    // Destination path is already fully qualified
    self.destination = destination;
  } else {
    NSString *tmpDir = NSTemporaryDirectory();
    NSString *tmpPath = [tmpDir stringByAppendingString:destination];
    self.destination = tmpPath;
  }
  
  // CompDurationSeconds indicates the total composition duration in floating point seconds
  
  NSNumber *compDurationSecondsNum = [compDict objectForKey:@"CompDurationSeconds"];
  float compDurationSeconds;

  if (compDurationSecondsNum == nil) {
    self.errorString = @"CompDurationSeconds not found";
    return FALSE;
  }
  
  compDurationSeconds = [compDurationSecondsNum floatValue];
  if (compDurationSeconds <= 0.0f) {
    self.errorString = @"CompDurationSeconds range";
    return FALSE;
  }
  
  self.compDuration = compDurationSeconds;
  
  // CompBackgroundColor defines a #RRGGBB string that indicates the background
  // color for the whole composition. By default, this color is black.
  
  NSString *bgColorStr = [compDict objectForKey:@"CompBackgroundColor"];
  
  if (bgColorStr == nil) {
    bgColorStr = @"#000000";
  }
  
  self->m_backgroundColor = [self createParsedCGColor:bgColorStr];
  
  if (self->m_backgroundColor == NULL) {
    return FALSE;
  }
  
  // CompFramesPerSecond is a floating point number that indicates how many frames per second
  // the resulting composition will be. This field is required.
  // Common Values: 1, 2, 15, 24, 29.97, 30, 48, 60
  
  NSNumber *compFramesPerSecondNum = [compDict objectForKey:@"CompFramesPerSecond"];
  float compFramesPerSecond;

  compFramesPerSecond = [compFramesPerSecondNum floatValue];

  self.compFPS = compFramesPerSecond;
  
  // Calculate total number of frames based on total duration and frame duration
  
  float frameDuration = 1.0 / compFramesPerSecond;
  self.compFrameDuration = frameDuration;
  int numFrames = (int) round(self.compDuration / frameDuration);
  self.numFrames = numFrames;
  
  // CompScale
  // 1 indicates normal 1x scale, 1 to 1 ratio between points and pixels (default)
  // 2 indicates 2x scale, 1 pt = 2 px
  // 0 indicate that the screen scale will be queried
  
  NSNumber *compScaleNum = [compDict objectForKey:@"CompScale"];
  
  NSInteger compScale;
  
  if (compScaleNum == nil) {
    compScale = 1;
  } else {
    compScale = [compScaleNum intValue];
    if (compScale == 0) {
      NSAssert(screenScale != 0, @"screenScale is zero");
      compScale = screenScale;
    } else if (compScale == 1 || compScale == 2) {
      // Nop
    } else {
      self.errorString = @"CompScale invalid";
      return FALSE;
    }
  }
  self.compScale = compScale;
  
  // Parse CompWidth and CompHeight to define size of movie
  
  NSNumber *compWidthNum = [compDict objectForKey:@"CompWidth"];
  
  if (compWidthNum == nil) {
    self.errorString = @"CompWidth not found";
    return FALSE;
  }

  NSNumber *compHeightNum = [compDict objectForKey:@"CompHeight"];

  if (compHeightNum == nil) {
    self.errorString = @"CompHeight not found";
    return FALSE;
  }

  NSInteger compWidth = [compWidthNum intValue];
  NSInteger compHeight= [compHeightNum intValue];

  if (compWidth < 1) {
    self.errorString = @"CompWidth invalid";
    return FALSE;
  }

  if (compHeight < 1) {
    self.errorString = @"CompHeight invalid";
    return FALSE;
  }
  
  self.compSize = CGSizeMake(compWidth, compHeight);

  // font specific options, these default settings apply to any clips
  // in the comp with the "text" type.

  // "Font"
  
  NSString *defaultFontName = [compDict objectForKey:@"Font"];
  NSUInteger defaultFontSize = 14.0;
  
  if (defaultFontName == nil) {
    UIFont *font = [UIFont systemFontOfSize:defaultFontSize];
    defaultFontName = font.fontName;
  } else {
    // Double check that font can be loaded by name
    
    UIFont *font = [UIFont fontWithName:defaultFontName size:defaultFontSize];
    
    if (font == nil) {
      self.errorString = @"default Font invalid";
      return FALSE;
    }
    
    // Use the system font name returned for user supplied name
    
    defaultFontName = font.fontName;
  }
  
  // "FontSize"
  
  NSNumber *defaultFontSizeNum = [compDict objectForKey:@"FontSize"];
  
  if (defaultFontSizeNum != nil) {
    defaultFontSize = [defaultFontSizeNum intValue];
    if (defaultFontSize <= 0) {
      self.errorString = @"FontSize invalid";
      return FALSE;
    }
  }
  
  // "FontColor"
  
  NSString *defaultFontColorStr = [compDict objectForKey:@"FontColor"];
  
  if (defaultFontColorStr == nil) {
    defaultFontColorStr = @"#000000";
  }
  
  self->m_defaultFontColor = [self createParsedCGColor:defaultFontColorStr];
  
  if (self->m_defaultFontColor == NULL) {
    self.errorString = @"FontColor invalid";
    return FALSE;
  }
  
  self.defaultFont = defaultFontName;
  self.defaultFontSize = defaultFontSize;
  
  // "DeleteTmpFiles" boolean property that defaults to TRUE.
  // If TRUE, then delete decompression tmp files once the
  // comp is finished. If FALSE, then the decompressed tmp files
  // are not deleted. If a specific comp needs to make use of
  // the same input movies over and over again, it can speed up
  // multiple comp operations to not delete the tmp files in between
  // comps. This option should be used with care since it is not
  // a good idea to leave lots of large tmp files sitting around
  // as the decompressed tmp files can be very large.
  
  NSNumber *deleteTmpFilesNum = [compDict objectForKey:@"DeleteTmpFiles"];

  BOOL deleteTmpFiles;
  
  if (deleteTmpFilesNum == nil) {
    deleteTmpFiles = TRUE;
  } else {
    deleteTmpFiles = [deleteTmpFilesNum boolValue];
  }
  
  self->m_deleteTmpFiles = deleteTmpFiles;
  
  // HighQualityInterpolation : This setting will enable the higher quality
  // but significantly slower interpolation mode. When an image is resized
  // or scaled by CoreGraphics this mode will use a more complex and slower
  // algo to generate the final pixel. The high quality mode may result in
  // fewer jaggies for certain classes of image data.

  NSNumber *highQualityInterpolationNum = [compDict objectForKey:@"HighQualityInterpolation"];
  
  BOOL highQualityInterpolation;
  
  if (highQualityInterpolationNum == nil) {
    highQualityInterpolation = FALSE;
  } else {
    highQualityInterpolation = [highQualityInterpolationNum boolValue];
  }
  
  self->m_highQualityInterpolation = highQualityInterpolation;
  
  // Parse CompClips, this array of dictionary property is optional

  if ([self parseClipProperties:compDict] == FALSE) {
    return FALSE;
  }
  
  return TRUE;
}

// Parse clip data from PLIST and setup objects that will read clip data
// from files.

- (BOOL) parseClipProperties:(NSDictionary*)compDict
{
  BOOL worked;
  
  NSArray *compClips = [compDict objectForKey:@"CompClips"];
  
  NSMutableArray *mArr = [NSMutableArray array];
  
  int clipOffset = 0;
  for (NSDictionary *clipDict in compClips) {
    // Each element of the CompClips array is parsed and added to the
    // self.compClips as an instance of AVOfflineCompositionClip.
    
    AVOfflineCompositionClip *compClip = [AVOfflineCompositionClip aVOfflineCompositionClip];
    
    // ClipType is a string to indicate the type of movie clip
    
    NSString *clipTypeStr = [clipDict objectForKey:@"ClipType"];
    
    if (clipTypeStr == nil) {
      self.errorString = @"ClipType key missing";
      return FALSE;
    }
    
    AVOfflineCompositionClipType clipType;
    UIImage *staticImage = nil;
    
    if ([clipTypeStr isEqualToString:@"mvid"]) {
      clipType = AVOfflineCompositionClipTypeMvid;
    } else if ([clipTypeStr isEqualToString:@"h264"]) {
      clipType = AVOfflineCompositionClipTypeH264;
    } else if ([clipTypeStr isEqualToString:@"image"]) {
      clipType = AVOfflineCompositionClipTypeImage;
    } else if ([clipTypeStr isEqualToString:@"text"]) {
      clipType = AVOfflineCompositionClipTypeText;
    } else {
      self.errorString = @"ClipType unsupported";
      return FALSE;
    }
    
    // ClipSource is a mvid or H264 movie that frames are loaded from, it could also be an image.
    // Note that for a "text" type, there is no source.
    
    NSString *clipSource = nil;
    
    if (clipType == AVOfflineCompositionClipTypeText) {
      // Store literal text in "clip source"
      
      clipSource = [clipDict objectForKey:@"ClipText"];
      
      if (clipSource == nil) {
        self.errorString = @"ClipText not found";
        return FALSE;
      }
    } else {
      // Movie or static image clip
      
      clipSource = [clipDict objectForKey:@"ClipSource"];
      
      if (clipSource == nil) {
        self.errorString = @"ClipSource not found";
        return FALSE;
      }
      
      // ClipSource could indicate a resource file (the assumed default).
      
      NSString *resPath = [[NSBundle mainBundle] pathForResource:clipSource ofType:@""];
      
      if (resPath != nil) {
        // ClipSource is the name of a resource file
        clipSource = resPath;
        staticImage = [UIImage imageWithContentsOfFile:clipSource];
      } else {
        // If ClipSource is not a resource file, check for a file with that name in the tmp dir
        NSString *tmpDir = NSTemporaryDirectory();
        NSString *tmpPath = [tmpDir stringByAppendingPathComponent:clipSource];
        if ([[NSFileManager defaultManager] fileExistsAtPath:tmpPath]) {
          clipSource = tmpPath;
          staticImage = [UIImage imageWithContentsOfFile:clipSource];
        } else if (clipType == AVOfflineCompositionClipTypeImage) {
          // If the image is not a filename found in the app resources or in the tmp dir, then
          // try to load as a named image. For example, "Foo" could map to "Foo@2x.png" for
          // example, it might also map to "Foo.jpg".
          
          staticImage = [UIImage imageNamed:clipSource];
        } else {
          // Either a mvid or h264 video but the file cannot be found in the
          // tmp dir or in the project resources.
          
          self.errorString = @"ClipSource file not found in tmp dir or resources";
          return FALSE;
        }
      }      
    }
    
    // ClipX, ClipY : signed int
    
    NSNumber *clipXNum = [clipDict objectForKey:@"ClipX"];
    NSNumber *clipYNum = [clipDict objectForKey:@"ClipY"];
    
    if (clipXNum == nil) {
      self.errorString = @"ClipX not found";
      return FALSE;
    }
    if (clipYNum == nil) {
      self.errorString = @"ClipY not found";
      return FALSE;
    }
    
    NSInteger clipX = [clipXNum intValue];
    NSInteger clipY = [clipYNum intValue];
    
    // ClipWidth, ClipHeight unsigned int
    
    NSNumber *clipWidthNum = [clipDict objectForKey:@"ClipWidth"];
    NSNumber *clipHeightNum = [clipDict objectForKey:@"ClipHeight"];
    
    if (clipWidthNum == nil) {
      self.errorString = @"ClipWidth not found";
      return FALSE;
    }
    if (clipHeightNum == nil) {
      self.errorString = @"ClipHeight not found";
      return FALSE;
    }
    
    NSInteger clipWidth = [clipWidthNum intValue];
    NSInteger clipHeight = [clipHeightNum intValue];
    
    if (clipWidth <= 0) {
      self.errorString = @"ClipWidth invalid";
      return FALSE;
    }
    
    if (clipHeight <= 0) {
      self.errorString = @"ClipHeight invalid";
      return FALSE;
    }
    
    // ClipStartSeconds, ClipEndSeconds : float time values
    
    NSNumber *clipStartSecondsNum = [clipDict objectForKey:@"ClipStartSeconds"];
    NSNumber *clipEndSecondsNum = [clipDict objectForKey:@"ClipEndSeconds"];
    
    float clipStartSeconds = [clipStartSecondsNum floatValue];
    float clipEndSeconds = [clipEndSecondsNum floatValue];
    
    if (clipEndSeconds <= clipStartSeconds) {
      self.errorString = @"ClipEndSeconds must be larger than ClipStartSeconds";
      return FALSE;
    }
    
    // ClipScaleFramePerSecond is an optional boolean field that indicates
    // that the FPS (frame duration) of the clip should be scaled so that
    // the total clip duration matches the indicated clip start and end
    // time on the global timeline.
    
    NSNumber *clipScaleFramePerSecondNum = [clipDict objectForKey:@"ClipScaleFramePerSecond"];
    BOOL clipScaleFramePerSecond = FALSE;

    if (clipScaleFramePerSecondNum != nil) {
      clipScaleFramePerSecond = [clipScaleFramePerSecondNum boolValue];
    }
    
    // Fill in fields of AVOfflineCompositionClip
    
    compClip.clipSource = clipSource;
    compClip->clipType = clipType;
    compClip->clipX = clipX;
    compClip->clipY = clipY;
    compClip->clipWidth = clipWidth;
    compClip->clipHeight = clipHeight;
    compClip->clipStartSeconds = clipStartSeconds;
    compClip->clipEndSeconds = clipEndSeconds;    

    NSString *mvidPath= nil;
    
    // FIXME: add support for compressed .mvid res attached to project file
    
    if (clipType == AVOfflineCompositionClipTypeMvid) {
      mvidPath = compClip.clipSource;
    } else if (clipType == AVOfflineCompositionClipTypeH264) {
      // H264 video is supported via decode to .mvid first, then read frames
      // Break path into components, extract the last one, then replace
      // existing extension with .mvid and create a path in the tmp
      // dir that corresponds to the .mvid to be written.

      NSString *tmpDir = NSTemporaryDirectory();
      
      NSString *movPath = compClip.clipSource;
      NSString *movLastPathComponent = [movPath lastPathComponent];
      
      NSString *movPrefix = [movLastPathComponent stringByDeletingPathExtension];
      //NSString *movExtension = [movLastPathComponent pathExtension];

      NSString *mvidFilename = [NSString stringWithFormat:@"%@.mvid", movPrefix];
      mvidPath = [tmpDir stringByAppendingString:mvidFilename];
      
      if ([[NSFileManager defaultManager] fileExistsAtPath:mvidPath] == FALSE) {
        // tmp/XYZ.mvid does not exist, decode from H264 now
        
#if defined(HAS_AVASSET_CONVERT_MAXVID)
        // Decode from h.264 and block the secondary thread waiting on the possibly slow
        // decode operation to finish. If the app were to crash during this decode we
        // do not want to leave a half written .mvid file, so make sure to decode to
        // an unnamed file and then rename the tmp file to XYZ.mvid when completed.
        
        NSString *phonyOutPath = [AVFileUtil generateUniqueTmpPath];
        
        AVAssetReaderConvertMaxvid *converter = [AVAssetReaderConvertMaxvid aVAssetReaderConvertMaxvid];
        converter.assetURL = [NSURL fileURLWithPath:movPath];
        converter.mvidPath = phonyOutPath;
        
        //converter.genAdler = TRUE;
        
#ifdef LOGGING
        NSLog(@"decoding h264 clip asset %@", [movPath lastPathComponent]);
#endif // LOGGING

        worked = [converter blockingDecode];
        
#ifdef LOGGING
        NSLog(@"done decoding h264 clip asset");
#endif // LOGGING
        
        if (worked) {
          // Rename to XYZ.mvid
          
          [AVFileUtil renameFile:phonyOutPath toPath:mvidPath];
        } else {
          // Delete the tmp file, since it was not completed and is just taking up disk space now.
          
          worked = [[NSFileManager defaultManager] removeItemAtPath:phonyOutPath error:nil];
          NSAssert(worked, @"could not remove tmp file");
          worked = FALSE;
        }
#else
        worked = FALSE;
#endif // HAS_AVASSET_CONVERT_MAXVID
        
        if (worked == FALSE) {
          return FALSE;
        }
      }
    }
  
    if (clipType == AVOfflineCompositionClipTypeText) {
      // clip specific font options
      
      // "Font"
      
      NSString *fontName = [clipDict objectForKey:@"Font"];
      NSUInteger fontSize = 0.0;
      
      if (fontName != nil) {
        // Double check that font can be loaded by name
        
        UIFont *font = [UIFont fontWithName:fontName size:14];
        
        if (font == nil) {
          self.errorString = @"clip Font invalid";
          return FALSE;
        }
        
        // Use the system font name returned for user supplied name
        
        fontName = font.fontName;
        
        compClip.font = fontName;
      }
      
      // "FontSize"
      
      NSNumber *fontSizeNum = [clipDict objectForKey:@"FontSize"];
      
      if (fontSizeNum != nil) {
        fontSize = [fontSizeNum intValue];
        if (fontSize <= 0) {
          self.errorString = @"clip FontSize invalid";
          return FALSE;
        }
        
        compClip->m_fontSize = fontSize;
      }
      
      // "FontColor"
      
      NSString *fontColorStr = [clipDict objectForKey:@"FontColor"];
      
      if (fontColorStr != nil) {
        compClip->m_fontColor = [self createParsedCGColor:fontColorStr];
        
        if (compClip->m_fontColor == NULL) {
          self.errorString = @"clip FontColor invalid";
          return FALSE;
        }
      }
    } else if (clipType == AVOfflineCompositionClipTypeImage) {
      if (staticImage == nil) {
        self.errorString = @"ClipSource does not correspond to a file in app resources, the tmp dir, or a named image";
        return FALSE;
      }
      
      compClip.image = staticImage;
    } else if (clipType == AVOfflineCompositionClipTypeMvid || clipType == AVOfflineCompositionClipTypeH264) {
      // Decode frames from input .mvid
      
      AVMvidFrameDecoder *mvidFrameDecoder = [AVMvidFrameDecoder aVMvidFrameDecoder];
      
      worked = [mvidFrameDecoder openForReading:mvidPath];
      if (worked == FALSE) {
        if (clipType == AVOfflineCompositionClipTypeMvid) {
          self.errorString = [NSString stringWithFormat:@"open of ClipSource file failed: %@", compClip.clipSource];
        } else {
          // Opening the decoded .mvid in the tmp dir is what failed
          self.errorString = [NSString stringWithFormat:@"open of decoded ClipSource file failed: %@", mvidPath];          
        }
        return FALSE;
      }
      
      compClip.mvidFrameDecoder = mvidFrameDecoder;
      
      // Grab the clip's frame duration out of the mvid header. This frame duration may
      // not match the frame rate of the whole comp.
      
      compClip->clipFrameDuration = mvidFrameDecoder.frameDuration;
      compClip->clipNumFrames = mvidFrameDecoder.numFrames;
      
      if (clipScaleFramePerSecond) {
        // Calculate a new clipFrameDuration based on duration that this clip will
        // be rendered for on the global timeline.
        
        float totalClipTime = (compClip->clipEndSeconds - compClip->clipStartSeconds);
        float clipFrameDuration = totalClipTime / compClip->clipNumFrames;
        
        compClip->clipFrameDuration = clipFrameDuration;
      }
    } else {
      assert(0);
    }
    
    [mArr addObject:compClip];
    clipOffset++;
  }
  
  self.compClips = [NSArray arrayWithArray:mArr];
  
  return TRUE;
}

// This method will send a notification to indicate that a composition has completed successfully.
// This method must be invoked in the secondary thread

- (void) notifyCompositionCompleted
{
  [self performSelectorOnMainThread:@selector(notifyCompositionCompletedInMainThread) withObject:nil waitUntilDone:TRUE];
}

// This method will send a notification to indicate that a composition has completed successfully.
// This method must be invoked in the main thread.

- (void) notifyCompositionCompletedInMainThread
{
  NSAssert([NSThread isMainThread] == TRUE, @"isMainThread");
  
  [[NSNotificationCenter defaultCenter] postNotificationName:AVOfflineCompositionCompletedNotification
                                                      object:self];	
}

// This method will send a notification to indicate that a composition has failed.

- (void) notifyCompositionFailed
{
  [self performSelectorOnMainThread:@selector(notifyCompositionFailedInMainThread) withObject:nil waitUntilDone:TRUE];
}

// This method will send a notification to indicate that a composition has failed.
// This method must be invoked in the main thread.

- (void) notifyCompositionFailedInMainThread
{
  NSAssert([NSThread isMainThread] == TRUE, @"isMainThread");
  
  [[NSNotificationCenter defaultCenter] postNotificationName:AVOfflineCompositionFailedNotification object:self];	
}

// Main compose frames operation, iterate over each frame, render specific views, then
// write each frame out to the .mvid movie file.

- (BOOL) composeFrames
{
  BOOL retcode = TRUE;
  BOOL worked;
  
  const NSUInteger maxFrame = self.numFrames;

  NSUInteger width = self.compSize.width;
  NSUInteger height = self.compSize.height;
  
  NSUInteger scaledWidth = width;
  NSUInteger scaledHeight = height;
  
  // If the comp scale is actually 2x the double the size of the framebuffer
  
  if (self.compScale == 2) {
    scaledWidth *= 2;
    scaledHeight *= 2;
  }
  
  // Allocate buffer that will contain the rendered frame for each time step
  
  CGFrameBuffer *cgFrameBuffer = [CGFrameBuffer cGFrameBufferWithBppDimensions:24
                                                                         width:scaledWidth
                                                                        height:scaledHeight];
  
  if (cgFrameBuffer == nil) {
    return FALSE;
  }
  
  // Wrap the pixels in a bitmap context ref
  
  CGContextRef bitmapContext = [cgFrameBuffer createBitmapContext];

  if (bitmapContext == NULL) {
    return FALSE;
  }
  
  // If the comp scale is 2x then push a multiply matrix so that coordinates come
  // out twice as large.
  
  if (self.compScale == 2) {
    CGContextScaleCTM(bitmapContext, 2.0f, 2.0f);
  }
  
  // Testing on iPhone4 and iPad2 indicates that using Medium interpolation shows
  // no real runtime difference as compared to the default mode. But, there
  // can be an improvement in graphical results, so use medium unless the
  // specific high quality flag is set. If the high quality flag is set, this
  // could slow down resizing by 2x so it should only be used if needed.
  
  // http://stackoverflow.com/questions/5685884/imagequality-with-cgcontextsetinterpolationquality

  if (self->m_highQualityInterpolation == FALSE) {
    CGContextSetInterpolationQuality(bitmapContext, kCGInterpolationMedium);
  } else {
    CGContextSetInterpolationQuality(bitmapContext, kCGInterpolationHigh);
  }

  // Before starting to write a new tmp file, make sure the previous output file is deleted.
  // If the system is low on disk space and a render is very large then this would
  // reclaim a bunch of hard drive space from a previous render of this same comp.
  
  if ([AVFileUtil fileExists:self.destination]) {
    worked = [[NSFileManager defaultManager] removeItemAtPath:self.destination error:nil];
    NSAssert(worked, @"could not remove output file");
  }
  
  // Create phony output file, this file will be renamed to XYZ.mvid when done writing
  
  NSString *phonyOutPath = [AVFileUtil generateUniqueTmpPath];
  
  AVMvidFileWriter *fileWriter = [AVMvidFileWriter aVMvidFileWriter];
  NSAssert(fileWriter, @"fileWriter");
  
  fileWriter.mvidPath = phonyOutPath;
  fileWriter.bpp = 24;
  fileWriter.movieSize = CGSizeMake(scaledWidth, scaledHeight);

  fileWriter.frameDuration = self.compFrameDuration;
  fileWriter.totalNumFrames = (int) maxFrame;

  //fileWriter.genAdler = TRUE;
  
  worked = [fileWriter open];
  if (worked == FALSE) {
    retcode = FALSE;
  }
  
  for (NSUInteger frame = 0; retcode && (frame < maxFrame); frame++) {
    // Clear the entire frame to the background color with a simple fill
    
    CGContextSetFillColorWithColor(bitmapContext, self->m_backgroundColor);
    CGContextFillRect(bitmapContext, CGRectMake(0, 0, width, height));
    
    CGContextSaveGState(bitmapContext);
    
    worked = [self composeClips:frame bitmapContext:bitmapContext];
    
    CGContextRestoreGState(bitmapContext);
    
    if (worked == FALSE) {
      retcode = FALSE;
      break;
    }
    
    // Write frame buffer out to .mvid container
    
    worked = [fileWriter writeKeyframe:(char*)cgFrameBuffer.pixels bufferSize:(int)cgFrameBuffer.numBytes];
    
    if (worked == FALSE) {
      retcode = FALSE;
      break;
    }
  }
  
  [self cleanupClips];
  
  CGContextRelease(bitmapContext);
  
  if (worked) {
    worked = [fileWriter rewriteHeader];
    if (worked == FALSE) {
      retcode = FALSE;
    }
  }
  
  [fileWriter close];
  
  // Rename tmp file to actual output filename on success, otherwise
  // nuke output since writing was unsuccessful and the tmp file
  // for the comp could be quite large.
  
  if (worked) {
    [AVFileUtil renameFile:phonyOutPath toPath:self.destination];
  } else {
    worked = [[NSFileManager defaultManager] removeItemAtPath:phonyOutPath error:nil];
    NSAssert(worked, @"could not remove output file");
    worked = FALSE;
  }
  
#ifdef LOGGING
  if (worked) {
    NSLog(@"Wrote comp file %@", self.destination);
  }
#endif // LOGGING
  
  return retcode;
}

// Iterate over each clip for a specific time and render clips that are visible.

#ifdef LOGGING
#define LOGGING_CLIP_ACTIVE
#endif

- (BOOL) composeClips:(NSUInteger)frame
        bitmapContext:(CGContextRef)bitmapContext
{
  BOOL worked;
  float frameTime = frame * self.compFrameDuration;
  
  if (self.compClips == nil) {
    // No clips
    return TRUE;
  }
  
  int clipOffset = 0;
  for (AVOfflineCompositionClip *compClip in self.compClips)
  @autoreleasepool {
    
    // ClipSource is a mvid or H264 movie that frames are loaded from

    float clipStartSeconds = compClip->clipStartSeconds;
    float clipEndSeconds = compClip->clipEndSeconds;
    
    // Render a specific clip if it the frame time is in [START, END] time bounds    
    
    if (frameTime >= clipStartSeconds && frameTime <= clipEndSeconds) {
      // Render specific frame from this clip
      
#ifdef LOGGING_CLIP_ACTIVE
      NSLog(@"Found clip active for comp time %0.2f, clip %d [%0.2f, %0.2f]", frameTime, clipOffset, clipStartSeconds, clipEndSeconds);
#endif // LOGGING_CLIP_ACTIVE
      
      // clipTime is relative to the start of the clip. Calculate which frame
      // a specific time would map to based on the clip time and the clip frame duration.
      
      float clipTime = frameTime - clipStartSeconds;
      
      // chop to integer : for example a clip duration of 2.0 and a time offset of 1.0
      // would chop to frame 0. Note that clipFrame is not used for an "image" or "text" clip.
      
      NSUInteger clipFrame = 0;
      
      if (compClip->clipType == AVOfflineCompositionClipTypeMvid || compClip->clipType == AVOfflineCompositionClipTypeH264) {
        float clipFrameDuration = compClip->clipFrameDuration;
        clipFrame = (NSUInteger) (clipTime / clipFrameDuration);
        
#ifdef LOGGING_CLIP_ACTIVE
        NSLog(@"clip time %0.2f maps to clip frame %d (duration %0.2f)", clipTime, (int)clipFrame, compClip->clipFrameDuration);
#endif // LOGGING_CLIP_ACTIVE
        
        if (clipFrame >= compClip->clipNumFrames) {
          // If the calculate frame is larger than the last frame in the clip, continue
          // to display the last frame. This can happen when a clip is shorter than
          // the display lenght, so the final frame continues to display.
          
          clipFrame = (compClip->clipNumFrames - 1);
          
#ifdef LOGGING_CLIP_ACTIVE
          NSLog(@"clip frame bound to the final frame %d", (int)clipFrame);
#endif // LOGGING_CLIP_ACTIVE
        }
      }
      
      CGImageRef cgImageRef = NULL;
      
      if (compClip->clipType == AVOfflineCompositionClipTypeMvid ||
          compClip->clipType == AVOfflineCompositionClipTypeH264) {
        AVMvidFrameDecoder *mvidFrameDecoder = compClip.mvidFrameDecoder;
        
#ifdef LOGGING_CLIP_ACTIVE
        NSLog(@"allocate decode resources for clip %d at frame %d", (int)clipOffset, (int)frame);
#endif // LOGGING_CLIP_ACTIVE
        
        worked = [mvidFrameDecoder allocateDecodeResources];
        
        if (worked == FALSE) {
          self.errorString = @"failed to allocate decode resources for clip";
          return FALSE;
        }
        
        // While this advanceToFrame returns a UIImage, we are not actually using
        // and UI layer rendering functions, so it should be thread safe to just
        // hold on to a UIImage and the CGImageRef it contains. Note that we don't
        // care if the frame returned is a duplicate since we just render it.
        
        AVFrame *frame = [mvidFrameDecoder advanceToFrame:clipFrame];
        UIImage *image = frame.image;
        NSAssert(image, @"image");
        cgImageRef = image.CGImage;
      } else if (compClip->clipType == AVOfflineCompositionClipTypeImage) {
        UIImage *image = compClip.image;
        NSAssert(image, @"compClip.image is nil");
        cgImageRef = image.CGImage;
      } else if (compClip->clipType == AVOfflineCompositionClipTypeText) {
        // Render text directly into bitmapContext in a secondary thread.
        // The simplified NSString render methods like drawInRect cannot
        // be used here because of thread safety issues.
        
        MutableAttrString *mAttrString = [MutableAttrString mutableAttrString];
        
        NSString *fontName = self.defaultFont;
        NSUInteger fontSize = self.defaultFontSize;
        CGColorRef fontColorRef = self->m_defaultFontColor;
        
        if (compClip.font != nil) {
          fontName = compClip.font;
        }
        if (compClip->m_fontSize > 0) {
          fontSize = compClip->m_fontSize;
        }
        if (compClip->m_fontColor != NULL) {
          fontColorRef = compClip->m_fontColor;
        }
        
        [mAttrString setDefaults:fontColorRef
                  fontSize:fontSize
             plainFontName:fontName
              boldFontName:fontName];
        
        NSString *text = compClip.clipSource;
        if ([text length] > 0) {
          [mAttrString appendText:text];
          [mAttrString doneAppendingText];
          
          CGRect bounds = CGRectMake(compClip->clipX, compClip->clipY, compClip->clipWidth, compClip->clipHeight);
          bounds = [self flipRect:bounds];
          
          if (FALSE) {
            // Debug fill text bounds with red so that bounds can be checked.
            // Note that these bounds have already been flipped by the time
            // this method is invoked.
            
            UIColor *textBackgroundColor;
            //textBackgroundColor = [UIColor redColor];
            textBackgroundColor = [UIColor greenColor];
            CGContextSetFillColorWithColor(bitmapContext, textBackgroundColor.CGColor);
            CGContextFillRect(bitmapContext, bounds);
          }
          
          if (TRUE) {
            // This block attempts to work around thread safety issues in CoreText by doing
            // an invocation of this one method on the main thread.
            
            self->m_mAttrString = mAttrString;
            self->m_bitmapContext = bitmapContext;
            self->m_renderBounds = bounds;
            
            [self performSelectorOnMainThread: @selector(threadSafeRender) withObject:nil waitUntilDone:YES];
            
            self->m_mAttrString = nil;
            self->m_bitmapContext = NULL;
            self->m_renderBounds = CGRectZero;
          } else {
            // Old (thread unsafe) approach where CoreText API is invoked in a non-main thread.
            
            [mAttrString render:bitmapContext bounds:bounds];
          }
        }
      } else {
        assert(0);
      }
      
      // Render frame by painting frame image into a specific rectangle in the framebuffer
      
      if (cgImageRef) {
        CGRect bounds = CGRectMake(compClip->clipX, compClip->clipY, compClip->clipWidth, compClip->clipHeight);
        bounds = [self flipRect:bounds];
        CGContextDrawImage(bitmapContext, bounds, cgImageRef);
      }
    }
    
    clipOffset++;
  }
  
  return TRUE;
}

// This method implements a thread safe text render operaiton using CoreText.
// This method is invoked on the main thread, so that only the main thread
// actually creates and releases CTFramesetter related objects. This will
// block the main thread for a short time, but only in the idle processing when
// UI tasks have been dealt with. This function call will allocate and deallocate
// the CoreText framesetter elements in the main thread so crashes related to
// http://stackoverflow.com/questions/3527877/sizewithfont-in-multithread-crash?lq=1
// http://stackoverflow.com/questions/5642721/coretext-crashes-when-run-in-multiple-threads
// should be avoided.

- (void) threadSafeRender
{
  [m_mAttrString render:m_bitmapContext bounds:m_renderBounds];
}

// This method will render into the given

// Close resources associated with each open clip and
// possibly delete tmp files.

- (void) cleanupClips
{
  if (self->m_deleteTmpFiles) {
    for (AVOfflineCompositionClip *compClip in self.compClips) {
      AVOfflineCompositionClipType clipType = compClip->clipType;
      
      if (clipType == AVOfflineCompositionClipTypeText) {
        // Nop
      } else if (clipType == AVOfflineCompositionClipTypeImage) {
        // Nop
      } else if (clipType == AVOfflineCompositionClipTypeMvid) {
        // When the input to the comp module is a MVID sitting on
        // dist, the comp operation does not delete the MVID file
        // once the comp is finished.
      } else if (clipType == AVOfflineCompositionClipTypeH264) {
        // A .mvid created when a .h264 video was decoded to
        // the tmp dir can be cleaned up when the comp is complete.
        // This tmp file could be quite large, so a cleanup will
        // reclaim disk space. But, if multiple comps were going
        // to decode the same movie then it would be more efficient
        // to decode the h.264 once and set the "DeleteTmpFiles"
        // property to FALSE so that only 1 decode from h.264
        // needs to be done for N comp operations.
        
        NSString *tmpPath = compClip.mvidFrameDecoder.filePath;
        BOOL worked = [[NSFileManager defaultManager] removeItemAtPath:tmpPath error:nil];
        NSAssert(worked, @"could not remove tmp file");
      } else {
        assert(0);
      }
    }
  }
  
  // Clips are automatically cleaned up when last ref is dropped
  
  self.compClips = nil;
}

// This utility method will translate a bounding box so that coordinates given in
// terms of the upper left corner of the bounding box are flipped into offset
// of the lower left corner from the bottom of the screen.

- (CGRect) flipRect:(CGRect)rect
{
  CGRect flipped = rect;
  float lowerLeftCornerYBelowZero = rect.origin.y + rect.size.height;
  float lowerLeftCornerYAboveBottom = self.compSize.height - lowerLeftCornerYBelowZero;
  flipped.origin.y = lowerLeftCornerYAboveBottom;
  return flipped;
}

// This util method will query the screen scale property from the UIScreen
// class and save it as a static integer value so that it can be read
// easily from secondary threads.

- (void) queryScreenScale
{
  NSAssert([NSThread isMainThread], @"queryScreenScale must be invoked from main thread");
  
  if ([[UIScreen mainScreen] respondsToSelector:@selector(scale)]) {
    screenScale = (int) [UIScreen mainScreen].scale;
  } else {
    // Would only get invoked on old iPad 1 with iOS 3.2
    screenScale = 1;
  }
  
  NSAssert(screenScale == 1 || screenScale == 2, @"bad screenScale %d", screenScale);
}

@end // AVOfflineComposition


// Util object, one is created for each clip to be rendered in the composition

@implementation AVOfflineCompositionClip

@synthesize clipSource = m_clipSource;

@synthesize image = m_image;

@synthesize mvidFrameDecoder = m_mvidFrameDecoder;

@synthesize font = m_font;

+ (AVOfflineCompositionClip*) aVOfflineCompositionClip
{
  AVOfflineCompositionClip *obj = [[AVOfflineCompositionClip alloc] init];
#if __has_feature(objc_arc)
  return obj;
#else
  return [obj autorelease];
#endif // objc_arc
}

- (void) dealloc
{
  if (self->m_fontColor) {
    CGColorRelease(self->m_fontColor);
  }
  
#if __has_feature(objc_arc)
#else
  [AutoPropertyRelease releaseProperties:self thisClass:AVOfflineCompositionClip.class];
  [super dealloc];
#endif // objc_arc
}

@end
