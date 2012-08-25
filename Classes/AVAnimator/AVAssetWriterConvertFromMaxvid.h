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
//  a hardware encoder on the iOS device, it will not function on devices
//  that do not include an H264 encoder. For example, iPhones earlier than
//  the iPhone4 (like the 3G and 3GS) do not include a hardware h264 encoder.
//  All iPad devices include H264 encoding hardware.
//
//  Note that there are some restrictions imposed by the H264 encoder
//  hardware on iOS devices. The smallest video successfully encoded
//  on tested iOS hardware appears to be 128x128. A video with a dimension
//  smaller than 128 will either fail to encode (iPad2) or it will encode
//  with corrupted video data (iPhone4). Video with well known aspect
//  ratios (2:1, 3:2, 4:3) encode correctly. Also note that video dimensions
//  should be a multiple of 4.
//
//  See http://en.wikipedia.org/wiki/Display_resolution for examples of resolutions
//  that are standard and known to work. Because H264 encoding hardware differs from
//  model to model, you will have to test the encoding logic with your specific
//  hardware and the specific input dimensions. If you find that the encoded video is
//  corrupted in strange ways, change the width x height of the video and see if that
//  fixes the problem. The corruption happens at the hardware level, there is no
//  available workaround as the problem is not at a software level.
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

@class AVFrameDecoder;

// The following notification is delivered when the conversion process is complete.
// The notification is delivered in both the success and failure case. The caller
// can check the object.state value to determine the actual result.

extern NSString * const AVAssetWriterConvertFromMaxvidCompletedNotification;

// AVAssetWriterConvertFromMaxvid

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

#if defined(REGRESSION_TESTS)
@property (nonatomic, retain) AVFrameDecoder *frameDecoder;
#endif // REGRESSION_TESTS

// constructor

+ (AVAssetWriterConvertFromMaxvid*) aVAssetWriterConvertFromMaxvid;

// Kick off an encode operation. This will block the calling thread until
// the encoding operation is completed. Be careful not to block the main
// thread with this invocation, this method would typically only be used
// from a secondary thread.

- (void) blockingEncode;

// Kick off an async (non-blocking call) encode operation in a secondary
// thread. This method will deliver a AVAssetWriterConvertFromMaxvidCompletedNotification
// in the main thread when complete. Check the state property during this notification to
// determine if the encoding process was a success or a failure.

- (void) nonblockingEncode;

// Return TRUE if a hardware h264 encoder is available for use with this
// iPhone, iPod Touch, or iPad model. This function always returns TRUE
// in the simulator.

+ (BOOL) isHardwareEncoderAvailable;

@end

#endif // HAS_AVASSET_CONVERT_MAXVID : iOS 4.1 or newer
