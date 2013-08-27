//
//  AVImageFrameDecoder.h
//  QTFileParserApp
//
//  Created by Moses DeJong on 1/4/11.
//
//  License terms defined in License.txt.
//
//  This class implements the AVFrameDecoder interface and supports
//  loading "frames" from individual images files. These image files
//  could be PNG, JPEG, or any other format supported by the system.
//  This implementation works, but does not work that well since
//  decoding an entire image each frame is not optimal. This class
//  is mostly a proof of concept. A real implementation would use
//  a file format that supports frame deltas, since frame deltas
//  provide reasonable memory and cpu usage results. This implementation
//  holds the entire encoded image data in memory, since IO between
//  frame rendering is too slow to produce useful results.

#import <Foundation/Foundation.h>
#import "AVFrameDecoder.h"

@class UIImage;

@interface AVImageFrameDecoder : AVFrameDecoder {
  NSArray *m_cgFrameBuffers;
  NSArray *m_urls;
  NSArray *m_dataObjs;
  NSArray *m_cachedImageObjs;
  UIImage *m_currentFrameImage;
  NSTimeInterval m_frameDuration;
  BOOL m_resourceUsageLimit;
}

@property (nonatomic, copy) NSArray *cgFrameBuffers;
@property (nonatomic, copy) NSArray *urls;
@property (nonatomic, copy) NSArray *dataObjs;
@property (nonatomic, copy) NSArray *cachedImageObjs;
@property (nonatomic, retain) UIImage *currentFrameImage;

+ (NSArray*) arrayWithNumberedNames:(NSString*)filenamePrefix
                         rangeStart:(NSInteger)rangeStart
                           rangeEnd:(NSInteger)rangeEnd
                       suffixFormat:(NSString*)suffixFormat;

+ (NSArray*) arrayWithResourcePrefixedURLs:(NSArray*)inNumberedNames;

// Create instance of AVImageFrameDecoder. Typically one would want to
// use this constructor as opposed to the next one.

+ (AVImageFrameDecoder*) aVImageFrameDecoder:(NSArray*)urls;

// This constructor provides an optional cacheDecodedImages that makes it possible
// to cache the decoded image data in memory. But, this will use up a ton a memory
// so it should only be used if you really know what you are doing!

+ (AVImageFrameDecoder*) aVImageFrameDecoder:(NSArray*)urls cacheDecodedImages:(BOOL)cacheDecodedImages;

// Open resource identified by path

- (BOOL) openForReading:(NSString*)path;

// Close resource opened earlier

- (void) close;

// Reset current frame index to -1, before the first frame

- (void) rewind;

// Advance the current frame index, see AVFrameDecoder.h for full method description.

- (AVFrame*) advanceToFrame:(NSUInteger)newFrameIndex;

// Decoding frames may require additional resources that are not required
// to open the file and examine the header contents. This method will
// allocate decoding resources that are required to actually decode the
// video frames from a specific file. It is possible that allocation
// could fail, for example if decoding would require too much memory.
// The caller would need to check for a FALSE return value to determine
// how to handle the case where allocation of decode resources fails.

- (BOOL) allocateDecodeResources;

- (void) releaseDecodeResources;

- (BOOL) isResourceUsageLimit;

// Properties

// Dimensions of each frame
- (NSUInteger) width;
- (NSUInteger) height;

// True when resource has been opened via openForReading
- (BOOL) isOpen;

// Total frame count
- (NSUInteger) numFrames;

// Current frame index, can be -1 at init or after rewind
- (NSInteger) frameIndex;

// Time each frame shold be displayed
- (NSTimeInterval) frameDuration;

// This method will explicitly set value returned by frameDuration.
- (void) setFrameDuration:(NSTimeInterval)duration;

- (BOOL) hasAlphaChannel;

// True when all mvid frames are keyframes. This means that none of
// the frames are delta frames that require a previous state in order
// to apply a delta.

- (BOOL) isAllKeyframes;

@end
