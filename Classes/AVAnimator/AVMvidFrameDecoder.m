//
//  AVMvidFrameDecoder.m
//
//  Created by Moses DeJong on 1/4/11.
//
//  License terms defined in License.txt.

#import "AVMvidFrameDecoder.h"

#import "CGFrameBuffer.h"

#import "AVFrame.h"

#import "maxvid_file.h"

#if MV_ENABLE_DELTAS
#include "maxvid_deltas.h"
#endif // MV_ENABLE_DELTAS

#if defined(USE_SEGMENTED_MMAP)
#import "SegmentedMappedData.h"
#endif // USE_SEGMENTED_MMAP

#ifndef __OPTIMIZE__
// Automatically define EXTRA_CHECKS when not optimizing (in debug mode)
# define EXTRA_CHECKS
#endif // DEBUG

#if TARGET_OS_IPHONE
// Adler checking not always enabled on iOS since it can slow down the decompression
// process. Specifically, when keyframe memory has been mapped but it has not yet
// been accessed, then we do not want to have to wait for all page faults by forcing
// an adler check every time.

//#define ALWAYS_CHECK_ADLER
#else
// Always check adler when executing in mvidmoviemaker on the desktop

#define ALWAYS_CHECK_ADLER
#endif // TARGET_OS_IPHONE

// private properties declaration for class

@interface AVMvidFrameDecoder ()

// This is the last AVFrame object returned via a call to advanceToFrame

@property (nonatomic, retain) AVFrame *lastFrame;

@property (nonatomic, assign) MVFrame *mvFrames;

@end


@implementation AVMvidFrameDecoder

@synthesize filePath = m_filePath;
@synthesize mappedData = m_mappedData;
@synthesize currentFrameBuffer = m_currentFrameBuffer;
@synthesize cgFrameBuffers = m_cgFrameBuffers;
@synthesize lastFrame = m_lastFrame;
@synthesize mvFrames = m_mvFrames;

#if defined(REGRESSION_TESTS)
@synthesize simulateMemoryMapFailure = m_simulateMemoryMapFailure;
#endif // REGRESSION_TESTS

@synthesize upgradeFromV1 = m_upgradeFromV1;

- (void) dealloc
{
  [self close];

  if (self->m_mvFrames) {
    free(self->m_mvFrames);
  }
  
  self.filePath = nil;
  self.mappedData = nil;
  self.currentFrameBuffer = nil;
  self.lastFrame = nil;
  
  /*
   for (CGFrameBuffer *aBuffer in self.cgFrameBuffers) {
   int count = [aBuffer retainCount];
   count = count;
   
   if (aBuffer.isLockedByDataProvider) {
   NSString *msg = [NSString stringWithFormat:@"%@, count %d",
   @"CGFrameBuffer is still locked by UIKit", count];
   NSLog(msg);
   
   if ([aBuffer isLockedByImageRef:imgRef1]) {
   NSLog(@"locked by imgRef1");
   } else if ([aBuffer isLockedByImageRef:imgRef2]) {
   NSLog(@"locked by imgRef2");
   } else if ([aBuffer isLockedByImageRef:imgRef3]) {
   NSLog(@"locked by imgRef3");
   } else {
   NSLog(@"locked by unknown image ref");				
   }
   }
   }
   */

  self.cgFrameBuffers = nil;

#if MV_ENABLE_DELTAS
  
  if (decompressionBuffer) {
    free(decompressionBuffer);
    decompressionBuffer = NULL;
    decompressionBufferSize = 0;
  }
  
#endif // MV_ENABLE_DELTAS
  
#if __has_feature(objc_arc)
#else
  [super dealloc];
#endif // objc_arc
}

- (id) init
{
  if ((self = [super init]) != nil) {
    self->frameIndex = -1;
    self->m_resourceUsageLimit = TRUE;
  }
  return self;
}

// Constructor

+ (AVMvidFrameDecoder*) aVMvidFrameDecoder
{
  AVMvidFrameDecoder *obj = [[AVMvidFrameDecoder alloc] init];
#if __has_feature(objc_arc)
  return obj;
#else
  return [obj autorelease];
#endif // objc_arc
}

- (MVFileHeader*) header
{
  NSAssert(self->m_isOpen == TRUE, @"isOpen");
  return &self->m_mvHeader;
}

- (void) _allocFrameBuffers
{
  // create buffers used for loading image data
  
  if (self.cgFrameBuffers != nil) {
    // Already allocated the frame buffers
    return;
  }
  
  int renderWidth  = (int) [self width];
  int renderHeight = (int) [self height];
  
  NSAssert(renderWidth > 0 && renderHeight > 0, @"renderWidth or renderHeight is zero");

  uint32_t bitsPerPixel = [self header]->bpp;
  
  CGFrameBuffer *cgFrameBuffer1 = [CGFrameBuffer cGFrameBufferWithBppDimensions:bitsPerPixel width:renderWidth height:renderHeight];
  CGFrameBuffer *cgFrameBuffer2 = [CGFrameBuffer cGFrameBufferWithBppDimensions:bitsPerPixel width:renderWidth height:renderHeight];
  CGFrameBuffer *cgFrameBuffer3 = [CGFrameBuffer cGFrameBufferWithBppDimensions:bitsPerPixel width:renderWidth height:renderHeight];
  
  self.cgFrameBuffers = [NSArray arrayWithObjects:cgFrameBuffer1, cgFrameBuffer2, cgFrameBuffer3, nil];
  
  // Double check size assumptions
  
  if (bitsPerPixel == 16) {
    NSAssert(cgFrameBuffer1.bytesPerPixel == 2, @"invalid bytesPerPixel");
  } else if (bitsPerPixel == 24 || bitsPerPixel == 32) {
    NSAssert(cgFrameBuffer1.bytesPerPixel == 4, @"invalid bytesPerPixel");
  } else {
    NSAssert(FALSE, @"invalid bitsPerPixel");
  }
  
  // If the input frames are in sRGB colorspace, then mark each frame so that RGB data is interpreted
  // as sRGB instead of generic RGB.
  // http://www.pupuweb.com/blog/wwdc-2012-session-523-practices-color-management-ken-greenebaum-luke-wallis/

#if TARGET_OS_IPHONE
  // No-op
#else
  // Under iOS, device is always sRGB. Under MacOSX we must always explicitly treat input pixels as
  // being defined in the sRGB colorspace.
  
  if (1) {
    CGColorSpaceRef colorSpace = NULL;
    colorSpace = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    NSAssert(colorSpace, @"colorSpace");
    for (CGFrameBuffer *cgFrameBuffer in self.cgFrameBuffers) {
      cgFrameBuffer.colorspace = colorSpace;
    }
    CGColorSpaceRelease(colorSpace);
  }
#endif // TARGET_OS_IPHONE
  
  self->m_resourceUsageLimit = FALSE;
}

- (void) _freeFrameBuffers
{
  self.currentFrameBuffer = nil;
  self.cgFrameBuffers = nil;
  // Drop AVFrame since it holds on to the image which holds on to a framebuffer
  self.lastFrame = nil;
}

// Return the next available framebuffer, this will be the framebuffer that the
// next decode operation will decode into.

- (CGFrameBuffer*) _getNextFramebuffer
{
  [self _allocFrameBuffers];
  
  CGFrameBuffer *cgFrameBuffer = nil;
  for (CGFrameBuffer *aBuffer in self.cgFrameBuffers) {
    if (aBuffer == self.currentFrameBuffer) {
      // When a framebuffer is the "current" one, it contains
      // the decoded output from a previous frame. Need to
      // ignore it and select the next available one.

      continue;
    }    
    if (!aBuffer.isLockedByDataProvider) {
      cgFrameBuffer = aBuffer;
      break;
    }
  }
  if (cgFrameBuffer == nil) {
    NSAssert(FALSE, @"no cgFrameBuffer is available");
  }
  return cgFrameBuffer;
}

// This utility method will read the header data from an mvid
// file without mapping it into memory. The contents of the
// header will be copied so that header metadata can be
// queried without having to map the whole file. A mvid file
// can't be changed after the header is written, so it is safe
// to cache the contents of the header and then map and unmap
// the whole file as needed without worry of an invalid cache.

- (BOOL) _openAndCopyHeaders
{
  MVFileHeader *hPtr = &self->m_mvHeader;

  char* filenameCstr = (char*)[self.filePath UTF8String];
  FILE *fp = fopen(filenameCstr, "rb");
  if (fp == NULL) {
    // Return FALSE to indicate that the file could not be opened
    return FALSE;
  }
  
  BOOL worked = TRUE;
  
  // Copy the whole header into the struct. Any valid file will
  // contain a whole header, so if the read does not work then
  // the file is not valid.
  
  assert(sizeof(MVFileHeader) == 16*4);
  assert(sizeof(MVFrame) == 3*4);
  
  int numRead = (int) fread(hPtr, sizeof(MVFileHeader), 1, fp);
  if (numRead != 1) {
    // Could not read header from file, it must be empty or invalid
    worked = FALSE;
  }
  
  
  if (worked) {
    uint32_t magic = hPtr->magic;
    if (magic != MV_FILE_MAGIC) {
      // Reading the header worked, but if the magic number is not valid then
      // this is not a valid maxvid file. Could have been another kind of file
      // or could have been a partially written maxvid file.
      
      worked = FALSE;
    }
    
    if (worked) {
      uint32_t bpp = hPtr->bpp;
      NSAssert(bpp == 16 || bpp == 24 || bpp == 32, @"bpp must be 16, 24, 32");
    }
  }
  
  if (worked) {
    // Read array of MVFrame objects into dynamically allocated array.
    
    NSUInteger numFrames = hPtr->numFrames;
    NSAssert(numFrames > 1, @"numFrames");
    int numBytes = (int) (sizeof(MVFrame) * numFrames);
    self->m_mvFrames = malloc(numBytes);
    
    if (self->m_mvFrames == NULL) {
      // Malloc failed
      worked = FALSE;
    }
    
    if (worked) {
      int numRead = (int) fread(self->m_mvFrames, numBytes, 1, fp);
      if (numRead != 1) {
        // Could not read frames from file
        worked = FALSE;
      }      
    }    
  }
  
  fclose(fp);
  return worked;
}

// Private utils to map the .mvid file into memory.
// Return TRUE if memory map was successful or file is already mapped.
// Otherwise, returns FALSE when memory map was not successful.

- (BOOL) _mapFile {
  if (self.mappedData == nil) {
    // Might need to map a very large mvid file in terms of 24 Meg chunks,
    // would want to write it that way?

    BOOL memoryMapFailed = FALSE;

#if defined(REGRESSION_TESTS)
    if (self.simulateMemoryMapFailure) {
      memoryMapFailed = TRUE;
    }
#endif // REGRESSION_TESTS

#if defined(USE_SEGMENTED_MMAP)
    if (memoryMapFailed == FALSE) {
      self.mappedData = [SegmentedMappedData segmentedMappedData:self.filePath];
      
      if (self.mappedData == nil) {
        memoryMapFailed = TRUE;
      }

      if (memoryMapFailed == FALSE) {
        // Map just the first page just to make sure mapping is actually working
        
        BOOL worked;
        
        NSRange range;
        range.location = 0;
        range.length = MV_PAGESIZE;
        
        SegmentedMappedData *seg0 = [self.mappedData subdataWithRange:range];
        if (seg0) {
          worked = TRUE;
        } else {
          worked = FALSE;
        }        
        if (worked) {
          worked = [seg0 mapSegment];
        }
        if (worked == FALSE) {
          self.mappedData = nil;
          memoryMapFailed = TRUE;
        } else {
          // Mapping the first page was successful, double check the contents
          // of the first page with maxvid_file_map_open().
          
          void *segPtr = (void*) [seg0 bytes];
          maxvid_file_map_verify(segPtr);
        }
        
        [seg0 unmapSegment];
      }
    }
    
    if (memoryMapFailed == TRUE) {
      return FALSE;
    }
    
#else // USE_SEGMENTED_MMAP
    if (memoryMapFailed == FALSE) {
      self.mappedData = [NSData dataWithContentsOfMappedFile:self.filePath];
      if (self.mappedData == nil) {
        memoryMapFailed = TRUE;
      }
    }
    
    if (memoryMapFailed == TRUE) {
      return FALSE;
    }
    
    void *mappedPtr = (void*)[self.mappedData bytes];
    maxvid_file_map_verify(mappedPtr);
#endif // USE_SEGMENTED_MMAP
  
    self->m_resourceUsageLimit = FALSE;
  } // end if (self.mappedData == nil)
    
  return TRUE;
}

- (void) _unmapFile {
  self.mappedData = nil;
}

- (BOOL) openForReading:(NSString*)moviePath
{
  if (self->m_isOpen) {
    return FALSE;
  }
  
  if (![[moviePath pathExtension] isEqualToString:@"mvid"]) {
    return FALSE;
  }
  
  self.filePath = moviePath;
  
  // Opening the file will verify that the header is correct to ensure that the file was not
  // partially written. The header will then be read so that this object has access to
  // the data contained in the header. Note that the file need not be successfully mapped
  // into memory at this point. It is possible that many files could be open but the file
  // need not be mapped into memory until it is actually used.  
  
  BOOL worked = [self _openAndCopyHeaders];
  if (!worked) {
    self.filePath = nil;
    return FALSE;
  }

  self->m_isOpen = TRUE;
  return TRUE;
}

// Close resource opened earlier

- (void) close
{
  [self _unmapFile];
  
  frameIndex = -1;
  self.currentFrameBuffer = nil;
  self.lastFrame = nil;
  
  self->m_isOpen = FALSE;  
}

- (void) rewind
{
  if (!self->m_isOpen) {
    return;
  }
  
  frameIndex = -1;
  self.currentFrameBuffer = nil;
  self.lastFrame = nil;
}

// This module scoped method will assert that the adler calculated from
// the passed in framebuffer exactly matches the expected adler checksum.
// In the case of an odd number of pixels in the framebuffer, the additional
// zero padded pixels in the framebuffer are included in the adler calculation
// logic.

#if defined(EXTRA_CHECKS) || defined(ALWAYS_CHECK_ADLER)

- (void) assertSameAdler:(uint32_t)expectedAdler
             frameBuffer:(void*)frameBuffer
     frameBufferNumBytes:(uint32_t)frameBufferNumBytes
{
  // If mvid file has adler checksum for frame, verify that it matches the decoded framebuffer contents
  if (expectedAdler != 0) {
    uint32_t frameAdler = maxvid_adler32(0, (unsigned char*)frameBuffer, frameBufferNumBytes);
    NSAssert(frameAdler == expectedAdler, @"frameAdler");
  }
}

#endif // EXTRA_CHECKS || ALWAYS_CHECK_ADLER

- (AVFrame*) advanceToFrame:(NSUInteger)newFrameIndex
{
  // The movie data must have been mapped into memory by the time advanceToFrame is invoked
  
  if (self.mappedData == nil) {
    NSAssert(FALSE, @"file not mapped");
  }
  
  // Get from queue of frame buffers!
  
  CGFrameBuffer *nextFrameBuffer = [self _getNextFramebuffer];
  
  // Double check that the current frame is not the exact same object as the one we pass as
  // the next frame buffer. This should not happen, and we can't copy the buffer into itself.
  
  NSAssert(nextFrameBuffer != self.currentFrameBuffer, @"current and next frame buffers can't be the same object");  
  
  // Advance to same frame a 2nd time, this should return the exact same frame object
  
  if ((frameIndex != -1) && (newFrameIndex == frameIndex)) {
    NSAssert(self.lastFrame != nil, @"lastFrame");
    return self.lastFrame;
  } else if ((frameIndex != -1) && (newFrameIndex < frameIndex)) {
    // movie frame index can only go forward via advanceToFrame
    NSAssert(FALSE, @"%@: %d -> %d",
             @"can't advance to frame before current frameIndex",
             frameIndex,
             (int)newFrameIndex);
  }
  
  // Get the number of frames directly from the header
  // instead of invoking method to query self.numFrames.
  
  int numFrames = (int) [self numFrames];
  
  if (newFrameIndex >= numFrames) {
    NSAssert(FALSE, @"%@: %d", @"can't advance past last frame", (int) newFrameIndex);
  }
  
#if defined(EXTRA_CHECKS)
  // Verify that input file is mvid version 2. Version 0 and 1 files will not
  // load properly on ARM64 hardware.
  
  MVFileHeader *header = [self header];
  
  if (self.upgradeFromV1 == FALSE && maxvid_file_version(header) < MV_FILE_VERSION_TWO) {
    NSAssert(FALSE, @"only .mvid files version 2 or newer can be used, you must -upgrade this .mvid from version %d", maxvid_file_version(header));
  }
#endif // EXTRA_CHECKS
  
  BOOL changeFrameData = FALSE;
  const int newFrameIndexSigned = (int) newFrameIndex;
  
#if defined(USE_SEGMENTED_MMAP)
#else
  char *mappedPtr = (char*) [self.mappedData bytes];
  NSAssert(mappedPtr, @"mappedPtr");
#endif // USE_SEGMENTED_MMAP
  
  uint32_t frameBufferSize = (uint32_t) ([self width] * [self height]);
  uint32_t bpp = [self header]->bpp;
  uint32_t frameBufferNumBytes = (uint32_t) nextFrameBuffer.numBytes;
  NSAssert(frameBufferNumBytes > 0, @"frameBufferNumBytes"); // to avoid compiler warning
  
#if MV_ENABLE_DELTAS
  uint32_t isDeltas = [self isDeltas];
#endif // MV_ENABLE_DELTAS
    
  // Check for the case where multiple frames need to be processed,
  // if one of the frames between the current frame and the target
  // frame is a keyframe, then save time by skipping directly to
  // that keyframe (avoids memcpy when not needed) and then
  // applying deltas from the keyframe to the target frame.
  
  if ((newFrameIndexSigned > 0) && ((newFrameIndexSigned - frameIndex) > 1)) {
    int lastKeyframeIndex = -1;
    
    for ( int i = frameIndex ; i < newFrameIndexSigned; i++) {
      int actualFrameIndex = i + 1;
      MVFrame *frame = maxvid_file_frame(self->m_mvFrames, actualFrameIndex);
      
      if (maxvid_frame_isnopframe(frame)) {
        // This frame is a no-op, since it duplicates data from the previous frame.
      } else {
        if (maxvid_frame_iskeyframe(frame)) {
          lastKeyframeIndex = i;
        }
      }
    }
    // Don't set frameIndex for the first frame (frameIndex == -1)
    if (lastKeyframeIndex > -1) {
      frameIndex = lastKeyframeIndex;
      
#ifdef EXTRA_CHECKS
      int actualFrameIndex = frameIndex + 1;
      MVFrame *frame = maxvid_file_frame(self->m_mvFrames, actualFrameIndex);
      NSAssert(maxvid_frame_iskeyframe(frame) == 1, @"frame must be a keyframe");
#endif // EXTRA_CHECKS      
    }
  }
  
  // loop from current frame to target frame, applying deltas as we go.
  
  int inputMemoryMapped = TRUE;
  
  for ( ; inputMemoryMapped && (frameIndex < newFrameIndexSigned); frameIndex++) @autoreleasepool {
    int actualFrameIndex = frameIndex + 1;
    MVFrame *frame = maxvid_file_frame(self->m_mvFrames, actualFrameIndex);

#ifdef EXTRA_CHECKS
# if MV_ENABLE_DELTAS
    if (isDeltas) {
      NSAssert(maxvid_frame_iskeyframe(frame) == 0, @"frame must not be a keyframe in deltas mode");
    }
# endif // MV_ENABLE_DELTAS
    
    if (actualFrameIndex == 0) {
# if MV_ENABLE_DELTAS
      if (isDeltas == FALSE) {
        NSAssert(maxvid_frame_iskeyframe(frame) == 1, @"initial frame must be a keyframe");
      }
# else
      NSAssert(maxvid_frame_iskeyframe(frame) == 1, @"initial frame must be a keyframe");
# endif // MV_ENABLE_DELTAS
    }
#endif // EXTRA_CHECKS
    
#if MV_ENABLE_DELTAS
    
    if (isDeltas && actualFrameIndex == 0) {
      // Delta logic assumes that the previous framebuffer is made up of all black zero pixels.
      // Explicitly create the "last" framebuffer so that we can apply a patch below. Note
      // that we have to explicitly mark the data as changed because we want a new frame
      // that is not marked as a duplicate of the previous frame to be returned.
      
      if (maxvid_frame_isnopframe(frame)) {
        changeFrameData = TRUE;
      }
      
      AVFrame *frame = [AVFrame aVFrame];
      NSAssert(frame, @"AVFrame is nil");
      
      // FIXME: would it be possible to not even create a "last frame and framebuffer"
      // and instead just set them to nil and clear the next framebuffer so that
      // we can avoid a copy of plain black pixels anyway? That would also mean
      // this logic would not need to get 2 buffers or set the lastFrame value.
      // Unclear how the nop initial frame would work with that approach though.
      
      // FIXME: is it possible to rewind in deltas mode and skip past the initial
      // frame such that the prev data framebuffer has some old junk video frames?
      
      // Mark the nextFrameBuffer as locked for a moment so that we can be sure
      // it will not be returned again by asking for the next framebuffer.
      nextFrameBuffer.isLockedByDataProvider = TRUE;
      CGFrameBuffer *emptyFrameBuffer = [self _getNextFramebuffer];
      NSAssert(emptyFrameBuffer != nextFrameBuffer, @"got same framebuffer twice");
      nextFrameBuffer.isLockedByDataProvider = FALSE;
      
      [emptyFrameBuffer clear];
      frame.cgFrameBuffer = emptyFrameBuffer;
      self.lastFrame = frame;
      
      self.currentFrameBuffer = emptyFrameBuffer;
    }
    
#endif // MV_ENABLE_DELTAS
    
    if (maxvid_frame_isnopframe(frame)) {
      // This frame is a no-op, since it duplicates data from the previous frame.
      //      fprintf(stdout, "Frame %d NOP\n", actualFrameIndex);
    } else {
      //      fprintf(stdout, "Frame %d [Size %d Offset %d Keyframe %d]\n", actualFrameIndex, frame->offset, movsample_length(frame), movsample_iskeyframe(frame));
      
      int isDeltaFrame = !maxvid_frame_iskeyframe(frame);
      
      if (self.currentFrameBuffer != nextFrameBuffer) {
        // Copy the previous frame buffer unless there was not one, or current is a keyframe
        
        if (isDeltaFrame && (self.currentFrameBuffer != nil)) {
          [nextFrameBuffer copyPixels:self.currentFrameBuffer];
        }
        self.currentFrameBuffer = nextFrameBuffer;
      } else {
        // In the case where the current cgframebuffer contains is a zero copy pointer, need to
        // explicitly copy the data from the zero copy buffer to the framebuffer so that we
        // have a writable memory region that a delta can be applied over.
        
        if (isDeltaFrame) {
          [self.currentFrameBuffer zeroCopyToPixels];
        }
      }
      
      // Query the framebuffer after possibly calling zeroCopyToPixels to copy
      // pixels from a zero copy buffer into the current framebuffer.
      
      void *frameBuffer = (void*)nextFrameBuffer.pixels;
#ifdef EXTRA_CHECKS
      NSAssert(frameBuffer, @"frameBuffer");
# if TARGET_OS_IPHONE
      if (isDeltaFrame) {
      NSAssert(frameBuffer != nextFrameBuffer.zeroCopyPixels, @"frameBuffer is zeroCopyPixels buffer");
      }
# endif // TARGET_OS_IPHONE
#endif // EXTRA_CHECKS

#if defined(USE_SEGMENTED_MMAP)
      // Create a mapped segment using the frame offset and length for this frame.

      uint32_t *inputBuffer32 = NULL;
      uint32_t inputBuffer32NumBytes = maxvid_frame_length(frame);
      
      NSRange range;
      range.location = maxvid_frame_offset(frame);
      range.length = inputBuffer32NumBytes;
  
      SegmentedMappedData *mappedSeg = [self.mappedData subdataWithRange:range];
      
      if (mappedSeg == nil) {
        inputMemoryMapped = FALSE;
      } else {
        
#if defined(REGRESSION_TESTS)
        if (self.simulateMemoryMapFailure) {
          inputMemoryMapped = FALSE;
        } else
#endif // REGRESSION_TESTS
        
        if ([mappedSeg mapSegment] == FALSE) {
          inputMemoryMapped = FALSE;
          
          NSLog(@"mapSegment failed for %@", [mappedSeg description]);
        } else {
          //NSLog(@"__mapSegment obj %p : %@", mappedSeg, [mappedSeg description]);
          
          inputBuffer32 = (uint32_t*) [mappedSeg bytes];
        }        
      }
      
      NSData *mappedDataObj = mappedSeg;
#else
      uint32_t *inputBuffer32 = (uint32_t*) (mappedPtr + maxvid_frame_offset(frame));
      uint32_t inputBuffer32NumBytes = maxvid_frame_length(frame);
      NSData *mappedDataObj = self.mappedData;
        
#if defined(REGRESSION_TESTS)
      if (self.simulateMemoryMapFailure) {
        inputMemoryMapped = FALSE;
      }
#endif // REGRESSION_TESTS
        
#endif // USE_SEGMENTED_MMAP
      
      if (inputMemoryMapped == FALSE) {
        // When input memory can't be mapped, it is likely the system is running low
        // on real memory. This logic can't assert when memory gets low, so deal
        // with this by indicating that there was no change or return the most
        // recent frame that was successfully decoded.
        
        frameIndex -= 1;
      } else if (isDeltaFrame) {
        // Apply delta from input buffer over the existing framebuffer

        changeFrameData = TRUE;
        
#ifdef EXTRA_CHECKS
        NSAssert(((uint32_t)inputBuffer32 % sizeof(uint32_t)) == 0, @"inputBuffer32 alignment");
        NSAssert((inputBuffer32NumBytes % sizeof(uint32_t)) == 0, @"inputBuffer32NumBytes");
        NSAssert(*inputBuffer32 == 0 || *inputBuffer32 != 0, @"access input buffer");
#endif // EXTRA_CHECKS        
        uint32_t inputBuffer32NumWords = inputBuffer32NumBytes >> 2;
        uint32_t status;
        
        uint32_t *actualInputBuffer32 = inputBuffer32;
        
#if MV_ENABLE_DELTAS
        
        if (isDeltas) {
          // In the case where the input contains pixel deltas, the input data needs to
          // be transformed in order to remove the deltas before the fast ASM code can
          // be invoked to actually apply the delta to the framebuffer. This does cost
          // an extra cycle or read/write logic but it means that multiple decompression
          // steps can be applied which could save significant space.
          
          uint32_t inputBuffer32NumBytes = (inputBuffer32NumWords * 4);
          
          if (self->decompressionBuffer == NULL) {
            self->decompressionBufferSize = (uint32_t) (self.currentFrameBuffer.numBytes / 4);
            if (inputBuffer32NumBytes > self->decompressionBufferSize) {
              self->decompressionBufferSize = inputBuffer32NumBytes;
            }
            self->decompressionBuffer = malloc(self->decompressionBufferSize);
            assert(self->decompressionBuffer);
          } else if (inputBuffer32NumBytes > self->decompressionBufferSize) {
            free(self->decompressionBuffer);
            self->decompressionBufferSize = inputBuffer32NumBytes;
            self->decompressionBuffer = malloc(self->decompressionBufferSize);
            assert(self->decompressionBuffer);
          }
          
          // Convert input delta codes to data that can be applied as a patch
          
          actualInputBuffer32 = self->decompressionBuffer;
          
          if (bpp == 16) {
            status = maxvid_deltas_decompress16(inputBuffer32, actualInputBuffer32, inputBuffer32NumWords);
          } else {
            status = maxvid_deltas_decompress32(inputBuffer32, actualInputBuffer32, inputBuffer32NumWords);
          }
          NSAssert(status == 0, @"status");
        }
        
#endif // MV_ENABLE_DELTAS
        
        if (bpp == 16) {
          status = maxvid_decode_c4_sample16(frameBuffer, actualInputBuffer32, inputBuffer32NumWords, frameBufferSize);
        } else {
          status = maxvid_decode_c4_sample32(frameBuffer, actualInputBuffer32, inputBuffer32NumWords, frameBufferSize);
        }
        NSAssert(status == 0, @"status");
        
#if defined(EXTRA_CHECKS) || defined(ALWAYS_CHECK_ADLER)
        // Mvid file verison 0 would calculate a delta checksum and not include zero padding pixels
        // in the checksum. This is inconsistent with the keyframe calculation which includes the
        // pixels and a zero padding pixel values. This issue is only a problem with a framebuffer
        // that has an odd number of pixels.
        
        MVFileHeader *header = [self header];
        
        uint32_t numBytesToIncludeInAdler;
        
        if (maxvid_file_version(header) == MV_FILE_VERSION_ZERO) {
          // File rev 0 will calculate an adler checksum using (width * height * numBytesInPixel)
          // such that an odd sized buffer will not include the zero padding pixels. This logic
          // was changed for file rev 1 so that both the keyframe and delta frame checksums
          // include any zero padding for odd sized framebuffers.
          
          if (bpp == 16) {
            numBytesToIncludeInAdler = frameBufferSize * sizeof(uint16_t);
          } else {
            numBytesToIncludeInAdler = frameBufferSize * sizeof(uint32_t);
          }
        } else {
          // File rev > 0, include any padding pixel in the delta frame calculation
          
          numBytesToIncludeInAdler = frameBufferNumBytes;
        }

        [self assertSameAdler:frame->adler frameBuffer:frameBuffer frameBufferNumBytes:numBytesToIncludeInAdler];
#endif // EXTRA_CHECKS || ALWAYS_CHECK_ADLER
      } else {
        // Input buffer contains a complete keyframe, use zero copy optimization
        
        changeFrameData = TRUE;
        
#ifdef EXTRA_CHECKS
        // FIXME: use zero copy of pointer into mapped file, impl OS page copy in util class
        if (bpp == 16) {
          if ((inputBuffer32NumBytes == (frameBufferSize * sizeof(uint16_t))) ||
              (inputBuffer32NumBytes == ((frameBufferSize+1) * sizeof(uint16_t)))) {
            // No-op
          } else {
            NSAssert(FALSE, @"framebuffer num bytes");
          }
        } else {
          if ((inputBuffer32NumBytes == (frameBufferSize * sizeof(uint32_t))) ||
              (inputBuffer32NumBytes == ((frameBufferSize+1) * sizeof(uint32_t)))) {
            // No-op
          } else {
            NSAssert(FALSE, @"framebuffer num bytes");
          }
        }
        NSAssert(((uint32_t)inputBuffer32 % getpagesize()) == 0, @"framebuffer num bytes : pagesize %d : addr %p : addr mod pagesize %d", getpagesize(), inputBuffer32, ((uint32_t)inputBuffer32 % getpagesize()));
#endif // EXTRA_CHECKS
    
#if defined(EXTRA_CHECKS) || defined(ALWAYS_CHECK_ADLER)
        // Calculate the keyframe checksum including the pixels and and zero padding pixels.
        NSAssert(inputBuffer32NumBytes == frameBufferNumBytes, @"frameBufferNumBytes");
        [self assertSameAdler:frame->adler frameBuffer:inputBuffer32 frameBufferNumBytes:inputBuffer32NumBytes];
#endif // EXTRA_CHECKS
  
        [nextFrameBuffer zeroCopyPixels:inputBuffer32 mappedData:mappedDataObj];
      }
    } // end for loop over indexes
    
  }
  
  if (!changeFrameData) {
    // When no change from previous frame is found, return a new AVFrame object
    // but make sure to return the same image object as was returned in the last frame.
    
    AVFrame *frame = [AVFrame aVFrame];
    NSAssert(frame, @"AVFrame is nil");
    
    // The image from the previous rendered frame is returned. Note that it is possible
    // that memory resources could not be mapped and in that case the previous frame
    // could be nil. Return either the last image or nil in this case.
    
    id lastFrameImage = self.lastFrame.image;
    frame.image = lastFrameImage;
    
    CGFrameBuffer *cgFrameBuffer = self.currentFrameBuffer;
    frame.cgFrameBuffer = cgFrameBuffer;
    
    frame.isDuplicate = TRUE;
    
    return frame;
  } else {
    // Delete ref to previous frame to be sure that image ref to framebuffer
    // is dropped before a new one is created.
    
    self.lastFrame = nil;
    
    // Return a CGImage wrapped in a AVFrame. Note that a new AVFrame object is returned
    // each time this method is invoked. The caller can hold on to this returned object
    // without worry about it being reused.

    AVFrame *frame = [AVFrame aVFrame];
    NSAssert(frame, @"AVFrame is nil");
    
    CGFrameBuffer *cgFrameBuffer = self.currentFrameBuffer;
    frame.cgFrameBuffer = cgFrameBuffer;
    
    [frame makeImageFromFramebuffer];
    
    self.lastFrame = frame;
    
    return frame;
  }
}

- (AVFrame*) duplicateCurrentFrame
{
  if (self.currentFrameBuffer == nil) {
    return nil;
  }
  
  // Create an in-memory copy of the current frame buffer and return a new image wrapped around the copy
  
  CGFrameBuffer *cgFrameBuffer = [CGFrameBuffer cGFrameBufferWithBppDimensions:self.currentFrameBuffer.bitsPerPixel
                                                                         width:self.currentFrameBuffer.width
                                                                        height:self.currentFrameBuffer.height];
  // If a specific non-default colorspace is being used, then copy it
  
  if (self.currentFrameBuffer.colorspace != NULL) {
    cgFrameBuffer.colorspace = self.currentFrameBuffer.colorspace;
  }
  
  // Using the OS level copy means that a small portion of the mapped memory will stay around, only the copied part.
  // Might be more efficient, unknown.
  
  //[cgFrameBuffer copyPixels:self.currentFrameBuffer];
  [cgFrameBuffer memcopyPixels:self.currentFrameBuffer];
  
  // Return a CGImage wrapped in a AVFrame
  
  AVFrame *frame = [AVFrame aVFrame];
  NSAssert(frame, @"AVFrame is nil");
  
  frame.cgFrameBuffer = cgFrameBuffer;
  
  [frame makeImageFromFramebuffer];
  
  return frame;
}

- (void) resourceUsageLimit:(BOOL)enabled
{
  self->m_resourceUsageLimit = enabled;  
}

- (BOOL) allocateDecodeResources
{
  NSAssert(self->m_isOpen == TRUE, @"isOpen");
  
  [self resourceUsageLimit:FALSE];
  
  // FIXME: should this logic also allocate input buffers and frame buffers?
  
  BOOL worked = [self _mapFile];
  if (!worked) {
    return FALSE;
  }
  return TRUE;
}

- (void) releaseDecodeResources
{
  [self resourceUsageLimit:TRUE];
  
  [self _freeFrameBuffers];
  [self _unmapFile];
}

- (BOOL) isResourceUsageLimit
{
  return self->m_resourceUsageLimit;
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
  return [self header]->width;
}

- (NSUInteger) height
{
  return [self header]->height;
}

- (BOOL) isOpen
{
  return self->m_isOpen;
}

- (NSUInteger) numFrames
{
  return [self header]->numFrames;
}

- (NSInteger) frameIndex
{
  // FIXME: What is the initial value of frameIndex, seems to be zero in MV impl, is it -1 in MOV reader?
  
  return self->frameIndex;
}

- (NSTimeInterval) frameDuration
{
  float frameDuration = [self header]->frameDuration;
  return frameDuration;
}

// Note that the file need to be open in order to query the bpp, but it need not be mapped.

- (BOOL) hasAlphaChannel
{
  uint32_t bpp = [self header]->bpp;
  if (bpp == 16 || bpp == 24) {
    return FALSE;
  } else if (bpp == 32) {
    return TRUE;
  } else {
    assert(0);
  }
}

- (BOOL) isAllKeyframes
{
  uint32_t isCond = maxvid_file_is_all_keyframes([self header]);  
  if (isCond) {
    return TRUE;
  } else {
    return FALSE;
  }
}

- (NSString*) description
{
  return [NSString stringWithFormat:@"AVMvidFrameDecoder %p, file %@, isOpen %d, isMapped %d, w/h %d x %d, numFrames %d",
          self,
          [self.filePath lastPathComponent],
          self.isOpen,
          (self.mappedData == nil ? 0 : 1),
          (int)self.width,
          (int)self.height,
          (int)self.numFrames];
}

#if MV_ENABLE_DELTAS

// FALSE by default, if the mvid file was created with the
// -deltas option then this property would be TRUE.

- (BOOL) isDeltas
{
  uint32_t isCond = maxvid_file_is_deltas([self header]);
  if (isCond) {
    return TRUE;
  } else {
    return FALSE;
  }
}

#endif // MV_ENABLE_DELTAS

@end
