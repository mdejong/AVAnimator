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
  float frameDuration;
  int   frameNum;
  int   m_totalNumFrames;
  MVFileHeader *mvHeader;
  MVFrame *mvFramesArray;
  uint32_t framesArrayNumBytes;
  uint32_t m_bpp;
  
  FILE *maxvidOutFile;

  long offset;
  CGSize m_movieSize;
  
  BOOL  m_genAdler;
}

@property (nonatomic, copy)   NSString      *mvidPath;
@property (nonatomic, assign) float         frameDuration;
@property (nonatomic, readonly) int         frameNum;
@property (nonatomic, assign) int           totalNumFrames;
@property (nonatomic, assign) BOOL          genAdler;
@property (nonatomic, assign) uint32_t      bpp;
@property (nonatomic, assign) CGSize        movieSize;

- (BOOL) openMvid;

- (void) close;

- (void) writeTrailingNopFrames:(float)frameDuration;

- (void) saveOffset;

- (void) skipToNextPageBound;

- (BOOL) writeKeyframe:(char*)ptr bufferSize:(int)bufferSize;

- (BOOL) rewriteHeader;

@end
