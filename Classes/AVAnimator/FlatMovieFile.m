//
//  FlatMovieFile.m
//
//  Created by Moses DeJong on 3/15/09.
//  Copyright 2009 __MyCompanyName__. All rights reserved.
//

#import "FlatMovieFile.h"

#import "CGFrameBuffer.h"

#import "movdata.h"

//#define LOGGING

// Determine the file size return 0 to indicate success.

static
int filesize(char *filename, uint32_t *filesize) {
  struct stat sb;
  if( 0 != stat( filename, &sb ) ) {
    return 1;
  }
  *filesize = (uint32_t) sb.st_size;
  return 0;
}

static
inline
int num_words(uint32_t numBytes)
{
	int numBytesOverWordBoundry = numBytes % 4;
	int numWords = numBytes / 4;
	if (numBytesOverWordBoundry > 0)
		numWords++;
	return numWords;
}

// FlatMovieFile class

@implementation FlatMovieFile

@synthesize isOpen;

- (id) init
{
	self = [super init];
	if (self == nil)
		return nil;

	self->frameIndex = -1;

	return self;
}

- (void) _allocateInputBuffer:(NSUInteger)numWords
{
	void *buf = malloc(numWords * sizeof(int));
	assert(buf);

	self->inputBuffer = buf;
	self->numWordsInputBuffer = numWords;

	return;
}

- (void) dealloc
{
	if (movFile != NULL)
		[self close];
  if (movData != NULL)
    movdata_free(movData);
	if (inputBuffer != NULL)
		free(inputBuffer);
	[super dealloc];
}	

- (BOOL) _readHeader:(uint32_t)filesize
{
	// opening the file reads the header data

  self->movData = malloc(sizeof(MovData));
  assert(self->movData);
  movdata_init(self->movData);
  
  int result;
  
  result = process_atoms(self->movFile, self->movData, filesize);
  
  if (result != 0) {
    fprintf(stderr, "%s\n", self->movData->errMsg);
    return FALSE;
  }

  result = process_sample_tables(movFile, self->movData);
  
  if (result != 0) {
    fprintf(stderr, "%s\n", self->movData->errMsg);
    return FALSE;
  }
  
  assert(self->movData->maxSampleSize > 0);
  
  assert(self->movData->bitDepth == 16); // FIXME: add others later
  
	// Figure out good size for input buffer.

  int maxNumWords = num_words(movData->maxSampleSize);
  
	[self _allocateInputBuffer:maxNumWords];

#ifdef LOG_MISSED_BUFFER_USAGE
	NSLog(@"allocated input buffer of size %d bytes", maxNumWords*sizeof(int));
#endif // LOG_MISSED_BUFFER_USAGE	

	return TRUE;
}

- (BOOL) openForReading:(NSString*)flatMoviePath
{
	if (isOpen)
		return FALSE;

	char *flatFilePath = (char*) [flatMoviePath UTF8String];
	self->movFile = fopen(flatFilePath, "rb");

	if (movFile == NULL) {
		return FALSE;
	}

  uint32_t fsize;
  int status = filesize(flatFilePath, &fsize);
	if (status != 0) {
		return FALSE;
	}
  
	if ([self _readHeader:fsize] == FALSE) {
		[self close];
		return FALSE;
	}

	self->isOpen = TRUE;
	return TRUE;
}

- (void) close
{
	if (self->movFile != NULL) {
		fclose(self->movFile);
		self->movFile = NULL;
		self->isOpen = FALSE;
	}
}

- (void) rewind
{
	if (!isOpen)
		return;

	frameIndex = -1;
}

- (BOOL) advanceToFrame:(NSUInteger)newFrameIndex nextFrameBuffer:(CGFrameBuffer*)nextFrameBuffer
{
  assert(self->currentFrameBuffer != nextFrameBuffer); // Can't pass same frame buffer object twice in a row
  
	// movie frame index can only go forward via advanceToFrame

	if ((frameIndex != -1) && (newFrameIndex <= frameIndex)) {
		NSString *msg = [NSString stringWithFormat:@"%@: %d -> %d",
						 @"can't advance to frame before current frameIndex",
						 frameIndex,
						 newFrameIndex];
		NSAssert(FALSE, msg);
	}

	// Get the number of frames directly from the header
	// instead of invoking method to query self.numFrames.

  int numFrames = self->movData->numFrames;

	if (newFrameIndex >= numFrames) {
		NSString *msg = [NSString stringWithFormat:@"%@: %d",
						 @"can't advance past last frame",
						 newFrameIndex];
		NSAssert(FALSE, msg);
	}

	// Return TRUE when a patch has been applied or a new keyframe was
	// read. Return FALSE when 1 or more duplicate frames were read.
	
	BOOL changeFrameData = FALSE;
	const int newFrameIndexSigned = (int) newFrameIndex;

	for ( ; frameIndex < newFrameIndexSigned; frameIndex++) {
		// Read one word from the stream and examine it to determine
		// the type of the next frame.
    
    int actualFrameIndex = frameIndex + 1;
    MovSample *frame = movData->frames[actualFrameIndex];
    
    if ((actualFrameIndex > 0) && (frame == movData->frames[actualFrameIndex-1])) {
      // This frame is a no-op, since it duplicates data from the previous frame.
      fprintf(stdout, "Frame %d NOP\n", actualFrameIndex);
    } else {
      fprintf(stdout, "Frame %d [%d %d]\n", actualFrameIndex, frame->offset, frame->length);
			changeFrameData = TRUE;
      
      if (self->currentFrameBuffer != nextFrameBuffer) {
        // Copy the previous frame buffer unless there was not one, or current is a keyframe

        if (self->currentFrameBuffer != nil && !frame->isKeyframe) {
          [nextFrameBuffer copyPixels:self->currentFrameBuffer];
        }
        self->currentFrameBuffer = nextFrameBuffer;
      }
      
      // FIXME: This logic currently lacks checking for keyframes on skip ahead!
      
      process_rle_sample(self->movFile, self->movData, frame, nextFrameBuffer.pixels, inputBuffer, numWordsInputBuffer * sizeof(int));
    }
	}
  
	return changeFrameData;
}

// Properties

- (NSUInteger) width
{
  return self->movData->width;
}

- (NSUInteger) height
{
  return self->movData->height;
}

- (NSUInteger) numFrames
{
  return self->movData->numFrames;
}

- (int) frameIndex
{
  return self->frameIndex;
}

@end

