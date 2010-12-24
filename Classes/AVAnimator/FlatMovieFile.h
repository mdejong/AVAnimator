//
//  FlatMovieFile.h
//  Manage the details of reading movie "frames" from a file and writing
//  of pixel data to framebuffers.
//
//  Created by Moses DeJong on 3/15/09.
//

#import <Foundation/Foundation.h>

#import "movdata.h"

@class CGFrameBuffer;

// Rename this FrameBuffer source or something and make protocol so that
// vc can make useof it generically. Also need some sort of loader.

@interface FlatMovieFile : NSObject {
@public
	FILE *movFile;
	MovData *movData;

	BOOL isOpen;

	// The input buffer stores incoming delta data from one frame to the next.
	// The input buffer is typically smaller than the frame buffer.

	void *inputBuffer;
	NSUInteger numWordsInputBuffer;
	BOOL isInputBufferLocked;

  CGFrameBuffer *currentFrameBuffer;
  
  NSData *m_mappedData;
  
	int frameIndex;
}

@property (readonly) NSUInteger width;
@property (readonly) NSUInteger height;
@property (readonly) NSUInteger numFrames;
@property (readonly) BOOL isOpen;
@property (readonly) int frameIndex;
@property (nonatomic, copy) NSData *mappedData;

- (id) init;

- (void) dealloc;

- (BOOL) openForReading:(NSString*)flatMoviePath;

- (void) close;

- (void) rewind;

- (BOOL) advanceToFrame:(NSUInteger)newFrameIndex nextFrameBuffer:(CGFrameBuffer*)nextFrameBuffer;

// Duration of frame in seconds

- (NSTimeInterval) frameInterval;

@end
