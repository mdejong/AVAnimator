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
  int width;
  int height;
  int numSamples;
	uint32_t maxSampleSize;
  
  MovSample *samples;
  int numFrames;
  MovSample **frames; // note that the number of frames can be larger than samples.

  int timeScale;
  int fps;
  float lengthInSeconds;
  uint32_t lengthInTicks;
  int bitDepth; // 16, 24, or 32
  uint16_t graphicsMode;
  char fccbuffer[5];

  int rleDataOffset;
  int rleDataLength;
  int errCode; // used to report an error condition
  char errMsg[1024]; // used to report an error condition

  int timeToSampleTableNumEntries;
  uint32_t timeToSampleTableOffset;
  int syncSampleTableNumEntries;
  uint32_t syncSampleTableOffset;
  int sampleToChunkTableNumEntries;
  uint32_t sampleToChunkTableOffset;
  int sampleSizeCommon; // non-zero if sampleSizeTableNumEntries is zero!
  int sampleSizeTableNumEntries;
  uint32_t sampleSizeTableOffset;
  int chunkOffsetTableNumEntries;
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
int movsample_iskeyframe(MovSample *movSample) {
  return (movSample->lengthAndFlags >> 24) & MOVSAMPLE_IS_KEYFRAME;
}

static
inline
int movsample_length(MovSample *movSample) {
  return movSample->lengthAndFlags & 0xFFFFFF;
}

// recurse into atoms and process them. Return 0 on success
// otherwise non-zero to indicate an error.

int
process_atoms(FILE *movFile, MovData *movData, uint32_t maxOffset);

// This method is invoked after all the atoms have been read
// successfully.

int
process_sample_tables(FILE *movFile, MovData *movData);

// Process a single sample, decode the RLE data contained at the
// file offset indicated in the sample. Returns 0 on success, otherwise non-zero.
//
// Note that the type of frameBuffer you pass in (uint16_t* or uint32_t*) depends
// on the bit depth of the mov. If NULL is passed as frameBuffer, no pixels are written during decoding.

int
read_process_rle_sample(FILE *movFile, MovData *movData, MovSample *sample, void *frameBuffer, const void *sampleBuffer, uint32_t sampleBufferSize);

// Process sample data contained in an already memory mapped file. Unlike process_rle_sample above
// this method requires that frameBuffer is not NULL.
// Returns 0 on success, otherwise non-zero.
//
// Note that the type of frameBuffer you pass in (uint16_t* or uint32_t*) depends
// on the bit depth of the mov.

int
process_rle_sample(void *mappedFilePtr, MovData *movData, MovSample *sample, void *frameBuffer);


// Use for testing just the decode logic for a single frame

void
exported_decode_rle_sample16(
                             void *sampleBuffer,
                             int sampleBufferSize,
                             int isKeyframe,
                             void *frameBuffer,
                             int frameBufferWidth,
                             int frameBufferHeight);
