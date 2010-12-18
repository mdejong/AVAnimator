//
//  CGFrameBuffer.m
//  AVAnimatorDemo
//
//  Created by Moses DeJong on 2/13/09.
//  Copyright 2009 __MyCompanyName__. All rights reserved.
//

#import "CGFrameBuffer.h"

#import <QuartzCore/QuartzCore.h>

#include <zlib.h>

#include "runlength.h"

//#define DEBUG_LOGGING

// Pixel format is ARGB with 2 bytes per pixel (alpha is ignored)

#define BITS_PER_COMPONENT 5
#define BITS_PER_PIXEL 16
#define BYTES_PER_PIXEL 2

void CGFrameBufferProviderReleaseData (void *info, const void *data, size_t size);

@implementation CGFrameBuffer

@synthesize pixels, numBytes, width, height;
@synthesize frameIndex, idc;

- (id) initWithDimensions:(NSInteger)inWidth :(NSInteger)inHeight
{
	// Ensure that memory is allocated in terms of whole words, the
	// bitmap context won't make use of the extra half-word.

	size_t numPixels = inWidth * inHeight;
	size_t numPixelsToAllocate = numPixels;

	if ((numPixels % 2) != 0) {
		numPixelsToAllocate++;
	}

	int inNumBytes = numPixelsToAllocate * BYTES_PER_PIXEL;
	char* buffer = (char*) malloc(inNumBytes);

	if (buffer == NULL)
		return nil;

	memset(buffer, 0, inNumBytes);

	self = [super init];

	self->pixels = buffer;
	self->numBytes = inNumBytes;
	self->width = inWidth;
	self->height = inHeight;

	return self;
}

- (BOOL) renderView:(UIView*)view
{
	// Capture the pixel content of the View that contains the
	// UIImageView. A view that displays at the full width and
	// height of the screen will be captured in a 320x480
	// bitmap context. Note that any transformations applied
	// to the UIImageView will be captured *after* the
	// transformation has been applied. Once the bitmap
	// context has been captured, it should be rendered with
	// no transformations. Also note that the colorspace
	// is always ARGBwith no alpha, the bitmap capture happens
	// *after* any colors in the image have been converted to RGB pixels.

	size_t w = view.layer.bounds.size.width;
	size_t h = view.layer.bounds.size.height;

//	if ((self.width != w) || (self.height != h)) {
//		return FALSE;
//	}

	BOOL isRotated;

	if ((self.width == w) && (self.height == h)) {
		isRotated = FALSE;
	} else if ((self.width == h) || (self.height != w)) {
		// view must have created a rotation transformation
		isRotated = TRUE;
	} else {
		return FALSE;
	}

	size_t bytesPerRow = width * BYTES_PER_PIXEL;
	CGBitmapInfo bitmapInfo = [self getBitmapInfo];

	CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();

	NSAssert(pixels != NULL, @"pixels must not be NULL");

	NSAssert(self.isLockedByDataProvider == FALSE, @"renderView: pixel buffer locked by data provider");

	CGContextRef bitmapContext =
		CGBitmapContextCreate(pixels, width, height, BITS_PER_COMPONENT, bytesPerRow, colorSpace, bitmapInfo);

	CGColorSpaceRelease(colorSpace);

	if (bitmapContext == NULL) {
		return FALSE;
	}

	// Translation matrix that maps CG space to view space

	CGContextTranslateCTM(bitmapContext, 0.0, height);
	CGContextScaleCTM(bitmapContext, 1.0, -1.0);

	[view.layer renderInContext:bitmapContext];

	CGContextRelease(bitmapContext);

	return TRUE;
}

- (BOOL) renderCGImage:(CGImageRef)cgImageRef
{
	// Render the contents of an image to pixels.

	size_t w = CGImageGetWidth(cgImageRef);
	size_t h = CGImageGetHeight(cgImageRef);
	
	BOOL isRotated = FALSE;
	
	if ((self.width == w) && (self.height == h)) {
		// pixels will render as expected
	} else if ((self.width == h) || (self.height != w)) {
		// image should be rotated before rendering
		isRotated = TRUE;
	} else {
		return FALSE;
	}
	
	size_t bytesPerRow = width * BYTES_PER_PIXEL;
	CGBitmapInfo bitmapInfo = [self getBitmapInfo];
	
	CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();

	NSAssert(pixels != NULL, @"pixels must not be NULL");
	NSAssert(self.isLockedByDataProvider == FALSE, @"renderCGImage: pixel buffer locked by data provider");

	CGContextRef bitmapContext =
		CGBitmapContextCreate(pixels, width, height, BITS_PER_COMPONENT, bytesPerRow, colorSpace, bitmapInfo);
	
	CGColorSpaceRelease(colorSpace);
	
	if (bitmapContext == NULL) {
		return FALSE;
	}
	
	// Translation matrix that maps CG space to view space

	if (isRotated) {
		// To landscape : 90 degrees CCW

		CGContextRotateCTM(bitmapContext, M_PI / 2);		
	}

	CGRect bounds = CGRectMake( 0.0f, 0.0f, width, height );

	CGContextDrawImage(bitmapContext, bounds, cgImageRef);
	
	CGContextRelease(bitmapContext);
	
	return TRUE;
}

- (CGImageRef) createCGImageRef
{
	// Load pixel data as a core graphics image object.

  NSAssert(width > 0 && height > 0, @"width or height is zero");

	size_t bytesPerRow = width * BYTES_PER_PIXEL; // ARGB = 2 bytes per pixel (16 bits)

	CGBitmapInfo bitmapInfo = [self getBitmapInfo];

	CGDataProviderReleaseDataCallback releaseData = CGFrameBufferProviderReleaseData;

	CGDataProviderRef dataProviderRef = CGDataProviderCreateWithData(self,
																	 pixels,
																	 width * height * BYTES_PER_PIXEL,
																	 releaseData);

	BOOL shouldInterpolate = FALSE; // images at exact size already

	CGColorRenderingIntent renderIntent = kCGRenderingIntentDefault;

	CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();

	CGImageRef inImageRef = CGImageCreate(width, height, BITS_PER_COMPONENT, BITS_PER_PIXEL, bytesPerRow,
										  colorSpace, bitmapInfo, dataProviderRef, NULL,
										  shouldInterpolate, renderIntent);

	CGDataProviderRelease(dataProviderRef);

	CGColorSpaceRelease(colorSpace);

	if (inImageRef != NULL) {
		self.isLockedByDataProvider = TRUE;
		self->lockedByImageRef = inImageRef; // Don't retain, just save pointer
	}

	return inImageRef;
}

- (BOOL) isLockedByImageRef:(CGImageRef)cgImageRef
{
	if (! self->_isLockedByDataProvider)
		return FALSE;

	return (self->lockedByImageRef == cgImageRef);
}

- (CGBitmapInfo) getBitmapInfo
{
/*
	CGBitmapInfo bitmapInfo = kCGBitmapByteOrderDefault;
	bitmapInfo |= kCGImageAlphaNoneSkipLast;		// 32 bit RGBA where the A is ignored
	//bitmapInfo |= kCGImageAlphaLast;				// 32 bit RGBA
	//bitmapInfo |= kCGImageAlphaPremultipliedLast;	// 32 bit RGBA where A is pre-multiplied alpha

*/

	CGBitmapInfo bitmapInfo = kCGBitmapByteOrder16Little;
	bitmapInfo |= kCGImageAlphaNoneSkipFirst;

	return bitmapInfo;
}

- (NSData*) runLengthEncode
{
	// Create a NSMutableData to contain the encoded data, then
	// encode to compress duplicate pixels.

	int encodedNumBytes = numBytes + numBytes/2;
	NSMutableData *buffer = [NSMutableData dataWithCapacity:encodedNumBytes];
	NSAssert(buffer, @"could not allocate pixel buffer");
	[buffer setLength:encodedNumBytes];

	uint16_t *buffer_bytes = (uint16_t *) [buffer mutableBytes];

	encodedNumBytes = pp_encode((uint16_t *)pixels, width * height,
								(char*)[buffer mutableBytes], encodedNumBytes);

	return [NSData dataWithBytes:buffer_bytes length:encodedNumBytes];	
}

- (void) runLengthDecode:(NSData*)encoded numEncodedBytes:(NSUInteger)numEncodedBytes
{
	char *input_bytes = (char *)[encoded bytes];
	pp_decode(input_bytes, numEncodedBytes, (uint16_t*) pixels, width * height);
}

- (void) runLengthDecodeBytes:(char*)encoded numEncodedBytes:(NSUInteger)numEncodedBytes
{
	assert(encoded);
	assert(numEncodedBytes > 0);
	pp_decode(encoded, numEncodedBytes, (uint16_t*) pixels, width * height);
}

// These properties are implemented explicitly to aid
// in debugging of read/write operations. These method
// are used to set values that could be set in one thread
// and read or set in another. The code must take care to
// use these fields correctly to remain thread safe.

- (BOOL) isLockedByDataProvider
{
	return self->_isLockedByDataProvider;
}

- (void) setIsLockedByDataProvider:(BOOL)newValue
{
	NSAssert(_isLockedByDataProvider == !newValue,
			 @"isLockedByDataProvider property can only be switched");

	self->_isLockedByDataProvider = newValue;

	if (_isLockedByDataProvider) {
		[self retain]; // retain extra ref to self
	} else {
#ifdef DEBUG_LOGGING
		if (TRUE)
#else
		if (FALSE)
#endif
		{
			// Catch the case where the very last ref to
			// an object is dropped fby CoreGraphics
			
			int refCount = [self retainCount];

			if (refCount == 1) {
				// About to drop last ref to this frame buffer

				NSLog(@"dropping last ref to CGFrameBuffer held by DataProvider");
			}

			[self release];
		} else {
			// Regular logic for non-debug situations

			[self release]; // release extra ref to self
		}
	}
}

- (void)dealloc {
	NSAssert(self.isLockedByDataProvider == FALSE, @"dealloc: buffer still locked by data provider");

	if (pixels != NULL)
		free(pixels);

#ifdef DEBUG_LOGGING
	NSLog(@"deallocate CGFrameBuffer");
#endif

    [super dealloc];
}

@end

// C callback invoked by core graphics when done with a buffer, this is tricky
// since an extra ref is held on the buffer while it is locked by the
// core graphics layer.

void CGFrameBufferProviderReleaseData (void *info, const void *data, size_t size) {
#ifdef DEBUG_LOGGING
	NSLog(@"CGFrameBufferProviderReleaseData() called");
#endif

	CGFrameBuffer *cgBuffer = (CGFrameBuffer *) info;
	cgBuffer.isLockedByDataProvider = FALSE;

	// Note that the cgBuffer just deallocated itself, so the
	// pointer no longer points to a valid memory.
}
