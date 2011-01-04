//
//  AVPNGFrameDecoder.m
//
//  Created by Moses DeJong on 1/4/11.
//

#import "AVPNGFrameDecoder.h"
#import "AutoPropertyRelease.h"

@implementation AVPNGFrameDecoder

@synthesize cgFrameBuffers = m_cgFrameBuffers;
@synthesize urls = m_urls;
@synthesize dataObjs = m_dataObjs;

- (void) dealloc {
  [AutoPropertyRelease releaseProperties:self thisClass:AVPNGFrameDecoder.class];
  [super dealloc];
}

// Create an array of file/resource names with the given filename prefix,
// the file names will have an integer appended in the range indicated
// by the rangeStart and rangeEnd arguments. The suffixFormat argument
// is a format string like "%02i.png", it must format an integer value
// into a string that is appended to the file/resource string.
//
// For example: [createNumberedNames:@"Image" rangeStart:1 rangeEnd:3 rangeFormat:@"%02i.png"]
//
// returns: {"Image01.png", "Image02.png", "Image03.png"}

+ (NSArray*) arrayWithNumberedNames:(NSString*)filenamePrefix
                         rangeStart:(NSInteger)rangeStart
                           rangeEnd:(NSInteger)rangeEnd
                       suffixFormat:(NSString*)suffixFormat
{
	NSMutableArray *numberedNames = [[NSMutableArray alloc] initWithCapacity:40];
  
	for (int i = rangeStart; i <= rangeEnd; i++) {
		NSString *suffix = [NSString stringWithFormat:suffixFormat, i];
		NSString *filename = [NSString stringWithFormat:@"%@%@", filenamePrefix, suffix];
    
		[numberedNames addObject:filename];
	}
  
	NSArray *newArray = [NSArray arrayWithArray:numberedNames];
	[numberedNames release];
	return newArray;
}

// Given an array of resource names (as returned by arrayWithNumberedNames)
// create a new array that contains these resource names prefixed as
// resource paths and wrapped in a NSURL object.

+ (NSArray*) arrayWithResourcePrefixedURLs:(NSArray*)inNumberedNames
{
	NSMutableArray *URLs = [[NSMutableArray alloc] initWithCapacity:[inNumberedNames count]];
	NSBundle* appBundle = [NSBundle mainBundle];
  
	for ( NSString* path in inNumberedNames ) {
		NSString* resPath = [appBundle pathForResource:path ofType:nil];
		NSURL* aURL = [NSURL fileURLWithPath:resPath];
		[URLs addObject:aURL];
	}
  
	NSArray *newArray = [NSArray arrayWithArray:URLs];
	[URLs release];
	return newArray;
}

+ (AVPNGFrameDecoder*) aVPNGFrameDecoder:(NSArray*)urls
{
  AVPNGFrameDecoder *obj = [[AVPNGFrameDecoder alloc] init];
  [obj autorelease];
  if (obj == nil) {
    return nil;
  }
  obj.urls = urls;
  
  // Load data from URL, if URL is a file then memory map the file
  
  NSMutableArray *mArr = [NSMutableArray arrayWithCapacity:[urls count]];
  for ( NSURL* url in urls ) {
    NSData *data;
    if ([url isFileURL]) {
      data = [NSData dataWithContentsOfMappedFile:[url path]];
    } else {
      data = [NSData dataWithContentsOfURL:url];
    }
    NSAssert(data, @"URL data is nil");
    [mArr addObject:data];
  }
  obj.dataObjs = [NSArray arrayWithArray:mArr];
  
  return obj;
}

- (UIImage*) advanceToFrame:(NSUInteger)newFrameIndex
{
  NSAssert(newFrameIndex >= 0 || newFrameIndex < [self.urls count], @"newFrameIndex is out of range");
  //NSURL *url = [self.urls objectAtIndex:newFrameIndex];
  NSData *data = [self.dataObjs objectAtIndex:newFrameIndex];
	UIImage *img = [UIImage imageWithData:data];
  NSAssert(img, @"img is nil");
  return img;
}

- (BOOL) openForReading:(NSString*)path
{
  return TRUE;
}

// Close resource opened earlier

- (void) close
{
}

// Reset current frame index to -1, before the first frame

- (void) rewind
{
}

// Properties

// Dimensions of each frame
- (NSUInteger) width
{
  return -1;
}

- (NSUInteger) height
{
  return -1;
}

// True when resource has been opened via openForReading
- (BOOL) isOpen
{
  return TRUE;
}

// Total frame count
- (NSUInteger) numFrames
{
  return [self.urls count];
}

// Current frame index, can be -1 at init or after rewind
- (NSInteger) frameIndex
{
  return 0;
}

// Time each frame shold be displayed
- (NSTimeInterval) frameDuration
{
  return 0.0;
}

@end
