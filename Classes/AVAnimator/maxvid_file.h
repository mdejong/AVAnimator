// maxvid_file module
//
//  License terms defined in License.txt.
//
// This module defines the format and logic to read and write a maxvid file.

#include "maxvid_decode.h"

// If this define is set to 1, then support for the experimental "deltas"
// input format will be enabled. This deltas logic will generate a diff
// of every frame, including the initial frame.

#define MV_ENABLE_DELTAS 1

#define MV_FILE_MAGIC 0xCAFEBABE

// This flag is set for a .mvid file that contains no delta frames. It is possible
// to significantly optimize reading logic using shared memory when we know that
// there are no delta frames that need to be applied. When running on the device
// the decode logic typically emits mvid files that contain only keyframes because
// of the CPU associated with recalculating frame deltas.

// Note that 0x1 is currently unused, it could be used in the future but keep in
// mind that already generated .mvids might have it set as it was used for sRGB flag.

#define MV_FILE_ALL_KEYFRAMES 0x2

// This flag is set for a .mvid file that contains all delta frames. Even the first
// frame is a delta. This makes it possible to delta specific pixels in the frame
// deltas.

#if MV_ENABLE_DELTAS
#define MV_FILE_DELTAS 0x4
#endif // MV_ENABLE_DELTAS

// These flags are set for a specific frame. A keyframe is not a delta. When
// data does not change from one frame to the next, that is a nop frame.

#define MV_FRAME_IS_KEYFRAME (1 << 0)
#define MV_FRAME_IS_NOPFRAME (1 << 1)
#define MV_FRAME_IS_COMPRESSED (1 << 2)

// These constants define .mvid file revision constants. For example, AVAnimator 1.0
// versions made use of the value 0, while AVAnimator 2.0 now emits files with the
// version set to 1. AVAnimator 3.0 supports version 3 which includes large file
// support and support for very large video sizes.

#define MV_FILE_VERSION_ZERO 0
#define MV_FILE_VERSION_ONE 1
#define MV_FILE_VERSION_TWO 2
#define MV_FILE_VERSION_THREE 3

// A maxvid file is an "in memory" representation of video data that has been
// written to a file. The data is always in the native endian format.
// The data structures are sized for efficient execution, not minimal space
// usage or portability. Data is a maxvid file is not validated, so the input data can't be
// invalid. This assumption is based on the fact that most usage will involve
// generating a maxvid file based on an intermediate format that can be validated.
// Instead of validating on data access on the embedded device, we validate on write
// typically done on the desktop.

typedef struct {
  uint32_t magic;
  uint32_t width;
  uint32_t height;
  uint32_t bpp;
  // FIXME: is float 32 bit on 64 bit systems ?
  float frameDuration;
  uint32_t numFrames;
  // version is the MVID file format version number, in cases where an earlier
  // version of the file needs to be read by a later version of the library.
  // The version portion is the first 8 bits while the rest are bit flags.
  uint32_t versionAndFlags;
  // Padding out to 16 words, so that there is room to add additional fields later
  uint32_t padding[16-7];
} MVFileHeader;

// After the MVFileHeader, an array of numFrames MVFrame word pairs.

typedef struct {
    uint32_t offset; // file offset where sample data is located
    uint32_t lengthAndFlags; // length stored in lower 24 bits. Upper 8 bits contain flags.
    uint32_t adler; // adler32 checksum of the decoded framebuffer
} MVFrame;

// Full support for very large (larger than 2 gigs) files was
// added for both delta and keyframe files as of version 4.
// This version requires a larger type of frame since the
// size in bytes is now stored as a 32 bit unsigned integer.

typedef struct {
  uint64_t offset64; // file offset where sample data is located (either keyframe or delta)
  uint32_t length; // length in bytes
  uint32_t flags; // flags for frame
  uint32_t adler; // adler32 checksum of the decoded framebuffer
  uint32_t dummy; // zero to fill out to double word length
} MVV3Frame;

static inline
void maxvid_frame_setkeyframe(MVFrame *mvFrame) {
  mvFrame->lengthAndFlags |= MV_FRAME_IS_KEYFRAME;
}

static inline
void maxvid_v3_frame_setkeyframe(MVV3Frame *mvFrame) {
  mvFrame->flags |= MV_FRAME_IS_KEYFRAME;
}

static inline
void maxvid_frame_setnopframe(MVFrame *mvFrame) {
  mvFrame->lengthAndFlags |= MV_FRAME_IS_NOPFRAME;
}

static inline
void maxvid_v3_frame_setnopframe(MVV3Frame *mvFrame) {
  mvFrame->flags |= MV_FRAME_IS_NOPFRAME;
}

static inline
void maxvid_v3_frame_setcompressed(MVV3Frame *mvFrame) {
  mvFrame->flags |= MV_FRAME_IS_COMPRESSED;
}

// Set/Get frame offset and length, both in terms of bytes

static inline
void maxvid_frame_setoffset(MVFrame *mvFrame, uint32_t offset) {
  mvFrame->offset = offset;
}

static inline
void maxvid_v3_frame_setoffset(MVV3Frame *mvFrame, uint64_t offset) {
  mvFrame->offset64 = offset;
}

static inline
void maxvid_frame_setlength(MVFrame *mvFrame, uint32_t size) {
  assert((size & MV_MAX_24_BITS) == size);
  mvFrame->lengthAndFlags &= MV_MAX_8_BITS;
  mvFrame->lengthAndFlags |= (size << 8);
}

static inline
void maxvid_v3_frame_setlength(MVV3Frame *mvFrame, uint32_t size) {
  mvFrame->length = size;
}

static inline
uint32_t maxvid_frame_iskeyframe(MVFrame *mvFrame) {
  return ((mvFrame->lengthAndFlags & MV_FRAME_IS_KEYFRAME) != 0);
}

static inline
uint32_t maxvid_v3_frame_iskeyframe(MVV3Frame *mvFrame) {
  return ((mvFrame->flags & MV_FRAME_IS_KEYFRAME) != 0);
}

static inline
uint32_t maxvid_frame_isnopframe(MVFrame *mvFrame) {
  return ((mvFrame->lengthAndFlags & MV_FRAME_IS_NOPFRAME) != 0);
}

static inline
uint32_t maxvid_v3_frame_isnopframe(MVV3Frame *mvFrame) {
  return ((mvFrame->flags & MV_FRAME_IS_NOPFRAME) != 0);
}

static inline
uint32_t maxvid_v3_frame_iscompressed(MVV3Frame *mvFrame) {
  return ((mvFrame->flags & MV_FRAME_IS_COMPRESSED) != 0);
}

static inline
uint32_t maxvid_frame_offset(MVFrame *mvFrame) {
  return mvFrame->offset;
}

static inline
uint64_t maxvid_v3_frame_offset(MVV3Frame *mvFrame) {
  return mvFrame->offset64;
}

static inline
uint32_t maxvid_frame_length(MVFrame *mvFrame) {
  return (mvFrame->lengthAndFlags >> 8);
}

static inline
uint32_t maxvid_v3_frame_length(MVV3Frame *mvFrame) {
  return mvFrame->length;
}

// Return non-zero if the framebuffer is so large that it cannot be stored as a maxvid file.
// This basically means that the number of bytes is so huge that a 24 bit value cannot hold it.

static inline
int maxvid_frame_check_max_size(uint32_t width, uint32_t height, int bpp) {
  int numBytesInPixel;
  if (bpp == 16) {
    numBytesInPixel = 2;
  } else {
    // 24 or 32 BPP pixels are both stored in 32 bits
    numBytesInPixel = 4;
  }
  int actualSize = numBytesInPixel * width * height;
  if (actualSize > MV_MAX_24_BITS) {
    return 1;
  } else {
    return 0;
  }
}

// Check that the W x H for a specific frame fits into a 32 bit word.
// This size will basically support any rational size, the upper limit
// is somethign like (4096*10)^2 which is insane.

static inline
int maxvid_v3_frame_check_max_size(uint32_t width, uint32_t height, int bpp) {
  int numBytesInPixel;
  if (bpp == 16) {
    numBytesInPixel = 2;
  } else {
    // 24 or 32 BPP pixels are both stored in 32 bits
    numBytesInPixel = 4;
  }
  int actualSize = numBytesInPixel * width * height;
  if (actualSize > MV_MAX_32_BITS) {
    return 1;
  } else {
    return 0;
  }
}

// This method returns 1 in the case where a given image is so large
// that a version 3 format file must be used to represent it.

static inline
int maxvid_v4_frame_required(uint32_t width, uint32_t height, int bpp) {
  return maxvid_frame_check_max_size(width, height, bpp);
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

// Verify the contents of the header for a MVID file.
// The magic number is validated to verify that the file was not
// partially written. In addition the bpp values are verified.

static inline
void maxvid_file_map_verify(void *buffer) {
  assert(sizeof(MVFileHeader) == 16*4);
  assert(sizeof(MVFrame) == 3*4);

  assert(buffer);
  MVFileHeader *mvFileHeaderPtr = (MVFileHeader *)buffer;
  uint32_t magic = mvFileHeaderPtr->magic;
  assert(magic == MV_FILE_MAGIC);
  assert(mvFileHeaderPtr->bpp == 16 || mvFileHeaderPtr->bpp == 24 || mvFileHeaderPtr->bpp == 32);
}

// Get the MVFrame* that corresponds to the frame at the given index.

static inline
MVFrame* maxvid_file_frame(void *framesPtr, uint32_t index) {
  MVFrame *mvFrames = (MVFrame*) framesPtr;
  return &(mvFrames[index]);
}

// Get the MVV3Frame* that corresponds to the frame at the given index.

static inline
MVV3Frame* maxvid_v3_file_frame(void *framesPtr, uint32_t index) {
  MVV3Frame *mvFrames = (MVV3Frame*) framesPtr;
  return &(mvFrames[index]);
}

// Return non-zero if the indicated FILE* is ready to be processed,
// meaning it has a valid magic number. In the case where a writer thread
// is generating a file, this test will not return true until the
// file is completely written.

static inline
uint32_t maxvid_file_is_valid(FILE *inFile) {
  (void)fseek(inFile, 0L, SEEK_SET);
  uint32_t magic;
  int numRead = (int) fread(&magic, sizeof(uint32_t), 1, inFile);
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

// Query the file "version", meaning a integer number that would get incremented
// when an incompatible change to the file format is made. This is only useful
// for library internals that might need to do something slightly different
// depending on the binary layout of older versions of the file.

static inline
uint8_t maxvid_file_version(MVFileHeader *fileHeaderPtr) {
  uint8_t version = fileHeaderPtr->versionAndFlags & 0xFF;
  return version;
}

// Explicitly set the maxvid file version. The initial version used is zero.

static inline
void maxvid_file_set_version(MVFileHeader *fileHeaderPtr, uint8_t revision) {
  uint32_t flags = fileHeaderPtr->versionAndFlags >> 8;
  fileHeaderPtr->versionAndFlags = (flags << 8) | revision;  
}

// Return TRUE if each frame in the file is a keyframe. A keyframe indicates
// that all frame data is contained in one place, so the frame does not
// depend on the previous framebuffer state like in the delta frame case.

static inline
uint32_t maxvid_file_is_all_keyframes(MVFileHeader *fileHeaderPtr) {
  uint32_t flags = fileHeaderPtr->versionAndFlags >> 8;
  uint32_t isAllKeyframes = flags & MV_FILE_ALL_KEYFRAMES;
  return isAllKeyframes;
}

// Explicitly set the all keyframes flag.

static inline
void maxvid_file_set_all_keyframes(MVFileHeader *fileHeaderPtr) {
  fileHeaderPtr->versionAndFlags |= (MV_FILE_ALL_KEYFRAMES << 8);
}

#if MV_ENABLE_DELTAS

// Return TRUE if this file was encoded with frame and pixel deltas.
// The -deltas option at the command line controls this special logic
// that makes it possible to treat pixel values as deltas as opposed
// to direct values.

static inline
uint32_t maxvid_file_is_deltas(MVFileHeader *fileHeaderPtr) {
  uint32_t flags = fileHeaderPtr->versionAndFlags >> 8;
  uint32_t isDeltas = flags & MV_FILE_DELTAS;
  return isDeltas;
}

// Explicitly set the deltas flag.

static inline
void maxvid_file_set_deltas(MVFileHeader *fileHeaderPtr) {
  fileHeaderPtr->versionAndFlags |= (MV_FILE_DELTAS << 8);
}

#endif // MV_ENABLE_DELTAS

// adler32 calculation method

uint32_t maxvid_adler32(
                        uint32_t adler,
                        unsigned char const *buf,
                        uint32_t len);
