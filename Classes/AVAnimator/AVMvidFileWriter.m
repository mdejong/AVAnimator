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
@synthesize movieSize = m_movieSize;
@synthesize isAllKeyframes = m_isAllKeyframes;

#if MV_ENABLE_DELTAS
@synthesize isDeltas = m_isDeltas;
#endif // MV_ENABLE_DELTAS

// Emit zero length words up to the next page bound after the keyframe data.
// Pass in the current offset, function returns the new offset.
// This method will emit zero words of padding if exactly on the page bound already.

- (off_t) paddingAfterKeyframe:(FILE*)outFile offset:(off_t)_offset
{
#if defined(DEBUG)
  if (self.genV3PageOffsetBlocks) {
    // Nop
  } else {
    assert((_offset % 4) == 0);
  }
#endif // DEBUG
  
  const uint32_t boundSize = MV_PAGESIZE;
  uint32_t bytesToBound = UINTMOD((uint32_t)_offset, boundSize);
  assert(bytesToBound >= 0 && bytesToBound <= boundSize);
  
  bytesToBound = boundSize - bytesToBound;
  
  if (self.genV3PageOffsetBlocks) {
    uint32_t nBytesToWordBound = bytesToBound % sizeof(uint32_t);
    uint8_t zeroByte = 0;
    while (nBytesToWordBound != 0) {
      size_t size = fwrite(&zeroByte, sizeof(zeroByte), 1, outFile);
      assert(size == 1);
      nBytesToWordBound--;
      bytesToBound--;
    }
  }
  
  uint32_t wordsToBound = bytesToBound >> 2;
  wordsToBound &= ((MV_PAGESIZE >> 2) - 1);
  
#if defined(DEBUG)
  if (wordsToBound > 0) {
    assert(bytesToBound == (wordsToBound * 4));
    assert(wordsToBound < (boundSize / 4));
  }
#endif // DEBUG
  
  // write aligned words
  
  uint32_t zero = 0;
  while (wordsToBound != 0) {
    size_t size = fwrite(&zero, sizeof(zero), 1, outFile);
    assert(size == 1);
    wordsToBound--;
  }
  
  off_t offsetAfterOff = ftello(outFile);
  assert(offsetAfterOff != -1);
  
  if (self.genV3PageOffsetBlocks) {
    // Nop
  } else {
    assert(offset < 0xFFFFFFFF);
  }
  
  // Note that in the case where offsetAfterOff is larger
  // than the max 32 bit value, this will clamp to 32 bits
  // and then only examine the low bits anyway.
  
#if defined(DEBUG)
  assert(UINTMOD((uint32_t)offsetAfterOff, boundSize) == 0);
#endif // DEBUG
  
  return offsetAfterOff;
}

- (void) close
{
  if (maxvidOutFile) {
    fclose(maxvidOutFile);
    maxvidOutFile = NULL;
  }
  isOpen = FALSE;
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
  
#if __has_feature(objc_arc)
#else
  [super dealloc];
#endif // objc_arc
}

+ (AVMvidFileWriter*) aVMvidFileWriter
{
  AVMvidFileWriter *obj = [[AVMvidFileWriter alloc] init];
#if __has_feature(objc_arc)
  return obj;
#else
  return [obj autorelease];
#endif // objc_arc
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
  
  numWritten = (int) fwrite(mvHeader, sizeof(MVFileHeader), 1, maxvidOutFile);
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
  
  numWritten = (int) fwrite(mvFramesArray, framesArrayNumBytes, 1, maxvidOutFile);
  if (numWritten != 1) {
    return FALSE;
  }
  
  // Store the offset immediately after writing the header
  
  [self saveOffset];
  
  self->isOpen = TRUE;
  self.isAllKeyframes = TRUE;
  
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

#if MV_ENABLE_DELTAS

// Write special case nop frame that appears at the begining of
// the file. The weird special case bascially means that the
// first frame is constructed by applying a frame delta to an
// all black framebuffer.

- (void) writeInitialNopFrame
{
#ifdef LOGGING
  NSLog(@"writeInitialNopFrame %d", frameNum);
#endif // LOGGING
  
  NSAssert(frameNum == 0, @"initial nop frame must be first frame");
  NSAssert(frameNum < self.totalNumFrames, @"totalNumFrames");
  
  MVFrame *mvFrame = &mvFramesArray[frameNum];
  
  maxvid_frame_setoffset(mvFrame, 0);
  maxvid_frame_setlength(mvFrame, 0);

  // This special case initial nop frame is only emitted with the
  // all deltas type of mvid file, this type of file contains no
  // keyframes, only deltas frames.
  
  maxvid_frame_setnopframe(mvFrame);
  
  // Normally, an adler is not generated for a nop frame. But
  // this nop frame is actually like a keyframe with all black
  // pixels. So, set the adler to all bits on.
  
  mvFrame->adler = 0xFFFFFFFF;
  
  frameNum++;
}

#endif // MV_ENABLE_DELTAS

+ (int) countTrailingNopFrames:(float)currentFrameDuration
                 frameDuration:(float)frameDuration
{
  int numFramesDelay = round(currentFrameDuration / frameDuration);
  
  if (numFramesDelay > 1) {
    return numFramesDelay - 1;
  } else {
    return 0;
  }
}

- (void) writeTrailingNopFrames:(float)currentFrameDuration
{
  int count = [self.class countTrailingNopFrames:currentFrameDuration frameDuration:self.frameDuration];
  
  if (count > 0) {
    for (; count; count--) {
      [self writeNopFrame];
    }
  }
}

// Store the current file offset

- (void) saveOffset
{
  offset = ftello(maxvidOutFile);
  NSAssert(offset != -1, @"ftello returned -1");
  
  if (self.genV3PageOffsetBlocks) {
    // Nop
  } else {
    NSAssert(offset < 0xFFFFFFFF, @"ftello offset must fit into 32 bits, got %qd", offset);
  }
}

// Advance the file offset to the start of the next page in memory.
// This method assumes that the offset was saved with an earlier call
// to saveOffset

- (void) skipToNextPageBound
{
  offset = [self paddingAfterKeyframe:maxvidOutFile offset:offset];
 
  NSAssert(frameNum < self.totalNumFrames, @"totalNumFrames");
  
  MVFrame *mvFrame = &mvFramesArray[frameNum];
  
  if (self.genV3PageOffsetBlocks) {
    // Write the total number of whole memory pages. Note that
    // in the case of writing uncompressed pixels the decoder
    // will be able to figure out the exact actual width
    // by calculating the number of bytes in the frame.
    
    uint32_t numPages = (uint32_t) (offset / MV_PAGESIZE);
    
    if ((offset % MV_PAGESIZE) != 0) {
      numPages++;
    }
    
#ifdef LOGGING
    NSLog(@"skipToNextPageBound %d : next page offset %llu will be written as %d pages", frameNum, offset, numPages);
#endif // LOGGING
    
    maxvid_frame_setoffset(mvFrame, numPages);
  } else {
    // Without the V3 flag file offsets are limited to 32 bits
    
    maxvid_frame_setoffset(mvFrame, (uint32_t)offset);
  }
  
  maxvid_frame_setkeyframe(mvFrame);
}

- (BOOL) writeKeyframe:(char*)ptr bufferSize:(int)bufferSize
{
  return [self writeKeyframe:ptr bufferSize:bufferSize adler:0];
}

- (BOOL) writeKeyframe:(char*)ptr bufferSize:(int)bufferSize adler:(uint32_t)adler
{
#ifdef LOGGING
  NSLog(@"writeKeyframe %d : bufferSize %d : adler %08X", frameNum, bufferSize, adler);
#endif // LOGGING
  
  [self skipToNextPageBound];
  
  int numWritten = (int) fwrite(ptr, bufferSize, 1, maxvidOutFile);
  
  if (numWritten != 1) {
    return FALSE;
  } else {
    // Finish emitting frame data
    
    uint32_t length = [self validateFileOffset:TRUE];
        
    NSAssert(frameNum < self.totalNumFrames, @"totalNumFrames");
    
    NSAssert(length == bufferSize, @"length");
    
    MVFrame *mvFrame = &mvFramesArray[frameNum];
    
    if (self.genV3PageOffsetBlocks) {
      // If the length of the data segment exactly matches the
      // number of pixels * size of pixel then set the length
      // to zero so that the decoder can simply assume the
      // dimensions.
      
      uint32_t expectedNumBytes;
      
      if (self.bpp == 16) {
        expectedNumBytes = self.movieSize.width * self.movieSize.height * sizeof(uint16_t);
        if ((expectedNumBytes % sizeof(uint32_t)) != 0) {
          expectedNumBytes += sizeof(uint16_t);
        }
      } else {
        expectedNumBytes = self.movieSize.width * self.movieSize.height * sizeof(uint32_t);
      }
      
      if (length == expectedNumBytes) {
#ifdef LOGGING
        NSLog(@"writeKeyframe %d : bufferSize %d will be written as zero implicit value", frameNum, bufferSize);
#endif // LOGGING
        
        length = 0;
      } else {
        // Use passed in length as num bytes
        
#ifdef LOGGING
        NSLog(@"writeKeyframe %d : bufferSize %d will be written as %d num bytes", frameNum, bufferSize, bufferSize);
#endif // LOGGING
      }
    }
    
    maxvid_frame_setlength(mvFrame, length);
    
    // Generate adler32 for pixel data and save into frame data
    
    if (self.genAdler) {
      if (adler == 0) {
        mvFrame->adler = maxvid_adler32(0, (unsigned char*)ptr, bufferSize);
      } else {
        mvFrame->adler = adler;
      }
      assert(mvFrame->adler != 0);
    }
    
    // zero pad to next page bound
    
    offset = [self paddingAfterKeyframe:maxvidOutFile offset:offset];
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
  
  // The number of frames must always be at least 2 frames.
  
  NSAssert(self.totalNumFrames > 1, @"animation must have at least 2 frames, not %d", self.totalNumFrames);  
  mvHeader->numFrames = self.totalNumFrames;
  
  // This file writer always emits a file with version set to 2
  
  if (self.genV3PageOffsetBlocks) {
    NSAssert(self.isAllKeyframes, @"isAllKeyframes must be TRUE when genV3PageOffsetBlocks is set");
    
    maxvid_file_set_version(mvHeader, MV_FILE_VERSION_THREE);
  } else {
    maxvid_file_set_version(mvHeader, MV_FILE_VERSION_TWO);
  }
  
  // If all frames written were keyframes (or nop frames)
  // then set a flag to indicate this special case.
  
  if (self.isAllKeyframes) {
    maxvid_file_set_all_keyframes(mvHeader);
  }
  
#if MV_ENABLE_DELTAS
  
  if (self.isDeltas) {
    maxvid_file_set_deltas(mvHeader);
  }
  
#endif // MV_ENABLE_DELTAS
  
  (void)fseek(maxvidOutFile, 0L, SEEK_SET);
  
  int numWritten = (int) fwrite(mvHeader, sizeof(MVFileHeader), 1, maxvidOutFile);
  if (numWritten != 1) {
    return FALSE;
  }
  
  numWritten = (int) fwrite(mvFramesArray, framesArrayNumBytes, 1, maxvidOutFile);
  if (numWritten != 1) {
    return FALSE;
  }  
  
  // Once all valid data and headers have been written, it is now safe to write the
  // file header magic number. This ensures that any threads reading the first word
  // of the file looking for a valid magic number will only ever get consistent
  // data in a read when a valid magic number is read.
  
  (void)fseek(maxvidOutFile, 0L, SEEK_SET);
  
  uint32_t magic = MV_FILE_MAGIC;
  numWritten = (int) fwrite(&magic, sizeof(uint32_t), 1, maxvidOutFile);
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
  
  if (self.genV3PageOffsetBlocks) {
    NSAssert(self.isAllKeyframes, @"writeDeltaframe can only emit keyframes in V3 mode");
  }
  
  self.isAllKeyframes = FALSE;
  
  [self saveOffset];
  
  int numWritten = (int) fwrite(ptr, bufferSize, 1, maxvidOutFile);
  
  if (numWritten != 1) {
    return FALSE;
  } else {
    // Finish writing the frame data

    NSAssert(frameNum < self.totalNumFrames, @"totalNumFrames");
    
    MVFrame *mvFrame = &mvFramesArray[frameNum];
    
    // FIXME: currently, the file offset is limited to the max size of a 32 bit unsigned
    // integer. This limits the total file size to abount 4 gigs, but that could be a
    // problem for really large files with high FPS. But, fixing this by adjusting the
    // offset to 64 bits would break backwards compat on the file offset in the frames
    // structure.
    
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

// Check the previous and current file offset and return the length
// of the frame data. Note that the difference between two frame offsets
// will always fit into a 32 bit integer.

- (uint32_t) validateFileOffset:(BOOL)isKeyFrame
{
  off_t offsetBefore = self->offset;
  offset = ftello(maxvidOutFile);
  NSAssert(offset != -1, @"ftello returned -1");
  
  if (self.genV3PageOffsetBlocks) {
    // nop
  } else {
    NSAssert(offset < 0xFFFFFFFF, @"ftello offset must fit into 32 bits, got %qd", offset);
  }
  off_t lengthOff = offset - offsetBefore;
  assert(lengthOff < 0xFFFFFFFF);
  uint32_t length = (uint32_t) lengthOff;
  NSAssert(length > 0, @"length must be larger than zero");
  
  if (self.genV3PageOffsetBlocks) {
    // Allow byte or half byte segment length with v3
    return length;
  }
  
  // Typically, the framebuffer is an even number of pixels.
  // There is an odd case though, when emitting 16 bit pixels
  // is is possible that the total number of pixels written
  // is odd, so in this case the framebuffer is not a whole
  // number of words.
  
  if (isKeyFrame) {
    NSAssert((length % 2) == 0, @"offset length must be even, not %d", length);
  }
  
  if (isKeyFrame && (self.bpp == 16)) {
    if ((length % 4) != 0) {
      // Write a zero half-word to the file so that additional padding is in terms of whole words.
      uint16_t zeroHalfword = 0;
      size_t size = fwrite(&zeroHalfword, sizeof(zeroHalfword), 1, maxvidOutFile);
      assert(size == 1);
      offset = ftello(maxvidOutFile);
      NSAssert(offset != -1, @"ftello returned -1");
      NSAssert(offset < 0xFFFFFFFF, @"ftello offset must fit into 32 bits, got %qd", offset);
      // Note that length is not recalculated. If a delta frame appears after this
      // one, it must begin on a word bound. The frame length ignores the halfword padding.
      //length = ...;
    }
  } else {
    NSAssert((length % 4) == 0, @"byte length is not in terms of whole words");    
  }

  return length;
}

@end
