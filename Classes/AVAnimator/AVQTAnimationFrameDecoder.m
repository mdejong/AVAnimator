//
//  AVQTAnimationFrameDecoder.m
//
//  Created by Moses DeJong on 12/30/10.
//

#import "AVQTAnimationFrameDecoder.h"

#import "CGFrameBuffer.h"

#import "movdata.h"

#define USE_MMAP

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

// AVQTAnimationFrameDecoder class

@implementation AVQTAnimationFrameDecoder

@synthesize mappedData = m_mappedData;
@synthesize currentFrameBuffer = m_currentFrameBuffer;

+ (AVQTAnimationFrameDecoder*) aVQTAnimationFrameDecoder
{
  return [[[AVQTAnimationFrameDecoder alloc] init] autorelease];
}

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
  assert(self->inputBuffer == NULL);
	void *buf = malloc(numWords * sizeof(int));
	assert(buf);
  
	self->inputBuffer = buf;
	self->numWordsInputBuffer = numWords;
  
	return;
}

- (void) _freeInputBuffer
{
  if (self->inputBuffer) {
    free(self->inputBuffer);
    self->inputBuffer = NULL;
  }
}

- (void) dealloc
{
	if (movFile != NULL) {
		[self close];
  }
  if (movData != NULL) {
    movdata_free(movData);
    free(movData);
  }
  [self _freeInputBuffer];
  self.mappedData = nil;
  self.currentFrameBuffer = nil;
	[super dealloc];
}	

- (BOOL) _readHeader:(uint32_t)filesize path:(NSString*)path
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
  
#ifdef USE_MMAP
  [self close];
  self->m_isOpen = TRUE;
  self.mappedData = [NSData dataWithContentsOfMappedFile:path];
  NSAssert(self.mappedData, @"could not map movie file");
#else
	// Figure out good size for input buffer.
  
  int maxNumWords = num_words(movData->maxSampleSize);
  
	[self _allocateInputBuffer:maxNumWords];
  
# ifdef LOG_MISSED_BUFFER_USAGE
	NSLog(@"allocated input buffer of size %d bytes", maxNumWords*sizeof(int));
# endif // LOG_MISSED_BUFFER_USAGE	  
  
#endif // USE_MMAP
  
	return TRUE;
}

- (BOOL) openForReading:(NSString*)flatMoviePath
{
	if (self->m_isOpen)
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
  
	if ([self _readHeader:fsize path:flatMoviePath] == FALSE) {
		[self close];
		return FALSE;
	}
  
	self->m_isOpen = TRUE;
	return TRUE;
}

- (void) close
{
	if (self->movFile != NULL) {
		fclose(self->movFile);
		self->movFile = NULL;
	}
  
  self.mappedData = nil;
  [self _freeInputBuffer];
  
	frameIndex = -1;
  self.currentFrameBuffer = nil;
  
  self->m_isOpen = FALSE;
}

- (void) rewind
{
	if (!self->m_isOpen) {
		return;
  }
  
	frameIndex = -1;
  self.currentFrameBuffer = nil;
}

- (BOOL) advanceToFrame:(NSUInteger)newFrameIndex nextFrameBuffer:(CGFrameBuffer*)nextFrameBuffer
{
  // Double check that the current frame is not the exact same object as the one we pass as
  // the next frame buffer. This should not happen, and we can't copy the buffer into itself.
  
  NSAssert(nextFrameBuffer != self->m_currentFrameBuffer, @"current and next frame buffers can't be the same object");  
  
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
  
#ifdef USE_MMAP
  char *mappedPtr = (char*) [self.mappedData bytes];
  NSAssert(mappedPtr, @"mappedPtr");
#endif // USE_MMAP
  
	for ( ; frameIndex < newFrameIndexSigned; frameIndex++) {
		// Read one word from the stream and examine it to determine
		// the type of the next frame.
    
    int actualFrameIndex = frameIndex + 1;
    MovSample *frame = movData->frames[actualFrameIndex];
    
    if ((actualFrameIndex > 0) && (frame == movData->frames[actualFrameIndex-1])) {
      // This frame is a no-op, since it duplicates data from the previous frame.
      //      fprintf(stdout, "Frame %d NOP\n", actualFrameIndex);
    } else {
      //      fprintf(stdout, "Frame %d [Size %d Offset %d Keyframe %d]\n", actualFrameIndex, frame->offset, movsample_length(frame), movsample_iskeyframe(frame));
			changeFrameData = TRUE;
      
      if (self.currentFrameBuffer != nextFrameBuffer) {
        // Copy the previous frame buffer unless there was not one, or current is a keyframe
        
        if (self.currentFrameBuffer != nil && !movsample_iskeyframe(frame)) {
          [nextFrameBuffer copyPixels:self.currentFrameBuffer];
        }
        self.currentFrameBuffer = nextFrameBuffer;
      }
      
      // FIXME: This logic currently lacks checking for keyframes on skip ahead!
      
#ifdef USE_MMAP
      process_rle_sample(mappedPtr, self->movData, frame, nextFrameBuffer.pixels);
#else
      read_process_rle_sample(self->movFile, self->movData, frame, nextFrameBuffer.pixels, inputBuffer, numWordsInputBuffer * sizeof(int));
#endif // USE_MMAP
    }
	}
  
	return changeFrameData;
}

// Return the current frame buffer, this is the buffer that was most recently written to via
// a call to advanceToFrame. Returns nil on init or after a rewind operation.

- (CGFrameBuffer*) currentFrameBuffer
{
  return self->m_currentFrameBuffer;
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

- (BOOL) isOpen
{
  return self->m_isOpen;
}

- (NSUInteger) numFrames
{
  return self->movData->numFrames;
}

- (int) frameIndex
{
  return self->frameIndex;
}

- (NSTimeInterval) frameDuration
{
  return 1.0 / movData->fps;
}

@end
