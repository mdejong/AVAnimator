//
//  AVFrameDecoder.h
//
//  Created by Moses DeJong on 12/30/10.
//
//  This abstract superclass defines the interface that needs to be implemented by
//  a class that implements frame decoding logic. A frame is 2D image decoded from
//  video data from a file or other resource.

#import <Foundation/Foundation.h>

@class CGFrameBuffer;

@interface AVFrameDecoder : NSObject {
}

// Open resource identified by path

- (BOOL) openForReading:(NSString*)path;

// Close resource opened earlier

- (void) close;

// Reset current frame index to -1, before the first frame

- (void) rewind;

// Advance the current frame index to the indicated frame index and store result in nextFrameBuffer

- (BOOL) advanceToFrame:(NSUInteger)newFrameIndex nextFrameBuffer:(CGFrameBuffer*)nextFrameBuffer;

// Return the current frame buffer, this is the buffer that was most recently written to via
// a call to advanceToFrame. Returns nil on init or after a rewind operation.

- (CGFrameBuffer*) currentFrameBuffer;

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

@end
