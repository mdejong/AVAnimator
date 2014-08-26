/*
 * Copyright (c) 2009 Max Stepin
 * maxst at users.sourceforge.net
 *
 * zlib license
 * ------------
 *
 * This software is provided 'as-is', without any express or implied
 * warranty.  In no event will the authors be held liable for any damages
 * arising from the use of this software.
 *
 * Permission is granted to anyone to use this software for any purpose,
 * including commercial applications, and to alter it and redistribute it
 * freely, subject to the following restrictions:
 *
 * 1. The origin of this software must not be misrepresented; you must not
 *    claim that you wrote the original software. If you use this software
 *    in a product, an acknowledgment in the product documentation would be
 *    appreciated but is not required.
 * 2. Altered source versions must be plainly marked as such, and must not be
 *    misrepresented as being the original software.
 * 3. This notice may not be removed or altered from any source distribution.
 */

// This module exports an API that provides access to animated APNG frames. The frame data is decoded into
// a framebuffer by this library. After each frame has been decoded, a user provided callback is invoked
// to allow for processing of the decoded data in the framebuffer.

#include "libapng.h"

#if defined(_MSC_VER) && _MSC_VER >= 1300
#define swap16(data) _byteswap_ushort(data)
#define swap32(data) _byteswap_ulong(data)
#elif defined(__linux__)
#include <byteswap.h>
#define swap16(data) bswap_16(data)
#define swap32(data) bswap_32(data)
#elif defined(__FreeBSD__)
#include <sys/endian.h>
#define swap16(data) bswap16(data)
#define swap32(data) bswap32(data)
#elif defined(__APPLE__)
#include <libkern/OSByteOrder.h>
#define swap16(data) OSSwapInt16(data)
#define swap32(data) OSSwapInt32(data)
#else
static inline
unsigned short swap16(unsigned short data) {return((data & 0xFF) << 8) | ((data >> 8) & 0xFF);}
static inline
unsigned int swap32(unsigned int data) {return((data & 0xFF) << 24) | ((data & 0xFF00) << 8) | ((data >> 8) & 0xFF00) | ((data >> 24) & 0xFF);}
#endif

#include "zlib.h"

#pragma clang diagnostic ignored "-Wmissing-prototypes"

#define PNG_ZBUF_SIZE  32768

#define PNG_DISPOSE_OP_NONE        0x00
#define PNG_DISPOSE_OP_BACKGROUND  0x01
#define PNG_DISPOSE_OP_PREVIOUS    0x02

#define PNG_BLEND_OP_SOURCE        0x00
#define PNG_BLEND_OP_OVER          0x01

#define notabc(c) ((c) < 65 || (c) > 122 || ((c) > 90 && (c) < 97))

#define ROWBYTES(pixel_bits, width) \
((pixel_bits) >= 8 ? \
((width) * (((unsigned int)(pixel_bits)) >> 3)) : \
(( ((width) * ((unsigned int)(pixel_bits))) + 7) >> 3) )

static const
unsigned char   png_sign[8] = {137, 80, 78, 71, 13, 10, 26, 10};

static const
int mask4[2]={240,15};
static const
int shift4[2]={4,0};

static const
int mask2[4]={192,48,12,3};
static const
int shift2[4]={6,4,2,0};

static const
int mask1[8]={128,64,32,16,8,4,2,1};
static const
int shift1[8]={7,6,5,4,3,2,1,0};

typedef struct
{
  unsigned char   pal[256][3];
  unsigned char   trns[256];
  unsigned int    palsize, trnssize;
  unsigned int    hasTRNS;
  unsigned int    allWrittenPalettePixelsAreOpaque;
  unsigned short  trns1, trns2, trns3;
  z_stream        zstream;
  unsigned int    lastOriginPixel;
} APNGCommonData;

static inline
unsigned int read32(FILE * f1)
{
  unsigned char a, b, c, d;
  fread(&a, 1, 1, f1);
  fread(&b, 1, 1, f1);
  fread(&c, 1, 1, f1);
  fread(&d, 1, 1, f1);
  return ((unsigned int)a<<24)+((unsigned int)b<<16)+((unsigned int)c<<8)+(unsigned int)d;
}

static inline
unsigned short read16(FILE * f1)
{
  unsigned char a, b;
  fread(&a, 1, 1, f1);
  fread(&b, 1, 1, f1);
  return ((unsigned short)a<<8)+(unsigned short)b;
}

static inline
unsigned short readshort(unsigned char * p)
{
  return ((unsigned short)(*p)<<8)+(unsigned short)(*(p+1));
}

static inline
void read_sub_row(unsigned char * row, unsigned int rowbytes, unsigned int bpp)
{
  unsigned int i;
  
  for (i=bpp; i<rowbytes; i++)
    row[i] += row[i-bpp];
}

static inline
void read_up_row(unsigned char * row, unsigned char * prev_row, unsigned int rowbytes, unsigned int bpp)
{
  unsigned int i;
  
  if (prev_row)
    for (i=0; i<rowbytes; i++)
      row[i] += prev_row[i];
}

static inline
void read_average_row(unsigned char * row, unsigned char * prev_row, unsigned int rowbytes, unsigned int bpp)
{
  unsigned int i;
  
  if (prev_row)
  {
    for (i=0; i<bpp; i++)
      row[i] += prev_row[i]>>1;
    for (i=bpp; i<rowbytes; i++)
      row[i] += (prev_row[i] + row[i-bpp])>>1;
  } 
  else 
  {
    for (i=bpp; i<rowbytes; i++)
      row[i] += row[i-bpp]>>1;
  }
}

static inline
void read_paeth_row(unsigned char * row, unsigned char * prev_row, unsigned int rowbytes, unsigned int bpp)
{
  unsigned int i;
  int a, b, c, pa, pb, pc, p;
  
  if (prev_row) 
  {
    for (i=0; i<bpp; i++)
      row[i] += prev_row[i];
    for (i=bpp; i<rowbytes; i++)
    {
      a = row[i-bpp];
      b = prev_row[i];
      c = prev_row[i-bpp];
      p = b - c;
      pc = a - c;
      pa = abs(p);
      pb = abs(pc);
      pc = abs(p + pc);
      row[i] += ((pa <= pb && pa <= pc) ? a : (pb <= pc) ? b : c);
    }
  } 
  else 
  {
    for (i=bpp; i<rowbytes; i++)
      row[i] += row[i-bpp];
  }
}

static inline
void unpack(unsigned char * dst, unsigned int dst_size, unsigned char * src, unsigned int src_size, unsigned int h, unsigned int rowbytes, unsigned char bpp, APNGCommonData *commonPtr)
{
  unsigned int    j;
  unsigned char * row = dst;
  unsigned char * prev_row = NULL;
  
  z_stream zstream = commonPtr->zstream;
  zstream.next_out  = dst;
  zstream.avail_out = dst_size;
  zstream.next_in   = src;
  zstream.avail_in  = src_size;
  inflate(&zstream, Z_FINISH);
  inflateReset(&zstream);
  
  for (j=0; j<h; j++)
  {
    switch (*row++) 
    {
      case 0: break;
      case 1: read_sub_row(row, rowbytes, bpp); break;
      case 2: read_up_row(row, prev_row, rowbytes, bpp); break;
      case 3: read_average_row(row, prev_row, rowbytes, bpp); break;
      case 4: read_paeth_row(row, prev_row, rowbytes, bpp); break;
    }
    prev_row = row;
    row += rowbytes;
  }
}

void compose0(unsigned char * dst, unsigned int dstbytes, unsigned char * src, unsigned int srcbytes, unsigned int w, unsigned int h, unsigned int bop, unsigned char depth, APNGCommonData *commonPtr)
{
  unsigned int    i, j, g, a;
  unsigned char * sp;
  unsigned int  * dp;
  uint32_t hasTRNS = commonPtr->hasTRNS;
  unsigned short  trns1 = commonPtr->trns1;
  
  for (j=0; j<h; j++)
  {
    sp = src+1;
    dp = (unsigned int*)dst;
    
    if (bop == PNG_BLEND_OP_SOURCE)
    {
      switch (depth)
      {
        case 16: for (i=0; i<w; i++) { a = 0xFF; if (hasTRNS && readshort(sp)==trns1) a = 0; *dp++ = (a << 24) + (*sp << 16) + (*sp << 8) + *sp; sp+=2; } break;
        case 8:  for (i=0; i<w; i++) { a = 0xFF; if (hasTRNS && *sp==trns1)           a = 0; *dp++ = (a << 24) + (*sp << 16) + (*sp << 8) + *sp; sp++;  } break;
        case 4:  for (i=0; i<w; i++) { g = (sp[i>>1] & mask4[i&1]) >> shift4[i&1]; a = 0xFF; if (hasTRNS && g==trns1) a = 0; *dp++ = (a<<24) + g*0x111111; } break;
        case 2:  for (i=0; i<w; i++) { g = (sp[i>>2] & mask2[i&3]) >> shift2[i&3]; a = 0xFF; if (hasTRNS && g==trns1) a = 0; *dp++ = (a<<24) + g*0x555555; } break;
        case 1:  for (i=0; i<w; i++) { g = (sp[i>>3] & mask1[i&7]) >> shift1[i&7]; a = 0xFF; if (hasTRNS && g==trns1) a = 0; *dp++ = (a<<24) + g*0xFFFFFF; } break;
      }
    }
    else /* PNG_BLEND_OP_OVER */
    {
      switch (depth)
      {
        case 16: for (i=0; i<w; i++, dp++) { if (readshort(sp) != trns1) { *dp = 0xFF000000 + (*sp << 16) + (*sp << 8) + *sp; } sp+=2; } break;
        case 8:  for (i=0; i<w; i++, dp++) { if (*sp != trns1)           { *dp = 0xFF000000 + (*sp << 16) + (*sp << 8) + *sp; } sp++;  } break;
        case 4:  for (i=0; i<w; i++, dp++) { g = (sp[i>>1] & mask4[i&1]) >> shift4[i&1]; if (g != trns1) { *dp = 0xFF000000+g*0x111111; } } break;
        case 2:  for (i=0; i<w; i++, dp++) { g = (sp[i>>2] & mask2[i&3]) >> shift2[i&3]; if (g != trns1) { *dp = 0xFF000000+g*0x555555; } } break;
        case 1:  for (i=0; i<w; i++, dp++) { g = (sp[i>>3] & mask1[i&7]) >> shift1[i&7]; if (g != trns1) { *dp = 0xFF000000+g*0xFFFFFF; } } break;
      }
    }
    
    src += srcbytes;
    dst += dstbytes;
  }
}

void compose2(unsigned char * dst, unsigned int dstbytes, unsigned char * src, unsigned int srcbytes, unsigned int w, unsigned int h, unsigned int bop, unsigned char depth, APNGCommonData *commonPtr)
{
  unsigned int    i, j;
  unsigned int    r, g, b, a;
  unsigned char * sp;
  unsigned int  * dp;
  uint32_t hasTRNS = commonPtr->hasTRNS;
  unsigned short  trns1 = commonPtr->trns1;
  unsigned short  trns2 = commonPtr->trns2;
  unsigned short  trns3 = commonPtr->trns3;
  
  for (j=0; j<h; j++)
  {
    sp = src+1;
    dp = (unsigned int*)dst;
    
    if (bop == PNG_BLEND_OP_SOURCE)
    {
      if (depth == 8)
      {
        for (i=0; i<w; i++)
        {
          b = *sp++;
          g = *sp++;
          r = *sp++;
          a = 0xFF;
          if (hasTRNS && b==trns1 && g==trns2 && r==trns3)
            a = 0;
          *dp++ = (a << 24) + (r << 16) + (g << 8) + b;
        }
      }
      else
      {
        for (i=0; i<w; i++, sp+=6)
        {
          b = *sp;
          g = *(sp+2);
          r = *(sp+4);
          a = 0xFF;
          if (hasTRNS && readshort(sp)==trns1 && readshort(sp+2)==trns2 && readshort(sp+4)==trns3)
            a = 0;
          *dp++ = (a << 24) + (r << 16) + (g << 8) + b;
        }
      }
    }
    else /* PNG_BLEND_OP_OVER */
    {
      if (depth == 8)
      {
        for (i=0; i<w; i++, sp+=3, dp++)
          if ((*sp != trns1) || (*(sp+1) != trns2) || (*(sp+2) != trns3))
            *dp = 0xFF000000 + (*(sp+2) << 16) + (*(sp+1) << 8) + *sp;
      }
      else
      {
        for (i=0; i<w; i++, sp+=6, dp++)
          if ((readshort(sp) != trns1) || (readshort(sp+2) != trns2) || (readshort(sp+4) != trns3))
            *dp = 0xFF000000 + (*(sp+4) << 16) + (*(sp+2) << 8) + *sp;
      }
    }
    src += srcbytes;
    dst += dstbytes;
  }
}

void compose3(unsigned char * dst, unsigned int dstbytes, unsigned char * src, unsigned int srcbytes, unsigned int w, unsigned int h, unsigned int bop, unsigned char depth, APNGCommonData *commonPtr)
{
  unsigned int    i, j;
  unsigned int    r, g, b, a;
  unsigned int    r2, g2, b2, a2;
  int             u, v, al;
  unsigned char   col;
  unsigned char * sp;
  unsigned int  * dp;

  unsigned int  allWrittenPalettePixelsAreOpaque = commonPtr->allWrittenPalettePixelsAreOpaque;
  
  for (j=0; j<h; j++)
  {
    sp = src+1;
    dp = (unsigned int*)dst;
    
    for (i=0; i<w; i++)
    {
      switch (depth)
      {
        case 8: col = sp[i]; break;
        case 4: col = (sp[i>>1] & mask4[i&1]) >> shift4[i&1]; break;
        case 2: col = (sp[i>>2] & mask2[i&3]) >> shift2[i&3]; break;
        case 1: col = (sp[i>>3] & mask1[i&7]) >> shift1[i&7]; break;
        default: assert(0);
      }
      
      b = commonPtr->pal[col][0];
      g = commonPtr->pal[col][1];
      r = commonPtr->pal[col][2];
      a = commonPtr->trns[col];
      
      if (bop == PNG_BLEND_OP_SOURCE)
      {
        *dp++ = (a << 24) + (r << 16) + (g << 8) + b;
        if (allWrittenPalettePixelsAreOpaque & (a < 255)) {
          allWrittenPalettePixelsAreOpaque = 0;
        }
      }
      else /* PNG_BLEND_OP_OVER */
      {
        if (a == 255)
          *dp++ = (a << 24) + (r << 16) + (g << 8) + b;
        else
          if (a != 0)
          {
            if ((a2 = (*dp)>>24))
            {
              u = a*255;
              v = (255-a)*a2;
              al = 255*255-(255-a)*(255-a2);
              b2 = ((*dp)&255);
              g2 = (((*dp)>>8)&255);
              r2 = (((*dp)>>16)&255);
              b = (b*u + b2*v)/al;
              g = (g*u + g2*v)/al;
              r = (r*u + r2*v)/al;
              a = al/255;
            }
            *dp++ = (a << 24) + (r << 16) + (g << 8) + b;
            if (allWrittenPalettePixelsAreOpaque & (a < 255)) {
              allWrittenPalettePixelsAreOpaque = 0;
            }            
          }
          else
            dp++;
      }
    }
    src += srcbytes;
    dst += dstbytes;
  }
  
  commonPtr->allWrittenPalettePixelsAreOpaque = allWrittenPalettePixelsAreOpaque;
}

void compose4(unsigned char * dst, unsigned int dstbytes, unsigned char * src, unsigned int srcbytes, unsigned int w, unsigned int h, unsigned int bop, unsigned char depth)
{
  unsigned int    i, j, step;
  unsigned int    g, a, g2, a2;
  int             u, v, al;
  unsigned char * sp;
  unsigned int  * dp;
  
  step = (depth+7)/8;
  
  for (j=0; j<h; j++)
  {
    sp = src+1;
    dp = (unsigned int*)dst;
    
    if (bop == PNG_BLEND_OP_SOURCE)
    {
      for (i=0; i<w; i++)
      {
        g = *sp; sp += step;
        a = *sp; sp += step;
        *dp++ = (a << 24) + (g << 16) + (g << 8) + g;
      }
    }
    else /* PNG_BLEND_OP_OVER */
    {
      for (i=0; i<w; i++)
      {
        g = *sp; sp += step;
        a = *sp; sp += step;
        if (a == 255)
          *dp++ = (a << 24) + (g << 16) + (g << 8) + g;
        else
          if (a != 0)
          {
            if ((a2 = (*dp)>>24))
            {
              u = a*255;
              v = (255-a)*a2;
              al = 255*255-(255-a)*(255-a2);
              g2 = ((*dp)&255);
              g = (g*u + g2*v)/al;
              a = al/255;
            }
            *dp++ = (a << 24) + (g << 16) + (g << 8) + g;
          }
          else
            dp++;
      }
    }
    src += srcbytes;
    dst += dstbytes;
  }
}

void compose6(unsigned char * dst, unsigned int dstbytes, unsigned char * src, unsigned int srcbytes, unsigned int w, unsigned int h, unsigned int bop, unsigned char depth)
{
  unsigned int    i, j, step;
  unsigned int    r, g, b, a;
  unsigned int    r2, g2, b2, a2;
  int             u, v, al;
  unsigned char * sp;
  unsigned int  * dp;
  
  step = (depth+7)/8;
  
  for (j=0; j<h; j++)
  {
    sp = src+1;
    dp = (unsigned int*)dst;
    
    if (bop == PNG_BLEND_OP_SOURCE)
    {
      for (i=0; i<w; i++)
      {
        b = *sp; sp += step;
        g = *sp; sp += step;
        r = *sp; sp += step;
        a = *sp; sp += step;
        *dp++ = (a << 24) + (r << 16) + (g << 8) + b;
      }
    }
    else /* PNG_BLEND_OP_OVER */
    {
      for (i=0; i<w; i++)
      {
        b = *sp; sp += step;
        g = *sp; sp += step;
        r = *sp; sp += step;
        a = *sp; sp += step;
        if (a == 255)
          *dp++ = (a << 24) + (r << 16) + (g << 8) + b;
        else
          if (a != 0)
          {
            if ((a2 = (*dp)>>24))
            {
              u = a*255;
              v = (255-a)*a2;
              al = 255*255-(255-a)*(255-a2);
              b2 = ((*dp)&255);
              g2 = (((*dp)>>8)&255);
              r2 = (((*dp)>>16)&255);
              b = (b*u + b2*v)/al;
              g = (g*u + g2*v)/al;
              r = (r*u + r2*v)/al;
              a = al/255;
            }
            *dp++ = (a << 24) + (r << 16) + (g << 8) + b;
          }
          else
            dp++;
      }
    }
    src += srcbytes;
    dst += dstbytes;
  }
}

// Open an APNG file and verify that the file contains APNG data.
// If the file can't be opened then NULL is returned. Note that
// this method can't be used to open a regular PNG data file,
// only APNG files are supported.

FILE*
libapng_open(char *apngPath)
{
  FILE *fp;
  uint8_t sig[8];
  
  fp = fopen(apngPath, "rb");
  if (fp == NULL) {
    return NULL;
  }

  // Verify that the PNG file signature matches
  
  if (fread(&sig[0], 8, 1, fp) != 1) {
    fclose(fp);
    return NULL;
  }

  uint32_t same = memcmp(sig, png_sign, 8);

  if (same != 0) {
    fclose(fp);
    return NULL;
  }
  
  // FIXME: scan for APNG specific chunks
  
  return fp;
}

void
libapng_close(FILE *apngFILE)
{
  if (apngFILE) {
    fclose(apngFILE);
  }
}

// This methods opens an APNG file 

uint32_t
libapng_main(FILE *apngFile, libapng_frame_func frame_func, void *userData)
{
  int             res;
  unsigned int    i, j;
  unsigned int    rowbytes; 
  int             imagesize, zbuf_size, zsize;
  unsigned int    len, chunk, crc;
  unsigned int    w, h, seq, w0, h0, x0, y0;
  unsigned int    frames, loops, num_fctl, num_idat;
  unsigned int    outrow, outimg;
  unsigned short  d1, d2;
  unsigned char   c, dop, bop;
  unsigned char   channels, depth, pixeldepth, bpp;
  unsigned char   coltype, compr, filter, interl;
  uint32_t retcode = 0;
  
  APNGCommonData common;
  memset(&common, 0, sizeof(APNGCommonData));
  APNGCommonData *commonPtr = &common;
  // Assume that all pixels written from the palette are opaque
  // until a non-opaque pixel has been written. A non-palette
  // image should not depend on this flag.
  commonPtr->allWrittenPalettePixelsAreOpaque = 1;
  
  assert(apngFile);
  assert(frame_func);
  assert(userData);
  
  for (i=0; i<256; i++)
  {
    commonPtr->pal[i][0] = i;
    commonPtr->pal[i][1] = i;
    commonPtr->pal[i][2] = i;
    commonPtr->trns[i] = 255;
  }
  
  commonPtr->zstream.zalloc = Z_NULL;
  commonPtr->zstream.zfree = Z_NULL;
  commonPtr->zstream.opaque = Z_NULL;
  inflateInit(&commonPtr->zstream);
  
  frames = 1;
  num_fctl = 0;
  num_idat = 0;
  zsize = 0;
  commonPtr->hasTRNS = 0;
  x0 = 0;
  y0 = 0;
  bop = PNG_BLEND_OP_SOURCE;
  
  if (1)
  {
    unsigned char sig[8];
    unsigned char * pOut;
    unsigned char * pRest;
    unsigned char * pTemp;
    unsigned char * pData;
    unsigned char * pDst;
    
    fseek(apngFile, 0, SEEK_SET);
    
    if ((res = (int)fread(sig, 1, 8, apngFile)) == 8)
    {
      if (memcmp(sig, png_sign, 8) == 0)
      {
        len  = read32(apngFile);
        chunk = read32(apngFile);
        
        if ((len == 13) && (chunk == 0x49484452)) /* IHDR */
        {
          w = w0 = read32(apngFile);
          h = h0 = read32(apngFile);
          fread(&depth, 1, 1, apngFile);
          fread(&coltype, 1, 1, apngFile);
          fread(&compr, 1, 1, apngFile);
          fread(&filter, 1, 1, apngFile);
          fread(&interl, 1, 1, apngFile);
          crc = read32(apngFile);
          
          // Color    Allowed    Interpretation
          // Type    Bit Depths
          //  
          //  0       1,2,4,8,16  Each pixel is a grayscale sample.
          //  
          //  2       8,16        Each pixel is an R,G,B triple.
          //  
          //  3       1,2,4,8     Each pixel is a palette index; a PLTE chunk must appear.
          //  
          //  4       8,16        Each pixel is a grayscale sample, followed by an alpha sample.
          //  
          //  6       8,16        Each pixel is an R,G,B triple, followed by an alpha sample.
          
          channels = 1;
          if (coltype == 2)
            channels = 3;
          else
            if (coltype == 4)
              channels = 2;
            else
              if (coltype == 6)
                channels = 4;
          
          pixeldepth = depth*channels;
          bpp = (pixeldepth + 7) >> 3;
          rowbytes = ROWBYTES(pixeldepth, w);
          
          imagesize = (rowbytes + 1) * h;
          zbuf_size = imagesize + ((imagesize + 7) >> 3) + ((imagesize + 63) >> 6) + 11;
          
          outrow = w*4;
          outimg = h*outrow;
          
          pOut =(unsigned char *)malloc(outimg);
          pRest=(unsigned char *)malloc(outimg);
          pTemp=(unsigned char *)malloc(imagesize);
          pData=(unsigned char *)malloc(zbuf_size);
          
          /* apng decoding - begin */
          memset(pOut, 0, outimg);
          
          while ( !feof(apngFile) )
          {
            len  = read32(apngFile);
            chunk = read32(apngFile);
            
            if (chunk == 0x504C5445) /* PLTE */
            {
              unsigned int col;
              for (i=0; i<len; i++)
              {
                fread(&c, 1, 1, apngFile);
                col = i/3;
                if (col<256)
                {
                  commonPtr->pal[col][i%3] = c;
                  commonPtr->palsize = col+1;
                }
              }
              crc = read32(apngFile);
            }
            else
              if (chunk == 0x74524E53) /* tRNS */
              {
                commonPtr->hasTRNS = 1;
                for (i=0; i<len; i++)
                {
                  fread(&c, 1, 1, apngFile);
                  if (i<256)
                  {
                    commonPtr->trns[i] = c;
                    commonPtr->trnssize = i+1;
                  }
                }
                if (coltype == 0)
                {
                  commonPtr->trns1 = readshort(&commonPtr->trns[0]);
                }
                else
                  if (coltype == 2)
                  {
                    commonPtr->trns1 = readshort(&commonPtr->trns[0]);
                    commonPtr->trns2 = readshort(&commonPtr->trns[2]);
                    commonPtr->trns3 = readshort(&commonPtr->trns[4]);
                  }
                crc = read32(apngFile);
              }
              else
                if (chunk == 0x6163544C) /* acTL */
                {
                  frames = read32(apngFile);
                  loops  = read32(apngFile);
                  crc = read32(apngFile);
                }
                else
                  if (chunk == 0x6663544C) /* fcTL */
                  {
                    if ((num_fctl == num_idat) && (num_idat > 0))
                    {
                      if (dop == PNG_DISPOSE_OP_PREVIOUS)
                        memcpy(pRest, pOut, outimg);
                      
                      pDst = pOut + y0*outrow + x0*4;
                      unpack(pTemp, imagesize, pData, zsize, h0, rowbytes, bpp, commonPtr);
                      switch (coltype)
                      {
                        case 0: compose0(pDst, outrow, pTemp, rowbytes+1, w0, h0, bop, depth, commonPtr); break;
                        case 2: compose2(pDst, outrow, pTemp, rowbytes+1, w0, h0, bop, depth, commonPtr); break;
                        case 3: compose3(pDst, outrow, pTemp, rowbytes+1, w0, h0, bop, depth, commonPtr); break;
                        case 4: compose4(pDst, outrow, pTemp, rowbytes+1, w0, h0, bop, depth); break;
                        case 6: compose6(pDst, outrow, pTemp, rowbytes+1, w0, h0, bop, depth); break;
                      }
                      
                      //SavePNG(pOut, w, h, num_idat, frames);
                      
                      if (1) {
                        uint32_t* framebuffer = (uint32_t*)pOut;
                        uint32_t framei = num_idat - 1;
                        uint32_t width = w;
                        uint32_t height = h;
                        uint32_t delta_x = x0;
                        uint32_t delta_y = y0;
                        uint32_t delta_width = w0;
                        uint32_t delta_height = h0;
                        uint32_t delay_num = d1;
                        uint32_t delay_den = d2;
                        uint32_t bpp = 24;
                        if ((coltype == 4) || (coltype == 6)) {
                          bpp = 32;
                        } else if (coltype == 3) {
                          // In palette mode, don't know if pixels written to the framebuffer are actually opaque
                          // or partially transparent until after the composition operation is done. The result is
                          // that it is possible that initial frames would appear to be 24bpp, while a later frame
                          // could make use of partial transparency.
                          
                          if (commonPtr->allWrittenPalettePixelsAreOpaque) {
                            // 24 BPP with no alpha channel
                          } else {
                            // 32 BPP with alpha channel
                            bpp = 32;
                          }
                        }
                        
                        // Odd way of representing no-op frame. The apngasm program will encode a no-op frame
                        // as a 1x1 window at the origin. This really should be done by extending the duration of the
                        // previous frame, but work around the issue here. Report a frame that is 0x0 at 0,0 to
                        // make it easier to detect a no-op frame in the callback.
                        
                        if (delta_x == 0 && delta_y == 0 && delta_width == 1 && delta_height == 1 && (framebuffer[0] == commonPtr->lastOriginPixel)) {
                          delta_width = 0;
                          delta_height = 0;
                        } else {
                          commonPtr->lastOriginPixel = framebuffer[0];
                        }
                        
                        uint32_t result = frame_func(framebuffer, framei, width, height, delta_x, delta_y, delta_width, delta_height, delay_num, delay_den, bpp, userData);
                        assert(result == 0);
                      }
                      
                      if (dop == PNG_DISPOSE_OP_PREVIOUS)
                        memcpy(pOut, pRest, outimg);
                      else
                        if (dop == PNG_DISPOSE_OP_BACKGROUND)
                        {
                          pDst = pOut + y0*outrow + x0*4;
                          
                          for (j=0; j<h0; j++)
                          {
                            memset(pDst, 0, w0*4);
                            pDst += outrow;
                          }
                        }
                    }
                    
                    seq = read32(apngFile);
                    w0  = read32(apngFile);
                    h0  = read32(apngFile);
                    x0  = read32(apngFile);
                    y0  = read32(apngFile);
                    d1  = read16(apngFile);
                    d2  = read16(apngFile);
                    fread(&dop, 1, 1, apngFile);
                    fread(&bop, 1, 1, apngFile);
                    crc = read32(apngFile);
                    
                    if (num_fctl == 0)
                    {
                      bop = PNG_BLEND_OP_SOURCE;
                      if (dop == PNG_DISPOSE_OP_PREVIOUS)
                        dop = PNG_DISPOSE_OP_BACKGROUND;
                    }
                    
                    if (!(coltype & 4) && !(commonPtr->hasTRNS))
                      bop = PNG_BLEND_OP_SOURCE;
                    
                    rowbytes = ROWBYTES(pixeldepth, w0);
                    num_fctl++;
                  }
                  else
                    if (chunk == 0x49444154) /* IDAT */
                    {
                      if (num_fctl > num_idat)
                      {
                        zsize = 0;
                        num_idat++;
                      }
                      fread(pData + zsize, 1, len, apngFile);
                      zsize += len;
                      crc = read32(apngFile);
                    }
                    else
                      if (chunk == 0x66644154) /* fdAT */
                      {
                        seq = read32(apngFile);
                        len -= 4;
                        if (num_fctl > num_idat)
                        {
                          zsize = 0;
                          num_idat++;
                        }
                        fread(pData + zsize, 1, len, apngFile);
                        zsize += len;
                        crc = read32(apngFile);
                      }
                      else
                        if (chunk == 0x49454E44) /* IEND */
                        {
                          pDst = pOut + y0*outrow + x0*4;
                          unpack(pTemp, imagesize, pData, zsize, h0, rowbytes, bpp, commonPtr);
                          switch (coltype)
                          {
                            case 0: compose0(pDst, outrow, pTemp, rowbytes+1, w0, h0, bop, depth, commonPtr); break;
                            case 2: compose2(pDst, outrow, pTemp, rowbytes+1, w0, h0, bop, depth, commonPtr); break;
                            case 3: compose3(pDst, outrow, pTemp, rowbytes+1, w0, h0, bop, depth, commonPtr); break;
                            case 4: compose4(pDst, outrow, pTemp, rowbytes+1, w0, h0, bop, depth); break;
                            case 6: compose6(pDst, outrow, pTemp, rowbytes+1, w0, h0, bop, depth); break;
                          }
                          
                          //SavePNG(pOut, w, h, num_idat, frames);
                          
                          if (1) {
                            uint32_t* framebuffer = (uint32_t*)pOut;
                            uint32_t framei = num_idat - 1;
                            uint32_t width = w;
                            uint32_t height = h;
                            uint32_t delta_x = x0;
                            uint32_t delta_y = y0;
                            uint32_t delta_width = w0;
                            uint32_t delta_height = h0;
                            uint32_t delay_num = d1;
                            uint32_t delay_den = d2;
                            uint32_t bpp = 24;
                            if ((coltype == 4) || (coltype == 6)) {
                              bpp = 32;
                            } else if (coltype == 3) {
                              // In palette mode, don't know if pixels written to the framebuffer are actually opaque
                              // or partially transparent until after the composition operation is done. The result is
                              // that it is possible that initial frames would appear to be 24bpp, while a later frame
                              // could make use of partial transparency.
                              
                              if (commonPtr->allWrittenPalettePixelsAreOpaque) {
                                // 24 BPP with no alpha channel
                              } else {
                                // 32 BPP with alpha channel
                                bpp = 32;
                              }
                            }
                            
                            // Odd way of representing no-op frame. The apngasm program will encode a no-op frame
                            // as a 1x1 window at the origin. This really should be done by extending the duration of the
                            // previous frame, but work around the issue here. Report a frame that is 0x0 at 0,0 to
                            // make it easier to detect a no-op frame in the callback.
                            
                            if (delta_x == 0 && delta_y == 0 && delta_width == 1 && delta_height == 1 && (framebuffer[0] == commonPtr->lastOriginPixel)) {
                              delta_width = 0;
                              delta_height = 0;
                            } else {
                              commonPtr->lastOriginPixel = framebuffer[0];
                            }                            
                            
                            uint32_t result = frame_func(framebuffer, framei, width, height, delta_x, delta_y, delta_width, delta_height, delay_num, delay_den, bpp, userData);
                            assert(result == 0);
                          }
                          
                          break;
                        }
                        else
                        {
                          c = (unsigned char)(chunk>>24);
                          if (notabc(c)) break;
                          c = (unsigned char)((chunk>>16) & 0xFF);
                          if (notabc(c)) break;
                          c = (unsigned char)((chunk>>8) & 0xFF);
                          if (notabc(c)) break;
                          c = (unsigned char)(chunk & 0xFF);
                          if (notabc(c)) break;
                          
                          fseek( apngFile, len, SEEK_CUR );
                          crc = read32(apngFile);
                        }
          }
          
          // apng decoding - end
          
          if (pData)
            free(pData);
          if (pTemp)
            free(pTemp);
          if (pOut)
            free(pOut);
          if (pRest)
            free(pRest);
        }
        else {
          retcode = LIBAPNG_ERROR_CODE_INVALID_INPUT;
          printf("IHDR missing\n");
        }
      }
      else {
        retcode = LIBAPNG_ERROR_CODE_INVALID_INPUT;
        printf("Error: wrong PNG sig\n");
      }
    }
    else {
      retcode = LIBAPNG_ERROR_CODE_INVALID_INPUT;
      printf("Error: can't read the sig\n");
    }
   
    // Assumes that the caller closes the file
    //fclose(apngFile);
  }
  else {
    retcode = LIBAPNG_ERROR_CODE_INVALID_FILENAME;
    //printf("Error: can't open the file\n");
  }
  
  inflateEnd(&commonPtr->zstream);
  
  //printf("all done\n");
  
  return retcode;
}

// Calculate the wall clock time that a specific frame will be displayed for.
// This logic has to take into account the fact that the delay times indicated
// in an APNG file could be zero.

//#define DEBUG_PRINT_FRAME_DURATION

float
libapng_frame_delay(uint32_t numerator, uint32_t denominator)
{
  // frameDuration : time that specific frame will be visible
  // 1/100 is the default if both numerator and denominator are zero
  
  float frameDuration;
  float fnumerator;
  float fdenominator;
  
  if (denominator == 0) {
    // denominator is 0, treat as 1/100 of a second
    fdenominator = 100.0f;
  } else {
    fdenominator = (float) denominator;
  }
  
  if (numerator == 0) {
    // if numerator is zero, use maximum frame rate of 30 FPS
    fnumerator = 1.0f;
    fdenominator = 30.0f;
  } else {
    fnumerator = (float) numerator;
  }
  
  frameDuration = fnumerator / fdenominator;
  
#ifdef DEBUG_PRINT_FRAME_DURATION
  fprintf(stdout, "numerator / denominator = %d / %d\n", numerator, denominator);
  fprintf(stdout, "fnumerator / fdenominator = %f / %f = %f\n", fnumerator, fdenominator, frameDuration);
#endif     
  
  return frameDuration;
}
