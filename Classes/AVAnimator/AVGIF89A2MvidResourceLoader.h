//
//  AVGIF89A2MvidResourceLoader.h
//
//  Created by Moses DeJong on 6/5/13.
//
//  License terms defined in License.txt.
//
// This loader converts an animated GIF89a file to the .mvid format.
// An animated GIF contains multiple frames of video data and can
// be loaded from an asset, a local file, or a URL. Because animated
// GIFs could be quite large, it is not a good idea to actually hold
// all the UIImage items in memory at the same time on an iOS device.
// This loader makes it possible to convert a GIF to MVID format so
// that the superior memory usage of the MVID format and loader code
// can selectively load specific keyframes as needed.

#import <Foundation/Foundation.h>

#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 40000 // iOS 4.0 or newer

#define AVANIMATOR_HAS_IMAGEIO_FRAMEWORK

#endif // iOS 4.0 or newer

#ifdef AVANIMATOR_HAS_IMAGEIO_FRAMEWORK

#import "AVAppResourceLoader.h"

@interface AVGIF89A2MvidResourceLoader : AVAppResourceLoader {
  NSString *m_outPath;
  BOOL startedLoading;
  BOOL m_alwaysGenerateAdler;
}

// The fully qualified filename for the extracted data. For example: "XYZ.mvid"

@property (nonatomic, copy) NSString *outPath;

@property (nonatomic, assign) BOOL alwaysGenerateAdler;

+ (AVGIF89A2MvidResourceLoader*) aVGIF89A2MvidResourceLoader;

@end

#endif // AVANIMATOR_HAS_IMAGEIO_FRAMEWORK