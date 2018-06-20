//
//  AVAssetAlphaFrameDecoder.h
//
//  Created by Moses DeJong on 1/4/13.
//
//  License terms defined in License.txt.
//
//  This frame decoder interface will read video frames from an AVAsset which
//  typically means a h264 video attached to the project file. Other file
//  types could be supported by iOS, but currently h264 is the only one that
//  actually works. A Frame decoder interface will load and decompress a
//  specific frame of video using the h264 decoder handware included in iOS.
//  Note that this frame decoder is currently limited in that only 1 frame
//  can be in memory at any one time, the decoder only supports
//  sequential access to frames, and frame can only be decoded once.
//  This frame decoder does not support random access, frame cannot be skipped
//  or repeated and one cannot loop or rewind the decode frame position. This
//  decoder should not be used with a AVAnimatorMedia object, it should only
//  be used to read frames from an asset is a non-realtime blocking usage.

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

#import "AVAssetConvertCommon.h"

#import "AVFrameDecoder.h"

#if defined(HAS_AVASSET_CONVERT_MAXVID)

@class AVFrame;
@class AVAssetFrameDecoder;
@class AVAssetReader;
@class AVAssetReaderOutput;

@interface AVAssetAlphaFrameDecoder : AVFrameDecoder
{
@private
  AVAssetFrameDecoder *m_rgbAssetDecoder;
  AVAssetFrameDecoder *m_alphaAssetDecoder;
  AVFrame *m_currentFrame;
  NSString *m_movieRGBFilename;
  NSString *m_movieAlphaFilename;
}

@property (nonatomic, readonly) NSUInteger  numFrames;

@property (nonatomic, retain) AVAssetFrameDecoder *rgbAssetDecoder;
@property (nonatomic, retain) AVAssetFrameDecoder *alphaAssetDecoder;

// The name of the RGB portion of the movie should be saved in the
// "movieRGBFilename" property.

@property (nonatomic, copy) NSString *movieRGBFilename;

// The name of the ALPHA portion of the movie should be saved in the
// "movieAlphaFilename" property.

@property (nonatomic, copy) NSString *movieAlphaFilename;

// Constructor

+ (AVAssetAlphaFrameDecoder*) aVAssetAlphaFrameDecoder;

// Return TRUE if opening the rgb and alpha asset file is successful.
// This method could return FALSE when the file does not exist or
// it is the wrong format.

- (BOOL) openForReading;

@end

#endif // HAS_AVASSET_CONVERT_MAXVID
