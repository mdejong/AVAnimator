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

#import <Foundation/Foundation.h>

#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 41000 // iOS 4.1 or newer

#define HAS_AVASSET_READER_CONVERT_MAXVID

#import "AVMvidFileWriter.h"

@class AVAssetReader;
@class AVAssetReaderOutput;

@interface AVAssetReaderConvertMaxvid : AVMvidFileWriter {
@private
  NSURL *m_assetURL;
  AVAssetReader *m_aVAssetReader;
  AVAssetReaderOutput *m_aVAssetReaderOutput;
}

@property (nonatomic, retain) NSURL         *assetURL;

+ (AVAssetReaderConvertMaxvid*) aVAssetReaderConvertMaxvid;

// Return TRUE if successful, FALSE otherwise.
// Decoding is done in a secondary thread.

- (BOOL) decodeAssetURL;

@end

#endif // iOS 4.1 or newer
