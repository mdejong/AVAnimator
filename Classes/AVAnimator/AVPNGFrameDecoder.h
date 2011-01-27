//
//  AVPNGFrameDecoder.h
//  QTFileParserApp
//
//  Created by Moses DeJong on 1/4/11.
//
//  License terms defined in License.txt.
//
//  This class implements the AVFrameDecoder such that PNG files can be
//  loaded and played in an AVAnimatorView. This implementation is not
//  meant to work all that well, it is only a simple demonstration of
//  the AVFrameDecoder interface.

#import <Foundation/Foundation.h>
#import "AVFrameDecoder.h"

@interface AVPNGFrameDecoder : AVFrameDecoder {
  NSArray *m_cgFrameBuffers;
  NSArray *m_urls;
  NSArray *m_dataObjs;
  NSArray *m_cachedImageObjs;
}

@property (nonatomic, copy) NSArray *cgFrameBuffers;
@property (nonatomic, copy) NSArray *urls;
@property (nonatomic, copy) NSArray *dataObjs;
@property (nonatomic, copy) NSArray *cachedImageObjs;

+ (NSArray*) arrayWithNumberedNames:(NSString*)filenamePrefix
                         rangeStart:(NSInteger)rangeStart
                           rangeEnd:(NSInteger)rangeEnd
                       suffixFormat:(NSString*)suffixFormat;

+ (NSArray*) arrayWithResourcePrefixedURLs:(NSArray*)inNumberedNames;

+ (AVPNGFrameDecoder*) aVPNGFrameDecoder:(NSArray*)urls cacheDecodedImages:(BOOL)cacheDecodedImages;

// Open resource identified by path

- (BOOL) openForReading:(NSString*)path;

// Close resource opened earlier

- (void) close;

// Reset current frame index to -1, before the first frame

- (void) rewind;

// Advance the current frame index to the indicated frame index and store result in nextFrameBuffer

- (UIImage*) advanceToFrame:(NSUInteger)newFrameIndex;

- (void) resourceUsageLimit:(BOOL)enabled;

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
