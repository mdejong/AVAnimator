//
//  AVAssetReaderConvertMaxvid.h
//
//  Created by Moses DeJong on 2/4/12.
//
//  License terms defined in License.txt.
//
//  This module implements a H264 to MVID decoder that can be used to
//  save the raw bits of a H264 video into a file. For videos without
//  an alpha channel, lossy H264 video encoding could save quite a lot
//  of space as compared to lossless video.

#include "AVAssetConvertCommon.h"

#if defined(HAS_AVASSET_CONVERT_MAXVID)

#import "AVMvidFileWriter.h"

// The following notification is delivered when the conversion process is complete.
// The notification is delivered in both the success and failure case. The caller
// can check the object.state value to determine the actual result.

extern NSString * const AVAssetReaderConvertMaxvidCompletedNotification;

@class AVAssetReader;
@class AVAssetReaderOutput;

@interface AVAssetReaderConvertMaxvid : AVMvidFileWriter {
@private
  NSURL *m_assetURL;
  AVAssetReader *m_aVAssetReader;
  AVAssetReaderOutput *m_aVAssetReaderOutput;
  BOOL m_wasSuccessful;
}

@property (nonatomic, retain) NSURL         *assetURL;

@property (nonatomic, assign) BOOL          wasSuccessful;

+ (AVAssetReaderConvertMaxvid*) aVAssetReaderConvertMaxvid;

// This method is a blocking call that will read data from the
// asset and write the output as a .mvid file. Note that decoding
// is done in the calling thread, so this method should typically
// be invoked only from a secondary thread.
// Return TRUE if successful, FALSE otherwise.

- (BOOL) blockingDecode;

// Kick off an async (non-blocking call) decode operation in a secondary
// thread. This method will deliver a AVAssetReaderConvertMaxvidCompletedNotification
// in the main thread when complete. Check the state property during this notification to
// determine if the encoding process was a success or a failure.

- (void) nonblockingDecode;

@end

#endif // HAS_AVASSET_CONVERT_MAXVID : iOS 4.1 or newer
