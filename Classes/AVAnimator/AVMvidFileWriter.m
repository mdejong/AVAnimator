//
//  AVMvidFileWriter.m
//
//  Created by Moses DeJong on 2/20/12.
//
//  License terms defined in License.txt.

#import "AVMvidFileWriter.h"

//#define LOGGING

#ifndef __OPTIMIZE__
// Automatically define EXTRA_CHECKS when not optimizing (in debug mode)
# define EXTRA_CHECKS
#endif // DEBUG

#ifdef EXTRA_CHECKS
#define ALWAYS_GENERATE_ADLER
#endif // EXTRA_CHECKS

// Emit zero length words up to the next page bound when emitting a keyframe.
// Pass in the current offset, function returns the new offset. This method
// will emit zero words of padding if exactly on the page bound already.

static inline
uint32_t maxvid_file_padding_before_keyframe(FILE *outFile, uint32_t offset) {
  assert((offset % 4) == 0);
  
  const uint32_t boundSize = MV_PAGESIZE;
  uint32_t bytesToBound = UINTMOD(offset, boundSize);
  assert(bytesToBound >= 0 && bytesToBound <= boundSize);
  
  bytesToBound = boundSize - bytesToBound;
  uint32_t wordsToBound = bytesToBound >> 2;
  wordsToBound &= ((MV_PAGESIZE >> 2) - 1);
  
  if (wordsToBound > 0) {
    assert(bytesToBound == (wordsToBound * 4));
    assert(wordsToBound < (boundSize / 4));
  }
  
  uint32_t zero = 0;
  while (wordsToBound != 0) {
    size_t size = fwrite(&zero, sizeof(zero), 1, outFile);
    assert(size == 1);
    wordsToBound--;
  }
  
  uint32_t offsetAfter = ftell(outFile);
  
  assert(UINTMOD(offsetAfter, boundSize) == 0);
  
  return offsetAfter;
}

// Emit zero length words up to the next page bound after the keyframe data.
// Pass in the current offset, function returns the new offset.
// This method will emit zero words of padding if exactly on the page bound already.

static inline
uint32_t maxvid_file_padding_after_keyframe(FILE *outFile, uint32_t offset) {
  return maxvid_file_padding_before_keyframe(outFile, offset);
}


@interface AVMvidFileWriter ()

- (void) saveOffset;

- (uint32_t) validateFileOffset:(BOOL)isKeyFrame;

@end

// AVMvidFileWriter

@implementation AVMvidFileWriter

@synthesize mvidPath = m_mvidPath;
@synthesize frameDuration = m_frameDuration;
@synthesize totalNumFrames = m_totalNumFrames;
@synthesize frameNum = frameNum;
@synthesize bpp = m_bpp;
@synthesize genAdler = m_genAdler;
@synthesize isSRGB = m_isSRGB;
@synthesize movieSize = m_movieSize;

- (void) close
{
  if (maxvidOutFile) {
    fclose(maxvidOutFile);
    maxvidOutFile = NULL;
  }
}

- (void) dealloc
{
  if (maxvidOutFile) {
    [self close];
  }
  
  if (mvHeader) {
    free(mvHeader);
    mvHeader = NULL;
  }
    
  if (mvFramesArray) {
    free(mvFramesArray);
    mvFramesArray = NULL;
  }
    
  self.mvidPath = nil;
  [super dealloc];
}

+ (AVMvidFileWriter*) aVMvidFileWriter
{
  return [[[AVMvidFileWriter alloc] init] autorelease];
}

- (BOOL) open
{
  NSAssert(isOpen == FALSE, @"isOpen");
  NSAssert(self.totalNumFrames > 0, @"totalNumFrames > 0");
  NSAssert(self.frameDuration != 0, @"frameDuration != 0");
  
#ifdef ALWAYS_GENERATE_ADLER
  const int genAdler = 1;
#else  // ALWAYS_GENERATE_ADLER
  const int genAdler = 0;
#endif // ALWAYS_GENERATE_ADLER
  
  if (genAdler) {
    self.genAdler = TRUE;
  }
  
  char *mvidStr = (char*)[self.mvidPath UTF8String];
  
  maxvidOutFile = fopen(mvidStr, "wb");
  
  if (maxvidOutFile == NULL) {
    return FALSE;
  }
  
  mvHeader = malloc(sizeof(MVFileHeader));
  if (mvHeader == NULL) {
    return FALSE;
  }
  memset(mvHeader, 0, sizeof(MVFileHeader));

  // Write zeroed file header
  
  int numWritten = 0;
  
  numWritten = fwrite(mvHeader, sizeof(MVFileHeader), 1, maxvidOutFile);
  if (numWritten != 1) {
    return FALSE;
  }
  
  // Write zeroed frames header
  
  int numOutputFrames = self.totalNumFrames;
  
  framesArrayNumBytes = sizeof(MVFrame) * numOutputFrames;
  mvFramesArray = malloc(framesArrayNumBytes);
  if (mvFramesArray == NULL) {
    return FALSE;
  }
  memset(mvFramesArray, 0, framesArrayNumBytes);
  
  numWritten = fwrite(mvFramesArray, framesArrayNumBytes, 1, maxvidOutFile);
  if (numWritten != 1) {
    return FALSE;
  }
  
  // Store the offset immediately after writing the header
  
  [self saveOffset];
  
  isOpen = TRUE;
  return TRUE;
}

// Write a single nop frame after a keyframe or a delta frame.
// A nop frame has the exact same offset, length, and flags settings
// as the previous frame, with the additional nop flag also set.

- (void) writeNopFrame
{
#ifdef LOGGING
  NSLog(@"writeNopFrame %d", frameNum);
#endif // LOGGING
  
  NSAssert(frameNum != 0, @"nop frame can't be first frame");
  NSAssert(frameNum < self.totalNumFrames, @"totalNumFrames");
  
  MVFrame *mvFrame = &mvFramesArray[frameNum];
  MVFrame *prevMvFrame = &mvFramesArray[frameNum-1];
  
  maxvid_frame_setoffset(mvFrame, maxvid_frame_offset(prevMvFrame));
  maxvid_frame_setlength(mvFrame, maxvid_frame_length(prevMvFrame));
  
  if (maxvid_frame_iskeyframe(prevMvFrame)) {
    maxvid_frame_setkeyframe(mvFrame);
  }
  
  maxvid_frame_setnopframe(mvFrame);
  
  // Note that an adler is not generated for a no-op frame
  
  frameNum++;
}

- (void) writeTrailingNopFrames:(float)currentFrameDuration
{
  int numFramesDelay = round(currentFrameDuration / self.frameDuration);
  
  if (numFramesDelay > 1) {
    for (int count = numFramesDelay; count > 1; count--) {
      [self writeNopFrame];      
    }
  }
}

// Store the current file offset

- (void) saveOffset
{
  offset = ftell(maxvidOutFile);
}

// Advance the file offset to the start of the next page in memory.
// This method assumes that the offset was saved with an earlier call
// to saveOffset

- (void) skipToNextPageBound
{
  offset = maxvid_file_padding_before_keyframe(maxvidOutFile, offset);
 
  NSAssert(frameNum < self.totalNumFrames, @"totalNumFrames");
  
  MVFrame *mvFrame = &mvFramesArray[frameNum];
  
  maxvid_frame_setoffset(mvFrame, (uint32_t)offset);
  
  maxvid_frame_setkeyframe(mvFrame);
}

- (BOOL) writeKeyframe:(char*)ptr bufferSize:(int)bufferSize
{
#ifdef LOGGING
  NSLog(@"writeKeyframe %d : bufferSize %d", frameNum, bufferSize);
#endif // LOGGING
  
  [self skipToNextPageBound];
  
  int numWritten = fwrite(ptr, bufferSize, 1, maxvidOutFile);
  
  if (numWritten != 1) {
    return FALSE;
  } else {
    // Finish emitting frame data
    
    uint32_t length = [self validateFileOffset:TRUE];
        
    NSAssert(frameNum < self.totalNumFrames, @"totalNumFrames");
    
    MVFrame *mvFrame = &mvFramesArray[frameNum];
    
    maxvid_frame_setlength(mvFrame, length);
    
    // Generate adler32 for pixel data and save into frame data
    
    if (self.genAdler) {
      mvFrame->adler = maxvid_adler32(0, (unsigned char*)ptr, bufferSize);
      assert(mvFrame->adler != 0);
    }
    
    // zero pad to next page bound
    
    offset = maxvid_file_padding_after_keyframe(maxvidOutFile, offset);
    assert(offset > 0); // silence compiler/analyzer warning
    
#ifdef LOGGING
    NSLog(@"frame[%d] : offset %u : length %u : adler %u", frameNum, mvFrame->offset, maxvid_frame_length(mvFrame),  mvFrame->adler);
#endif // LOGGING
    
    frameNum++;
    
    return TRUE;
  }
}

- (BOOL) rewriteHeader
{
  NSAssert(self.movieSize.width > 0, @"width");
  NSAssert(self.movieSize.height > 0, @"height");
  NSAssert(self.bpp != 0, @"cpp");
  
  mvHeader->magic = 0; // magic still not valid
  mvHeader->width = self.movieSize.width;
  mvHeader->height = self.movieSize.height;
  mvHeader->bpp = self.bpp;
  
  mvHeader->frameDuration = self.frameDuration;
  assert(mvHeader->frameDuration > 0.0);
  
  mvHeader->numFrames = self.totalNumFrames;
  
  if (self.isSRGB) {
    maxvid_file_colorspace_set_srgb(mvHeader);
  }
  
  (void)fseek(maxvidOutFile, 0L, SEEK_SET);
  
  int numWritten = fwrite(mvHeader, sizeof(MVFileHeader), 1, maxvidOutFile);
  if (numWritten != 1) {
    return FALSE;
  }
  
  numWritten = fwrite(mvFramesArray, framesArrayNumBytes, 1, maxvidOutFile);
  if (numWritten != 1) {
    return FALSE;
  }  
  
  // Once all valid data and headers have been written, it is now safe to write the
  // file header magic number. This ensures that any threads reading the first word
  // of the file looking for a valid magic number will only ever get consistent
  // data in a read when a valid magic number is read.
  
  (void)fseek(maxvidOutFile, 0L, SEEK_SET);
  
  uint32_t magic = MV_FILE_MAGIC;
  numWritten = fwrite(&magic, sizeof(uint32_t), 1, maxvidOutFile);
  if (numWritten != 1) {
    return FALSE;
  }
  
  return TRUE;
}

// write delta frame, non-zero adler must be passed if adler is enabled

- (BOOL) writeDeltaframe:(char*)ptr bufferSize:(int)bufferSize adler:(uint32_t)adler
{
#ifdef LOGGING
  NSLog(@"writeDeltaframe %d : bufferSize %d", frameNum, bufferSize);
#endif // LOGGING

  [self saveOffset];
  
  int numWritten = fwrite(ptr, bufferSize, 1, maxvidOutFile);
  
  if (numWritten != 1) {
    return FALSE;
  } else {
    // Finish writing the frame data

    NSAssert(frameNum < self.totalNumFrames, @"totalNumFrames");
    
    MVFrame *mvFrame = &mvFramesArray[frameNum];
    
    // Note that offset must be saved before validateFileOffset is invoked
    
    maxvid_frame_setoffset(mvFrame, (uint32_t)offset);
    
    uint32_t length = [self validateFileOffset:FALSE];
    
    maxvid_frame_setlength(mvFrame, length);
    
    mvFrame->adler = adler;
    
#ifdef LOGGING
    NSLog(@"frame[%d] : offset %u : length %u : adler %u", frameNum, mvFrame->offset, maxvid_frame_length(mvFrame),  mvFrame->adler);
#endif // LOGGING
    
    frameNum++;
    
    return TRUE;
  }
}

- (uint32_t) validateFileOffset:(BOOL)isKeyFrame
{
  uint32_t offsetBefore = (uint32_t)self->offset;
  offset = ftell(maxvidOutFile);
  uint32_t length = ((uint32_t)offset) - offsetBefore;
  NSAssert(length > 0, @"length must be larger than");
    
  // Typically, the framebuffer is an even number of pixels.
  // There is an odd case though, when emitting 16 bit pixels
  // is is possible that the total number of pixels written
  // is odd, so in this case the framebuffer is not a whole
  // number of words.
  
  if (isKeyFrame) {
    NSAssert((length % 2) == 0, @"offset length must be even");
  }
  
  if (isKeyFrame && (self.bpp == 16)) {
    if ((length % 4) != 0) {
      // Write a zero half-word to the file so that additional padding is in terms of whole words.
      uint16_t zeroHalfword = 0;
      size_t size = fwrite(&zeroHalfword, sizeof(zeroHalfword), 1, maxvidOutFile);
      assert(size == 1);
      offset = ftell(maxvidOutFile);
      // Note that length is not recalculated. If a delta frame appears after this
      // one, it must begin on a word bound. The frame length ignores the halfword padding.
      //length = ((uint32_t)offset) - offsetBefore;
    }
  } else {
    NSAssert((length % 4) == 0, @"byte length is not in terms of whole words");    
  }

  return length;
}

@end
