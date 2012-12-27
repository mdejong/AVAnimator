// maxvid_file module
//
//  License terms defined in License.txt.
//
// This module defines the format and logic to read and write a maxvid file.

#include "maxvid_decode.h"

#define MV_FILE_MAGIC 0xCAFEBABE

// This flag is set for a .mvid file that contains no delta frames. It is possible
// to significantly optimize reading logic using shared memory when we know that
// there are no delta frames that need to be applied. When running on the device
// the decode logic typically emits mvid files that contain only keyframes because
// of the CPU associated with recalculating frame deltas.

// Note that 0x1 is currently unused, it could be used in the future but keep in
// mind that already generated .mvids might have it set as it was used for sRGB flag.

#define MV_FILE_ALL_KEYFRAMES 0x2

#define MV_FRAME_IS_KEYFRAME 0x1
#define MV_FRAME_IS_NOPFRAME 0x2

// These constants define .mvid file revision constants. For example, AVAnimator 1.0
// versions made use of the value 0, while AVAnimator 2.0 now emits files with the
// version set to 1.

#define MV_FILE_VERSION_ZERO 0
#define MV_FILE_VERSION_ONE 1

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
MVFrame* maxvid_file_frame(MVFrame *mvFrames, uint32_t index) {
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

// adler32 calculation method

uint32_t maxvid_adler32(
                        uint32_t adler,
                        unsigned char const *buf,
                        uint32_t len);
