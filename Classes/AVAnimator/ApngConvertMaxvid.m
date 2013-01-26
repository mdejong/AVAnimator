// apng convert to maxvid module
//
//  License terms defined in License.txt.
//
// This module defines logic that convert from an APNG to a memory mapped maxvid file.

#import "ApngConvertMaxvid.h"

#import "movdata.h"

#include "maxvid_decode.h"
#include "maxvid_encode.h"
#include "maxvid_file.h"

#include "libapng.h"

#import "AVMvidFileWriter.h"

#pragma clang diagnostic ignored "-Wmissing-prototypes"

typedef struct {
  AVMvidFileWriter *avMvidFileWriter;
  uint32_t bpp;
  uint32_t *cgFrameBuffer;
} LibapngUserData;

// Read a big endian uint32_t from a char* and store in result (ARGB).
// Each pixel needs to be multiplied by the alpha channel value.
// Optimized premultiplication implementation using table lookups

// Input is a ARGB (non-premultiplied) pixel.
// Output is a ABGR (premultiplied) pixel for CoreGraphics bitmap.
//
// Note that extern_alphaTablesPtr is defined in movdata.h

static inline
uint32_t argb_to_abgr_and_premultiply(uint32_t pixel)
{
  uint32_t alpha = (pixel >> 24) & 0xFF;
  uint32_t red = (pixel >> 16) & 0xFF;
  uint32_t green = (pixel >> 8) & 0xFF;
  uint32_t blue = (pixel >> 0) & 0xFF;
  
  const uint8_t* const restrict alphaTable = &extern_alphaTablesPtr[alpha * PREMULT_TABLEMAX];
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
#define MALLOC_ERROR 4

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
        RETCODE(READ_ERROR);
      }

      float frameDuration = libapng_frame_delay(fcTLChunk.delay_num, fcTLChunk.delay_den);
      
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
#ifdef DEBUG_PRINT_FRAME_DURATION
      fprintf(stdout, "frameDurations[%d] = %f\n", (apngNumFrames-1), frameDurations[apngNumFrames-1]);
#endif
      
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
  
  if (apngNumFrames < 2) {
    RETCODE(UNSUPPORTED_FILE);
  }
  
  for (int i=0; i < apngNumFrames; i++) {
    float duration = frameDurations[i];
    
    int numFramesDelay = round(duration / smallestFrameDuration);
    if (numFramesDelay < 1) {
      assert(numFramesDelay >= 1);
    }
    
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
  
  AVMvidFileWriter *aVMvidFileWriter = userDataPtr->avMvidFileWriter;
  
  uint32_t framebufferNumBytes;
  
  if (((width * height) % 2) == 0) {
    // Even number of pixels in framebuffer
    framebufferNumBytes = width * height * sizeof(uint32_t);
  } else {
    // Odd number of pixels in framebuffer, include one more pixel
    // of padding and make sure it is initialized to zero.
    framebufferNumBytes = (width * height) + 1;
    assert((framebufferNumBytes % 2) == 0);
    framebufferNumBytes *= sizeof(uint32_t);
  }

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
    
    CGSize size = CGSizeMake(width, height);
    aVMvidFileWriter.movieSize = size;
  } else {
    CGSize size = aVMvidFileWriter.movieSize;
    CGSize currentSize = CGSizeMake(width, height);
    assert(CGSizeEqualToSize(size, currentSize));
  }
  
  // The bpp value can only be 24 or 32 (alpha), but there is a possibility of a weird edge case when dealing with palette mode images.
  // It is possible that 1 or more frames could be reported as 24 BPP because only opaque pixels are used, but then later frames
  // are reported as 32 BPP with an alpha channel because palette entries with a transparency value were used. Deal with this edge
  // case by recording the largest BPP value reported for all frames. The result of this edge case is that we don't know if there
  // is an alpha channel until all the pixels in all the frames have been processed.
  
  assert(bpp == 24 || bpp == 32);
  
  if (bpp > userDataPtr->bpp) {
    userDataPtr->bpp = bpp;
  }
  
  // In the case where the first frame is hidden, this callback is not invoked for the first frame in the APNG file.
  
  // Query the delay between the previous frame and this one. If this value is longer than 1 frame
  // then no-op frames appear in between the two APNG frames.
  
  float frameDisplayTime = libapng_frame_delay(delay_num, delay_den);
  
#ifdef DEBUG_PRINT_FRAME_DURATION
  fprintf(stdout, "APNG frame index %d corresponds to MVID frame index %d\n", framei, aVMvidFileWriter.frameNum);
#endif
  
  // In the case where this frame is exactly the same as the previous frame, then delta_x, delta_y, delta_width, delta_height are all zero
  
  if (delta_x == 0 && delta_y == 0 && delta_width == 0 && delta_height == 0) {
    // The no-op delta case

    [aVMvidFileWriter writeNopFrame];
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
    
    // FIXME: unclear what to do with .apng data that is not in the sRGB colorspace
    // when running under iOS. We do not know what colorspace the input RGB values
    // are in, and the system does not support color profiles. Logic might need to
    // require that input pixels be in sRGB colorspace or else fail to load on iOS.
    
    // Each frame is emitted as a keyframe
    
    BOOL worked = [aVMvidFileWriter writeKeyframe:(char*)userDataPtr->cgFrameBuffer bufferSize:framebufferNumBytes];
    
    if (worked == FALSE) {
      return WRITE_ERROR;
    }
  }
  
  // When the delay after the frame is longer than 1 frame, emit trailing nop frames
  
#ifdef DEBUG_PRINT_FRAME_DURATION
  int numFramesDelay = round(frameDisplayTime / aVMvidFileWriter.frameDuration);
  fprintf(stdout, "frame delay after APNG frame %d is %d\n", framei, numFramesDelay);
#endif
  
  [aVMvidFileWriter writeTrailingNopFrames:frameDisplayTime];
    
  return 0;
}

// Exported C API entry point, this method will convert a .apng file to a .mvid file in the tmp dir

uint32_t
apng_convert_maxvid_file(
               char *inAPNGPath,
               char *outMaxvidPath,
               uint32_t genAdler)
{
  NSString *inAPNGPathStr = [NSString stringWithFormat:@"%s", inAPNGPath];
  NSString *outMaxvidPathStr = [NSString stringWithFormat:@"%s", outMaxvidPath];
  BOOL genAdlerBool = (genAdler != 0);
  
  return [ApngConvertMaxvid convertToMaxvid:inAPNGPathStr outMaxvidPath:outMaxvidPathStr genAdler:genAdlerBool];
}

// This method tests a local file to determine if it is an APNG with multiple frames. It is possible that
// a regular non-animated .png file would be downloaded. This is a design flaw in the APNG design, but
// basically we need to work around it by scanning the contents of the .png to see if it is in fact animated.
// This method will return 0 if the file is in fact an animated PNG, otherwise a non-zero result indicates
// that the file can't be parsed as an APNG.

uint32_t
apng_verify_png_is_animated(char *inAPNGPath)
{
  FILE *inAPNGFile = NULL;
  uint32_t retcode = 1000;
  
  uint32_t numApngFrames;
  uint32_t numOutputFrames;
  uint32_t status;
  float frameDuration;  
  
#undef RETCODE
#define RETCODE(status) \
if (status != 0) { \
retcode = status; \
goto retcode; \
}  
  
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
 
  retcode = 0;
  
retcode:
  libapng_close(inAPNGFile);
  
  return retcode;
}

// ApngConvertMaxvid

@implementation ApngConvertMaxvid

+ (uint32_t) convertToMaxvid:(NSString*)inAPNGPath
               outMaxvidPath:(NSString*)outMaxvidPath
                    genAdler:(BOOL)genAdler
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  
  uint32_t retcode = 0;
  
  FILE *inAPNGFile = NULL;
  
  AVMvidFileWriter *aVMvidFileWriter = nil;
  
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
  
  premultiply_init();
  
  // FIXME: test to check that filename ends with ".apng" wither here or in caller
  
  char *inAPNGPathCstr = (char*) [inAPNGPath UTF8String];
  
  inAPNGFile = libapng_open(inAPNGPathCstr);
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
  
  // Create .mvid file writer utility object
  
  aVMvidFileWriter = [AVMvidFileWriter aVMvidFileWriter];
  
  aVMvidFileWriter.mvidPath = outMaxvidPath;
  aVMvidFileWriter.frameDuration = frameDuration;
  aVMvidFileWriter.totalNumFrames = numOutputFrames;
  aVMvidFileWriter.genAdler = genAdler;
  
  BOOL worked = [aVMvidFileWriter open];
  
	if (worked == FALSE) {
    RETCODE(WRITE_ERROR);
  }
  
  // Init user data passed to libapng_main()
  
  userData.avMvidFileWriter = aVMvidFileWriter;
  
  // Invoke library interface to parse frames from .apng file and render to .mvid
  
  status = libapng_main(inAPNGFile, process_apng_frame, &userData);
  if (status != 0) {
    RETCODE(status);
  }
  
  // Write .mvid header again, now that info is up to date
  
  aVMvidFileWriter.bpp = userData.bpp;
  
  worked = [aVMvidFileWriter rewriteHeader];
  
	if (worked == FALSE) {
    RETCODE(WRITE_ERROR);
  }
  
retcode:
  libapng_close(inAPNGFile);
  
  if (userData.cgFrameBuffer) {
    free(userData.cgFrameBuffer);
  }
  
  [aVMvidFileWriter close];
  
  [pool drain];
  
	return retcode;
}

@end
