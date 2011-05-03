//
//  AVApng2MvidResourceLoader.h
//
//  Created by Moses DeJong on 5/2/11.
//
//  License terms defined in License.txt.
//
// This loader converts an APNG resource .apng to a .mvid movie file.
// This class works only on a file with the .apng extension.
// Don't attach an animated PNG file with the .png extension, because
// Xcode will modify the internal format and compression in a way that
// makes the file unreadable to libpng.
//
// The APNG converter makes use of libpng plus the APNG patch to decode
// image data as a series of frames. Any of the formats supported by
// libpng can be decoded. All formats will be decoded to 24 BPP or 32 BPP
// if an alpha channel or transparency is used. Unlike the Quicktime Animation
// decoder, the APNG decoder has no 16BPP (Thousands of colors) support.
// The PNG image format is able to achive some impressive compression ratios
// for a variety of input. The most effective results come with computer generated
// images that use a limited number of colors.
//
// The APNG decoder will decode all frames as keyframes, so the resulting .mvid
// file can grow quite large. A user of this class should take care to delete
// these tmp files when no longer needed. This behavior is a design trade off,
// because while the intermediate files are large, the runtime performance is
// exceptionally good as a result of a special zero copy optimization.
// In practice, one should be able to get 30 FPS performance for full screen 480x320
// video that was decoded from a .apng file, even on an old iPhone 3g.

#import <Foundation/Foundation.h>

#import "AV7zAppResourceLoader.h"

@interface AVApng2MvidResourceLoader : AVAppResourceLoader {
  NSString *m_outPath;
  BOOL startedLoading;
  BOOL m_alwaysGenerateAdler;
}

// The fully qualified filename for the extracted data. For example: "XYZ.mvid"
@property (nonatomic, copy) NSString *outPath;

@property (nonatomic, assign) BOOL alwaysGenerateAdler;

+ (AVApng2MvidResourceLoader*) aVApng2MvidResourceLoader;

@end
