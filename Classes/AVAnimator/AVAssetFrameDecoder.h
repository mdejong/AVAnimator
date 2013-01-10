//
//  AVAssetFrameDecoder.h
//
//  Created by Moses DeJong on 1/4/13.
//
//  License terms defined in License.txt.
//
//  This frame decoder interface will read video frames from an AVAsset which
//  typically means an H264 video attached to the project file. Other file
//  types could be supported by iOS, but currently H264 is the only one that
//  actually works. A Frame decoder interface will load and decompress a
//  specific frame of video using the H264 decoder handware included in iOS.
//  Note that this frame decoder is currently limited such that it only support
//  sequential access to frame, so frames cannot be skipped or repeated and
//  a specific video can only be decode into frames once. This assets frame
//  decoder should not be used with a AVAnimatorMedia object, it should only
//  be used to read frames from an asset is a non-realtime blocking usage.

#import <Foundation/Foundation.h>

#include "AVAssetConvertCommon.h"

#import "AVFrameDecoder.h"

#if defined(HAS_AVASSET_CONVERT_MAXVID)

@class AVAssetReader;
@class AVAssetReaderOutput;

@interface AVAssetFrameDecoder : AVFrameDecoder
{
@private
  NSURL *m_assetURL;
  AVAssetReader *m_aVAssetReader;
  AVAssetReaderOutput *m_aVAssetReaderOutput;
  
  NSTimeInterval m_frameDuration;
  NSUInteger     m_numFrames;
  int            frameIndex;
  
  CGSize detectedMovieSize;
  float prevFrameDisplayTime;
  int numTrailingNopFrames;
  
  BOOL m_isOpen;
  BOOL m_isReading;
}

@property (nonatomic, readonly) NSUInteger  numFrames;

+ (AVAssetFrameDecoder*) aVAssetFrameDecoder;

@end

#endif // HAS_AVASSET_CONVERT_MAXVID
