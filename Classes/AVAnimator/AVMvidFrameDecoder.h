//
//  AVMvidFrameDecoder.h
//
//  Created by Moses DeJong on 1/4/11.
//
//  License terms defined in License.txt.

#import <Foundation/Foundation.h>

#import "AVFrameDecoder.h"
#import "maxvid_file.h"

// Define USE_SEGMENTED_MMAP for both iOS and MacOSX to support very large files

//#if TARGET_OS_IPHONE
# define USE_SEGMENTED_MMAP
//#endif // TARGET_OS_IPHONE

#if defined(USE_SEGMENTED_MMAP)
@class SegmentedMappedData;
#endif // USE_SEGMENTED_MMAP

@interface AVMvidFrameDecoder : AVFrameDecoder {
  NSString *m_filePath;
  MVFileHeader m_mvHeader;
  void *m_mvFrames;
  BOOL m_isOpen;
  
#if defined(USE_SEGMENTED_MMAP)
  SegmentedMappedData *m_mappedData;
#else
  NSData *m_mappedData;
#endif // USE_SEGMENTED_MMAP
  
  CGFrameBuffer *m_currentFrameBuffer;  
  NSArray *m_cgFrameBuffers;
  
  AVFrame *m_lastFrame;
  
#if MV_ENABLE_DELTAS
  
  uint32_t *decompressionBuffer;
  uint32_t decompressionBufferSize;
  
#endif // MV_ENABLE_DELTAS
  
  int frameIndex;
  BOOL m_resourceUsageLimit;

#if defined(REGRESSION_TESTS)
  BOOL m_simulateMemoryMapFailure;
#endif // REGRESSION_TESTS
  
  BOOL m_upgradeFromV1;
}

@property (nonatomic, copy) NSString *filePath;
@property (nonatomic, retain) CGFrameBuffer *currentFrameBuffer;
@property (nonatomic, copy) NSArray *cgFrameBuffers;

#if defined(USE_SEGMENTED_MMAP)
@property (nonatomic, retain) SegmentedMappedData *mappedData;
#else
@property (nonatomic, copy) NSData *mappedData;
#endif // REGRESSION_TESTS

#if defined(REGRESSION_TESTS)
@property (nonatomic, assign) BOOL simulateMemoryMapFailure;
#endif // REGRESSION_TESTS

// This property must be explicitly set to enable reading
// older version 0 and 1 format .mvid files. Only the
// "mvidmoviemaker -upgrade ..." should do this. Any new code
// must import version 2 and newer files only so that the
// movies can be read with either 32 or 64 bit hardware.

@property (nonatomic, assign) BOOL upgradeFromV1;

+ (AVMvidFrameDecoder*) aVMvidFrameDecoder;

// Open resource identified by path

- (BOOL) openForReading:(NSString*)path;

// Close resource opened earlier

- (void) close;

// Reset current frame index to -1, before the first frame

- (void) rewind;

// Advance the current frame index, see AVFrameDecoder.h for full method description.

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

// Return direct access to the header info, caller might want to inspect the header without decoding

- (MVFileHeader*) header;

// True when all mvid frames are keyframes. This means that none of
// the frames are delta frames that require a previous state in order
// to apply a delta.

- (BOOL) isAllKeyframes;

#if MV_ENABLE_DELTAS

// If the mvid file was created with the -deltas encoding
// then this property returns TRUE. If a mvid file was
// created with delta frames, then it cannot be decoded
// but this frame decoder, instead a new .mvid should
// be written and the delta frames should be converted
// to a plain .mvid file. This makes it possible to have
// a move highly optimized file attached to the project file
// but the runtime optimized loader will be used after the
// conversion has completed.

- (BOOL) isDeltas;

#endif // MV_ENABLE_DELTAS

@end
