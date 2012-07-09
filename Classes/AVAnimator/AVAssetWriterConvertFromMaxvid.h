//
//  AVAssetWriterConvertFromMaxvid.h
//
//  Created by Moses DeJong on 7/8/12.
//
//  License terms defined in License.txt.
//
//  This module implements a MVID to H264 encoder API that can be used to
//  encode the video frames from an MVID file into a H264 video in
//  a Quicktime container. The H264 video format is lossy as compared to
//  a lossless H264, but the space savings can be quite significant.

#include "AVAssetConvertCommon.h"

#if defined(HAS_AVASSET_CONVERT_MAXVID)

typedef enum
{
  AVAssetWriterConvertFromMaxvidStateInit = 0,
  AVAssetWriterConvertFromMaxvidStateSuccess,
  AVAssetWriterConvertFromMaxvidStateFailed
} AVAssetWriterConvertFromMaxvidState;

@interface AVAssetWriterConvertFromMaxvid : NSObject

// This state value starts life as AVAssetWriterConvertFromMaxvidStateInit and
// gets set to AVAssetWriterConvertFromMaxvidStateSuccess on success. If the
// encode operation fails then another enum value is set to indicate a reason.

@property (nonatomic, assign) AVAssetWriterConvertFromMaxvidState state;

// The input path is the fully qualified filename for the .mvid video input file

@property (nonatomic, copy) NSString *inputPath;

// The output path is the fully qualified filename for the .mov or .m4v H264
// video file to be written.

@property (nonatomic, copy) NSString *outputPath;

// constructor

+ (AVAssetWriterConvertFromMaxvid*) aVAssetWriterConvertFromMaxvid;

// Kick off an encode operation

- (void) encodeOutputFile;

@end

#endif // HAS_AVASSET_CONVERT_MAXVID : iOS 4.1 or newer