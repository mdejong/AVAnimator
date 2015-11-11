//
//  AVAssetMixAlphaResourceLoader.h
//
//  Created by Moses DeJong on 1/1/13.
//
//  License terms defined in License.txt.
//
// This loader will decompress a "mixed" video where RGB and Alpha frames
// are mixed together. A video of this type must be encoded with the main
// profile so that effective compression is retained.

@class AVAsset2MvidResourceLoader;

#import <Foundation/Foundation.h>

#import "AVAppResourceLoader.h"

@interface AVAssetMixAlphaResourceLoader : AVAppResourceLoader

// The fully qualified filename of the final result file, for example
// the output path might be constructed by combining the mvid filename
// like "Ghost.mvid" with the tmp dir.

@property (nonatomic, copy) NSString *outPath;

@property (nonatomic, assign) BOOL alwaysGenerateAdler;

// constructor

+ (AVAssetMixAlphaResourceLoader*) aVAssetMixAlphaResourceLoader;

@end
