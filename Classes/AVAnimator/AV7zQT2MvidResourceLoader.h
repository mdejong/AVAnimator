//
//  AV7zQT2MvidResourceLoader.h
//
//  Created by Moses DeJong on 4/22/11.
//
//  License terms defined in License.txt.
//
// This loader decompresses a 7zip compressed mov file and converts the
// Quicktime MOV data to a optimized maxvid .mvid file.

#import <Foundation/Foundation.h>

#import "AV7zAppResourceLoader.h"

@interface AV7zQT2MvidResourceLoader : AV7zAppResourceLoader {
  BOOL m_alwaysGenerateAdler;
}

@property (nonatomic, assign) BOOL alwaysGenerateAdler;

+ (AV7zQT2MvidResourceLoader*) aV7zQT2MvidResourceLoader;

@end
