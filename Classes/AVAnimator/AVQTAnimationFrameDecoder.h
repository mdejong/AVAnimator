//
//  AVQTAnimationFrameDecoder.h
//
//  Created by Moses DeJong on 12/30/10.
//
//  License terms defined in License.txt.
//
//  This class implements the AVFrameDecoder interface and provides
//  decoding of Quicktime Animation video frames from a MOV file.
//  The mov to be decoded must be stored on the filesystem.

#import <Foundation/Foundation.h>

#import "AVFrameDecoder.h"

typedef struct MovData *MovDataPtr;

@interface AVQTAnimationFrameDecoder : AVFrameDecoder {
  FILE *movFile;
	MovDataPtr movData;
  
	BOOL m_isOpen;
  
	// The input buffer stores incoming delta data from one frame to the next.
	// The input buffer is typically smaller than the frame buffer.
  
	void *inputBuffer;
	NSUInteger numWordsInputBuffer;
	BOOL isInputBufferLocked;
  
  NSData *m_mappedData;
  
  CGFrameBuffer *m_currentFrameBuffer;  
	NSArray *m_cgFrameBuffers;
  
	int frameIndex;  
}

@property (nonatomic, copy) NSData *mappedData;
@property (nonatomic, retain) CGFrameBuffer *currentFrameBuffer;
@property (nonatomic, copy) NSArray *cgFrameBuffers;

+ (AVQTAnimationFrameDecoder*) aVQTAnimationFrameDecoder;

// Open resource identified by path

- (BOOL) openForReading:(NSString*)path;

// Close resource opened earlier

- (void) close;

// Reset current frame index to -1, before the first frame

- (void) rewind;

// Advance the current frame index to the indicated frame index and store result in nextFrameBuffer

- (UIImage*) advanceToFrame:(NSUInteger)newFrameIndex;

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

