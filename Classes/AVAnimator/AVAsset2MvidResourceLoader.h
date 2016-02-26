//
//  AVAsset2MvidResourceLoader.h
//
//  Created by Moses DeJong on 2/24/12.
//
//  License terms defined in License.txt.
//
// This loader will decompress the video portion of an existing
// asset and save as a .mvid file. This module makes it possible
// to decode H.264 stored as a .mov file that has been attached
// to the project as a resource.

#import <Foundation/Foundation.h>

#import <CoreGraphics/CoreGraphics.h>

#import "AVAppResourceLoader.h"

#import "AVAssetConvertCommon.h"

#if defined(HAS_AVASSET_CONVERT_MAXVID)

@interface AVAsset2MvidResourceLoader : AVAppResourceLoader {
  NSString *m_outPath;
  BOOL m_alwaysGenerateAdler;
  BOOL startedLoading;
  CGSize m_movieSize;
  
#if defined(HAS_LIB_COMPRESSION_API)
  BOOL m_compressed;
#endif // HAS_LIB_COMPRESSION_API
}

// The fully qualified filename for the extracted data. For example: "XYZ.mvid"
@property (nonatomic, copy) NSString *outPath;

@property (nonatomic, assign) BOOL alwaysGenerateAdler;

@property (nonatomic, assign) CGSize movieSize;

#if defined(HAS_LIB_COMPRESSION_API)
@property (nonatomic, assign) BOOL compressed;
#endif // HAS_LIB_COMPRESSION_API

+ (AVAsset2MvidResourceLoader*) aVAsset2MvidResourceLoader;

@end

#endif // HAS_AVASSET_CONVERT_MAXVID
