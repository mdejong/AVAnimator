//
//  AVAssetJoinAlphaResourceLoader.h
//
//  Created by Moses DeJong on 1/1/13.
//
//  License terms defined in License.txt.
//
// This loader will decompress a video with a full alpha channel stored
// as a pair of h264 encoded videos. The first video contains the RGB
// values while the second video contains just the alpha channel
// stored as grayscale. Typically, the h264 video should be encoded with
// ffmpeg+x264 and it would be stored in a .m4v file.

@class AVAsset2MvidResourceLoader;

#import <Foundation/Foundation.h>

#import "AVAppResourceLoader.h"

@interface AVAssetJoinAlphaResourceLoader : AVAppResourceLoader
{
  NSString *m_movieRGBFilename;
  NSString *m_movieAlphaFilename;
  NSString *m_outPath;
  AVAsset2MvidResourceLoader *m_rgbLoader;
  AVAsset2MvidResourceLoader *m_alphaLoader;
  BOOL m_alwaysGenerateAdler;
  BOOL startedLoading;
}

// The name of the RGB portion of the movie should be saved in the
// "movieRGBFilename" property.

@property (nonatomic, copy) NSString *movieRGBFilename;

// The name of the ALPHA portion of the movie should be saved in the
// "movieAlphaFilename" property.

@property (nonatomic, copy) NSString *movieAlphaFilename;

// The fully qualified filename of the final result file, for example
// the output path might be constructed by combining the mvid filename
// like "Ghost.mvid" with the tmp dir.

@property (nonatomic, copy) NSString *outPath;

@property (nonatomic, assign) BOOL alwaysGenerateAdler;

// constructor

+ (AVAssetJoinAlphaResourceLoader*) aVAssetJoinAlphaResourceLoader;

@end
