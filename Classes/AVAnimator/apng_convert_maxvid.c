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

#include "png.h"

// Read a big endian uint32_t from a char* and store in result (ARGB).
// Each pixel needs to be multiplied by the alpha channel value.
// Optimized premultiplication implementation using table lookups

#define TABLEMAX 256
//#define TABLEDUMP

static
uint8_t alphaTables[TABLEMAX*TABLEMAX];
static
int alphaTablesInitialized = 0;

static inline
uint32_t PREMULTIPLY_UTIL(uint32_t pixel) 
{
  // Input : ARGB (non-premultiplied)
  // Output : ARGB (premultiplied)

  uint32_t alpha = (pixel >> 24) & 0xFF;
  uint32_t red = (pixel >> 16) & 0xFF;
  uint32_t green = (pixel >> 8) & 0xFF;
  uint32_t blue = (pixel >> 0) & 0xFF;
  
  uint8_t * restrict alphaTable = &alphaTables[alpha * TABLEMAX];
  return (alpha << 24) | (alphaTable[red] << 16) | (alphaTable[green] << 8) | alphaTable[blue];
}

#define PREMULTIPLY(result, pixel) result = PREMULTIPLY_UTIL(pixel)

//#define TO_RGBA(red, green, blue, alpha) ((red << 24)|  (green << 16) | (blue << 8) | alpha)

#define TO_ARGB(red, green, blue, alpha) ((alpha << 24)|  (red << 16) | (green << 8) | blue)

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
      PREMULTIPLY(premult_pixel_le, pixel);
      
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
      uint32_t expected_pixel_le = TO_ARGB(round_red, round_green, round_blue, round_alpha);
                                          
      if (premult_pixel_le != expected_pixel_le) {
        uint8_t premult_pixel_alpha = (premult_pixel_le >> 24) & 0xFF;
        uint8_t premult_pixel_red = (premult_pixel_le >> 16) & 0xFF;
        uint8_t premult_pixel_green = (premult_pixel_le >> 8) & 0xFF;
        uint8_t premult_pixel_blue = (premult_pixel_le >> 0) & 0xFF;
        
        uint8_t rounded_pixel_alpha = (expected_pixel_le >> 24) & 0xFF;
        uint8_t rounded_pixel_red = (expected_pixel_le >> 16) & 0xFF;
        uint8_t rounded_pixel_green = (expected_pixel_le >> 8) & 0xFF;
        uint8_t rounded_pixel_blue = (expected_pixel_le >> 0) & 0xFF;        
        
        assert(premult_pixel_alpha == rounded_pixel_alpha);
        assert(premult_pixel_red == rounded_pixel_red);
        assert(premult_pixel_green == rounded_pixel_green);
        assert(premult_pixel_blue == rounded_pixel_blue);
        
        assert(premult_pixel_le == expected_pixel_le);
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

uint32_t
apng_decode_frame_duration(
                           FILE *fp,
                           float *outFrameDurationPtr,
                           uint32_t *numMaxvidFramesPtr,
                           uint32_t *numApngFramesPtr)
{
  uint32_t len, chunk, crc;
  uint32_t retcode = 1000;
  uint32_t status;
  
  uint32_t apngNumFrames = 0;
  uint32_t mvidNumFrames = 0;
  //char chunkNameBuffer[4+1];
  
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
  
  //printf("Reading APNG chunks...\n");
  status = fseek(fp, 0, SEEK_END);
  if (status != 0) {
    RETCODE(READ_ERROR);
  }
  uint32_t endOffset = ftell(fp);
  //printf("file length %d\n", (int)ftell(fp));
  
  // Seek past PNG signature
  
  status = fseek(fp, 8, SEEK_SET);
  if (status != 0) {
    RETCODE(READ_ERROR);
  }
    
  do {
    // LENGTH
    
    //fprintf(stdout, "offet %d : before chunk read : eof %d\n", (int)ftell(fp), feof(fp));
    
    if (fread_word(fp, &len)) {
      RETCODE(READ_ERROR);
    }
    
    // CHUNK TYPE
    
    if (fread_word(fp, &chunk)) {
      RETCODE(READ_ERROR);
    }
    
    //apng_decode_chunk_name(chunk, chunkNameBuffer);
    //fprintf(stdout, "offet %d : chunk 0x%X \"%s\" : len %d\n", (int)ftell(fp), chunk, chunkNameBuffer, len);
        
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
      
      //fprintf(stdout, "frameDuration (%d) = %f\n", fcTLChunk.sequence_number, frameDuration);
      
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

  // Iterate over each frame delay in the apng file and determine how many mvid frames this is
  
  assert(apngNumFrames > 0);
  
  for (int i=0; i < apngNumFrames; i++) {
    float duration = frameDurations[i];
    
    int numFramesDelay = round(duration / smallestFrameDuration);
    assert(numFramesDelay >= 1);
    
    mvidNumFrames++;
    
    if (numFramesDelay > 1) {
      mvidNumFrames += (numFramesDelay - 1);
    }
  }
  
  *outFrameDurationPtr = smallestFrameDuration;  
  *numMaxvidFramesPtr = mvidNumFrames;
  *numApngFramesPtr = apngNumFrames;
  
  retcode = 0;
  
retcode:
  
  if (frameDurations) {
    free(frameDurations);
  }
  
  return retcode;
}

uint32_t
apng_convert_maxvid_file(
                         char *inAPNGPath,
                         char *outMaxvidPath,
                         uint32_t genAdler)
{
  // File and pointers that need to be cleaned up
  
  png_byte* pixels = NULL;
	png_byte** row_ptrs = NULL;
  FILE *fp = NULL;
  FILE *maxvidOutFile = NULL;
  uint32_t retcode = 0;
  
  MVFileHeader *mvHeader = NULL;
  MVFrame *mvFramesArray = NULL;  
  
	png_structp *pngReadStructPtr = NULL;
  
#undef RETCODE
#define RETCODE(status) \
if (status != 0) { \
retcode = status; \
goto retcode; \
}

  // These don't need to be cleaned up at function exit
  
  png_uint_32 width;
  png_uint_32 height;
  uint32_t numApngFrames;
  uint32_t numMaxvidFrames;
  uint32_t status;
  float frameDuration;
  uint32_t bpp;
  uint32_t frameBufferNumBytes;
  uint32_t *frameBuffer;
  
  init_alphaTables();
  
	// header for testing if it is a png
	png_byte header[8];
	
  // FIXME: test to check that filename ends with ".apng" wither here or in caller
  
	// open file as binary
	fp = fopen(inAPNGPath, "rb");
	if (!fp) {
    RETCODE(UNSUPPORTED_FILE);
  }
	
	// read the header
	fread(header, 1, 8, fp);
	
	// test if png
	int is_png = !png_sig_cmp(header, 0, 8);
	if (!is_png) {
    RETCODE(UNSUPPORTED_FILE);
  }
	
  // Read header in PNG file and determine the framerate
  
  status = apng_decode_frame_duration(fp, &frameDuration, &numMaxvidFrames, &numApngFrames);
  if (status != 0) {
    RETCODE(READ_ERROR);
  }
  
  // If fewer than animation frames, then it will not be possible to animate.
  // This could happen when there is only a single frame in a PNG file, for example.
  // It might also happen in a 2 frame .apng where the first frame is marked as hidden.
  
  if (numApngFrames < 2) {
    RETCODE(UNSUPPORTED_FILE);
  }
  
  fseek(fp, 8, SEEK_SET);
  
  // Setup mvid file
  
  // open output file as binary
	maxvidOutFile = fopen(outMaxvidPath, "wb");
	if (!maxvidOutFile) {
    RETCODE(WRITE_ERROR);
  }
  
  mvHeader = malloc(sizeof(MVFileHeader));
  memset(mvHeader, 0, sizeof(MVFileHeader));
  
  // FIXME: Don't know how many maxvid frames there will be until the animation frames
  // are iterated over. But, this assumes that we know the duration first. Need to figure
  // out how many mv frames there are in the util function.
  
  const uint32_t framesArrayNumBytes = sizeof(MVFrame) * numMaxvidFrames;
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
  
	// create png struct
  
	png_structp png_ptr = png_create_read_struct(PNG_LIBPNG_VER_STRING, NULL, NULL, NULL);
	if (!png_ptr) {
    RETCODE(READ_ERROR);
  }
  pngReadStructPtr = &png_ptr;
	
	// create png info struct
	png_infop info_ptr = png_create_info_struct(png_ptr);
	if (!info_ptr) {
    RETCODE(READ_ERROR);
	}
	
	// create png info struct
	png_infop end_info = png_create_info_struct(png_ptr);
	if (!end_info) {
    RETCODE(READ_ERROR);
	}
	
	// png error stuff, not sure libpng man suggests this.
	if (setjmp(png_jmpbuf(png_ptr))) {
    RETCODE(READ_ERROR);
  }
	
	// init png reading
	png_init_io(png_ptr, fp);
	
	// let libpng know you already read the first 8 bytes
	png_set_sig_bytes(png_ptr, 8);
	
	// read all the info up to the image data
	png_read_info(png_ptr, info_ptr);
	
  // Must be .apng file, regular PNG images contain only 1 frame, they can't be animated.
  
	if(!png_get_valid(png_ptr, info_ptr, PNG_INFO_acTL)) {
    RETCODE(UNSUPPORTED_FILE);
  }
	
	// variables to pass to get info
	int bit_depth, color_type;
	
	bit_depth = png_get_bit_depth(png_ptr, info_ptr);
	color_type = png_get_color_type(png_ptr, info_ptr);
  
  // Expand color table values to RGB
	if( color_type == PNG_COLOR_TYPE_PALETTE ) {
		png_set_palette_to_rgb( png_ptr );
  }
  // Transparency represented as alpha
	if( png_get_valid( png_ptr, info_ptr, PNG_INFO_tRNS ) ) {
		png_set_tRNS_to_alpha (png_ptr);
  }
  // Reduce 16 bit samples to 8 bit samples (48 bit RGB) -> (24 bit RGB)
	if( bit_depth == 16 ) {
		png_set_strip_16( png_ptr );
  }
  // Expand samples less than 8 bits to 8 bits.
	else if( bit_depth < 8 ) {
		png_set_packing( png_ptr );
  }
  // Convert greyscale to RGB
  if (color_type == PNG_COLOR_TYPE_GRAY ||
      color_type == PNG_COLOR_TYPE_GRAY_ALPHA) {
    png_set_gray_to_rgb(png_ptr);
  }
  // Emit RGBA for RGB values with no alpha channel
  if (color_type == PNG_COLOR_TYPE_RGB ||
      color_type == PNG_COLOR_TYPE_GRAY) {
    png_uint_32 filler = 0xFF;
    png_set_add_alpha(png_ptr, filler, PNG_FILLER_AFTER);
  }

  // If no alpha or trns is used, don't bother with premultiply and set header properly.
  // Note that this depend on the actual data stored in the apng file, if none of
  // the pixels are transparent then this logic will emit a 24 bpp mvid file.
  
  // FIXME: unclear if this covers conversion with alpha, like with a table that maps to a trns 
  
  if (color_type & PNG_COLOR_MASK_ALPHA) {
    bpp = 32;
  } else {
    bpp = 24;
  }
  
  /*
   Color    Allowed    Interpretation
   Type    Bit Depths
   
   0       1,2,4,8,16  Each pixel is a grayscale sample.
   
   2       8,16        Each pixel is an R,G,B triple.
   
   3       1,2,4,8     Each pixel is a palette index; a PLTE chunk must appear.
   
   4       8,16        Each pixel is a grayscale sample, followed by an alpha sample.
   
   6       8,16        Each pixel is an R,G,B triple, followed by an alpha sample.   
   */
  
  // Swap B and R, so that pixel format written by libpng is ARGB
  png_set_bgr(png_ptr);
  
	png_read_update_info(png_ptr, info_ptr);
	
	// get info about png
	png_get_IHDR(png_ptr, info_ptr, &width, &height, &bit_depth, &color_type,
               NULL, NULL, NULL);
	
	int bits;
	switch (color_type)
	{
		case PNG_COLOR_TYPE_GRAY:
      assert(0); // greyscale should be converted to RGB
			bits = 1;
			break;
			
		case PNG_COLOR_TYPE_GRAY_ALPHA:
      assert(0); // greyscale should be converted to RGBA
			bits = 2;
			break;
			
		case PNG_COLOR_TYPE_RGB:
      assert(0); // RGB should be converted to RGBA
			bits = 3;
			break;
			
		case PNG_COLOR_TYPE_RGB_ALPHA:
			bits = 4;
			break;
      
    default:
      assert(0); // greyscale should be converted to RGBA      
	}
  
  // Allocated framebuffer

  frameBufferNumBytes = width * height * bits;
  pixels = (png_byte*)calloc(width * height * bits, sizeof(png_byte));
  assert(pixels);
  frameBuffer = (uint32_t*)pixels;
	row_ptrs = (png_byte**)malloc(height * sizeof(png_bytep));
  assert(row_ptrs);
  
  int i;
	for (i=0; i<height; i++) {
		row_ptrs[i] = pixels + i*width*bits;
  }
  
  uint32_t firstFrameIsHidden = 0;
  uint32_t numCombinedApngFrames = png_get_num_frames(png_ptr, info_ptr);
  if (numApngFrames == (numCombinedApngFrames - 1)) {
    // The first frame is hidden, it is not animated.
    firstFrameIsHidden = 1;
  } else {
    assert(numApngFrames == numCombinedApngFrames);    
  }
  
  fprintf(stdout, "frameDuration = %f\n", frameDuration);
  
  // Once the framerate is know, each frame delay can be defined in terms of the framerate.
  // Decode the data for each frame, convert to mvid frames, and then write one frame at a time.
  
  int mvFramei = 0;
  
  uint32_t singlePixel = 0;
  uint32_t couldBeNoOpSinglePixel = 0;
  
	for (int framei = 0; framei < numCombinedApngFrames; framei++)
  {
		png_uint_32 next_frame_width, next_frame_height, next_frame_x_offset, next_frame_y_offset;
		png_uint_16 next_frame_delay_num, next_frame_delay_den;
		png_byte next_frame_dispose_op, next_frame_blend_op;
		
    png_read_frame_head(png_ptr, info_ptr);
    
    if (png_get_valid(png_ptr, info_ptr, PNG_INFO_fcTL))
    {
      if (framei == 0) {
        assert(firstFrameIsHidden == 0);
      }
      
      png_get_next_frame_fcTL(png_ptr, info_ptr, 
                              &next_frame_width, &next_frame_height, &next_frame_x_offset, &next_frame_y_offset,
                              &next_frame_delay_num, &next_frame_delay_den, &next_frame_dispose_op,
                              &next_frame_blend_op);
      
      fprintf(stdout, "fcTL frame : x,y %d,%d : w/h %d/%d\n", next_frame_x_offset, next_frame_y_offset,
              next_frame_width, next_frame_height);
      
      if (next_frame_x_offset == 0 && next_frame_y_offset == 0 && next_frame_width == 1 && next_frame_height == 1) {
        // Special case of a 1x1 frame at the origin. apngopt will write a frame like this when there is no change
        // from one frame to the next. Check for the edge case of an actual 1x1 image that does change, before
        // emitting a no-op.

        couldBeNoOpSinglePixel = 1;
        singlePixel = frameBuffer[0];
      } else {
        couldBeNoOpSinglePixel = 0;
      }
    }
    else
    {
      // the first frame doesn't have an fcTL so it must be a hidden frame. Note that the data
      // is extracted to the framebuffer, but the next frame should also be a keyframe so the
      // data for this frame will not be used.
      
      assert(framei == 0);
      assert(firstFrameIsHidden == 1);
      
      next_frame_width = png_get_image_width(png_ptr, info_ptr);
      next_frame_height = png_get_image_height(png_ptr, info_ptr);
    }
		
		png_read_image(png_ptr, row_ptrs);
		
    // Don't emit a mvid frame for a hidden initial frame. The hidden frame has no delay info.
    
    if (framei == 0 && firstFrameIsHidden) {
      continue;
    }
    
    // Query the delay between the previous frame and this one. If this value is longer than 1 frame
    // then no-op frames appear in between the two APNG frames.
    
    float delay = (float) next_frame_delay_num / (float) next_frame_delay_den;
    
    int numFramesDelay = round(delay / frameDuration);
    assert(numFramesDelay >= 1);
    
    fprintf(stdout, "APNG frame %d corresponds to MVID frame %d\n", framei, mvFramei);
    
    // Get the frame that this APNG frame corresponds to
    
    MVFrame *mvFrame = &mvFramesArray[mvFramei++];
    
    if (couldBeNoOpSinglePixel) {
      if (singlePixel == frameBuffer[0]) {
        // The no-op case
      } else {
        // First pixel is not the same, treat as a keyframe
        couldBeNoOpSinglePixel = 0;
      }
    }
    
    if (couldBeNoOpSinglePixel) {
      // The no-op case
      
      MVFrame *prevMvFrame = mvFrame - 1;
      
      maxvid_frame_setoffset(mvFrame, maxvid_frame_offset(prevMvFrame));
      maxvid_frame_setlength(mvFrame, maxvid_frame_length(prevMvFrame));
      maxvid_frame_setnopframe(mvFrame);
      
      if (maxvid_frame_iskeyframe(prevMvFrame)) {
        maxvid_frame_setkeyframe(mvFrame);
      }
    } else {
      
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
        
        if (bpp == 32) {
          // If 32 bpp pixels have an alpha value other than 1.0, premultiply pixels before writing to .mvid file
          
          uint32_t count = width * height;
          uint32_t *pixelPtr = frameBuffer + count - 1;
          do {
            uint32_t pixel = *pixelPtr;
            uint32_t result;
            PREMULTIPLY(result, pixel);
            *pixelPtr = result;
            pixelPtr--;
          } while (--count != 0);
        }
        
        uint32_t numWritten = fwrite(frameBuffer, frameBufferNumBytes, 1, maxvidOutFile);
        if (numWritten != 1) {
          RETCODE(WRITE_ERROR);
        }
        
        if (genAdler) {
          mvFrame->adler = maxvid_adler32(0, (unsigned char*)frameBuffer, frameBufferNumBytes);
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
      assert(mvFramei > 0);
      
      for (int count = numFramesDelay; count > 1; count--) {
        MVFrame *mvFrame = &mvFramesArray[mvFramei];
        MVFrame *prevMvFrame = &mvFramesArray[mvFramei-1];
        
        maxvid_frame_setoffset(mvFrame, maxvid_frame_offset(prevMvFrame));
        maxvid_frame_setlength(mvFrame, maxvid_frame_length(prevMvFrame));
        maxvid_frame_setnopframe(mvFrame);
        
        if (maxvid_frame_iskeyframe(prevMvFrame)) {
          maxvid_frame_setkeyframe(mvFrame);
        }
        
        mvFramei++;
      }
    }
    
    fprintf(stdout, "frame delay after APNG frame %d is %d\n", framei, numFramesDelay);    
	}
	
	png_read_end(png_ptr, NULL);
  
  // Write .mvid headers again, now that info is up to date
  
  mvHeader->magic = 0; // magic still not valid
  mvHeader->width = width;
  mvHeader->height = height;
  mvHeader->bpp = bpp;
  
  mvHeader->frameDuration = frameDuration;
  assert(mvHeader->frameDuration > 0.0);
  
  mvHeader->numFrames = numMaxvidFrames;
  
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
  if (fp) {
    fclose(fp);
  }
  if (maxvidOutFile) {
    fclose(maxvidOutFile);
  }  
  if (row_ptrs) {
    free(row_ptrs);
  }
  if (pixels) {
    free(pixels);
  }
  if (mvHeader) {
    free(mvHeader);
  }
  if (mvFramesArray) {
    free(mvFramesArray);
  }
  if (pngReadStructPtr) {
    png_destroy_read_struct(&png_ptr, (png_infopp) NULL, (png_infopp) NULL);
  }
	return retcode;
}
