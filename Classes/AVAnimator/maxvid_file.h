/*
 *  maxvid_file.h
 *  QTDecodeAnimationByteOrderTestApp
 *
 *  Created by Moses DeJong on 4/19/11.
 *  Copyright 2011 `. All rights reserved.
 *
 */

#include "maxvid_decode.h"

#define MV_FILE_MAGIC 0xCAFEBABE

#define MV_FRAME_IS_KEYFRAME 0x1
#define MV_FRAME_IS_NOPFRAME 0x2

// A maxvid file is an "in memory" representation of video data that has been
// written to a file. The data is always in the native endian format.
// The data structures are sized for efficient execution, not minimal space
// usage or portability. Data is a maxvid file is not validated, so the input data can't be
// invalid. This assumption is based on the fact that most usage will involve
// generating a maxvid file based on an intermediate format that can be validated.

typedef struct {
  uint32_t magic;
  uint32_t width;
  uint32_t height;
  uint32_t bpp;
  // FIXME: is flaot 32 bit on 64 bit systems ?
  float frameDuration;
  uint32_t numFrames;
  // Padding out to 16 words, so that there is room to add additional fields later
  uint32_t padding[16-6];
} MVFileHeader;

// After the MVFileHeader, an array of numFrames MVFrame word pairs.

typedef struct {
    uint32_t offset; // file offset where sample data is located
    uint32_t lengthAndFlags; // length stored in lower 24 bits. Upper 8 bits contain flags.
    uint32_t adler; // adler32 checksum of the decoded framebuffer
} MVFrame;

// A MVFile points to the start of the file, the header and frames can be accessed directly.

typedef struct {
  MVFileHeader header;
  MVFrame frames[0];
} MVFile;

static inline
void maxvid_frame_setkeyframe(MVFrame *mvFrame) {
  mvFrame->lengthAndFlags |= MV_FRAME_IS_KEYFRAME;
}

static inline
void maxvid_frame_setnopframe(MVFrame *mvFrame) {
  mvFrame->lengthAndFlags |= MV_FRAME_IS_NOPFRAME;
}

static inline
void maxvid_frame_setoffset(MVFrame *mvFrame, uint32_t offset) {
  mvFrame->offset = offset;
}

static inline
void maxvid_frame_setlength(MVFrame *mvFrame, uint32_t size) {
  assert((size & MV_MAX_24_BITS) == size);
  mvFrame->lengthAndFlags &= MV_MAX_8_BITS;
  mvFrame->lengthAndFlags |= (size << 8);
}

static inline
uint32_t maxvid_frame_iskeyframe(MVFrame *mvFrame) {
  return ((mvFrame->lengthAndFlags & MV_FRAME_IS_KEYFRAME) != 0);
}

static inline
uint32_t maxvid_frame_isnopframe(MVFrame *mvFrame) {
  return ((mvFrame->lengthAndFlags & MV_FRAME_IS_NOPFRAME) != 0);
}

static inline
uint32_t maxvid_frame_offset(MVFrame *mvFrame) {
  return mvFrame->offset;
}

static inline
uint32_t maxvid_frame_length(MVFrame *mvFrame) {
  return (mvFrame->lengthAndFlags >> 8);
}

// Emit a word that represents a nop frame, an empty delta.
// A nop frame is never decoded, it simply acts as a placeholder
// so that the next frame does not begin on the exact same
// word as the nop frame. This zero word will compress well,
// so many nop frames in a row will also compress well.

static inline
uint32_t maxvid_file_emit_nopframe() {
  return 0;
}

// "open" a memory mapped buffer that contains a completely
// written .mvid file. The magic number is validated to
// verify that the file was not partially written, but no
// other validation is done. The mapped data must not
// be unmapped while this ref is being used.

static inline
MVFile* maxvid_file_map_open(void *buffer) {
  assert(sizeof(MVFileHeader) == 16*4);
  assert(sizeof(MVFrame) == 3*4);
  
  MVFile *mvFilePtr = (MVFile *)buffer;
  uint32_t magic = mvFilePtr->header.magic;
  assert(magic == MV_FILE_MAGIC);
  assert(mvFilePtr->header.bpp == 16 || mvFilePtr->header.bpp == 24 || mvFilePtr->header.bpp == 32);
  return mvFilePtr;
}

// "close" is actually a no-op.

static inline
void maxvid_file_map_close(MVFile *mvFile) {
  return;
}

// Get the MVFrame* that corresponds to the frame at the given index.

static inline
MVFrame* maxvid_file_frame(MVFile *mvFile, uint32_t index) {
  return &(mvFile->frames[index]);
}

// Return non-zero if the indicated FILE* is ready to be processed,
// meaning it has a valid magic number. In the case where a writer thread
// is generating a file, this test will not return true until the
// file is completely written.

static inline
uint32_t maxvid_file_is_valid(FILE *inFile) {
  (void)fseek(inFile, 0L, SEEK_SET);
  uint32_t magic;
  int numRead = fread(&magic, sizeof(uint32_t), 1, inFile);
  if (numRead != 1) {
    // Could not read magic number
    return 0;
  }
  assert(numRead == 1);
  if (magic == MV_FILE_MAGIC) {
    return 1;
  } else {
    assert(magic == 0);
    return 0;
  }
}

// Emit zero length words up to the next page bound when emitting a keyframe.
// Pass in the current offset, function returns the new offset. This method
// will emit zero words of padding if exactly on the page bound already.

static inline
uint32_t maxvid_file_padding_before_keyframe(FILE *outFile, uint32_t offset) {
  assert((offset % 4) == 0);
  
  const uint32_t boundSize = MV_PAGESIZE;
  uint32_t bytesToBound = UINTMOD(offset, boundSize);
  assert(bytesToBound >= 0 && bytesToBound <= boundSize);
    
  bytesToBound = boundSize - bytesToBound;
  uint32_t wordsToBound = bytesToBound >> 2;
  wordsToBound &= ((MV_PAGESIZE >> 2) - 1);

  if (wordsToBound > 0) {
    assert(bytesToBound == (wordsToBound * 4));
    assert(wordsToBound < (boundSize / 4));
  }

  uint32_t zero = 0;
  while (wordsToBound != 0) {
    size_t size = fwrite(&zero, sizeof(zero), 1, outFile);
    assert(size == 1);
    wordsToBound--;
  }
  
  offset = ftell(outFile);

  assert(UINTMOD(offset, boundSize) == 0);
  
  return offset;
}

// Emit zero length words up to the next page bound after the keyframe data.
// Pass in the current offset, function returns the new offset.
// This method will emit zero words of padding if exactly on the page bound already.

static inline
uint32_t maxvid_file_padding_after_keyframe(FILE *outFile, uint32_t offset) {
  return maxvid_file_padding_before_keyframe(outFile, offset);
}

uint32_t maxvid_adler32(
                        uint32_t adler,
                        unsigned char const *buf,
                        uint32_t len);
