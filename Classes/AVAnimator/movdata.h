// movdata module
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

#define PREMULT_TABLEMAX 256

extern const uint8_t* const extern_alphaTablesPtr;

void premultiply_init();

// Execute premultiply logic on RGBA components split into componenets.
// For example, a pixel RGB (128, 0, 0) with A = 128
// would return (255, 0, 0) with A = 128

static
inline
uint32_t premultiply_bgra_inline(uint32_t red, uint32_t green, uint32_t blue, uint32_t alpha)
{
#if defined(DEBUG)
  assert(red >= 0 && red <= 255);
  assert(green >= 0 && green <= 255);
  assert(blue >= 0 && blue <= 255);
  assert(alpha >= 0 && alpha <= 255);
#endif
  const uint8_t* const restrict alphaTable = &extern_alphaTablesPtr[alpha * PREMULT_TABLEMAX];
  uint32_t result = (alpha << 24) | (alphaTable[red] << 16) | (alphaTable[green] << 8) | alphaTable[blue];
  return result;
}

// undo a "premultiply" operation. Note that a premultiplication is not fully
// reversable in the sense that the result of an unpremultiply call is
// the original RGB+A data. A premultiply operation will round the result
// of the (Component * (ALPHA/255)) calculation such that the premultiplied
// pixel contains less actual information. But, since this rounding always
// needs to be done before rendering, there is no functional loss of information
// as long as the final render operation is executed with a graphics subsystem
// that accepts only premultiplied values.

uint32_t unpremultiply_bgra(uint32_t premultPixelBGRA);

// Contains specific data about a sample. A sample contains
// info that tells the system how to decompress movie data
// for a specific frame. But, multiple frames could map to
// the same sample in the case where no data changes in the
// video from one frame to the next.

#define MOVSAMPLE_IS_KEYFRAME 0x1

typedef struct MovSample {
  uint32_t offset; // file offset where sample data is located
  uint32_t lengthAndFlags; // length stored in lower 24 bits. Upper 8 bits contain flags.
} MovSample;

// This structure is filled in by a parse operation.

typedef struct MovData {
  uint32_t width;
  uint32_t height;
  uint32_t numSamples;
	uint32_t maxSampleSize;
  
  MovSample *samples;
  uint32_t numFrames;
  MovSample **frames; // note that the number of frames can be larger than samples.

  uint32_t timeScale;
  uint32_t fps;
  float lengthInSeconds;
  uint32_t lengthInTicks;
  uint32_t bitDepth; // 16, 24, or 32
  uint16_t graphicsMode;
  char fccbuffer[5];

  uint32_t rleDataOffset;
  uint32_t rleDataLength;
  uint32_t errCode; // used to report an error condition
  char errMsg[1024]; // used to report an error condition

  uint32_t timeToSampleTableNumEntries;
  uint32_t timeToSampleTableOffset;
  uint32_t syncSampleTableNumEntries;
  uint32_t syncSampleTableOffset;
  uint32_t sampleToChunkTableNumEntries;
  uint32_t sampleToChunkTableOffset;
  uint32_t sampleSizeCommon; // non-zero if sampleSizeTableNumEntries is zero!
  uint32_t sampleSizeTableNumEntries;
  uint32_t sampleSizeTableOffset;
  uint32_t chunkOffsetTableNumEntries;
  uint32_t chunkOffsetTableOffset;  
  
  unsigned foundMDAT:1;
  unsigned foundMVHD:1;
  unsigned foundTRAK:1;
  unsigned foundTKHD:1;
  unsigned foundEDTS:1;
  unsigned foundELST:1;
  unsigned foundMDIA:1;
  unsigned foundMHLR:1;
  unsigned foundDHLR:1;
  unsigned foundVMHD:1;  
  unsigned foundDREF:1;
  unsigned foundSTBL:1;
  unsigned foundSTSD:1;
  unsigned foundSTTS:1;
  unsigned foundSTSS:1;
  unsigned foundSTSC:1;
  unsigned foundSTSZ:1;
  unsigned foundSTCO:1;
} MovData;

// ctor/dtor

void movdata_init(MovData *movData);
void movdata_free(MovData *movData);  

static
inline
uint32_t movsample_iskeyframe(MovSample *movSample) {
  return ((movSample->lengthAndFlags >> 24) & MOVSAMPLE_IS_KEYFRAME) != 0;
}

static
inline
uint32_t movsample_length(MovSample *movSample) {
  return movSample->lengthAndFlags & 0xFFFFFF;
}

// recurse into atoms and process them. Return 0 on success
// otherwise non-zero to indicate an error.

uint32_t
process_atoms(FILE *movFile, MovData *movData, uint32_t maxOffset);

// This method is invoked after all the atoms have been read
// successfully.

uint32_t
process_sample_tables(FILE *movFile, MovData *movData);

// Process a single sample, decode the RLE data contained at the
// file offset indicated in the sample. Returns 0 on success, otherwise non-zero.
//
// Note that the type of frameBuffer you pass in (uint16_t* or uint32_t*) depends
// on the bit depth of the mov. If NULL is passed as frameBuffer, no pixels are written during decoding.

uint32_t
read_process_rle_sample(FILE *movFile, MovData *movData, MovSample *sample, void *frameBuffer, const void *sampleBuffer, uint32_t sampleBufferSize);

// Process sample data contained in an already memory mapped file. Unlike process_rle_sample above
// this method requires that frameBuffer is not NULL.
// Returns 0 on success, otherwise non-zero.
//
// Note that the type of frameBuffer you pass in (uint16_t* or uint32_t*) depends
// on the bit depth of the mov.

uint32_t
process_rle_sample(void *mappedFilePtr, MovData *movData, MovSample *sample, void *frameBuffer);


// Use for testing just the decode logic for a single frame

void
exported_decode_rle_sample16(
                             void *sampleBuffer,
                             uint32_t sampleBufferSize,
                             uint32_t isKeyframe,
                             void *frameBuffer,
                             uint32_t frameBufferWidth,
                             uint32_t frameBufferHeight);

void
exported_decode_rle_sample24(
                             void *sampleBuffer,
                             uint32_t sampleBufferSize,
                             uint32_t isKeyframe,
                             void *frameBuffer,
                             uint32_t frameBufferWidth,
                             uint32_t frameBufferHeight);

void
exported_decode_rle_sample32(
                             void *sampleBuffer,
                             uint32_t sampleBufferSize,
                             uint32_t isKeyframe,
                             void *frameBuffer,
                             uint32_t frameBufferWidth,
                             uint32_t frameBufferHeight);
