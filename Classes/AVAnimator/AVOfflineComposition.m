//
//  AVOfflineComposition.h
//  Created by Moses DeJong on 3/31/12.
//
//  License terms defined in License.txt.

#import "AVOfflineComposition.h"

#import "AutoPropertyRelease.h"

#import <QuartzCore/QuartzCore.h>

// Notification name constants

NSString * const AVOfflineCompositionCompletedNotification = @"AVOfflineCompositionCompletedNotification";

NSString * const AVOfflineCompositionFailedNotification = @"AVOfflineCompositionFailedNotification";

// Private API

@interface AVOfflineComposition ()

// Read a plist from a resource file. Either a NSDictionary or NSArray

+ (id) readPlist:(NSString*)resFileName;

- (BOOL) parseToplevelProperties:(NSDictionary*)compDict;

- (void) notifyCompositionCompleted;

- (void) notifyCompositionFailed;

- (NSString*) backgroundColorStr;

@property (nonatomic, copy) NSString *errorString;

@property (nonatomic, copy) NSString *source;

@property (nonatomic, copy) NSArray *compClips;

@property (nonatomic, assign) float compDuration;

@property (nonatomic, assign) float compFPS;

@property (nonatomic, assign) CGSize compSize;

@end

// Implementation of AVOfflineComposition

@implementation AVOfflineComposition

@synthesize errorString = m_errorString;

@synthesize source = m_source;

@synthesize compClips = m_compClips;

@synthesize compDuration = m_compDuration;

@synthesize compFPS = m_compFPS;

@synthesize compSize = m_compSize;

// Constructor

+ (AVOfflineComposition*) aVOfflineComposition
{
  AVOfflineComposition *obj = [[[AVOfflineComposition alloc] init] autorelease];
  return obj;
}

- (void) dealloc
{
  if (self->m_backgroundColor) {
    CGColorRelease(self->m_backgroundColor);
  }
  [AutoPropertyRelease releaseProperties:self thisClass:AVOfflineComposition.class];
  [super dealloc];
}

// Initiate a composition operation given info about the composition
// contained in the indicated dictionary.

- (void) compose:(NSDictionary*)compDict
{
  BOOL worked;
  
  NSAssert(compDict, @"compDict must not be nil");

  worked = [self parseToplevelProperties:compDict];
  
  if (!worked) {
    [self notifyCompositionFailed];
    return;
  }
  
  if (TRUE) {
    // Deliver success notification
    [self notifyCompositionCompleted];
  }
  
  return;
}

+ (id) readPlist:(NSString*)resFileName
{
  NSData *plistData;  
  NSString *error;  
  NSPropertyListFormat format;  
  id plist;  
  
  NSString *resPath = [[NSBundle mainBundle] pathForResource:resFileName ofType:@""];  
  plistData = [NSData dataWithContentsOfFile:resPath];   
  
  plist = [NSPropertyListSerialization propertyListFromData:plistData mutabilityOption:NSPropertyListImmutable format:&format errorDescription:&error];
  if (!plist) {
    NSLog(@"Error reading plist from file '%s', error = '%s'", [resFileName UTF8String], [error UTF8String]);  
    [error release];  
  }
  return plist;  
}

- (CGColorRef) createCGColor:(CGFloat)red green:(CGFloat)green blue:(CGFloat)blue alpha:(CGFloat)alpha
{
  CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
  CGFloat components[4] = {red, green, blue, alpha};
  CGColorRef cgColor = CGColorCreate(colorSpace, components);
  CGColorSpaceRelease(colorSpace);
  return cgColor;
}

- (CGColorRef) createColorWithHexString:(NSString*)stringToConvert
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
{
  int len = [colorSpec length];
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
  
  // FIXME: parse background color into color componenets (CG Color, not UIColor for thread safety)
  
  // CompFramesPerSecond is a floating point number that indicates how many frames per second
  // the resulting composition will be. This field is required.
  // Common Values: 1, 2, 15, 24, 29.97, 30, 48, 60
  
  NSNumber *compFramesPerSecondNum = [compDict objectForKey:@"CompFramesPerSecond"];
  float compFramesPerSecond;

  compFramesPerSecond = [compFramesPerSecondNum floatValue];

  self.compFPS = compFramesPerSecond;
  
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

  // Parse CompClips, this array of dicttionary property is optional
  
  NSArray *compClips = [compDict objectForKey:@"CompClips"];

  self.compClips = compClips;
  
  return TRUE;
}

- (void) notifyCompositionCompleted
{
  [[NSNotificationCenter defaultCenter] postNotificationName:AVOfflineCompositionCompletedNotification
                                                      object:self];	
}

- (void) notifyCompositionFailed
{
  [[NSNotificationCenter defaultCenter] postNotificationName:AVOfflineCompositionFailedNotification
                                                      object:self];	
}

@end
