// movdata conversion module
//
//  License terms defined in License.txt.
//
// This module implements a self contained Quicktime MOV file parser
// with verification that the MOV contains only a single Animation video track.
// This file should be #included into an implementation main file
// so that inline functions are seen as being in the same module.

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

//#define DUMP_WHILE_PARSING
//#define DUMP_WHILE_DECODING

// Use for testing just the decode logic for a single frame

uint32_t
movdata_convert_maxvid_decode_rle_sample16(
                                            void *sampleBuffer,
                                            uint32_t sampleBufferSize,
                                            uint32_t isKeyframe,
                                            uint32_t * restrict maxvidCodes,
                                            uint32_t * restrict numCodesWords,
                                            uint32_t width,
                                            uint32_t height);

uint32_t
movdata_convert_maxvid_decode_rle_sample24(
                                           void *sampleBuffer,
                                           uint32_t sampleBufferSize,
                                           uint32_t isKeyframe,
                                           uint32_t * restrict maxvidCodes,
                                           uint32_t * restrict numCodesWords,
                                           uint32_t width,
                                           uint32_t height);

uint32_t
movdata_convert_maxvid_decode_rle_sample32(
                                           void *sampleBuffer,
                                           uint32_t sampleBufferSize,
                                           uint32_t isKeyframe,
                                           uint32_t * restrict maxvidCodes,
                                           uint32_t * restrict numCodesWords,
                                           uint32_t width,
                                           uint32_t height);

// Convert a specific frame of .mov data to a maxvid c4 encoded frame.

uint32_t
movdata_convert_maxvid_frame(
                       const void * restrict movSampleBuffer,
                       const uint32_t movSampleBufferNumBytes,
                       const uint32_t isKeyframe,
                       uint32_t **maxvidCodeBufferPtr,
                       uint32_t *maxvidCodeBufferNumBytesPtr,
                       FILE *maxvidOutFile,
                       const uint32_t width,
                       const uint32_t height,
                       const uint32_t bpp);

// Convert each frame of .mov data into a c4 encoded maxvid frame
// and save as a maxvid file. Returns zero on success, non-zero otherwise.

uint32_t
movdata_convert_maxvid_file(
                            char *inMovPath,
                            char *inMovData,
                            uint32_t inMovDataNumBytes,
                            char *outMaxvidPath,
                            uint32_t genAdler);

// Util to open and process headers of a .mov file

#import "movdata.h"

uint32_t
movdata_convert_open_file(
                          char *inMovPath,
                          uint32_t inMovDataNumBytes,
                          MovData *movData);
