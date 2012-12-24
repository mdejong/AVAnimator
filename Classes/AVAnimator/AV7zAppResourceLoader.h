//
//  AV7zAppResourceLoader.h
//
//  Created by Moses DeJong on 4/22/11.
//
//  License terms defined in License.txt.
//
// Extend AVAppResourceLoader to support loading of 7zip compressed resource files.
// For example, a resource named "2x2_black_blue_16BPP.mvid.7z" could be decompressed
// to "2x2_black_blue_16BPP.mvid". The file is decompressed into the tmp dir in
// a second thread. The caller must define the archiveFilename, movieFilename, and
// outPath properties. The outPath is a .mvid file path.

#import <Foundation/Foundation.h>

#import "AVAppResourceLoader.h"

@interface AV7zAppResourceLoader : AVAppResourceLoader {
  NSString *m_archiveFilename;
  NSString *m_outPath;
  BOOL startedLoading;
}

// The name of the archive resource file. For example: "XYZ.mov.7z"
@property (nonatomic, copy) NSString *archiveFilename;

// The fully qualified filename for the extracted data. For example: "XYZ.mov"
@property (nonatomic, copy) NSString *outPath;

+ (AV7zAppResourceLoader*) aV7zAppResourceLoader;

@end
