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

@interface AVImageFrameDecoder : AVFrameDecoder {
  NSArray *m_cgFrameBuffers;
  NSArray *m_urls;
  NSArray *m_dataObjs;
  NSArray *m_cachedImageObjs;
  UIImage *m_currentFrame;
  BOOL m_resourceUsageLimit;
}

@property (nonatomic, copy) NSArray *cgFrameBuffers;
@property (nonatomic, copy) NSArray *urls;
@property (nonatomic, copy) NSArray *dataObjs;
@property (nonatomic, copy) NSArray *cachedImageObjs;
@property (nonatomic, retain) UIImage *currentFrame;

+ (NSArray*) arrayWithNumberedNames:(NSString*)filenamePrefix
                         rangeStart:(NSInteger)rangeStart
                           rangeEnd:(NSInteger)rangeEnd
                       suffixFormat:(NSString*)suffixFormat;

+ (NSArray*) arrayWithResourcePrefixedURLs:(NSArray*)inNumberedNames;

+ (AVImageFrameDecoder*) aVImageFrameDecoder:(NSArray*)urls cacheDecodedImages:(BOOL)cacheDecodedImages;

// Open resource identified by path

- (BOOL) openForReading:(NSString*)path;

// Close resource opened earlier

- (void) close;

// Reset current frame index to -1, before the first frame

- (void) rewind;

// Advance the current frame index to the indicated frame index and store result in nextFrameBuffer

- (UIImage*) advanceToFrame:(NSUInteger)newFrameIndex;

- (void) resourceUsageLimit:(BOOL)enabled;

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

- (BOOL) hasAlphaChannel;

@end
