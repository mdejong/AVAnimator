/*
 *  apng_convert_maxvid.h
 *
 *  Created by Moses DeJong on 4/29/11.
 */

#include "apng_convert_maxvid.h"

#include "movdata.h"

#include "maxvid_decode.h"
#include "maxvid_encode.h"
#include "maxvid_file.h"

#include "libapng.h"

typedef struct {
  FILE *maxvidOutFile;
  MVFrame *mvFramesArray;
  float frameDuration;
  uint32_t outFrame;
  uint32_t width;
  uint32_t height;
  uint32_t bpp;
  uint32_t genAdler;
  uint32_t *cgFrameBuffer;
} LibapngUserData;

// Read a big endian uint32_t from a char* and store in result (ARGB).
// Each pixel needs to be multiplied by the alpha channel value.
// Optimized premultiplication implementation using table lookups

#define TABLEMAX 256
//#define TABLEDUMP

static
uint8_t alphaTables[TABLEMAX*TABLEMAX];
static
int alphaTablesInitialized = 0;

// Input is a ARGB (non-premultiplied) pixel.
// Output is a ABGR (premultiplied) pixel for CoreGraphics bitmap.

static inline
uint32_t argb_to_abgr_and_premultiply(uint32_t pixel)
{
  uint32_t alpha = (pixel >> 24) & 0xFF;
  uint32_t red = (pixel >> 16) & 0xFF;
  uint32_t green = (pixel >> 8) & 0xFF;
  uint32_t blue = (pixel >> 0) & 0xFF;
  
  uint8_t * restrict alphaTable = &alphaTables[alpha * TABLEMAX];
  return (alpha << 24) | (alphaTable[blue] << 16) | (alphaTable[green] << 8) | alphaTable[red];
}

// Input is a ARGB where A is always 0xFF
// Output is a ABGR pixel for CoreGraphics bitmap.

static inline
uint32_t argb_to_abgr(uint32_t pixel)
{
  uint32_t alpha = (pixel >> 24) & 0xFF;
  uint32_t red = (pixel >> 16) & 0xFF;
  uint32_t green = (pixel >> 8) & 0xFF;
  uint32_t blue = (pixel >> 0) & 0xFF;
  
  return (alpha << 24) | (blue << 16) | (green << 8) | red;
}

//#define TO_RGBA(red, green, blue, alpha) ((red << 24)|  (green << 16) | (blue << 8) | alpha)
#define TO_ARGB(red, green, blue, alpha) ((alpha << 24)|  (red << 16) | (green << 8) | blue)
#define TO_ABGR(red, green, blue, alpha) ((alpha << 24)|  (blue << 16) | (green << 8) | red)

static
void init_alphaTables() {
  if (alphaTablesInitialized) {
    return;
  }
  
  for (int alpha = 0; alpha < TABLEMAX; alpha++) {
    uint8_t *alphaTable = &alphaTables[alpha * TABLEMAX];
    float alphaf = alpha / 255.0; // (TABLEMAX - 1)
#ifdef TABLEDUMP
    fprintf(stdout, "alpha table for alpha %d = %f\n", alpha, alphaf);
#endif
    for (int i = 0; i < TABLEMAX; i++) {
      int rounded = (int) round(i * alphaf);
      if (rounded < 0 || rounded >= TABLEMAX) {
        assert(0);
      }
      assert(rounded == (int) (i * alphaf + 0.5));
      alphaTable[i] = (uint8_t)rounded;
#ifdef TABLEDUMP
      if (i == 0 || i == 1 || i == 2 || i == 126 || i == 127 || i == 128 || i == 254 || i == 255) {
        fprintf(stdout, "alphaTable[%d] = %d\n", i, alphaTable[i]);
      }
#endif
    }
  }
  
  // alpha = 0.0
  
  assert(alphaTables[(0 * TABLEMAX) + 0] == 0);
  assert(alphaTables[(0 * TABLEMAX) + 255] == 0);
  
  // alpha = 1.0
  
  assert(alphaTables[(255 * TABLEMAX) + 0] == 0);
  assert(alphaTables[(255 * TABLEMAX) + 127] == 127);
  assert(alphaTables[(255 * TABLEMAX) + 255] == 255);
  
  // Test all generated alpha values in table using
  // read_ARGB_and_premultiply()
  
  for (int alphai = 0; alphai < TABLEMAX; alphai++) {
    for (int i = 0; i < TABLEMAX; i++) {
      uint8_t in_alpha = (uint8_t) alphai;
      uint8_t in_red = 0;
      uint8_t in_green = (uint8_t) i;
      uint8_t in_blue = (uint8_t) i;
      //if (i == 1) {
      //  assert(alphaTables[(255 * TABLEMAX) + 0] == 0);
      //}

      // RGBA input
      //uint32_t in_pixel = TO_RGBA(in_red, in_green, in_blue, in_alpha);
      
      // ARGB input
      uint32_t in_pixel = TO_ARGB(in_red, in_green, in_blue, in_alpha);
      
      //uint32_t in_pixel_be = htonl(in_pixel); // pixel in BE byte order
      uint32_t pixel = in_pixel; // native byte order
      uint32_t premult_pixel_le;
      premult_pixel_le = argb_to_abgr_and_premultiply(pixel);
      
      // Compare read_ARGB_and_premultiply() result to known good value
      
      float alphaf = in_alpha / 255.0; // (TABLEMAX - 1)
      int rounded = (int) round(i * alphaf);      
      uint8_t round_alpha = in_alpha;
      uint8_t round_red = 0;
      uint8_t round_green = (uint8_t) rounded;
      uint8_t round_blue = (uint8_t) rounded;
      // Special case: If alpha is 0, then all 3 components are zero
      if (round_alpha == 0) {
        round_red = round_green = round_blue = 0;
      }
      uint32_t expected_pixel_le = TO_ABGR(round_red, round_green, round_blue, round_alpha);
      
      if (premult_pixel_le != expected_pixel_le) {
        assert(0);
      }
    }
  }
  
  // Everything worked
  
  alphaTablesInitialized = 1;
}

static inline
uint32_t
fwrite_word(FILE *fp, uint32_t word) {
  size_t size = fwrite(&word, sizeof(uint32_t), 1, fp);
  if (size != 1) {
    return MV_ERROR_CODE_WRITE_FAILED;
  }
  return 0;
}

static inline
uint32_t
fread_word(FILE *fp, uint32_t *wordPtr) {
  uint8_t buffer[4];
  size_t size = fread(&buffer, sizeof(uint32_t), 1, fp);
  if (size != 1) {
    return MV_ERROR_CODE_READ_FAILED;
  }
  *wordPtr = (((uint32_t)buffer[0]) << 24) | (((uint32_t)buffer[1]) << 16) | (((uint32_t)buffer[2]) << 8) | (((uint32_t)buffer[3]) << 0);
  return 0;
}

static inline
uint32_t
fread_half_word(FILE *fp, uint16_t *halfwordPtr) {
  uint8_t buffer[2];
  size_t size = fread(&buffer, sizeof(uint16_t), 1, fp);
  if (size != 1) {
    return MV_ERROR_CODE_READ_FAILED;
  }
  *halfwordPtr = (((uint32_t)buffer[0]) << 8) | (((uint32_t)buffer[1]) << 0);
  return 0;
}

// Returned if the filename does not match *.apng or the data is not APNG data.

#define UNSUPPORTED_FILE 1
#define READ_ERROR 2
#define WRITE_ERROR 3

// This util method scans through the APNG chunks and determines the shortest frame duration.
// The mvid format is strictly frame oriented, so a delay of multiple frames is represented
// as a no-op frame. APNG instead uses variable frame delays, which is more compact but
// complicates the decoder. This util method can't make use of libpng because libpng wants
// to decode frame data to iterate over the animation frames. This method assumes that the
// file has already been validated as being a APNG file. The input fp is not closed in case
// an error is returned, the caller should take care to close it.

typedef struct
{
  uint32_t sequence_number;
  uint32_t width;
  uint32_t height;
  uint32_t x_offset;
  uint32_t y_offset;
  uint16_t delay_num;
  uint16_t delay_den;
  uint8_t dispose_op;
  uint8_t blend_op;
} fcTLChunkType;

#define IHDR_CHUNK 0x49484452
#define PTLE_CHUNK 0x504C5445
#define TRNS_CHUNK 0x74524E53
#define IDAT_CHUNK 0x49444154
#define FDAT_CHUNK 0x66644154
#define IEND_CHUNK 0x49454E44

// acTL : Animation Control Chunk
#define ACTL_CHUNK 0x6163544C

// fcTL : Frame Control Chunk 
#define FCTL_CHUNK 0x6663544C

void
apng_decode_chunk_name(
                       uint32_t chunk,
                       char *buffer)
{  
  switch (chunk) {
    case IHDR_CHUNK: {
      strcpy(buffer, "IHDR");
      break;
    }
    case IEND_CHUNK: {
      strcpy(buffer, "IEND");
      break;
    }      
    case PTLE_CHUNK: {
      strcpy(buffer, "PTLE");
      break;
    }
    case TRNS_CHUNK: {
      strcpy(buffer, "tRNS");
      break;
    }
    case IDAT_CHUNK: {
      strcpy(buffer, "IDAT");
      break;
    }
    case FDAT_CHUNK: {
      strcpy(buffer, "FDAT");
      break;
    }      
    case ACTL_CHUNK: {
      strcpy(buffer, "acTL");
      break;
    }
    case FCTL_CHUNK: {
      strcpy(buffer, "fcTL");
      break;
    }      
    default: {
      strcpy(buffer, "????");
      break;
    }
  }
  
  return;
}

// This utility method scans the PNG chunks before frame decoding begins. This logic is needed to detect the framerate
// before actually decoding frame data.

//#define DEBUG_PRINT_FRAME_DURATION

uint32_t
apng_decode_frame_duration(
                           FILE *fp,
                           float *outFrameDurationPtr,
                           uint32_t *numOutputFramesPtr,
                           uint32_t *numApngFramesPtr)
{
  uint32_t len, chunk, crc;
  uint32_t retcode = 1000;
  uint32_t status;
  
  uint32_t apngNumFrames = 0;
  uint32_t outputNumFrames = 0;
#ifdef DEBUG_PRINT_FRAME_DURATION
  char chunkNameBuffer[4+1];
#endif
  
  fcTLChunkType fcTLChunk;
  
  float smallestFrameDuration = (float) 10000;
  
  float *frameDurations = NULL;
  uint32_t frameDurationsSize = 0;
  
#undef RETCODE
#define RETCODE(status) \
if (status != 0) { \
retcode = status; \
goto retcode; \
}  
  
#ifdef DEBUG_PRINT_FRAME_DURATION
  printf("Reading APNG chunks...\n");
#endif
  status = fseek(fp, 0, SEEK_END);
  if (status != 0) {
    RETCODE(READ_ERROR);
  }
  uint32_t endOffset = ftell(fp);
#ifdef DEBUG_PRINT_FRAME_DURATION
  printf("file length %d\n", (int)ftell(fp));
#endif
  
  // Seek past PNG signature
  
  status = fseek(fp, 8, SEEK_SET);
  if (status != 0) {
    RETCODE(READ_ERROR);
  }
  
  do {
    // LENGTH
    
#ifdef DEBUG_PRINT_FRAME_DURATION
    fprintf(stdout, "offet %d : before chunk read : eof %d\n", (int)ftell(fp), feof(fp));
#endif
    
    if (fread_word(fp, &len)) {
      RETCODE(READ_ERROR);
    }
    
    // CHUNK TYPE
    
    if (fread_word(fp, &chunk)) {
      RETCODE(READ_ERROR);
    }
    
#ifdef DEBUG_PRINT_FRAME_DURATION
    apng_decode_chunk_name(chunk, chunkNameBuffer);
    fprintf(stdout, "offet %d : chunk 0x%X \"%s\" : len %d\n", (int)ftell(fp), chunk, chunkNameBuffer, len);
#endif
    
    if (chunk == ACTL_CHUNK) {
      // acTL
      
      // The acTL is quite useless because we can't assume that it appears before the fcTL      
    } else if (chunk == FCTL_CHUNK) {
      // fcTL : read from stream but avoid structure packing issues!
      
      if (fread_word(fp, &fcTLChunk.sequence_number) != 0 ||
          fread_word(fp, &fcTLChunk.width) != 0 ||
          fread_word(fp, &fcTLChunk.height) != 0 ||
          fread_word(fp, &fcTLChunk.x_offset) != 0 ||
          fread_word(fp, &fcTLChunk.y_offset) != 0 ||
          fread_half_word(fp, &fcTLChunk.delay_num) != 0 ||
          fread_half_word(fp, &fcTLChunk.delay_den) != 0 ||
          fread(&fcTLChunk.dispose_op, 1, 1, fp) != 1 ||
          fread(&fcTLChunk.blend_op, 1, 1, fp) != 1) {
        return READ_ERROR;
      }
      
      float frameDuration = (float) fcTLChunk.delay_num / (float) fcTLChunk.delay_den;
      
#ifdef DEBUG_PRINT_FRAME_DURATION
      fprintf(stdout, "frameDuration (%d) = %f\n", fcTLChunk.sequence_number, frameDuration);
#endif
      
      if (frameDurations == NULL) {
        frameDurationsSize = 16;
        frameDurations = malloc(sizeof(float) * frameDurationsSize);
      }
      if (apngNumFrames >= frameDurationsSize) {
        uint32_t oldSize = frameDurationsSize;
        frameDurationsSize *= 2;
        float *tmp = malloc(sizeof(float) * frameDurationsSize);
        memcpy(tmp, frameDurations, oldSize * sizeof(float));
        free(frameDurations);
        frameDurations = tmp;
      }
      frameDurations[apngNumFrames++] = frameDuration;
      
      if (frameDuration < smallestFrameDuration) {
        smallestFrameDuration = frameDuration;
      }
      
      len -= (sizeof(uint32_t) * 5) + (sizeof(uint16_t) * 2) + (sizeof(uint8_t) * 2);
    }
    
    // CHUNK DATA (can be zero)
    
    if (len > 0) {
      status = fseek(fp, len, SEEK_CUR);
      if (status != 0) {
        RETCODE(READ_ERROR);
      }
    }
    
    // CRC
    
    if (fread_word(fp, &crc)) {
      RETCODE(READ_ERROR);
    }
    
  } while (((int)ftell(fp)) < endOffset);
  
  // Iterate over each frame delay in the apng file and determine how many output frames there will be
  
  assert(apngNumFrames > 0);
  
  for (int i=0; i < apngNumFrames; i++) {
    float duration = frameDurations[i];
    
    int numFramesDelay = round(duration / smallestFrameDuration);
    assert(numFramesDelay >= 1);
    
    outputNumFrames++;
    
    if (numFramesDelay > 1) {
      outputNumFrames += (numFramesDelay - 1);
    }
  }
  
  *outFrameDurationPtr = smallestFrameDuration;  
  *numOutputFramesPtr = outputNumFrames;
  *numApngFramesPtr = apngNumFrames;
  
  retcode = 0;
  
retcode:
  
  if (frameDurations) {
    free(frameDurations);
  }
  
  return retcode;
}

// This callback is invoked when a specific framebuffer has been decoded from the APNG file

static int
process_apng_frame(
                   uint32_t* framebuffer,
                   uint32_t framei,
                   uint32_t width, uint32_t height,
                   uint32_t delta_x, uint32_t delta_y, uint32_t delta_width, uint32_t delta_height,
                   uint32_t delay_num, uint32_t delay_den,
                   uint32_t bpp,
                   void *userData)
{
  LibapngUserData *userDataPtr = (LibapngUserData*)userData;
  FILE *maxvidOutFile = userDataPtr->maxvidOutFile;
  MVFrame *mvFramesArray = userDataPtr->mvFramesArray;
  uint32_t genAdler = userDataPtr->genAdler;
  
  const uint32_t framebufferNumBytes = width * height * sizeof(uint32_t);

#ifdef DEBUG_PRINT_FRAME_DURATION
  printf("process_apng_frame(fbPtr, framei=%d, width=%d, height=%d, delta_x=%d, delta_y=%d, delta_width=%d, delta_height=%d, delay_num=%d, delay_den=%d, bpp=%d, ptr)\n",
         framei,
         width, height,
         delta_x, delta_y, delta_width, delta_height,
         delay_num, delay_den,
         bpp);
#endif

  if (framei == 0) {
    // Save width/height from initial frame
    userDataPtr->width = width;
    userDataPtr->height = height;
  }
  
  // The bpp value can only be 24 or 32 (alpha), but there is a possibility of a weird edge case when dealing with palette mode images.
  // It is possible that 1 or more frames could be reported as 24 BPP because only opaque pixels are used, but then later frames
  // are reported as 32 BPP with an alpha channel because palette entries with a transparency value were used. Deal with this edge
  // case by recording the largest BPP value reported for all frames. The result of this edge case is that we don't know if there
  // is an alpha channel until all the pixels in all the frames have been processed.
  
  if (bpp > userDataPtr->bpp) {
    userDataPtr->bpp = bpp;
  }
  
  // In the case where the first frame is hidden, this callback is not invoked for the first frame in the APNG file.
  
  // Query the delay between the previous frame and this one. If this value is longer than 1 frame
  // then no-op frames appear in between the two APNG frames.
  
  float delay = (float) delay_num / (float) delay_den;
  
  int numFramesDelay = round(delay / userDataPtr->frameDuration);
  assert(numFramesDelay >= 1);
  
#ifdef DEBUG_PRINT_FRAME_DURATION
  fprintf(stdout, "APNG frame index %d corresponds to MVID frame index %d\n", framei, userDataPtr->outFrame);
#endif
  
  // Get the frame that this APNG frame corresponds to
  
  MVFrame *mvFrame = &mvFramesArray[userDataPtr->outFrame++];
  
  // In the case where this frame is exactly the same as the previous frame, then delta_x, delta_y, delta_width, delta_height are all zero
  
  if (delta_x == 0 && delta_y == 0 && delta_width == 0 && delta_height == 0) {
    // The no-op delta case
    assert(userDataPtr->outFrame > 0);
    
    MVFrame *prevMvFrame = mvFrame - 1;
    
    maxvid_frame_setoffset(mvFrame, maxvid_frame_offset(prevMvFrame));
    maxvid_frame_setlength(mvFrame, maxvid_frame_length(prevMvFrame));
    maxvid_frame_setnopframe(mvFrame);
    
    if (maxvid_frame_iskeyframe(prevMvFrame)) {
      maxvid_frame_setkeyframe(mvFrame);
    }
    
    // Note that an adler is not generated for a no-op frame
    
  } else {
    
    // Each pixel in the framebuffer must be prepared before it can be passed to the CoreGraphics framebuffer.
    // ARGB must be pre-multiplied and converted to ABGR.
    
    if (userDataPtr->cgFrameBuffer == NULL) {
      userDataPtr->cgFrameBuffer = malloc(framebufferNumBytes);
      memset(userDataPtr->cgFrameBuffer, 0, framebufferNumBytes);
    }
    
    uint32_t count = width * height;
    uint32_t *inPtr = framebuffer;
    uint32_t *outPtr = userDataPtr->cgFrameBuffer;  
    if (bpp == 32) {
      do {
        *outPtr++ = argb_to_abgr_and_premultiply(*inPtr++);
      } while (--count != 0);
    } else {
      // 24 BPP : no need to premultiply since alpha is always 0xFF
      do {
        *outPtr++ = argb_to_abgr(*inPtr++);
      } while (--count != 0);    
    }    
    
    // Each frame is emitted as a keyframe
    
    uint32_t isKeyFrame = 1;
    
    long offset = ftell(maxvidOutFile);
    
    if (isKeyFrame) {
      offset = maxvid_file_padding_before_keyframe(maxvidOutFile, offset);
    }    
    
    maxvid_frame_setoffset(mvFrame, (uint32_t)offset);
    
    if (isKeyFrame) {
      maxvid_frame_setkeyframe(mvFrame);
    }    
    
    if (isKeyFrame) {
      // A keyframe is a special case where a zero-copy optimization can be used.
            
      uint32_t numWritten = fwrite(userDataPtr->cgFrameBuffer, framebufferNumBytes, 1, maxvidOutFile);
      if (numWritten != 1) {
        return WRITE_ERROR;
      }
      
      if (genAdler) {
        mvFrame->adler = maxvid_adler32(0, (unsigned char*)userDataPtr->cgFrameBuffer, framebufferNumBytes);
        assert(mvFrame->adler != 0);
      }
    } else {
      // Delta frames not generated currently
      assert(0);
    }
    
    // After data is written to the file, query the file position again to determine how many
    // words were written.
    
    uint32_t offsetBefore = (uint32_t)offset;
    offset = ftell(maxvidOutFile);
    uint32_t length = ((uint32_t)offset) - offsetBefore;
    
    // Typically, the framebuffer is an even number of pixels.
    // There is an odd case though, when emitting 16 bit pixels
    // is is possible that the total number of pixels written
    // is odd, so in this case the framebuffer is not a whole
    // number of words.
    
    if (isKeyFrame && (bpp == 16)) {
      assert((length % 2) == 0);
      if ((length % 4) != 0) {
        // Write a zero half-word to the file so that additional padding is in terms of whole words.
        uint16_t zeroHalfword = 0;
        size_t size = fwrite(&zeroHalfword, sizeof(zeroHalfword), 1, maxvidOutFile);
        assert(size == 1);
        offset = ftell(maxvidOutFile);
      }
    } else {
      assert((length % 4) == 0);
    }
    
    maxvid_frame_setlength(mvFrame, length);
    
    // In the case of a keyframe, zero pad up to the next page bound. Note that the "length"
    // of the frame data does not include the zero padding.
    
    if (isKeyFrame) {
      offset = maxvid_file_padding_after_keyframe(maxvidOutFile, offset);
    }      
  }
  
  // When the delay after the frame is longer than 1 frame, emit no-op frames
  
  if (numFramesDelay > 1) {
    assert(userDataPtr->outFrame > 0);
    
    for (int count = numFramesDelay; count > 1; count--) {
      MVFrame *mvFrame = &mvFramesArray[userDataPtr->outFrame];
      MVFrame *prevMvFrame = &mvFramesArray[userDataPtr->outFrame-1];
      
      maxvid_frame_setoffset(mvFrame, maxvid_frame_offset(prevMvFrame));
      maxvid_frame_setlength(mvFrame, maxvid_frame_length(prevMvFrame));
      maxvid_frame_setnopframe(mvFrame);
      
      if (maxvid_frame_iskeyframe(prevMvFrame)) {
        maxvid_frame_setkeyframe(mvFrame);
      }
      
      userDataPtr->outFrame++;
    }
  }
  
#ifdef DEBUG_PRINT_FRAME_DURATION
  fprintf(stdout, "frame delay after APNG frame %d is %d\n", framei, numFramesDelay);
#endif
  
  return 0;
}

// Exported API entry point, this method will convert a .apng file to a .mvid file in the tmp dir

uint32_t
apng_convert_maxvid_file(
               char *inAPNGPath,
               char *outMaxvidPath,
               uint32_t genAdler)
{
  // File and pointers that need to be cleaned up
  
  uint32_t retcode = 0;
  
  FILE *inAPNGFile = NULL;
  FILE *maxvidOutFile = NULL;
  
  MVFileHeader *mvHeader = NULL;
  MVFrame *mvFramesArray = NULL;
  
  LibapngUserData userData;
  memset(&userData, 0, sizeof(LibapngUserData));
  assert(userData.cgFrameBuffer == NULL);  
  
#undef RETCODE
#define RETCODE(status) \
if (status != 0) { \
retcode = status; \
goto retcode; \
}
  
  // These don't need to be cleaned up at function exit
  
  uint32_t numApngFrames;
  uint32_t numOutputFrames;
  uint32_t status;
  float frameDuration;
    
  init_alphaTables();
  
  // FIXME: test to check that filename ends with ".apng" wither here or in caller
  
  inAPNGFile = libapng_open(inAPNGPath);
	if (inAPNGFile == NULL) {
    RETCODE(UNSUPPORTED_FILE);
  }
	
  // Read header in PNG file and determine the framerate
  
  status = apng_decode_frame_duration(inAPNGFile, &frameDuration, &numOutputFrames, &numApngFrames);
  if (status != 0) {
    RETCODE(READ_ERROR);
  }
  
  // If fewer than animation frames, then it will not be possible to animate.
  // This could happen when there is only a single frame in a PNG file, for example.
  // It might also happen in a 2 frame .apng where the first frame is marked as hidden.
  
  if (numApngFrames < 2) {
    RETCODE(UNSUPPORTED_FILE);
  }
  
  // open output .mvid file as binary

	maxvidOutFile = fopen(outMaxvidPath, "wb");
	if (!maxvidOutFile) {
    RETCODE(WRITE_ERROR);
  }
  
  mvHeader = malloc(sizeof(MVFileHeader));
  memset(mvHeader, 0, sizeof(MVFileHeader));
  
  // FIXME: Don't know how many maxvid frames there will be until the animation frames
  // are iterated over. But, this assumes that we know the duration first. Need to figure
  // out how many mv frames there are in the util function.
  
  const uint32_t framesArrayNumBytes = sizeof(MVFrame) * numOutputFrames;
  mvFramesArray = malloc(framesArrayNumBytes);
  memset(mvFramesArray, 0, framesArrayNumBytes);  
  
  // Write header and frame info array in initial zeroed state. These data fields
  // don't become valid until the file has been completely written and then
  // the headers are rewritten.
  
  uint32_t numWritten;
  
  numWritten = fwrite(mvHeader, sizeof(MVFileHeader), 1, maxvidOutFile);
  if (numWritten != 1) {
    RETCODE(WRITE_ERROR);
  }
  
  numWritten = fwrite(mvFramesArray, framesArrayNumBytes, 1, maxvidOutFile);
  if (numWritten != 1) {
    RETCODE(WRITE_ERROR);
  }  

  // Init user data passed to libapng_main()
  
  userData.maxvidOutFile = maxvidOutFile;
  userData.mvFramesArray = mvFramesArray;
  userData.frameDuration = frameDuration;
  userData.genAdler = genAdler;
  
  // Invoke library interface to parse frames from .apng file and render to .mvid
  
  status = libapng_main(inAPNGFile, process_apng_frame, &userData);
  if (status != 0) {
    RETCODE(status);
  }
  
  // Rewrite the maxvid headers, once all frames have been emitted
  
  // Write .mvid headers again, now that info is up to date
  
  assert(userData.width);
  assert(userData.height);
  assert(userData.bpp);
  
  mvHeader->magic = 0; // magic still not valid
  mvHeader->width = userData.width;
  mvHeader->height = userData.height;
  mvHeader->bpp = userData.bpp;
  
  mvHeader->frameDuration = frameDuration;
  assert(mvHeader->frameDuration > 0.0);
  
  mvHeader->numFrames = numOutputFrames;
  
  (void)fseek(maxvidOutFile, 0L, SEEK_SET);
  
  numWritten = fwrite(mvHeader, sizeof(MVFileHeader), 1, maxvidOutFile);
  if (numWritten != 1) {
    RETCODE(WRITE_ERROR);
  }
  
  numWritten = fwrite(mvFramesArray, framesArrayNumBytes, 1, maxvidOutFile);
  if (numWritten != 1) {
    RETCODE(WRITE_ERROR);
  }  
  
  // Once all valid data and headers have been written, it is now safe to write the
  // file header magic number. This ensures that any threads reading the first word
  // of the file looking for a valid magic number will only ever get consistent
  // data in a read when a valid magic number is read.
  
  (void)fseek(maxvidOutFile, 0L, SEEK_SET);
  
  uint32_t magic = MV_FILE_MAGIC;
  status = fwrite_word(maxvidOutFile, magic);
  if (status) {
    RETCODE(WRITE_ERROR);
  }  
  
retcode:
  libapng_close(inAPNGFile);
  
  if (userData.cgFrameBuffer) {
    free(userData.cgFrameBuffer);
  }  
  
  if (maxvidOutFile) {
    fclose(maxvidOutFile);
  }
  
  if (mvHeader) {
    free(mvHeader);
  }
  if (mvFramesArray) {
    free(mvFramesArray);
  }  
  
	return retcode;
}

