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

#include "movdata.h"

// Chunks of data contain 1 to N samples and are stored in mdat.
// The chunk contains an array of sample pointers and the
// offset in the file where the chunk begins.

typedef struct MovChunk {
  uint32_t numSamples;
  MovSample **samples;
  uint32_t offset;
} MovChunk;

// The chunk table can't be processed until after the
// total number of chunks is known. Save it until
// after the chunk offset list has been processed.

typedef struct SampleToChunkTableEntry {
  uint32_t first_chunk_id, samples_per_chunk;
} SampleToChunkTableEntry;


static inline
void movchunk_init(MovChunk *movChunk) {
  bzero(movChunk, sizeof(MovChunk));
}

static inline
void movchunk_free(MovChunk *movChunk) {
  if (movChunk->samples) {
    free(movChunk->samples);
  }
  bzero(movChunk, sizeof(MovChunk));
}

static
inline
void movsample_setkeyframe(MovSample *movSample) {
  movSample->lengthAndFlags |= (0x1 << 24);
}

void movdata_init(MovData *movData) {
  bzero(movData, sizeof(MovData));
}

void movdata_free(MovData *movData) {
  if (movData->frames) {
    free(movData->frames);
  }
  if (movData->samples) {
    free(movData->samples);
  }
  bzero(movData, sizeof(MovData));
}

// errCode values
#define ERR_READ 1
#define ERR_UNSUPPORTED_64BIT_FIELD 2
#define ERR_INVALID_FIELD 3
#define ERR_MALLOC_FAILED 4

typedef struct Atom {
  uint32_t asize;
  uint32_t atype;
} Atom;

typedef struct DataRefTableEntry
{
  uint32_t size;
  uint32_t type;
  uint8_t version;
  uint32_t flags;
  uint32_t data_offset;
  uint32_t data_size;
} DataRefTableEntry;

static inline char *
moviedata_fcc_tostring(MovData *movData, int i)
{
  movData->fccbuffer[0] = ((char) (i & 0xFF)),
  movData->fccbuffer[1] = ((char) ((i >> 8) & 0xFF)),
  movData->fccbuffer[2] = ((char) ((i >> 16) & 0xFF)),
  movData->fccbuffer[3] = ((char) ((i >> 24) & 0xFF)),
  movData->fccbuffer[4] = '\0';
  return movData->fccbuffer;  
}

static inline int
fcc_toint(char a, char b, char c, char d)
{
  return ((a) | ((b) << 8) | ((c) << 16) | ((d) << 24));
}

// read an unsigned 32 bit number in big endian format, returns 0 on success.

static inline int
read_be_uint32(FILE *fp, uint32_t *ptr)
{
  uint32_t lv;
  if (fread(&lv, sizeof(lv), 1, fp) != 1) {
    return 1;
  }
  *ptr = ntohl(lv);
  return 0;
}

// read an unsigned 16 bit number in big endian format, returns 0 on success.

static inline int
read_be_int16(FILE *fp, int16_t *ptr)
{
  int16_t lv;
  if (fread(&lv, sizeof(lv), 1, fp) != 1) {
    return 1;
  }
  *ptr = ntohs(lv);
  return 0;
}

// read an unsigned 32 bit number, returns 0 on success.

static inline int
read_uint32(FILE *fp, uint32_t *ptr)
{
  uint32_t lv;
  if (fread(&lv, sizeof(lv), 1, fp) != 1) {
    return 1;
  }
  *ptr = lv;
  return 0;
}

// read a quicktime floating point format number, returns 0 on success

static inline int
read_fixed32(FILE *fp, float *ptr)
{
  char bytes[4];
  uint8_t b1, b2, b3, b4;
  uint32_t r1, r2;
  
  if (fread(bytes, sizeof(bytes), 1, fp) != 1) {
    return 1;
  }
  b1 = bytes[0];
  b2 = bytes[1];
  b3 = bytes[2];
  b4 = bytes[3];
  
  r1 = (b1 << 8) | b2;
  r2 = (b3 << 8) | b4;
  
  if (r2 == 0) {
    *ptr = r1;    
  } else {
    *ptr = b1 + (b2 / 65536.0);
  }
  
  return 0;
}

static
void init_alphaTables();

// recurse into atoms and process them. Return 0 on success
// otherwise non-zero to indicate an error.

int
process_atoms(FILE *movFile, MovData *movData, uint32_t maxOffset)
{
  init_alphaTables();
  
  // first 4 bytes indicate the size of the atom
  
  Atom atom;
  int seek_status;
  
  while (1) {
    uint32_t atomOffset = ftell(movFile);
    
    if (atomOffset >= maxOffset || feof(movFile)) {
      // Done reading from atom at this point
      break;
    }
    
#ifdef DUMP_WHILE_PARSING
    fprintf(stdout, "read atom at byte %d\n", (int) atomOffset);
#endif
    
    if (read_be_uint32(movFile, &atom.asize) != 0) {
      movData->errCode = ERR_READ;
      snprintf(movData->errMsg, sizeof(movData->errMsg), "read error for atom size");
      return 1;
    }
    if (atom.asize == 0x00000001) {
      movData->errCode = ERR_UNSUPPORTED_64BIT_FIELD;
      snprintf(movData->errMsg, sizeof(movData->errMsg), "64 bit atoms not supported");
      return 1;
    }
    // an atom with zero size means the atom extends to the end
    // of the file.
    if (atom.asize == 0) {
      break;
    }
    uint32_t atomMaxOffset = atomOffset + atom.asize;
    // If the atom size is larger than the file size, then
    // this can't be a valid quicktime file.
    if (atomMaxOffset > maxOffset) {
      movData->errCode = ERR_INVALID_FIELD;
      snprintf(movData->errMsg, sizeof(movData->errMsg),
               "invalid atom size not supported (%d + %d) > %d",
               (int)atomOffset, (int)atom.asize, (int)maxOffset);
      return 1;
    }
    
    // Read the "type" as a series of bytes, not a big endian number!
    
    if (read_uint32(movFile, &atom.atype) != 0) {
      movData->errCode = ERR_READ;
      snprintf(movData->errMsg, sizeof(movData->errMsg), "read error for atom type");
      return 1;
    }
    
    // FIXME: Read the data for this specific Atom with one read operation, then parse
    // using the data in the pointer. This is easier than doing feek type operations
    // each time? Also, less can go wrong since IO handling is in one place. Note, that
    // this read should not be done for a mdat atom because it is really large! Might
    // also be good to just memory map the entire file at the start, and then use
    // a pointer into that memory instead of messing about with specific reads and such.
    
#ifdef DUMP_WHILE_PARSING
    fprintf(stdout, "type \"%s\", size %d\n", moviedata_fcc_tostring(movData, atom.atype), atom.asize);
#endif
    if (atom.atype == fcc_toint('s', 't', 'b', 'l')) {
      atom.asize = -(-atom.asize);
    }
    
    if (atom.atype == fcc_toint('f', 't', 'y', 'p')) {
      // FILE TYPE : http://ftyps.com/
      // Major Brand (ftyp code)
      // Major Brand version
      // Compatible Brand (ftyp code)
      // Compatible Brand 2...N
      
      uint32_t brand;
      
      if (read_uint32(movFile, &brand) != 0) {
        movData->errCode = ERR_READ;
        snprintf(movData->errMsg, sizeof(movData->errMsg), "read error for atom ftyp brand");
        return 1;
      }
      
#ifdef DUMP_WHILE_PARSING
      fprintf(stdout, "ftyp brand \"%s\"\n", moviedata_fcc_tostring(movData, brand));
#endif
      
      // FIXME: Fail to load if this does not match "qt  " ???
    } else if (atom.atype == fcc_toint('m', 'd', 'a', 't')) {
      // Movie Data container : mdat
      
      if (movData->foundMDAT) {
        // Only a single mdat is supported
        movData->errCode = ERR_INVALID_FIELD;
        snprintf(movData->errMsg, sizeof(movData->errMsg),
                 "movie can't contain more than 1 movie data field");
        return 1;
      }
      
      movData->rleDataOffset = ftell(movFile);
      movData->rleDataLength = atom.asize - 8;
      
#ifdef DUMP_WHILE_PARSING
      fprintf(stdout, "mdat rle data at offset %d, size is %d bytes\n", movData->rleDataOffset, movData->rleDataLength);
#endif
      
      movData->foundMDAT = 1;
    } else if (atom.atype == fcc_toint('m', 'o', 'o', 'v')) {
      // Movie container : toplevel
      // moov atom contains children mvhd and trak
      
      if (process_atoms(movFile, movData, atomMaxOffset) != 0) {
        return 1;
      }
      
    } else if (atom.atype == fcc_toint('m', 'd', 'a', 't')) {
      // media data atom : skip
      
    } else if (atom.atype == fcc_toint('m', 'v', 'h', 'd')) {
      // Movie header : moov.mvhd
      
      // version : byte
      
      char version;
      
      if (fread(&version, sizeof(version), 1, movFile) != 1) {
        movData->errCode = ERR_READ;
        snprintf(movData->errMsg, sizeof(movData->errMsg), "read error for mvhd version");
        return 1;
      }
      
      if (version == 1) {
        movData->errCode = ERR_UNSUPPORTED_64BIT_FIELD;
        snprintf(movData->errMsg, sizeof(movData->errMsg), "64 bit fields in mvhd not supported");
        return 1;
      }
      
      // flags : 3 bytes
      // creation time : 4 bytes
      // modification time : 4 bytes
      // time scale : 4 bytes
      // duration : 4 bytes
      // ...
      
      seek_status = fseek(movFile, 3 + 4 + 4, SEEK_CUR);
      assert(seek_status == 0);
      
      uint32_t time_scale;
      
      if (read_be_uint32(movFile, &time_scale) != 0) {
        movData->errCode = ERR_READ;
        snprintf(movData->errMsg, sizeof(movData->errMsg), "read error for mvhd time_scale");
        return 1;
      }
      
      uint32_t duration;
      
      if (read_be_uint32(movFile, &duration) != 0) {
        movData->errCode = ERR_READ;
        snprintf(movData->errMsg, sizeof(movData->errMsg), "read error for mvhd duration");
        return 1;
      }
      
#ifdef DUMP_WHILE_PARSING
      fprintf(stdout, "mvhd time_scale %d, duration %d\n", time_scale, duration);
#endif
      
      // The time scale is the number of time units per second.
      // So, if there are 60 "ticks" in a second then the time scale is 60.
      // The default time scale is 600, meaning 1/600 of a second.
      
      movData->lengthInSeconds = ((float)duration) / time_scale;
      movData->lengthInTicks = duration;
      
#ifdef DUMP_WHILE_PARSING
      fprintf(stdout, "mvhd lengthInSeconds %f\n", movData->lengthInSeconds);
#endif
      
      movData->timeScale = time_scale;
      
      movData->foundMVHD = 1;
      
    } else if (atom.atype == fcc_toint('t', 'r', 'a', 'k')) {
      // Track container : moov.trak
      
      if (movData->foundTRAK) {
        // A movie with multiple tracks is not supported
        movData->errCode = ERR_INVALID_FIELD;
        snprintf(movData->errMsg, sizeof(movData->errMsg),
                 "movie can't contain more than 1 track");
        return 1;
      } else if (process_atoms(movFile, movData, atomMaxOffset) != 0) {
        return 1;
      }
      
      movData->foundTRAK = 1;
    } else if (atom.atype == fcc_toint('t', 'k', 'h', 'd')) {
      // Track header : moov.trak.tkhd
      
      // version : byte
      // flags : 3 bytes
      // creation time : 4 bytes
      // modification time : 4 bytes
      // track id : 4 bytes
      // reserved : 4 bytes
      // duration : 4 bytes
      // reserved : 8 bytes
      // layer : 2 bytes
      // alt group : 2 bytes
      // volume : 2 bytes
      // reserved : 2 bytes
      // matrix : 9 * 4 bytes
      // track width : 4 bytes
      // track height : 4 bytes
      
      // skip ahead to the track id field
      
      fseek(movFile, (1 + 3 + 4 + 4), SEEK_CUR);
      
      uint32_t track_id;
      
      if (read_be_uint32(movFile, &track_id) != 0) {
        movData->errCode = ERR_READ;
        snprintf(movData->errMsg, sizeof(movData->errMsg), "read error for trak id");
        return 1;
      }
      
      // track id must be 1, can't be 0 or more than 1 track
      
      if (track_id != 1) {
        movData->errCode = ERR_INVALID_FIELD;
        snprintf(movData->errMsg, sizeof(movData->errMsg),
                 "invalid track id %d, only a single video track is supported", track_id);
        return 1;
      }
      
      fseek(movFile, (4 + 4 + 8 + 2 + 2 + 2 + 2 + 9*4), SEEK_CUR);
      
      float width;
      
      if (read_fixed32(movFile, &width) != 0) {
        movData->errCode = ERR_READ;
        snprintf(movData->errMsg, sizeof(movData->errMsg), "read error for trak track width");
        return 1;
      }
      
      float height;
      
      if (read_fixed32(movFile, &height) != 0) {
        movData->errCode = ERR_READ;
        snprintf(movData->errMsg, sizeof(movData->errMsg), "read error for trak track height");
        return 1;
      }
      
      // If width and height are zero, this must be an audio track
      
      if (width == 0.0 && height == 0.0) {
        movData->errCode = ERR_INVALID_FIELD;
        snprintf(movData->errMsg, sizeof(movData->errMsg),
                 "invalid track width/height of zero, mov can only contain a single video track",
                 width, height);
        return 1;
      }      
      
      // width and height must be whole numbers as they will be converted to int.
      // Also check for a common sense upper limit on the encoded movie size, 2000x2000 is huge.
      
      if (width <= 0.0 || height <= 0.0 || floor(width) != width || floor(height) != height || width > 2000.0 || height > 2000.0) {
        movData->errCode = ERR_INVALID_FIELD;
        snprintf(movData->errMsg, sizeof(movData->errMsg),
                 "invalid track width/height (%f / %f)",
                 width, height);
        return 1;
      }
      
      movData->foundTKHD = 1;
      movData->width = (int) width;
      movData->height = (int) height;
      
#ifdef DUMP_WHILE_PARSING
      fprintf(stdout, "tkhd width / height %d / %d\n", movData->width, movData->height);
#endif
      
    } else if (atom.atype == fcc_toint('e', 'd', 't', 's')) {
      // Edit container : moov.trak.edts
      
      if (movData->foundEDTS) {
        // Ignore any edit lists other than the first one
      } else if (process_atoms(movFile, movData, atomMaxOffset) != 0) {
        return 1;
      }
      
      movData->foundEDTS = 1;
      
    } else if (atom.atype == fcc_toint('e', 'l', 's', 't')) {
      // Edit list : moov.trak.elst
      
      // version : byte
      // flags : 3 bytes
      // num entries : 4 bytes
      // table : 12 bytes * num entries
      //  (track duration, media time, media rate)
      //  track duration : 4 byte integer
      //  media time : 4 byte integer
      //  media rate : 4 byte integer
      
      // skip version and flags
      fseek(movFile, 4, SEEK_CUR);
      
      uint32_t num_entries;
      
      if (read_be_uint32(movFile, &num_entries) != 0) {
        movData->errCode = ERR_READ;
        snprintf(movData->errMsg, sizeof(movData->errMsg), "read error for elst num entries");
        return 1;
      }
      
      // The track can only appear on the timeline once, at time = 0.0 to end
      
      if (num_entries != 1) {
        movData->errCode = ERR_INVALID_FIELD;
        snprintf(movData->errMsg, sizeof(movData->errMsg), "elst must contain only a single entry");
        return 1;
      }
      
      uint32_t track_duration, media_time;
      float media_rate;
      
      if (read_be_uint32(movFile, &track_duration) != 0) {
        movData->errCode = ERR_READ;
        snprintf(movData->errMsg, sizeof(movData->errMsg), "read error for elst track duration");
        return 1;
      }
      if (read_be_uint32(movFile, &media_time) != 0) {
        movData->errCode = ERR_READ;
        snprintf(movData->errMsg, sizeof(movData->errMsg), "read error for elst media time");
        return 1;
      }
      if (read_fixed32(movFile, &media_rate) != 0) {
        movData->errCode = ERR_READ;
        snprintf(movData->errMsg, sizeof(movData->errMsg), "read error for elst media rate");
        return 1;
      }      
      
      if (track_duration != movData->lengthInTicks) {
        movData->errCode = ERR_INVALID_FIELD;
        snprintf(movData->errMsg, sizeof(movData->errMsg), "elst track duration %d does not match mov duration %d", track_duration, movData->lengthInTicks);
        return 1;
      }
      if (media_time != 0) {
        movData->errCode = ERR_INVALID_FIELD;
        snprintf(movData->errMsg, sizeof(movData->errMsg), "elst track media time must begin at 0, not %d", media_time);
        return 1;
      }
      if (media_rate != 1.0) {
        movData->errCode = ERR_INVALID_FIELD;
        snprintf(movData->errMsg, sizeof(movData->errMsg), "elst track media rate must be 1.0, not %d", media_time);
        return 1;
      }
      
      movData->foundELST = 1;
    } else if (atom.atype == fcc_toint('m', 'd', 'i', 'a')) {
      // Media container : moov.trak.mdia
      
      if (movData->foundMDIA) {
        // Ignore any media segments other than the first one
      } else if (process_atoms(movFile, movData, atomMaxOffset) != 0) {
        return 1;
      }
      
      movData->foundMDIA = 1;
    } else if (atom.atype == fcc_toint('m', 'd', 'h', 'd')) {
      // Media header : moov.trak.mdia.mdhd
      
    } else if (atom.atype == fcc_toint('h', 'd', 'l', 'r')) {
      // Handler Reference Atom : moov.trak.mdia.hdlr
      // Must contain [mhlr/vide - Apple Video Media Handler]
      
      // version : byte
      // flags : 3 bytes
      // component type : 4 bytes
      // component subtype : 4 bytes
      // component manufacturer : 4 bytes
      // component name : N bytes (ignored)
      
      fseek(movFile, 4, SEEK_CUR);
      
      uint32_t component_type;
      
      if (read_uint32(movFile, &component_type) != 0) {
        movData->errCode = ERR_READ;
        snprintf(movData->errMsg, sizeof(movData->errMsg), "read error for hdlr component type");
        return 1;
      }
      
      uint32_t component_subtype;
      
      if (read_uint32(movFile, &component_subtype) != 0) {
        movData->errCode = ERR_READ;
        snprintf(movData->errMsg, sizeof(movData->errMsg), "read error for hdlr component subtype");
        return 1;
      }
      
      uint32_t component_manufacturer;
      
      if (read_uint32(movFile, &component_manufacturer) != 0) {
        movData->errCode = ERR_READ;
        snprintf(movData->errMsg, sizeof(movData->errMsg), "read error for hdlr component manufacturer");
        return 1;
      }
      
#ifdef DUMP_WHILE_PARSING
      fprintf(stdout, "component type \"%s\"\n", moviedata_fcc_tostring(movData, component_type));
      fprintf(stdout, "component subtype \"%s\"\n", moviedata_fcc_tostring(movData, component_subtype));
      fprintf(stdout, "component manufacturer \"%s\"\n", moviedata_fcc_tostring(movData, component_manufacturer));      
#endif
      
      if (component_type == fcc_toint('m', 'h', 'l', 'r')) {
        // Defines an alias to the data handler
        
        if (component_subtype != fcc_toint('v', 'i', 'd', 'e')) {
          movData->errCode = ERR_INVALID_FIELD;
          snprintf(movData->errMsg, sizeof(movData->errMsg), "hdlr component subtype is not vide");
          return 1;
        }
        if (component_manufacturer != fcc_toint('a', 'p', 'p', 'l')) {
          movData->errCode = ERR_INVALID_FIELD;
          snprintf(movData->errMsg, sizeof(movData->errMsg), "hdlr component manufacturer is not appl");
          return 1;
        }
        
        movData->foundMHLR = 1;
      } else if (component_type == fcc_toint('d', 'h', 'l', 'r')) {
        // Defines the handler in the minf atom (aliased to)
        
        if (component_subtype != fcc_toint('a', 'l', 'i', 's')) {
          movData->errCode = ERR_INVALID_FIELD;
          snprintf(movData->errMsg, sizeof(movData->errMsg), "dhlr component subtype is not alis");
          return 1;
        }
        if (component_manufacturer != fcc_toint('a', 'p', 'p', 'l')) {
          movData->errCode = ERR_INVALID_FIELD;
          snprintf(movData->errMsg, sizeof(movData->errMsg), "dhlr component manufacturer is not appl");
          return 1;
        }
        
        movData->foundDHLR = 1;
      } else {
        movData->errCode = ERR_INVALID_FIELD;
        snprintf(movData->errMsg, sizeof(movData->errMsg), "hdlr component type is not mhlr or dhlr");
        return 1;
      }
    } else if (atom.atype == fcc_toint('m', 'i', 'n', 'f')) {
      // Sound Media container : moov.trak.mdia.minf
      
      if (process_atoms(movFile, movData, atomMaxOffset) != 0) {
        return 1;
      }
    } else if (atom.atype == fcc_toint('d', 'i', 'n', 'f')) {
      // Data Information container : moov.trak.mdia.minf.dinf
      
      if (process_atoms(movFile, movData, atomMaxOffset) != 0) {
        return 1;
      }
    } else if (atom.atype == fcc_toint('v', 'm', 'h', 'd')) {
      // Video media information header : moov.trak.mdia.minf.vmhd
      
      movData->foundVMHD = 1;
      
      // version : byte
      // flags : 3 bytes
      // graphics mode : 2 bytes
      // op color : 6 bytes
      
      // skip version + flags
      
      fseek(movFile, 4, SEEK_CUR);
      
      // Read 16 bit graphics mode flag and support only simple ones

      uint16_t graphics_mode;
      
      if (read_be_int16(movFile, (int16_t*)&graphics_mode) != 0) {
        movData->errCode = ERR_READ;
        snprintf(movData->errMsg, sizeof(movData->errMsg), "read error for vmhd graphics mode");
        return 1;
      }

      // Can't validate graphics mode until bit depth is known

      movData->graphicsMode = graphics_mode;
      
    } else if (atom.atype == fcc_toint('d', 'r', 'e', 'f')) {
      // Data reference: moov.trak.mdia.minf.dinf.dref
      
      // version : byte
      // flags : 3 bytes
      // num entries : 4 bytes
      
      fseek(movFile, 4, SEEK_CUR);
      
      uint32_t num_entries;
      
      if (read_be_uint32(movFile, &num_entries) != 0) {
        movData->errCode = ERR_READ;
        snprintf(movData->errMsg, sizeof(movData->errMsg), "read error for dref num entres");
        return 1;
      }
      
      // FIXME: seems like none of this is actually needed!
      // Is it possible to just avoid parsing the dref completely?
      
      // FIXME : Can there only be 1 entry in this data ref table?
      // what happens if there are zero entries?
      
      // Now there are num_entries number of data references to read
      
      DataRefTableEntry *table = malloc(sizeof(DataRefTableEntry) * num_entries);
      if (table == NULL) {
        movData->errCode = ERR_MALLOC_FAILED;
        snprintf(movData->errMsg, sizeof(movData->errMsg),
                 "malloc of %d bytes failed for dref table", (int) (sizeof(DataRefTableEntry) * num_entries));
        return 1;        
      }
      bzero(table, sizeof(DataRefTableEntry) * num_entries);
      
      for (int i = 0; i < num_entries; i++) {
        DataRefTableEntry *entry = &table[i];
        
        // size : 4 bytes 
        // type : 4 bytes
        // version : 1 byte
        // flags : 3 bytes
        
        if (read_be_uint32(movFile, &entry->size) != 0) {
          movData->errCode = ERR_READ;
          snprintf(movData->errMsg, sizeof(movData->errMsg), "read error for dref table entry size");
          return 1;
        }
        
        if (read_uint32(movFile, &entry->type) != 0) {
          movData->errCode = ERR_READ;
          snprintf(movData->errMsg, sizeof(movData->errMsg), "read error for dref table entry type");
          return 1;
        }
        // type must be 'dref' ?
        
        // Skip version and flags
        fseek(movFile, 4, SEEK_CUR);
        
        // Record location of data along with the number of bytes.
        // We don't want to actually read the data since there could
        // be a lot of data.
        
        entry->data_offset = ftell(movFile);
        entry->data_size = entry->size - (4 + 4 + 1 + 3);
        
#ifdef DUMP_WHILE_PARSING
        fprintf(stdout, "data ref %d, size %d, type \"%s\", data at %d of length %d\n", i,
                entry->size, moviedata_fcc_tostring(movData, entry->type),
                entry->data_offset, entry->data_size);
#endif
      }
      
      free(table);
      
      movData->foundDREF = 1;
    } else if (atom.atype == fcc_toint('s', 't', 'b', 'l')) {
      // Sample table container : moov.trak.mdia.minf.stbl
      // Contains the atoms that contain the actual video data to be decoded
      
      if (movData->foundSTBL) {
        movData->errCode = ERR_INVALID_FIELD;
        snprintf(movData->errMsg, sizeof(movData->errMsg), "found multiple stbl atoms");
        return 1;
      }
      movData->foundSTBL = 1;

      if (process_atoms(movFile, movData, atomMaxOffset) != 0) {
        return 1;
      }
      
    } else if (atom.atype == fcc_toint('s', 't', 's', 'd')) {
      // Sample description : moov.trak.mdia.minf.stbl.stsd
      // Describes the format of the RLE data that appears in the mdat
      
      if (movData->foundSTSD) {
        movData->errCode = ERR_INVALID_FIELD;
        snprintf(movData->errMsg, sizeof(movData->errMsg), "found multiple stsd atoms");
        return 1;
      }
      movData->foundSTSD = 1;
      
      // version : byte
      // flags : 3 bytes
      // num entries : 4 bytes
      
      fseek(movFile, 4, SEEK_CUR);
      
      uint32_t num_entries;
      
      if (read_be_uint32(movFile, &num_entries) != 0) {
        movData->errCode = ERR_READ;
        snprintf(movData->errMsg, sizeof(movData->errMsg), "read error for stsd num entres");
        return 1;
      }
      
      if (num_entries != 1) {
        movData->errCode = ERR_INVALID_FIELD;
        snprintf(movData->errMsg, sizeof(movData->errMsg),
                 "stsd table must contain 1 entry, not %d entries", (int) num_entries);
        return 1;        
      }
      
      // Read a single "Sample Description" data field
      
      // Sample description size : 4 bytes
      // Data format : 4 bytes
      // Reserved : 6 bytes
      // Data reference index : 2 bytes (16 bit integer index)
      
      uint32_t sample_description_size, data_format;
      
      if (read_be_uint32(movFile, &sample_description_size) != 0) {
        movData->errCode = ERR_READ;
        snprintf(movData->errMsg, sizeof(movData->errMsg), "read error for stsd sample description size");
        return 1;
      }      
      
      if (read_uint32(movFile, &data_format) != 0) {
        movData->errCode = ERR_READ;
        snprintf(movData->errMsg, sizeof(movData->errMsg), "read error for stsd sample data format");
        return 1;
      }
      
      // Only "Animation" codec is supported
      
      if (data_format != fcc_toint('r', 'l', 'e', ' ')) {
        movData->errCode = ERR_INVALID_FIELD;
        snprintf(movData->errMsg, sizeof(movData->errMsg), "stsd table data format must be \"rle \" not \"%s\"",
                 moviedata_fcc_tostring(movData, data_format));
        return 1;
      }
      
      // skip reserved
      fseek(movFile, 6, SEEK_CUR);
      
      uint32_t data_ref_size = sample_description_size - (4 + 4 + 6 + 2);
      
      if (data_ref_size == 0) {
        movData->errCode = ERR_INVALID_FIELD;
        snprintf(movData->errMsg, sizeof(movData->errMsg), "stsd table data ref size is zero");
        return 1;        
      }      
      
      int16_t data_ref_index;
      
      if (read_be_int16(movFile, &data_ref_index) != 0) {
        movData->errCode = ERR_READ;
        snprintf(movData->errMsg, sizeof(movData->errMsg), "read error for stsd sample data ref index");
        return 1;
      }
      
      // Indicates that rle data is contained in the first (and only) mdat
      
      if (data_ref_index != 1) {
        movData->errCode = ERR_INVALID_FIELD;
        snprintf(movData->errMsg, sizeof(movData->errMsg), "stsd table data ref index must be 1");
        return 1;        
      }
      
      // Additional fields for video sample description
      
      // version : 2 bytes
      // revision : 2 bytes
      // vendor : 4 bytes
      // temporal quality : 4 bytes
      // spatial quality : 4 bytes
      // width : 2 bytes
      // height : 2 bytes
      // horizontal resolution : 4 bytes (fixed)
      // vertical resolution : 4 bytes (fixed)
      // data size : 4 bytes
      // frame count : 2 bytes
      // compressor name : 32 byte string
      // depth : 2 bytes
      // color table id : 2 bytes
      
      // skip version and revision
      fseek(movFile, 2 + 2, SEEK_CUR);
      
      uint32_t vendor;
      
      if (read_uint32(movFile, &vendor) != 0) {
        movData->errCode = ERR_READ;
        snprintf(movData->errMsg, sizeof(movData->errMsg), "read error for stsd vendor");
        return 1;
      }
      
      // Only Apple "Animation" codec is supported
      
      if (vendor != fcc_toint('a', 'p', 'p', 'l')) {
        movData->errCode = ERR_INVALID_FIELD;
        snprintf(movData->errMsg, sizeof(movData->errMsg), "stsd table data format must be \"appl\" not \"%s\"",
                 moviedata_fcc_tostring(movData, vendor));
        return 1;
      }
      
      // FIXME: check the return result of all of the fseek() calls!
      
      // skip to frame count field
      fseek(movFile, 4 + 4 + 2 + 2 + 4 + 4 + 4, SEEK_CUR);
      
      // Verify that movie format stores only 1 frame in each sample.
      
      int16_t frame_count;
      
      if (read_be_int16(movFile, &frame_count) != 0) {
        movData->errCode = ERR_READ;
        snprintf(movData->errMsg, sizeof(movData->errMsg), "read error for stsd frame count");
        return 1;
      }
      
      if (frame_count != 1) {
        movData->errCode = ERR_INVALID_FIELD;
        snprintf(movData->errMsg, sizeof(movData->errMsg), "stsd table frame count must be 1, not %d", (int)frame_count);
        return 1;
      }
      
      uint8_t compressor_name_len;
      char compressor_name[31];
      
      if (fread(&compressor_name_len, sizeof(compressor_name_len), 1, movFile) != 1) {
        movData->errCode = ERR_READ;
        snprintf(movData->errMsg, sizeof(movData->errMsg), "read error for stsd compressor name len");
        return 1;
      }
      if (fread(&compressor_name[0], sizeof(compressor_name), 1, movFile) != 1) {
        movData->errCode = ERR_READ;
        snprintf(movData->errMsg, sizeof(movData->errMsg), "read error for stsd compressor name");
        return 1;
      }
      compressor_name[30] = '\0';
      char *animation_name = "Animation";
      
      if (compressor_name_len != strlen(animation_name) || strcmp(compressor_name, animation_name) != 0) {
        movData->errCode = ERR_INVALID_FIELD;
        snprintf(movData->errMsg, sizeof(movData->errMsg), "stsd table data compressor name must be \"Animation\" not \"%s\"",
                 compressor_name);
        return 1;
      }
      
      // depth == 16 | 24 | 32
      
      int16_t depth;
      
      if (read_be_int16(movFile, &depth) != 0) {
        movData->errCode = ERR_READ;
        snprintf(movData->errMsg, sizeof(movData->errMsg), "read error for stsd depth");
        return 1;
      }
      
      if (depth != 16 && depth != 24 && depth != 32) {
        movData->errCode = ERR_INVALID_FIELD;
        snprintf(movData->errMsg, sizeof(movData->errMsg), "stsd table data ref index must be 16, 24, or 32. Not %d", (int)depth);
        return 1;
      }
      movData->bitDepth = depth;
      
      // color table id == -1 
      
      int16_t color_table_id;
      
      if (read_be_int16(movFile, &color_table_id) != 0) {
        movData->errCode = ERR_READ;
        snprintf(movData->errMsg, sizeof(movData->errMsg), "read error for stsd color table id");
        return 1;
      }
      
      if (color_table_id != -1) {
        movData->errCode = ERR_INVALID_FIELD;
        snprintf(movData->errMsg, sizeof(movData->errMsg), "stsd table entry must not make use of a color table");
        return 1;
      }

    } else if (atom.atype == fcc_toint('s', 't', 't', 's')) {
      // Time to sample : moov.trak.mdia.minf.stbl.stts
      // Table that maps media time to sample number

      if (movData->foundSTTS) {
        movData->errCode = ERR_INVALID_FIELD;
        snprintf(movData->errMsg, sizeof(movData->errMsg), "found multiple stts atoms");
        return 1;
      }
      movData->foundSTTS = 1;
                  
      // version : byte
      // flags : 3 bytes
      // num entries : 4 bytes
      // table : 8 bytes * num entries
      //  (sample count, sample duration)
      //  sample count : 4 byte integer of # of samples with same duration
      //  sample duration : 4 byte integer of duration of each sample
      
      // skip version and flags
      fseek(movFile, 4, SEEK_CUR);
      
      uint32_t num_entries;
      
      if (read_be_uint32(movFile, &num_entries) != 0) {
        movData->errCode = ERR_READ;
        snprintf(movData->errMsg, sizeof(movData->errMsg), "read error for stts num entres");
        return 1;
      }
      assert(num_entries > 0);

      // Record the size and locaton of this table
      movData->timeToSampleTableNumEntries = num_entries;
      movData->timeToSampleTableOffset = ftell(movFile);
      
    } else if (atom.atype == fcc_toint('s', 't', 's', 's')) {
      // Sync sample : moov.trak.mdia.minf.stbl.stss
      // Table that defines which samples (not frames) indicate a key frame.
      // A frame that is a nop (no change) could still be a keyframe (it is a sample property)
      // Note that if this atom is not defined, then all the frames are key frames!
      
      if (movData->foundSTSS) {
        movData->errCode = ERR_INVALID_FIELD;
        snprintf(movData->errMsg, sizeof(movData->errMsg), "found multiple stss atoms");
        return 1;
      }
      movData->foundSTSS = 1;      
      
      // version : byte
      // flags : 3 bytes
      // num entries : 4 bytes
      // table : 4 bytes * num entries
      //  each table entry is in increasing order : (2, 4, 5) indicate that these frames are key frames
      
      // skip version and flags
      fseek(movFile, 4, SEEK_CUR);
      
      uint32_t num_entries;
      
      if (read_be_uint32(movFile, &num_entries) != 0) {
        movData->errCode = ERR_READ;
        snprintf(movData->errMsg, sizeof(movData->errMsg), "read error for stss num entries");
        return 1;
      }
      assert(num_entries > 0);
      
      // Record the size and locaton of this table
      movData->syncSampleTableNumEntries = num_entries;
      movData->syncSampleTableOffset = ftell(movFile);      
            
    } else if (atom.atype == fcc_toint('s', 't', 's', 'c')) {
      // Sample to chunk : moov.trak.mdia.minf.stbl.stsc
      // Mapping of sample number to chunk number
      
      if (movData->foundSTSC) {
        movData->errCode = ERR_INVALID_FIELD;
        snprintf(movData->errMsg, sizeof(movData->errMsg), "found multiple stsc atoms");
        return 1;
      }
      movData->foundSTSC = 1;      
      
      // version : byte
      // flags : 3 bytes
      // num entries : 4 bytes
      // table : 0 or N 12 byte entries
      //  First chunk : 4 bytes
      //  Samples per chunk : 4 bytes
      //  Sample description ID : 4 bytes
      
      // skip version and flags
      fseek(movFile, 4, SEEK_CUR);
      
      uint32_t num_entries;
      
      if (read_be_uint32(movFile, &num_entries) != 0) {
        movData->errCode = ERR_READ;
        snprintf(movData->errMsg, sizeof(movData->errMsg), "read error for stsc num entries");
        return 1;
      }
      assert(num_entries > 0);
      
      // Record the size and locaton of this table
      movData->sampleToChunkTableNumEntries = num_entries;
      movData->sampleToChunkTableOffset = ftell(movFile);      
            
    } else if (atom.atype == fcc_toint('s', 't', 's', 'z')) {
      // Sample size : moov.trak.mdia.minf.stbl.stsz
      // Table that defines the size of each sample data region (in mdat)
      
      if (movData->foundSTSZ) {
        movData->errCode = ERR_INVALID_FIELD;
        snprintf(movData->errMsg, sizeof(movData->errMsg), "found multiple stsc atoms");
        return 1;
      }
      movData->foundSTSZ = 1;
      
      // version : byte
      // flags : 3 bytes
      // sample size : 4 bytes
      // num entries : 4 bytes
      // table : 0 or N 4 byte integers, one for each sample
      
      // skip version and flags
      fseek(movFile, 4, SEEK_CUR);
      
      uint32_t sample_size;
      
      if (read_be_uint32(movFile, &sample_size) != 0) {
        movData->errCode = ERR_READ;
        snprintf(movData->errMsg, sizeof(movData->errMsg), "read error for stsz sample size");
        return 1;
      }
      
      uint32_t num_entries;
      
      if (read_be_uint32(movFile, &num_entries) != 0) {
        movData->errCode = ERR_READ;
        snprintf(movData->errMsg, sizeof(movData->errMsg), "read error for stsz num entres");
        return 1;
      }

      movData->sampleSizeCommon = sample_size;
      movData->sampleSizeTableNumEntries = num_entries;
      if (num_entries > 0) {
        movData->sampleSizeTableOffset = ftell(movFile);
      }
      
    } else if (atom.atype == fcc_toint('s', 't', 'c', 'o')) {
      // Chunk Offset : moov.trak.mdia.minf.stbl.stco
      // Table that defines the file byte offset for each chunk in the mdat.
      // Note that a single chunk can contain N samples.
      
      if (movData->foundSTCO) {
        movData->errCode = ERR_INVALID_FIELD;
        snprintf(movData->errMsg, sizeof(movData->errMsg), "found multiple stco atoms");
        return 1;
      }
      movData->foundSTCO = 1;
            
      // version : byte
      // flags : 3 bytes
      // num entries : 4 bytes
      // table : 0 or N 4 byte integers
      
      // skip version and flags
      fseek(movFile, 4, SEEK_CUR);
      
      uint32_t num_entries;
      
      if (read_be_uint32(movFile, &num_entries) != 0) {
        movData->errCode = ERR_READ;
        snprintf(movData->errMsg, sizeof(movData->errMsg), "read error for stco num entres");
        return 1;
      }
      
      assert(num_entries > 0);

      // Record the size and locaton of this table
      movData->chunkOffsetTableNumEntries = num_entries;
      movData->chunkOffsetTableOffset = ftell(movFile);      
      
    }
    
    // Skip the rest of the bytes in this atom

/*
#ifdef DUMP_WHILE_PARSING
    fprintf(stdout, "done with atom \"%s\" at byte %d, will seek to %d\n",
            moviedata_fcc_tostring(movData, atom.atype),
            (int)ftell(movFile), (int) (atomOffset + atom.asize));
#endif
*/

    seek_status = fseek(movFile, atomOffset + atom.asize, SEEK_SET);
    assert(seek_status == 0);
  }
  
  return 0;
}

// Util method for reading a SampleToChunkTableEntry 

static inline
int SampleToChunkTableEntry_read(FILE *movFile, MovData *movData, SampleToChunkTableEntry *sampleToChunkTableEntryPtr)
{
  uint32_t first_chunk_id, samples_per_chunk, sample_desc_id;
  
  if (read_be_uint32(movFile, &first_chunk_id) != 0) {
    movData->errCode = ERR_READ;
    snprintf(movData->errMsg, sizeof(movData->errMsg), "read error for stsc first chunk");
    return 1;
  }
  if (read_be_uint32(movFile, &samples_per_chunk) != 0) {
    movData->errCode = ERR_READ;
    snprintf(movData->errMsg, sizeof(movData->errMsg), "read error for stsc samples per chunk");
    return 1;
  }
  if (read_be_uint32(movFile, &sample_desc_id) != 0) {
    movData->errCode = ERR_READ;
    snprintf(movData->errMsg, sizeof(movData->errMsg), "read error for stsc sample description id");
    return 1;
  }
  assert(sample_desc_id == 1);

  sampleToChunkTableEntryPtr->first_chunk_id = first_chunk_id;
  sampleToChunkTableEntryPtr->samples_per_chunk = samples_per_chunk;

  return 0;
}

// This method is invoked after all the atoms have been read
// successfully.

int
process_sample_tables(FILE *movFile, MovData *movData) {
  // All atoms except sync are required at this point
  
  if (!movData->foundMDAT) { 
    movData->errCode = ERR_INVALID_FIELD;
    snprintf(movData->errMsg, sizeof(movData->errMsg), "mdat atom was not found");
    return 1;
  }
  if (!movData->foundMVHD) { 
    movData->errCode = ERR_INVALID_FIELD;
    snprintf(movData->errMsg, sizeof(movData->errMsg), "mvhd atom was not found");
    return 1;
  }
  if (!movData->foundTRAK) { 
    movData->errCode = ERR_INVALID_FIELD;
    snprintf(movData->errMsg, sizeof(movData->errMsg), "trak atom was not found");
    return 1;
  }
  if (!movData->foundTKHD) { 
    movData->errCode = ERR_INVALID_FIELD;
    snprintf(movData->errMsg, sizeof(movData->errMsg), "tkhd atom was not found");
    return 1;
  }
  if (!movData->foundEDTS) { 
    movData->errCode = ERR_INVALID_FIELD;
    snprintf(movData->errMsg, sizeof(movData->errMsg), "edts atom was not found");
    return 1;
  }
  if (!movData->foundELST) { 
    movData->errCode = ERR_INVALID_FIELD;
    snprintf(movData->errMsg, sizeof(movData->errMsg), "elst atom was not found");
    return 1;
  }
  if (!movData->foundMDIA) { 
    movData->errCode = ERR_INVALID_FIELD;
    snprintf(movData->errMsg, sizeof(movData->errMsg), "mdia atom was not found");
    return 1;
  }  
  if (!movData->foundMHLR) { 
    movData->errCode = ERR_INVALID_FIELD;
    snprintf(movData->errMsg, sizeof(movData->errMsg), "mhlr atom was not found");
    return 1;
  }
  if (!movData->foundDHLR) { 
    movData->errCode = ERR_INVALID_FIELD;
    snprintf(movData->errMsg, sizeof(movData->errMsg), "dhlr atom was not found");
    return 1;
  }  
  if (!movData->foundDREF) { 
    movData->errCode = ERR_INVALID_FIELD;
    snprintf(movData->errMsg, sizeof(movData->errMsg), "dref atom was not found");
    return 1;
  }  
  if (!movData->foundSTBL) { 
    movData->errCode = ERR_INVALID_FIELD;
    snprintf(movData->errMsg, sizeof(movData->errMsg), "stbl atom was not found");
    return 1;
  }  
  if (!movData->foundSTSD) { 
    movData->errCode = ERR_INVALID_FIELD;
    snprintf(movData->errMsg, sizeof(movData->errMsg), "stsd atom was not found");
    return 1;
  }
  if (!movData->foundSTTS) { 
    movData->errCode = ERR_INVALID_FIELD;
    snprintf(movData->errMsg, sizeof(movData->errMsg), "stts atom was not found");
    return 1;
  }
//  if (!movData->foundSTSS) { 
//    movData->errCode = ERR_INVALID_FIELD;
//    snprintf(movData->errMsg, sizeof(movData->errMsg), "stss atom was not found");
//    return 1;
//  }
  if (!movData->foundSTSC) { 
    movData->errCode = ERR_INVALID_FIELD;
    snprintf(movData->errMsg, sizeof(movData->errMsg), "stsc atom was not found");
    return 1;
  }  
  if (!movData->foundSTSZ) { 
    movData->errCode = ERR_INVALID_FIELD;
    snprintf(movData->errMsg, sizeof(movData->errMsg), "stsz atom was not found");
    return 1;
  }
  if (!movData->foundSTCO) { 
    movData->errCode = ERR_INVALID_FIELD;
    snprintf(movData->errMsg, sizeof(movData->errMsg), "stco atom was not found");
    return 1;
  }
  if (!movData->foundVMHD) { 
    movData->errCode = ERR_INVALID_FIELD;
    snprintf(movData->errMsg, sizeof(movData->errMsg), "vmhd atom was not found");
    return 1;
  }
  
  // Check graphics mode flag in vmhd header now that bit depth is known.
  // This step is more strict than it needs to be, for exampe a movie
  // encoded with 32bpp and no transparency is valid, but what is the
  // point as it wasted 8 bits per pixel. It could be recoded to 24bpp.
  
  // Video graphics modes
  
  #define GRAPHICS_MODE_COPY 0
  #define GRAPHICS_MODE_DITHER_COPY 0x40
  #define GRAPHICS_MODE_BLEND 0x20
  #define GRAPHICS_MODE_TRANSPARENT 0x24
  #define GRAPHICS_MODE_STRAIGHT_ALPHA 0x100
  #define GRAPHICS_MODE_PREMUL_WHITE_ALPHA 0x101
  #define GRAPHICS_MODE_PREMUL_BLACK_ALPHA 0x102
  #define GRAPHICS_MODE_STRAIGHT_ALPHA_BLEND 0x104
  #define GRAPHICS_MODE_COMPOSITION 0x103
  
  // After much testing, it appears that exporting a Quicktime movie with the Animation
  // codec only works when the GRAPHICS_MODE_COPY or GRAPHICS_MODE_DITHER_COPY mode
  // is enabled. There seems to be no way to use any other flags, as they interfere
  // with the alpha channel. The pixels encoded in the Animation codec use straight
  // alpha, so we always need to premultiply them.
  
  // A "Thousands of colors" 16bpp encoding could support a transparency bit,
  // but CoreGraphics does not support that mode.
    
  if (movData->graphicsMode == GRAPHICS_MODE_COPY ||
      movData->graphicsMode == GRAPHICS_MODE_DITHER_COPY) {
    // Supported, src pixels replace dest pixels
  } else {
    movData->errCode = ERR_INVALID_FIELD;
    snprintf(movData->errMsg, sizeof(movData->errMsg), "unsupported graphics mode (0x%X) in vmhd header, only copy and dither copy are supported", movData->graphicsMode);
    return 1;
  }
  
  // Begin parsing tables
  
  int status = 1; // err status returned via "goto reterr"

  // pointers that need to be cleaned up when exiting this function
  MovChunk *chunks = NULL;
  uint32_t *TimeToSampleTable = NULL;

  int seek_result;
  
  // Get the number of chunks in the stco chunk offset table
  
  const int numChunks = movData->chunkOffsetTableNumEntries;

  chunks = malloc(sizeof(MovChunk) * numChunks);
  bzero(chunks, sizeof(sizeof(MovChunk) * numChunks));

  assert(movData->chunkOffsetTableOffset > 0);
  seek_result = fseek(movFile, movData->chunkOffsetTableOffset, SEEK_SET);
  if (seek_result != 0) {
    movData->errCode = ERR_READ;
    snprintf(movData->errMsg, sizeof(movData->errMsg), "seek error for stco table offset");
    goto reterr;    
  }
  
  for (int chunk_index = 0; chunk_index < numChunks; chunk_index++) {
    MovChunk *movChunk = &chunks[chunk_index];
    movchunk_init(movChunk);
    
    // Read the file offset and save in the chunk
    
    uint32_t offset;
    
    if (read_be_uint32(movFile, &offset) != 0) {
      movData->errCode = ERR_READ;
      snprintf(movData->errMsg, sizeof(movData->errMsg), "read error for stco table offset");
      goto reterr;
    }        
    
    assert(offset > 0);
    movChunk->offset = offset;
  }

  // Next we need to determine how many samples there actually are (may not be in stsz).  
  // Allocate table of SAMPLE COUNT, SAMPLE DURATION for time to sample info.
  // Iterate through the time to sample table and find the smallest time
  // that a sample is displayed. This is the effective frame duration.
  // It is possible that a movie could be encoded at 10FPS but every 2nd
  // frame is the same, so that would be an effective frame rate of 5FPS.
  
  assert(movData->timeToSampleTableOffset > 0);
  seek_result = fseek(movFile, movData->timeToSampleTableOffset, SEEK_SET);
  if (seek_result != 0) {
    movData->errCode = ERR_READ;
    snprintf(movData->errMsg, sizeof(movData->errMsg), "seek error for stts table offset");
    goto reterr;    
  }  
  
  TimeToSampleTable = malloc(movData->timeToSampleTableNumEntries * 2 * sizeof(uint32_t));
  bzero(TimeToSampleTable, movData->timeToSampleTableNumEntries * 2 * sizeof(uint32_t));
  
  uint32_t smallest_duration = INT_MAX;
  uint32_t num_samples = 0;
    
  for (int i = 0; i < movData->timeToSampleTableNumEntries; i++) {
    uint32_t *sampleCountPtr = TimeToSampleTable + (i*2+0);
    uint32_t *sampleDurationPtr = TimeToSampleTable + (i*2+1);
    
    if (read_be_uint32(movFile, sampleCountPtr) != 0) {
      movData->errCode = ERR_READ;
      snprintf(movData->errMsg, sizeof(movData->errMsg), "read error for stts sample table count");
      goto reterr;
    }
    if (read_be_uint32(movFile, sampleDurationPtr) != 0) {
      movData->errCode = ERR_READ;
      snprintf(movData->errMsg, sizeof(movData->errMsg), "read error for stts sample table duration");
      goto reterr;
    }
    
    if (*sampleDurationPtr > 0 && *sampleDurationPtr < smallest_duration) {
      smallest_duration = *sampleDurationPtr;
    }
    num_samples += *sampleCountPtr;
    
#ifdef DUMP_WHILE_PARSING
    fprintf(stdout, "TimeToSampleTable[%d] = (%d %d)\n", i, *sampleCountPtr, *sampleDurationPtr);
#endif
  }
  
  if (movData->sampleSizeCommon == 0) {
    // Should match the number of samples from the sample size table.
    assert(num_samples == movData->sampleSizeTableNumEntries);
  }
  
  movData->samples = malloc(sizeof(MovSample) * num_samples);
  bzero(movData->samples, sizeof(MovSample) * num_samples);
  movData->numSamples = num_samples;
  
  // Use the effective frame rate to calculate the approx FPS and
  // the total number of frames in the track.
  
  assert(movData->timeScale > 0);
  float frameDuration = ((float)smallest_duration) / movData->timeScale;
  float numFrames = movData->lengthInSeconds / frameDuration;
  float fps = numFrames / movData->lengthInSeconds;

  movData->fps = fps;
  int numFramesInt = round(numFrames);

#ifdef DUMP_WHILE_PARSING
  fprintf(stdout, "mov length %f, frameDuration %f, numFrames is %f, FPS is %f\n",
          movData->lengthInSeconds, frameDuration, numFrames, fps);
#endif  
  
  // This err only seems to show up in odd cases where both audio and
  // video were included in a movie, but then the audio track was deleted.
  // Exporting from QT again instead of just deleting the track will
  // purge the unused samples from the mdat (saving space) and fix this problem.

  if (numFramesInt < num_samples) {
    movData->errCode = ERR_INVALID_FIELD;
    snprintf(movData->errMsg, sizeof(movData->errMsg),
             "found %d samples, but only %d frames of video, re-exporting from Quicktime may fix this",
             num_samples, numFramesInt);
    return 1;
  }
    
  movData->frames = malloc(sizeof(MovSample*) * numFramesInt);
  bzero(movData->frames, sizeof(MovSample*) * numFramesInt);
  movData->numFrames = numFramesInt;

  // Iterate over each entry in the TimeToSampleTable and figure out
  // which frames map to which samples.
  
  uint32_t sample_index = 0;
  uint32_t frame_index = 0;
  uint32_t start_time = 0;
  
  for (int i = 0; i < movData->timeToSampleTableNumEntries; i++) {
    uint32_t sampleCount = *(TimeToSampleTable + (i*2+0));
    uint32_t sampleDuration = *(TimeToSampleTable + (i*2+1));
    
#ifdef DUMP_WHILE_PARSING
    fprintf(stdout, "TimeToSampleTable[%d] = (%d %d)\n", i, (int)sampleCount, (int)sampleDuration);
#endif
    
    for ( ; sampleCount > 0 ; sampleCount--) {
      uint32_t sample_start_time = start_time;
      uint32_t sample_end_time = sample_start_time + sampleDuration;
      
      assert(sample_index < movData->numSamples);
      MovSample *samplePtr = &movData->samples[sample_index];
      
      while (1) {
        uint32_t frame_start_time = frame_index * smallest_duration;
        assert(frame_start_time >= sample_start_time); // always increasing
        
        if (frame_start_time < sample_end_time) {
          // Frame is contained within this sample time
          
#ifdef DUMP_WHILE_PARSING
          fprintf(stdout, "frame %d at sample %d time %f is in sample %d window [%d, %d] [%f, %f]\n",
                  frame_index, frame_start_time, ((float)frame_start_time) / movData->timeScale, sample_index,
                  sample_start_time, sample_end_time,
                  ((float)sample_start_time) / movData->timeScale, ((float)sample_end_time) / movData->timeScale);              
#endif
          
          assert(frame_index < movData->numFrames);
          movData->frames[frame_index] = samplePtr;
          frame_index++;
          if (frame_index >= movData->numFrames) {
            break;
          }
        } else {
          // Frame is larger than or equal to the sample_end_time
          
#ifdef DUMP_WHILE_PARSING
          fprintf(stdout, "frame %d at sample %d time %f is larger than sample %d window [%d, %d] [%f, %f]\n",
                  frame_index, frame_start_time, ((float)frame_start_time) / movData->timeScale, sample_index,
                  sample_start_time, sample_end_time,
                  ((float)sample_start_time) / movData->timeScale, ((float)sample_end_time) / movData->timeScale);              
#endif
          
          break;
        }
      }
      
      start_time = sample_end_time;
      sample_index++;
    }
  }
  
  assert(movData->numSamples);
  assert(movData->numFrames);
  
  // Update the sample size field by reading the entries in the sample size table stsz.
  // In the easy case, all the samples are the same size. Also handle the case of
  // all the frames being key frames while iterating over all the samples.
  
  assert(movData->sampleSizeTableOffset > 0);
  seek_result = fseek(movFile, movData->sampleSizeTableOffset, SEEK_SET);
  if (seek_result != 0) {
    movData->errCode = ERR_READ;
    snprintf(movData->errMsg, sizeof(movData->errMsg), "seek error for stsz table offset");
    goto reterr;    
  }
  
  for (int i=0; i < movData->numSamples; i++) {
    MovSample *samplePtr = &movData->samples[i];
    uint32_t sample_size = 0;
    
    if (movData->sampleSizeCommon == 0) {
      // Set the sample size to the value in the table
      
      if (read_be_uint32(movFile, &sample_size) != 0) {
        movData->errCode = ERR_READ;
        snprintf(movData->errMsg, sizeof(movData->errMsg), "read error for stsz table sample size");
        goto reterr;
      }
    } else {
      sample_size = movData->sampleSizeCommon;
    }
    
    assert(sample_size > 0);
    assert(samplePtr->lengthAndFlags == 0);
    assert((sample_size & 0xFFFFFF) == sample_size); // sample length must fit in 24 bit value
    samplePtr->lengthAndFlags = sample_size;
    if (sample_size > movData->maxSampleSize) {
      movData->maxSampleSize = sample_size;
    }
    if (!movData->foundSTSS) {
      movsample_setkeyframe(samplePtr);
    }
  }
  
#ifdef DUMP_WHILE_PARSING
  fprintf(stdout, "post length and isKeyframe read\n");
            
  for (int i = 0; i < movData->numSamples; i++) {
    MovSample *samplePtr = &movData->samples[i];
    
    fprintf(stdout, "movData->samples[%d] offset %d, length %d, isKeyFrame %d\n", i,
            samplePtr->offset, movsample_length(samplePtr), movsample_iskeyframe(samplePtr));
  }
#endif  
  
  // Determine the number of samples that each chunk contains. All the chunks
  // could contain the same number of samples in the case where there is only
  // a single entry in the table. Otherwise, search the sample to chunk chunk table.
  
  assert(movData->sampleToChunkTableOffset > 0);
  seek_result = fseek(movFile, movData->sampleToChunkTableOffset, SEEK_SET);
  if (seek_result != 0) {
    movData->errCode = ERR_READ;
    snprintf(movData->errMsg, sizeof(movData->errMsg), "seek error for stsc table offset");
    goto reterr;
  }  
  
  sample_index = 0;
  uint32_t all_chunks_same_size = 0;
  uint32_t samples_per_chunk = 0;
  
  SampleToChunkTableEntry currentEntry;
  SampleToChunkTableEntry nextEntry;
  int sampleToChunkTableNumEntriesRemaining = movData->sampleToChunkTableNumEntries;
  
  if (SampleToChunkTableEntry_read(movFile, movData, &currentEntry) != 0) {
    goto reterr;
  }
  sampleToChunkTableNumEntriesRemaining--;

  if (movData->sampleToChunkTableNumEntries == 1) {
    all_chunks_same_size = 1;
    samples_per_chunk = currentEntry.samples_per_chunk;
  } else {
    // Read the next entry also
    if (SampleToChunkTableEntry_read(movFile, movData, &nextEntry) != 0) {
      goto reterr;
    }
    sampleToChunkTableNumEntriesRemaining--;
  }
    
  for (int chunk_index = 0; chunk_index < numChunks; chunk_index++) {
    MovChunk *movChunk = &chunks[chunk_index];
    
    if (!all_chunks_same_size) {
      // If this chunk index is less than the next one, use the current samples per chunk,
      // otherwise advance to the next row in the table.
      
      int chunk_id = chunk_index + 1;
      
#ifdef DUMP_WHILE_PARSING
      fprintf(stdout, "comparing current chunk id %d to next chunk id %d\n",
              chunk_id, nextEntry.first_chunk_id);
#endif // DUMP_WHILE_PARSING
      
      if (chunk_id >= nextEntry.first_chunk_id) {
        currentEntry.first_chunk_id = nextEntry.first_chunk_id;
        currentEntry.samples_per_chunk = nextEntry.samples_per_chunk;
        if (sampleToChunkTableNumEntriesRemaining > 0) {
          if (SampleToChunkTableEntry_read(movFile, movData, &nextEntry) != 0) {
            goto reterr;
          }
          sampleToChunkTableNumEntriesRemaining--;
        }
      }
      samples_per_chunk = currentEntry.samples_per_chunk;
      
#ifdef DUMP_WHILE_PARSING
      fprintf(stdout, "chunk id %d maps to samples_per_chunk %d\n", chunk_id, samples_per_chunk);
#endif // DUMP_WHILE_PARSING
    }
        
    assert(samples_per_chunk != 0);
    movChunk->numSamples = samples_per_chunk;
    
    assert(movChunk->samples == NULL);
    movChunk->samples = malloc(sizeof(MovSample*) * movChunk->numSamples);
    bzero(movChunk->samples, sizeof(MovSample*) * movChunk->numSamples);
    
    // for each sample contained in this chunk, copy the sample pointer
    // into the chunk samples array.
    
    for (int i = 0; i < movChunk->numSamples; i++) {
      assert(sample_index < movData->numSamples);
      MovSample *movSample = &movData->samples[sample_index];
      sample_index++;
      movChunk->samples[i] = movSample;
    }
    
    // Use the sample lengths to calculate the file offsets for
    // each sample in this chunk.
    
    assert(movChunk->offset);
    for (int i = 0; i < movChunk->numSamples; i++) {
      MovSample *movSample = movChunk->samples[i];
      
      assert(movSample->offset == 0);
      uint32_t offsetFromChunk = 0;
      for (int j=0; j < i; j++) {
        MovSample *prevMovSampleInChunk = movChunk->samples[j];
        assert(prevMovSampleInChunk != movSample);
        uint32_t length = movsample_length(prevMovSampleInChunk);
        assert(length > 0);
        offsetFromChunk += length;
      }
      movSample->offset = movChunk->offset + offsetFromChunk;
      assert(movSample->offset != 0);
    }
  }
  
#ifdef DUMP_WHILE_PARSING
  fprintf(stdout, "post offset update\n");
  
  for (int i = 0; i < movData->numSamples; i++) {
    MovSample *samplePtr = &movData->samples[i];
    
    fprintf(stdout, "movData->samples[%d] offset %d, length %d, isKeyFrame %d\n", i,
            samplePtr->offset, movsample_length(samplePtr), movsample_iskeyframe(samplePtr));
  }
#endif  
  
  // Optional Sync sample table
  
  if (movData->foundSTSS) {
    assert(movData->syncSampleTableOffset > 0);
    seek_result = fseek(movFile, movData->syncSampleTableOffset, SEEK_SET);
    if (seek_result != 0) {
      movData->errCode = ERR_READ;
      snprintf(movData->errMsg, sizeof(movData->errMsg), "seek error for stss table offset");
      goto reterr;    
    }  
    
    for (int i = 0; i < movData->syncSampleTableNumEntries; i++) {
      uint32_t key_frame;
      
      if (read_be_uint32(movFile, &key_frame) != 0) {
        movData->errCode = ERR_READ;
        snprintf(movData->errMsg, sizeof(movData->errMsg), "read error for stss key frame");
        goto reterr;
      }
      
      uint32_t sample_index = key_frame - 1;
      assert(sample_index < movData->numSamples);
      MovSample *samplePtr = &movData->samples[sample_index];
      movsample_setkeyframe(samplePtr);
    }    
  }
  
#ifdef DUMP_WHILE_PARSING
  fprintf(stdout, "finished isKeyframe\n");
  
  for (int i = 0; i < movData->numSamples; i++) {
    MovSample *samplePtr = &movData->samples[i];
    
    fprintf(stdout, "movData->samples[%d] offset %d, length %d, isKeyFrame %d\n", i,
            samplePtr->offset, movsample_length(samplePtr), movsample_iskeyframe(samplePtr));
  }
  
  for (int i = 0; i < movData->numFrames; i++) {
    MovSample *samplePtr = movData->frames[i];
    
    fprintf(stdout, "movData->frames[%d] offset %d, length %d, isKeyFrame %d\n", i,
            samplePtr->offset, movsample_length(samplePtr), movsample_iskeyframe(samplePtr));
  }      
#endif
  
  status = 0;
  
reterr:
  // cleanup dynamic memory on successful or fail return
  
  if (chunks) {
    for (int i=0; i < numChunks; i++) {
      MovChunk *movChunk = &chunks[i];
      movchunk_free(movChunk);
    }
    free(chunks);
  }
  if (TimeToSampleTable) {
    free(TimeToSampleTable);
  }
  
  return status;
}

// Read a big endian uint16_t from a char* and store in result.

#define READ_UINT16(result, ptr) \
{ \
uint8_t b1 = *ptr++; \
uint8_t b2 = *ptr++; \
result = (b1 << 8) | b2; \
}

// Read a big endian uint24_t from a char* and store in result (ARGB) with no alpha.

#define READ_UINT24(result, ptr) \
{ \
uint8_t b1 = *ptr++; \
uint8_t b2 = *ptr++; \
uint8_t b3 = *ptr++; \
result = (b1 << 16) | (b2 << 8) | b3; \
}

// Read a big endian uint32_t from a char* and store in result (ARGB).
// Each pixel needs to be multiplied by the alpha channel value.
// Optimized premultiplication implementation using table lookups

#define TABLEMAX 256
//#define TABLEDUMP

static
uint8_t alphaTables[TABLEMAX*TABLEMAX];
static
int alphaTablesInitialized = 0;

#define READ_AND_PREMULTIPLY(result, ptr) \
{ \
uint8_t alpha = *ptr++; \
uint8_t red = *ptr++; \
uint8_t green = *ptr++; \
uint8_t blue = *ptr++; \
uint8_t * restrict alphaTable = &alphaTables[alpha * TABLEMAX]; \
result = (alpha << 24) | (alphaTable[red] << 16) | (alphaTable[green] << 8) | alphaTable[blue]; \
}

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
      uint32_t in_pixel = (in_alpha << 24) | (in_red << 16) | (in_green << 8) | in_blue;
      uint32_t in_pixel_be = htonl(in_pixel); // pixel in BE byte order
      uint32_t premult_pixel_le;
      char *inPixelPtr = (char*) &in_pixel_be;
      READ_AND_PREMULTIPLY(premult_pixel_le, inPixelPtr);
      
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
      uint32_t expected_pixel_le = (round_alpha << 24) | (round_red << 16) | (round_green << 8) | round_blue;
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

/*

// This is the old floating point multiplicaiton impl
 
static inline
uint32_t
read_ARGB_and_premultiply(const char *ptr) {
  uint8_t alpha = *ptr++;
  uint8_t red = *ptr++;
  uint8_t green = *ptr++;
  uint8_t blue = *ptr++;
  uint32_t pixel;

  if (0) {
    // Skip premultiplication, useful for debugging
  } else if (alpha == 0) {
    // Any pixel that is fully transparent can be represented by zero (bzero is fast)
    return 0;
  } else if (alpha == 0xFF) {
    // Any pixel that is fully opaque need not be multiplied by 1.0
  } else {
    float alphaf = alpha / 255.0;
    red = (int) (red * alphaf + 0.5);
    green = (int) (green * alphaf + 0.5);
    blue = (int) (blue * alphaf + 0.5);
  }
  pixel = (alpha << 24) | (red << 16) | (green << 8) | blue;
  return pixel;
}
 
*/

// 16 bit rgb555 pixels with no alpha channel
// Works for (RBG555, RGB5551, or RGB565) though only XRRRRRGGGGGBBBBB is supported.

static inline
void
decode_rle_sample16(
                  const void* restrict sampleBuffer,
                  int sampleBufferSize,
                  int isKeyFrame,
                  uint16_t* restrict frameBuffer,
                  int frameBufferWidth,
                  int frameBufferHeight)
{
  assert(sampleBuffer);
  assert(sampleBufferSize > 0);
  assert(frameBuffer);
  
  uint32_t bytesRemaining = sampleBufferSize;
  
  uint16_t* restrict rowPtr = NULL;
  uint16_t* restrict rowPtrMax = NULL;
  
  // Optionally use passed in buffer that is known to be large enough to hold the sample.
  
  const char* restrict samplePtr = sampleBuffer;
  
  if (1) {
    // http://wiki.multimedia.cx/index.php?title=Apple_QuickTime_RLE
    //
    // sample size : 4 bytes
    // header : 2 bytes
    // optional : 8 bytes
    //  starting line at which to begin updating frame : 2 bytes
    //  unknown : 2 bytes
    //  the number of lines to update : 2 bytes
    //  unknown    
    // compressed lines : ?
    
    // Dump the bytes that remain at this point in the sample reading process.
    
#ifdef DUMP_WHILE_DECODING
    if (1) {
      fprintf(stdout, "sample bytes dump : bytesRemaining %d, sample length %d\n", bytesRemaining, sampleBufferSize);
      for (int i = 0; i < bytesRemaining; i++ ) {
        uint8_t b = *(samplePtr + i);
        fprintf(stdout, "0x%X ", b);
      }
      fprintf(stdout, "\n");
      
      uint32_t size = byte_read_be_uint32(samplePtr);
      uint32_t size_m24 = byte_read_be_uint32(samplePtr) & 0xFFFFFF;
      uint32_t flags = (byte_read_be_uint32(samplePtr) >> 24) & 0xFF;
      fprintf(stdout, "sample size : flags %d, size %d, size mask24 %d\n", flags, size, size_m24);
      for (int i = 0; i < 4; i++ ) {
        uint8_t b = *(samplePtr + i);
        fprintf(stdout, "0x%X ", b);
      }
      fprintf(stdout, "\n");
      
      uint16_t header = byte_read_be_uint16(samplePtr + 4);
      fprintf(stdout, "header %d\n", header);
      for (int i = 4; i < 6; i++ ) {
        uint8_t b = *(samplePtr + i);
        fprintf(stdout, "0x%X ", b);
      }
      fprintf(stdout, "\n");
      
      if (header == 0) {
        // No optional 8 bytes
        fprintf(stdout, "no optional line info\n");
      } else {
        fprintf(stdout, "optional line info\n");
        for (int i = 6; i < 6+8; i++ ) {
          uint8_t b = *(samplePtr + i);
          fprintf(stdout, "0x%X ", b);
        }
        fprintf(stdout, "\n");        
      }
      
      uint8_t skip_code = *(samplePtr + 6 + 8);
      fprintf(stdout, "skip code 0x%X = %d\n", skip_code, skip_code);
    }
#endif // DUMP_WHILE_DECODING
    
    // Skip sample size, this field looks like a 1 byte flags value and then a 24 bit length
    // value (size & 0xFFFFFF) results in a correct 24 bit length. The flag element seems to
    // be 0x1 when set. But, this field is undocumented and can be safely skipped because
    // the sample length is already known.
    
    assert(bytesRemaining >= 4);
    samplePtr += 4;
    bytesRemaining -= 4;
    
    assert(bytesRemaining >= 2);
    uint16_t header;
    READ_UINT16(header, samplePtr);
    bytesRemaining -= 2;
    
    assert(header == 0x0 || header == 0x0008);
    
    int16_t starting_line, lines_to_update;
    
    if (header != 0) {
      // Frame delta
      
      assert(bytesRemaining >= 8);
      
      READ_UINT16(starting_line, samplePtr);
      bytesRemaining -= 2;
      
      // skip 2 unknown bytes
      samplePtr += 2;
      bytesRemaining -= 2;
      
      READ_UINT16(lines_to_update, samplePtr);
      bytesRemaining -= 2;
      
      // skip 2 unknown bytes
      samplePtr += 2;
      bytesRemaining -= 2;
    } else {
      // Keyframe
      
      starting_line = 0;
      lines_to_update = frameBufferHeight;
    }
    assert(lines_to_update > 0);
    
#ifdef DUMP_WHILE_DECODING
    if (isKeyFrame) {
      fprintf(stdout, "key frame!\n");
    } else {
      fprintf(stdout, "starting line %d\n", starting_line);
      fprintf(stdout, "lines to update %d\n", lines_to_update);
    }
#endif // DUMP_WHILE_DECODING
    
    // Get a pointer to the start of a row in the framebuffer based on the starting_line
    
    uint32_t current_line = starting_line;
    assert(current_line < frameBufferHeight);
    
    rowPtr = frameBuffer + (current_line * frameBufferWidth);
    rowPtrMax = rowPtr + frameBufferWidth;
    
    // Increment the input/output line after seeing a -1 skip byte
    
    uint32_t incr_current_line = 0;
    
    while (1) {
#ifdef DUMP_WHILE_DECODING
      if (1) {
        fprintf(stdout, "skip code bytes dump : bytesRemaining %d, sample length %d\n", bytesRemaining, sampleBufferSize);
        for (int i = 0; i < bytesRemaining; i++ ) {
          uint8_t b = *(samplePtr + i);
          fprintf(stdout, "0x%X ", b);
        }
        fprintf(stdout, "\n");
      }
#endif // DUMP_WHILE_DECODING
      
      // Skip code
      
      assert(bytesRemaining >= 1);
      uint8_t skip_code = *samplePtr++;
      bytesRemaining--;
      
      if (skip_code == 0) {
        // Done decoding all lines in this frame
        // a zero skip code should only be found at the end of the sample
        assert(bytesRemaining == 0);
        break;
      }
      
      // Increment the current line once we know that another line
      // will be written (skip code is non-zero). This is useful
      // here since we don't want the row pointer to ever point past
      // the number of valid rows.
      
      if (incr_current_line) {
        incr_current_line = 0;
        current_line++;
        
        assert(current_line < frameBufferHeight);
        
        rowPtr = frameBuffer + (current_line * frameBufferWidth);
        rowPtrMax = rowPtr + frameBufferWidth;
      }
      
      uint8_t num_to_skip = skip_code - 1;
      
      if (num_to_skip > 0) {
#ifdef DUMP_WHILE_DECODING
        fprintf(stdout, "skip %d pixels\n", num_to_skip);
#endif // DUMP_WHILE_DECODING
        
        // Advance the row ptr by skip pixels checking that it does
        // not skip past the end of the row.
        
        assert((rowPtr + num_to_skip) < rowPtrMax);          
        rowPtr += num_to_skip;
      }
      
      while (1) {
        // RLE code (signed)
        
        assert(bytesRemaining >= 1);
        int8_t rle_code = *samplePtr++;
        bytesRemaining--;
        
        if (rle_code == 0) {
          // There is another skip code ahead in the stream, continue with next skip code
#ifdef DUMP_WHILE_DECODING
          fprintf(stdout, "rle_code == 0x0 (0) found to indicate another skip code\n");
#endif // DUMP_WHILE_DECODING
          break;
        } else if (rle_code == -1) {
          // When a RLE line is finished decoding, increment the current line row ptr.
          // Note that multiple -1 codes can be used to skip multiple unchanged lines.
          
#ifdef DUMP_WHILE_DECODING
          fprintf(stdout, "rle_code == 0xFF (-1) found to indicate end of RLE line %d\n", current_line);
#endif // DUMP_WHILE_DECODING
          
          incr_current_line = 1;
          
          break;
        } else if (rle_code < -1) {
          // Read pixel value and repeat it -rle_code times in the frame buffer
          
          uint32_t numTimesToRepeat = -rle_code;
          
          // 16 bit pixels : rgb555 or rgb565
            
          assert(bytesRemaining >= 2);
          uint16_t pixel;
          READ_UINT16(pixel, samplePtr);
          bytesRemaining -= 2;
          
#ifdef DUMP_WHILE_DECODING
          fprintf(stdout, "repeat 16 bit pixel 0x%X %d times\n", pixel, numTimesToRepeat);
#endif // DUMP_WHILE_DECODING
          
          assert((rowPtr + numTimesToRepeat - 1) < rowPtrMax);
          
          if (pixel == 0x0) {
            bzero(rowPtr, numTimesToRepeat * sizeof(uint16_t));
            rowPtr += numTimesToRepeat;
          } else {
            for (int i = 0; i < numTimesToRepeat; i++) {
              *rowPtr++ = pixel;
            }
          }
          
        } else {
          // Greater than 0, copy pixels from input to output stream
          assert(rle_code > 0);
          
          // 16 bit pixels
          
          uint32_t numBytesToCopy = sizeof(uint16_t) * rle_code;
            
          assert(bytesRemaining >= numBytesToCopy);
          
          bytesRemaining -= numBytesToCopy;
          
          assert((rowPtr + rle_code - 1) < rowPtrMax);
            
          for (int i = 0; i < rle_code; i++) {
            uint16_t pixel;
            READ_UINT16(pixel, samplePtr);
            
#ifdef DUMP_WHILE_DECODING
            fprintf(stdout, "copy 16 bit pixel 0x%X to dest\n", pixel);
#endif // DUMP_WHILE_DECODING
            
            *rowPtr++ = pixel;
          }

        }        
      }
    }
  }
  
  return;
}

// 24 bit RGB pixels with no alpha channel

static inline
void
decode_rle_sample24(
                    const void* restrict sampleBuffer,
                    int sampleBufferSize,
                    int isKeyFrame,
                    uint32_t* restrict frameBuffer,
                    int frameBufferWidth,
                    int frameBufferHeight)
{
  assert(sampleBuffer);
  assert(sampleBufferSize > 0);
  assert(frameBuffer);
  
  uint32_t bytesRemaining = sampleBufferSize;
  
  uint32_t* restrict rowPtr = NULL;
  uint32_t* restrict rowPtrMax = NULL;
  
  // Optionally use passed in buffer that is known to be large enough to hold the sample.
  
  const char* restrict samplePtr = sampleBuffer;
  
  if (1) {
    // http://wiki.multimedia.cx/index.php?title=Apple_QuickTime_RLE
    //
    // sample size : 4 bytes
    // header : 2 bytes
    // optional : 8 bytes
    //  starting line at which to begin updating frame : 2 bytes
    //  unknown : 2 bytes
    //  the number of lines to update : 2 bytes
    //  unknown    
    // compressed lines : ?
    
    // Dump the bytes that remain at this point in the sample reading process.
    
#ifdef DUMP_WHILE_DECODING
    if (1) {
      fprintf(stdout, "sample bytes dump : bytesRemaining %d, sample length %d\n", bytesRemaining, sampleBufferSize);
      for (int i = 0; i < bytesRemaining; i++ ) {
        uint8_t b = *(samplePtr + i);
        fprintf(stdout, "0x%X ", b);
      }
      fprintf(stdout, "\n");
      
      uint32_t size = byte_read_be_uint32(samplePtr);
      uint32_t size_m24 = byte_read_be_uint32(samplePtr) & 0xFFFFFF;
      uint32_t flags = (byte_read_be_uint32(samplePtr) >> 24) & 0xFF;
      fprintf(stdout, "sample size : flags %d, size %d, size mask24 %d\n", flags, size, size_m24);
      for (int i = 0; i < 4; i++ ) {
        uint8_t b = *(samplePtr + i);
        fprintf(stdout, "0x%X ", b);
      }
      fprintf(stdout, "\n");
      
      uint16_t header = byte_read_be_uint16(samplePtr + 4);
      fprintf(stdout, "header %d\n", header);
      for (int i = 4; i < 6; i++ ) {
        uint8_t b = *(samplePtr + i);
        fprintf(stdout, "0x%X ", b);
      }
      fprintf(stdout, "\n");
      
      if (header == 0) {
        // No optional 8 bytes
        fprintf(stdout, "no optional line info\n");
      } else {
        fprintf(stdout, "optional line info\n");
        for (int i = 6; i < 6+8; i++ ) {
          uint8_t b = *(samplePtr + i);
          fprintf(stdout, "0x%X ", b);
        }
        fprintf(stdout, "\n");        
      }
      
      uint8_t skip_code = *(samplePtr + 6 + 8);
      fprintf(stdout, "skip code 0x%X = %d\n", skip_code, skip_code);
    }
#endif // DUMP_WHILE_DECODING
    
    // Skip sample size, this field looks like a 1 byte flags value and then a 24 bit length
    // value (size & 0xFFFFFF) results in a correct 24 bit length. The flag element seems to
    // be 0x1 when set. But, this field is undocumented and can be safely skipped because
    // the sample length is already known.
    
    assert(bytesRemaining >= 4);
    samplePtr += 4;
    bytesRemaining -= 4;
    
    assert(bytesRemaining >= 2);
    uint16_t header;
    READ_UINT16(header, samplePtr);
    bytesRemaining -= 2;
    
    assert(header == 0x0 || header == 0x0008);
    
    int16_t starting_line, lines_to_update;
    
    if (header != 0) {
      // Frame delta
      
      assert(bytesRemaining >= 8);
      
      READ_UINT16(starting_line, samplePtr);
      bytesRemaining -= 2;
      
      // skip 2 unknown bytes
      samplePtr += 2;
      bytesRemaining -= 2;
      
      READ_UINT16(lines_to_update, samplePtr);
      bytesRemaining -= 2;
      
      // skip 2 unknown bytes
      samplePtr += 2;
      bytesRemaining -= 2;
    } else {
      // Keyframe
      
      starting_line = 0;
      lines_to_update = frameBufferHeight;
    }
    assert(lines_to_update > 0);
    
#ifdef DUMP_WHILE_DECODING
    if (isKeyFrame) {
      fprintf(stdout, "key frame!\n");
    } else {
      fprintf(stdout, "starting line %d\n", starting_line);
      fprintf(stdout, "lines to update %d\n", lines_to_update);
    }
#endif // DUMP_WHILE_DECODING
    
    // Get a pointer to the start of a row in the framebuffer based on the starting_line
    
    uint32_t current_line = starting_line;
    assert(current_line < frameBufferHeight);
    
    rowPtr = frameBuffer + (current_line * frameBufferWidth);
    rowPtrMax = rowPtr + frameBufferWidth;
    
    // Increment the input/output line after seeing a -1 skip byte
    
    uint32_t incr_current_line = 0;
    
    while (1) {
#ifdef DUMP_WHILE_DECODING
      if (1) {
        fprintf(stdout, "skip code bytes dump : bytesRemaining %d, sample length %d\n", bytesRemaining, sampleBufferSize);
        for (int i = 0; i < bytesRemaining; i++ ) {
          uint8_t b = *(samplePtr + i);
          fprintf(stdout, "0x%X ", b);
        }
        fprintf(stdout, "\n");
      }
#endif // DUMP_WHILE_DECODING
      
      // Skip code
      
      assert(bytesRemaining >= 1);
      uint8_t skip_code = *samplePtr++;
      bytesRemaining--;
      
      if (skip_code == 0) {
        // Done decoding all lines in this frame
        // a zero skip code should only be found at the end of the sample
        assert(bytesRemaining == 0);
        break;
      }
      
      // Increment the current line once we know that another line
      // will be written (skip code is non-zero). This is useful
      // here since we don't want the row pointer to ever point past
      // the number of valid rows.
      
      if (incr_current_line) {
        incr_current_line = 0;
        current_line++;
        
        assert(current_line < frameBufferHeight);
        
        rowPtr = frameBuffer + (current_line * frameBufferWidth);
        rowPtrMax = rowPtr + frameBufferWidth;
      }
      
      uint8_t num_to_skip = skip_code - 1;
      
      if (num_to_skip > 0) {
#ifdef DUMP_WHILE_DECODING
        fprintf(stdout, "skip %d pixels\n", num_to_skip);
#endif // DUMP_WHILE_DECODING
        
        // Advance the row ptr by skip pixels checking that it does
        // not skip past the end of the row.
        
        assert((rowPtr + num_to_skip) < rowPtrMax);          
        rowPtr += num_to_skip;
      }
      
      while (1) {
        // RLE code (signed)
        
        assert(bytesRemaining >= 1);
        int8_t rle_code = *samplePtr++;
        bytesRemaining--;
        
        if (rle_code == 0) {
          // There is another skip code ahead in the stream, continue with next skip code
#ifdef DUMP_WHILE_DECODING
          fprintf(stdout, "rle_code == 0x0 (0) found to indicate another skip code\n");
#endif // DUMP_WHILE_DECODING
          break;
        } else if (rle_code == -1) {
          // When a RLE line is finished decoding, increment the current line row ptr.
          // Note that multiple -1 codes can be used to skip multiple unchanged lines.
          
#ifdef DUMP_WHILE_DECODING
          fprintf(stdout, "rle_code == 0xFF (-1) found to indicate end of RLE line %d\n", current_line);
#endif // DUMP_WHILE_DECODING
          
          incr_current_line = 1;
          
          break;
        } else if (rle_code < -1) {
          // Read pixel value and repeat it -rle_code times in the frame buffer
          
          uint32_t numTimesToRepeat = -rle_code;
          
          // 24 bit pixels : RGB
          // write 32 bit pixels : ARGB
          
          assert(bytesRemaining >= 3);
          uint32_t pixel;
          READ_UINT24(pixel, samplePtr);
          bytesRemaining -= 3;
          
#ifdef DUMP_WHILE_DECODING
          fprintf(stdout, "repeat 24 bit pixel 0x%X %d times\n", pixel, numTimesToRepeat);
#endif // DUMP_WHILE_DECODING
          
          assert((rowPtr + numTimesToRepeat - 1) < rowPtrMax);
          
          if (pixel == 0x0) {
            bzero(rowPtr, numTimesToRepeat * sizeof(uint32_t));
            rowPtr += numTimesToRepeat;
          } else {
            for (int i = 0; i < numTimesToRepeat; i++) {
              *rowPtr++ = pixel;
            }
          }
          
        } else {
          // Greater than 0, copy pixels from input to output stream
          assert(rle_code > 0);
          
          // 24 bit pixels : RGB
          // write 32 bit pixels : ARGB
          
          uint32_t numBytesToCopy = 3 * rle_code;
          
          assert(bytesRemaining >= numBytesToCopy);
          
          bytesRemaining -= numBytesToCopy;
          
          assert((rowPtr + rle_code - 1) < rowPtrMax);
          
          for (int i = 0; i < rle_code; i++) {
            uint32_t pixel;
            READ_UINT24(pixel, samplePtr);
            
#ifdef DUMP_WHILE_DECODING
            fprintf(stdout, "copy 24 bit pixel 0x%X to dest\n", pixel);
#endif // DUMP_WHILE_DECODING
            
            *rowPtr++ = pixel;
          }
          
        }        
      }
    }
  }
  
  return;
}

// 32 bit ARGB pixels, always straight alpha

static inline
void
decode_rle_sample32(
                    const void* restrict sampleBuffer,
                    int sampleBufferSize,
                    int isKeyFrame,
                    uint32_t* restrict frameBuffer,
                    int frameBufferWidth,
                    int frameBufferHeight)
{
  assert(sampleBuffer);
  assert(sampleBufferSize > 0);
  assert(frameBuffer);
  
  uint32_t bytesRemaining = sampleBufferSize;
  
  uint32_t* restrict rowPtr = NULL;
  uint32_t* restrict rowPtrMax = NULL;
  
  // Optionally use passed in buffer that is known to be large enough to hold the sample.
  
  const char* restrict samplePtr = sampleBuffer;
  
  if (1) {
    // http://wiki.multimedia.cx/index.php?title=Apple_QuickTime_RLE
    //
    // sample size : 4 bytes
    // header : 2 bytes
    // optional : 8 bytes
    //  starting line at which to begin updating frame : 2 bytes
    //  unknown : 2 bytes
    //  the number of lines to update : 2 bytes
    //  unknown    
    // compressed lines : ?
    
    // Dump the bytes that remain at this point in the sample reading process.
    
#ifdef DUMP_WHILE_DECODING
    if (1) {
      fprintf(stdout, "sample bytes dump : bytesRemaining %d, sample length %d\n", bytesRemaining, sampleBufferSize);
      for (int i = 0; i < bytesRemaining; i++ ) {
        uint8_t b = *(samplePtr + i);
        fprintf(stdout, "0x%X ", b);
      }
      fprintf(stdout, "\n");
      
      uint32_t size = byte_read_be_uint32(samplePtr);
      uint32_t size_m24 = byte_read_be_uint32(samplePtr) & 0xFFFFFF;
      uint32_t flags = (byte_read_be_uint32(samplePtr) >> 24) & 0xFF;
      fprintf(stdout, "sample size : flags %d, size %d, size mask24 %d\n", flags, size, size_m24);
      for (int i = 0; i < 4; i++ ) {
        uint8_t b = *(samplePtr + i);
        fprintf(stdout, "0x%X ", b);
      }
      fprintf(stdout, "\n");
      
      uint16_t header = byte_read_be_uint16(samplePtr + 4);
      fprintf(stdout, "header %d\n", header);
      for (int i = 4; i < 6; i++ ) {
        uint8_t b = *(samplePtr + i);
        fprintf(stdout, "0x%X ", b);
      }
      fprintf(stdout, "\n");
      
      if (header == 0) {
        // No optional 8 bytes
        fprintf(stdout, "no optional line info\n");
      } else {
        fprintf(stdout, "optional line info\n");
        for (int i = 6; i < 6+8; i++ ) {
          uint8_t b = *(samplePtr + i);
          fprintf(stdout, "0x%X ", b);
        }
        fprintf(stdout, "\n");        
      }
      
      uint8_t skip_code = *(samplePtr + 6 + 8);
      fprintf(stdout, "skip code 0x%X = %d\n", skip_code, skip_code);
    }
#endif // DUMP_WHILE_DECODING
    
    // Skip sample size, this field looks like a 1 byte flags value and then a 24 bit length
    // value (size & 0xFFFFFF) results in a correct 24 bit length. The flag element seems to
    // be 0x1 when set. But, this field is undocumented and can be safely skipped because
    // the sample length is already known.
    
    assert(bytesRemaining >= 4);
    samplePtr += 4;
    bytesRemaining -= 4;
    
    assert(bytesRemaining >= 2);
    uint16_t header;
    READ_UINT16(header, samplePtr);
    bytesRemaining -= 2;
    
    assert(header == 0x0 || header == 0x0008);
    
    int16_t starting_line, lines_to_update;
    
    if (header != 0) {
      // Frame delta
      
      assert(bytesRemaining >= 8);
      
      READ_UINT16(starting_line, samplePtr);
      bytesRemaining -= 2;
      
      // skip 2 unknown bytes
      samplePtr += 2;
      bytesRemaining -= 2;
      
      READ_UINT16(lines_to_update, samplePtr);
      bytesRemaining -= 2;
      
      // skip 2 unknown bytes
      samplePtr += 2;
      bytesRemaining -= 2;
    } else {
      // Keyframe
      
      starting_line = 0;
      lines_to_update = frameBufferHeight;
    }
    assert(lines_to_update > 0);
    
#ifdef DUMP_WHILE_DECODING
    if (isKeyFrame) {
      fprintf(stdout, "key frame!\n");
    } else {
      fprintf(stdout, "starting line %d\n", starting_line);
      fprintf(stdout, "lines to update %d\n", lines_to_update);
    }
#endif // DUMP_WHILE_DECODING
    
    // Get a pointer to the start of a row in the framebuffer based on the starting_line
    
    uint32_t current_line = starting_line;
    assert(current_line < frameBufferHeight);
    
    rowPtr = frameBuffer + (current_line * frameBufferWidth);
    rowPtrMax = rowPtr + frameBufferWidth;
    
    // Increment the input/output line after seeing a -1 skip byte
    
    uint32_t incr_current_line = 0;
    
    while (1) {
#ifdef DUMP_WHILE_DECODING
      if (1) {
        fprintf(stdout, "skip code bytes dump : bytesRemaining %d, sample length %d\n", bytesRemaining, sampleBufferSize);
        for (int i = 0; i < bytesRemaining; i++ ) {
          uint8_t b = *(samplePtr + i);
          fprintf(stdout, "0x%X ", b);
        }
        fprintf(stdout, "\n");
      }
#endif // DUMP_WHILE_DECODING
      
      // Skip code
      
      assert(bytesRemaining >= 1);
      uint8_t skip_code = *samplePtr++;
      bytesRemaining--;
      
      if (skip_code == 0) {
        // Done decoding all lines in this frame
        // a zero skip code should only be found at the end of the sample
        assert(bytesRemaining == 0);
        break;
      }
      
      // Increment the current line once we know that another line
      // will be written (skip code is non-zero). This is useful
      // here since we don't want the row pointer to ever point past
      // the number of valid rows.
      
      if (incr_current_line) {
        incr_current_line = 0;
        current_line++;
        
        assert(current_line < frameBufferHeight);
        
        rowPtr = frameBuffer + (current_line * frameBufferWidth);
        rowPtrMax = rowPtr + frameBufferWidth;
      }
      
      uint8_t num_to_skip = skip_code - 1;
      
      if (num_to_skip > 0) {
#ifdef DUMP_WHILE_DECODING
        fprintf(stdout, "skip %d pixels\n", num_to_skip);
#endif // DUMP_WHILE_DECODING
        
        // Advance the row ptr by skip pixels checking that it does
        // not skip past the end of the row.
        
        assert((rowPtr + num_to_skip) < rowPtrMax);          
        rowPtr += num_to_skip;
      }
      
      while (1) {
        // RLE code (signed)
        
        assert(bytesRemaining >= 1);
        int8_t rle_code = *samplePtr++;
        bytesRemaining--;
        
        if (rle_code == 0) {
          // There is another skip code ahead in the stream, continue with next skip code
#ifdef DUMP_WHILE_DECODING
          fprintf(stdout, "rle_code == 0x0 (0) found to indicate another skip code\n");
#endif // DUMP_WHILE_DECODING
          break;
        } else if (rle_code == -1) {
          // When a RLE line is finished decoding, increment the current line row ptr.
          // Note that multiple -1 codes can be used to skip multiple unchanged lines.
          
#ifdef DUMP_WHILE_DECODING
          fprintf(stdout, "rle_code == 0xFF (-1) found to indicate end of RLE line %d\n", current_line);
#endif // DUMP_WHILE_DECODING
          
          incr_current_line = 1;
          
          break;
        } else if (rle_code < -1) {
          // Read pixel value and repeat it -rle_code times in the frame buffer
          
          uint32_t numTimesToRepeat = -rle_code;
          
          // 32 bit pixels : ARGB
          
          assert(bytesRemaining >= 4);
          uint32_t pixel;
          READ_AND_PREMULTIPLY(pixel, samplePtr);
          bytesRemaining -= 4;
          
#ifdef DUMP_WHILE_DECODING
          fprintf(stdout, "repeat 32 bit pixel 0x%X %d times\n", pixel, numTimesToRepeat);
#endif // DUMP_WHILE_DECODING          
          
          assert((rowPtr + numTimesToRepeat - 1) < rowPtrMax);
          
          if (pixel == 0x0) {
            bzero(rowPtr, numTimesToRepeat * sizeof(uint32_t));
            rowPtr += numTimesToRepeat;
          } else {
            for (int i = 0; i < numTimesToRepeat; i++) {
              *rowPtr++ = pixel;
            }
          }
          
        } else {
          // Greater than 0, copy pixels from input to output stream
          assert(rle_code > 0);
          
          // 32 bit pixels : ARGB
          
          uint32_t numBytesToCopy = 4 * rle_code;
          
          assert(bytesRemaining >= numBytesToCopy);
          
          bytesRemaining -= numBytesToCopy;
          
          assert((rowPtr + rle_code - 1) < rowPtrMax);
          
          for (int i = 0; i < rle_code; i++) {
            uint32_t pixel;
            READ_AND_PREMULTIPLY(pixel, samplePtr);
            
#ifdef DUMP_WHILE_DECODING
            fprintf(stdout, "copy 32 bit pixel 0x%X to dest\n", pixel);
#endif // DUMP_WHILE_DECODING
            
            *rowPtr++ = pixel;
          }
          
        }        
      }
    }
  }
  
  return;
}


// Read sample data from file and then process the RLE data at a specific file offset.
// Returns 0 on success, otherwise non-zero.
//
// Note that the type of frameBuffer you pass in (uint16_t* or uint32_t*) depends
// on the bit depth of the mov. If NULL is passed as frameBuffer, then a phony
// framebuffer will be allocated and then released.

int
read_process_rle_sample(FILE *movFile, MovData *movData, MovSample *sample, void *frameBuffer, const void *sampleBuffer, uint32_t sampleBufferSize)
{
  void* frameBufferPtr = NULL;
  const char *samplePtr = NULL;
  int status = 1;
  uint32_t bytesRemaining = movsample_length(sample);
  
  // Optionally use passed in buffer that is known to be large enough to hold the sample.

  if (sampleBuffer == NULL) {
    samplePtr = malloc(bytesRemaining);
    if (samplePtr == NULL) {
      movData->errCode = ERR_MALLOC_FAILED;
      snprintf(movData->errMsg, sizeof(movData->errMsg),
               "malloc of %d bytes failed for sample buffer", (int) bytesRemaining);
      goto retstatus;
    }
  } else {
    assert(sampleBufferSize >= bytesRemaining);
    samplePtr = sampleBuffer;
  }
  
  // User might have passed NULL as frameBuffer, but the decode logic needs a framebuffer to write to.
  
  if (frameBuffer == NULL) {
    int numBytesNeeded;
    if (movData->bitDepth == 16) {
      numBytesNeeded = sizeof(uint16_t) * movData->width * movData->height + ((movData->width * movData->height) % 2);
    } else if (movData->bitDepth == 24 || movData->bitDepth == 32) {
      numBytesNeeded = sizeof(uint32_t) * movData->width * movData->height + ((movData->width * movData->height) % 2);
    } else {
      assert(0);
    }
    frameBufferPtr = malloc(numBytesNeeded);
    if (frameBufferPtr == NULL) {
      movData->errCode = ERR_MALLOC_FAILED;
      snprintf(movData->errMsg, sizeof(movData->errMsg),
               "malloc of %d bytes failed for phony frame buffer", (int) bytesRemaining);
      goto retstatus;
    }
  } else {
    frameBufferPtr = frameBuffer;
  }
  
  // Move to the file offset where the sample data is located and then read the sample buffer
  assert(sample->offset > 0);
  int retval = fseek(movFile, sample->offset, SEEK_SET);
  assert(retval == 0);
  if (fread((char*)samplePtr, bytesRemaining, 1, movFile) != 1) {
    movData->errCode = ERR_READ;
    snprintf(movData->errMsg, sizeof(movData->errMsg),
             "read sample buffer of %d bytes failed", (int) bytesRemaining);
    goto retstatus;
  }
  
  switch (movData->bitDepth) {
    case 16:
      decode_rle_sample16(samplePtr, bytesRemaining, movsample_iskeyframe(sample), frameBufferPtr, movData->width, movData->height);
      break;
    case 24:
      decode_rle_sample24(samplePtr, bytesRemaining, movsample_iskeyframe(sample), frameBufferPtr, movData->width, movData->height);
      break;
    case 32:
      decode_rle_sample32(samplePtr, bytesRemaining, movsample_iskeyframe(sample), frameBufferPtr, movData->width, movData->height);
      break;
    default:
      assert(0);
  }
  
  status = 0;

retstatus:
  if (samplePtr && (sampleBuffer == NULL)) {
    free((void*)samplePtr);
  }
  if (frameBufferPtr && (frameBuffer == NULL)) {
    free((void*)frameBufferPtr);
  }  
  
  return status;
}

// Process sample data contained in an already memory mapped file. Unlike process_rle_sample above
// this method requires that frameBuffer is not NULL.
// Returns 0 on success, otherwise non-zero.
//
// Note that the type of frameBuffer you pass in (uint16_t* or uint32_t*) depends
// on the bit depth of the mov.

int
process_rle_sample(void *mappedFilePtr, MovData *movData, MovSample *sample, void *frameBuffer)
{
  const char *samplePtr = NULL;
  int status = 1;
  uint32_t bytesRemaining = movsample_length(sample);

  assert(mappedFilePtr);
  assert(frameBuffer);
  
  // Determine where the sample data starts in the mapped file

  assert(sample->offset > 0);
  samplePtr = ((char*)mappedFilePtr) + sample->offset;
  
  switch (movData->bitDepth) {
    case 16:
      decode_rle_sample16(samplePtr, bytesRemaining, movsample_iskeyframe(sample), frameBuffer, movData->width, movData->height);
      break;
    case 24:
      decode_rle_sample24(samplePtr, bytesRemaining, movsample_iskeyframe(sample), frameBuffer, movData->width, movData->height);
      break;
    case 32:
      decode_rle_sample32(samplePtr, bytesRemaining, movsample_iskeyframe(sample), frameBuffer, movData->width, movData->height);
      break;
    default:
      assert(0);
  }
  
  status = 0;
  
  return status;
}

// Decode just 1 sample contained in a buffer

void
exported_decode_rle_sample16(
                  void *sampleBuffer,
                  int sampleBufferSize,
                  int isKeyFrame,
                  void *frameBuffer,
                  int frameBufferWidth,
                  int frameBufferHeight)
{
  decode_rle_sample16(sampleBuffer, sampleBufferSize, isKeyFrame,
                           frameBuffer, frameBufferWidth, frameBufferHeight);
}
