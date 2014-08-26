// maxvid_file module
//
//  License terms defined in License.txt.
//
// This module defines the format and logic to read and write a maxvid file.

#include "maxvid_file.h"

/* largest prime smaller than 65536 */
#define BASE 65521L

/* NMAX is the largest n such that 255n(n+1)/2 + (n+1)(BASE-1) <= 2^32-1 */
#define NMAX 5552

#define DO1(buf, i)  { s1 += buf[i]; s2 += s1; }
#define DO2(buf, i)  DO1(buf, i); DO1(buf, i + 1);
#define DO4(buf, i)  DO2(buf, i); DO2(buf, i + 2);
#define DO8(buf, i)  DO4(buf, i); DO4(buf, i + 4);
#define DO16(buf)    DO8(buf, 0); DO8(buf, 8);

uint32_t maxvid_adler32(
                          uint32_t adler,
                          unsigned char const *buf,
                          uint32_t len)
{
	int k;
	uint32_t s1 = adler & 0xffff;
	uint32_t s2 = (adler >> 16) & 0xffff;
  
	if (!buf)
		return 1;
  
	while (len > 0) {
		k = len < NMAX ? len :NMAX;
		len -= k;
		while (k >= 16) {
			DO16(buf);
			buf += 16;
			k -= 16;
		}
		if (k != 0)
			do {
				s1 += *buf++;
				s2 += s1;
			} while (--k);
		s1 %= BASE;
		s2 %= BASE;
	}
  
  uint32_t result = (s2 << 16) | s1;
  
  if (result == 0) {
    // All zero input, use 0xFFFFFFFF instead
    result = 0xFFFFFFFF;
  }
  
	return result;
}
