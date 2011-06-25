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

// This header defines a simple interface to a library that decodes frames from an APNG file.

#ifndef LIBAPNG_H
#define LIBAPNG_H

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

#define LIBAPNG_ERROR_CODE_INVALID_INPUT 1
#define LIBAPNG_ERROR_CODE_INVALID_FILENAME 2
#define LIBAPNG_ERROR_CODE_WRITE_FAILED 3
#define LIBAPNG_ERROR_CODE_READ_FAILED 4

typedef int (*libapng_frame_func)(
                                  uint32_t* framebuffer,
                                  uint32_t framei,
                                  uint32_t width, uint32_t height,
                                  uint32_t delta_x, uint32_t delta_y, uint32_t delta_width, uint32_t delta_height,
                                  uint32_t delay_num, uint32_t delay_den,
                                  uint32_t bpp,
                                  void *userData);

FILE*
libapng_open(char *apngPath);

void
libapng_close(FILE *apngFILE);

uint32_t
libapng_main(FILE *apngFile, libapng_frame_func frame_func, void *userData);

float
libapng_frame_delay(uint32_t numerator, uint32_t denominator);

#endif
