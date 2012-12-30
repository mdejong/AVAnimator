//
//  CGFrameBuffer.h
//
//  Created by Moses DeJong on 2/13/09.
//
//  License terms defined in License.txt.

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <CoreGraphics/CoreGraphics.h>

// Avoid incorrect warnings from clang
#ifndef __has_feature      // Optional.
#define __has_feature(x) 0 // Compatibility with non-clang compilers.
#endif

#ifndef CF_RETURNS_RETAINED
#if __has_feature(attribute_cf_returns_retained)
#define CF_RETURNS_RETAINED __attribute__((cf_returns_retained))
#else
#define CF_RETURNS_RETAINED
#endif
#endif

@interface CGFrameBuffer : NSObject {
@protected
	char *m_pixels;
	char *m_zeroCopyPixels;
	NSData *m_zeroCopyMappedData;
	size_t m_numBytes;
	size_t m_numBytesAllocated;
	size_t m_width;
	size_t m_height;
	size_t m_bitsPerPixel;
	size_t m_bytesPerPixel;
	int32_t m_isLockedByDataProvider;
	CGImageRef m_lockedByImageRef;
	CGColorSpaceRef m_colorspace;
}

@property (readonly) char *pixels;
@property (readonly) char *zeroCopyPixels;
@property (nonatomic, copy) NSData *zeroCopyMappedData;

// The numBytes property indicates the number of bytes in length
// of the buffer pointed to by the pixels property. In the event
// that an odd number of pixels is allocated, this numBytes value
// could also include a zero padding pixel in order to keep the
// buffer size an even number of pixels.

@property (readonly) size_t numBytes;
@property (readonly) size_t width;
@property (readonly) size_t height;
@property (readonly) size_t bitsPerPixel;
@property (readonly) size_t bytesPerPixel;

@property (nonatomic, assign) BOOL isLockedByDataProvider;
@property (nonatomic, readonly) CGImageRef lockedByImageRef;

// The colorspace will default to device RGB unless explicitly set. If set, then
// the indicated colorspace will be used when invoking CGBitmapContextCreate()
// such that a drawing operation will output pixels in the indicated colorspace.
// The same colorspace will be used when creating a CGImageRef via createCGImageRef.
// While this property is marked as assign, it will retain a ref to the indicate colorspace.

@property (nonatomic, assign) CGColorSpaceRef colorspace;

+ (CGFrameBuffer*) cGFrameBufferWithBppDimensions:(NSInteger)bitsPerPixel width:(NSInteger)width height:(NSInteger)height;

- (id) initWithBppDimensions:(NSInteger)bitsPerPixel width:(NSInteger)width height:(NSInteger)height;

// Render the contents of a view as pixels. Returns TRUE
// is successful, otherwise FALSE. Note that the view
// must be opaque and render all of its pixels. 

- (BOOL) renderView:(UIView*)view;

// Render a CGImageRef directly into the pixels

- (BOOL) renderCGImage:(CGImageRef)cgImageRef;

// Wrap the framebuffer in a CoreGraphics bitmap context.
// This API creates a handle that can be used to render
// directly into the bitmap pixels. The handle must
// be explicitly released by the caller via CGContextRelease()

- (CGContextRef) createBitmapContext CF_RETURNS_RETAINED;

// Create a Core Graphics image from the pixel data
// in this buffer. The hasDataProvider property
// will be TRUE while the CGImageRef is in use.
// This name is upper case to avoid warnings from the analyzer.

- (CGImageRef) createCGImageRef CF_RETURNS_RETAINED;

// Defines the pixel layout, could be overloaded in a derived class

- (CGBitmapInfo) getBitmapInfo;

- (BOOL) isLockedByImageRef:(CGImageRef)cgImageRef;

// Set all pixels to 0x0

- (void) clear;

// Copy data from another framebuffer into this one

- (void) copyPixels:(CGFrameBuffer *)anotherFrameBuffer;

// USe memcopy() as opposed to an OS level page copy

- (void) memcopyPixels:(CGFrameBuffer *)anotherFrameBuffer;

// Zero copy from an external read-only location

- (void) zeroCopyPixels:(void*)zeroCopyPtr mappedData:(NSData*)mappedData;
- (void) zeroCopyToPixels;
- (void) doneZeroCopyPixels;

@end
