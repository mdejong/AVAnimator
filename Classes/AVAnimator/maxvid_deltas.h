// maxvid_deltas module
//
//  License terms defined in License.txt.
//
// This module contains logic related to the "deltas" file format which is like
// a normal maxvid file except that all frames are deltas and the pixels are
// stored in a format that makes it easier to compress. This module trades
// execution time for maximum compactness in the data being sent to the
// compressor. Note that this delta file format is not related to frame to
// frame deltas, which are used to implement the basic diff and patch logic
// for frames (fast blit).

#import "maxvid_file.h"

#import <Foundation/Foundation.h>

// Set this value to 1 to enable simple "diff" from one pixel value to the next.

#define MV_DELTAS_SUBTRACT_PIXELS 0

#if MV_ENABLE_DELTAS

BOOL
maxvid_deltas_compress(NSData *maxvidInData,
                       NSMutableData *maxvidOutData,
                       void *inputBuffer,
                       uint32_t inputBufferNumBytes,
                       NSUInteger frameBufferNumPixels,
                       uint32_t processAsBPP);

// Rewrite generic maxvid delta codes to "pixel delta" codes where each
// pixel data element is a delta as compared to the previous pixel.

uint32_t
maxvid_deltas_decompress16(uint32_t *inputBuffer32, uint32_t *outputBuffer32, uint32_t inputBuffer32NumWords);

uint32_t
maxvid_deltas_decompress32(uint32_t *inputBuffer32, uint32_t *outputBuffer32, uint32_t inputBuffer32NumWords);

#endif // MV_ENABLE_DELTAS
