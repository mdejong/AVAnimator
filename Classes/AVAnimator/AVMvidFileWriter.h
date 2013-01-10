//
//  AVMvidFileWriter.h
//
//  Created by Moses DeJong on 2/20/12.
//
//  License terms defined in License.txt.
//
//  This module implements a class that handles the details of writing a .mvid
//  file. This file type is a specially optimized binary layout of pixel data
//  useful for animations and general video. Pixels in a .mvid file are optimized
//  so that regions can be blitted into memory as quickly as possible. In addition
//  memory is configured on page bounds and word bounds for maximum efficiency
//  at the cost of a little on disk space.

#import <Foundation/Foundation.h>

#import <QuartzCore/QuartzCore.h>

#import "maxvid_file.h"

@interface AVMvidFileWriter : NSObject {
@private
  NSString *m_mvidPath;
  float m_frameDuration;
  int   frameNum;
  int   m_totalNumFrames;
  MVFileHeader *mvHeader;
  MVFrame *mvFramesArray;
  uint32_t framesArrayNumBytes;
  uint32_t m_bpp;
  
  FILE *maxvidOutFile;

  long offset;
  CGSize m_movieSize;

  BOOL  isOpen;
  BOOL  m_genAdler;
  BOOL  m_isAllKeyframes;
}

@property (nonatomic, copy)   NSString      *mvidPath;
@property (nonatomic, assign) float         frameDuration;
@property (nonatomic, readonly) int         frameNum;
@property (nonatomic, assign) int           totalNumFrames;
@property (nonatomic, assign) BOOL          genAdler;
@property (nonatomic, assign) uint32_t      bpp;
@property (nonatomic, assign) CGSize        movieSize;

// TRUE by default, if writeDeltaframe is invoked then this
// property is set to FALSE.

@property (nonatomic, assign) BOOL          isAllKeyframes;

+ (AVMvidFileWriter*) aVMvidFileWriter;

- (BOOL) open;

- (void) close;

// Write a single nop frame after a keyframe or a delta frame

- (void) writeNopFrame;

// Count up the number of nop frames that would appear after the indicated
// frame display time. The currentFrameDuration is the duration that
// a frame would be displayed, it could be longer than the expected FPS
// duration indicated by the frameDuration argument.

+ (int) countTrailingNopFrames:(float)currentFrameDuration
                 frameDuration:(float)frameDuration;

// Write 0 to N trailing nop frames, pass in total frame display time

- (void) writeTrailingNopFrames:(float)frameDuration;

- (void) skipToNextPageBound;

// Write a self contained key frame. Note that the bufferSize argument
// here should contain all the pixels and any zero pading in the case
// of an odd number of pixels.

- (BOOL) writeKeyframe:(char*)ptr bufferSize:(int)bufferSize;

// Write a delta frame that depends on the previous frame. The adler needs to be
// generated in the caller since both previous and current frames would need to be
// decoded in order to generate the adler.

- (BOOL) writeDeltaframe:(char*)ptr bufferSize:(int)bufferSize adler:(uint32_t)adler;

- (BOOL) rewriteHeader;

@end
