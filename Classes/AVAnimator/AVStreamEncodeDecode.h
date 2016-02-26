//
//  AVStreamEncodeDecode.h
//
//  Created by Moses DeJong on 2/24/16.
//
//  License terms defined in License.txt.

#import <Foundation/Foundation.h>

#import "AVAssetConvertCommon.h" // HAS_LIB_COMPRESSION_API

#if defined(HAS_LIB_COMPRESSION_API)

#import "compression.h"

@interface AVStreamEncodeDecode : NSObject

// Stream compression interface, compress input and store into encodedData buffer

+ (void) streamCompress:(NSData*)inputData
            encodedData:(NSMutableData*)encodedData
              algorithm:(compression_algorithm)algorithm;

// Streaming delta + compress encoding operation that reads 16, 24, 32 BPP pixels
// and writes data to an output mutable data that contains encoded bytes

+ (BOOL) streamDeltaAndCompress:(NSData*)inputData
                    encodedData:(NSMutableData*)encodedData
                            bpp:(int)bpp
                      algorithm:(compression_algorithm)algorithm;

// Undo the delta + compress operation so that the original pixel data is recovered
// and written to the indicated pixel buffer.

+ (BOOL) streamUnDeltaAndUncompress:(NSData*)encodedData
                        frameBuffer:(void*)frameBuffer
                frameBufferNumBytes:(uint32_t)frameBufferNumBytes
                                bpp:(int)bpp
                          algorithm:(compression_algorithm)algorithm
                expectedDecodedSize:(int)expectedDecodedSize;

@end

#endif // HAS_LIB_COMPRESSION_API
