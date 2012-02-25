// apng convert to maxvid module
//
//  License terms defined in License.txt.
//
// This module defines logic that convert from an APNG to a memory mapped maxvid file.

#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include <stdlib.h>

#include <sys/types.h>
#include <sys/stat.h>
#include <math.h>
#include <assert.h>
#include <limits.h>
#include <unistd.h>

// Convert each frame of .apng data into a maxvid frame and save to .mvid file.

uint32_t
apng_convert_maxvid_file(
                            char *inAPNGPath,
                            char *outMaxvidPath,
                            uint32_t genAdler);

uint32_t
apng_verify_png_is_animated(char *inAPNGPath);

// class ApngConvertMaxvid

#import <Foundation/Foundation.h>

@interface ApngConvertMaxvid : NSObject

+ (uint32_t) convertToMaxvid:(NSString*)inAPNGPath
               outMaxvidPath:(NSString*)outMaxvidPath
                    genAdler:(BOOL)genAdler;

@end
