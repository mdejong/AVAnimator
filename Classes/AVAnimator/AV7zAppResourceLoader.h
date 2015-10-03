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

// The name of the archive resource file. Typically: "XYZ.mvid.7z" but
// any file type can be 7z decoded.
@property (nonatomic, copy) NSString *archiveFilename;

// The fully qualified filename for the extracted data. For example: "XYZ.mov"
@property (nonatomic, copy) NSString *outPath;

// Set this property to TRUE to indicate that the file to be decompressed
// is a .mvid file and that the result should be processed to flatten out
// all delta frames into keyframes. This typically results in a larger
// .mvid file when written to disk but it makes possible the use of
// a mapped memory optimization that can directly blit whole pages
// into video memory without having to copy data. Setting the property
// to TRUE while decompressing a .mvid that contains only keyframes is a nop.

@property (nonatomic, assign) BOOL flattenMvid;

+ (AV7zAppResourceLoader*) aV7zAppResourceLoader;

@end
