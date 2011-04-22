//
//  AV7zAppResourceLoader.h
//
//  Created by Moses DeJong on 4/22/11.
//
//  License terms defined in License.txt.
//
// Extend AVAppResourceLoader to support loading of 7zip compressed resource files.
// For example, a resource named "2x2_black_blue_16BPP.mov.7z" could be decompressed
// to "2x2_black_blue_16BPP.mov". The file is decompressed into the tmp dir in
// a second thread.

#import <Foundation/Foundation.h>

#import "AVAppResourceLoader.h"

@interface AV7zAppResourceLoader : AVAppResourceLoader {
  NSString *m_archiveFilename;
}

@property (nonatomic, copy) NSString *archiveFilename;

+ (AV7zAppResourceLoader*) aV7zAppResourceLoader;

// Non-public utils

- (NSString*) _getTmpDirPath:(NSString*)filename;

@end
