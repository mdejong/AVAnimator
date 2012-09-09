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
  NSString *m_filePath;
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
  
  AVFrame *m_lastFrame;
  
	int frameIndex;
  
  BOOL m_resourceUsageLimit;
  
#if defined(REGRESSION_TESTS)
  BOOL m_simulateMemoryMapFailure;
#endif // REGRESSION_TESTS
}

@property (nonatomic, copy) NSString *filePath;
@property (nonatomic, copy) NSData *mappedData;
@property (nonatomic, retain) CGFrameBuffer *currentFrameBuffer;
@property (nonatomic, copy) NSArray *cgFrameBuffers;

#if defined(REGRESSION_TESTS)
@property (nonatomic, assign) BOOL simulateMemoryMapFailure;
#endif // REGRESSION_TESTS

+ (AVQTAnimationFrameDecoder*) aVQTAnimationFrameDecoder;

// Open resource identified by path

- (BOOL) openForReading:(NSString*)path;

// Close resource opened earlier

- (void) close;

// Reset current frame index to -1, before the first frame

- (void) rewind;

// Advance the current frame index to the indicated frame index and store result in nextFrameBuffer

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

