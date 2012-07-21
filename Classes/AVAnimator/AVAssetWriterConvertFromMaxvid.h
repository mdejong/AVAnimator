//
//  AVAssetWriterConvertFromMaxvid.h
//
//  Created by Moses DeJong on 7/8/12.
//
//  License terms defined in License.txt.
//
//  This module implements a MVID to H264 encoder API that can be used to
//  encode the video frames from an MVID file into a H264 video in
//  a Quicktime container (.mvid -> .mov). The H264 video format is
//  lossy as compared to the lossless MVID format, but the space savings
//  can be quite significant. Note that because this module depends on
//  a hardware encoder on the iOS deice, it will not function on devices
//  that do not include an H264 encoder. For example, iPhones earlier than
//  the iPhone4 (like the 3G and 3GS) do not include a hardware h264 encoder.
//  All iPad devices include H264 encoding hardware.
//
//  Note that there are some restrictions imposed by the H264 encoder
//  hardware on iOS devices. The smallest video successfully encoded
//  on tested iOS hardware appears to be 128x128. A video with a dimension
//  smaller than 128 will either fail to encode (iPad2) or it will encode
//  with corrupted video data (iPhone4). Video with well known aspect
//  ratios (2:1, 3:2, 4:3) encode correctly.
//
//  In addition, H264 supports only 24BPP fully opaque video. Attempting to
//  encode a .mvid with an alpha channel will not work as expected, the
//  alpha channel will compose over a black background since the output
//  must be opaque.

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

// Kick off an encode operation. This will block the calling thread until
// the encoding operation is completed.

- (void) blockingEncode;

@end

#endif // HAS_AVASSET_CONVERT_MAXVID : iOS 4.1 or newer