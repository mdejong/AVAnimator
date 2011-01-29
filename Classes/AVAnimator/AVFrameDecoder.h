//
//  AVFrameDecoder.h
//
//  Created by Moses DeJong on 12/30/10.
//
//  License terms defined in License.txt.
//
//  This abstract superclass defines the interface that needs to be implemented by
//  a class that implements frame decoding logic. A frame is 2D image decoded from
//  video data from a file or other resource.

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@class CGFrameBuffer;

@interface AVFrameDecoder : NSObject {
}

// Open resource identified by path

- (BOOL) openForReading:(NSString*)path;

// Close resource opened earlier

- (void) close;

// Reset current frame index to -1, before the first frame

- (void) rewind;

// Advance the current frame index to the indicated frame index. Return the new frame
// encoded as a UIImage object, or nil if the frame data was not changed. The UIImage
// returned is assumed to be in the autorelease pool.

- (UIImage*) advanceToFrame:(NSUInteger)newFrameIndex;

// A frame decoder may be asked to limit memory usage or deallocate
// resources when it is not being actively used. When TRUE is passed
// as the enabled flag, the frame decoder should deallocate as
// many resources as possible.

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

// TRUE if the decoded frame supports and alpha channel.
- (BOOL) hasAlphaChannel;

@end
