//
//  CGFrameBuffer.h
//  AVAnimatorDemo
//
//  Created by Moses DeJong on 2/13/09.
//  Copyright 2009 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>

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

@public
	char *pixels;
	size_t numBytes;
	size_t width;
	size_t height;
	char idc;

@private
	int32_t _isLockedByDataProvider;
	CGImageRef lockedByImageRef;
}

@property (readonly) char *pixels;
@property (readonly) size_t numBytes;
@property (readonly) size_t width;
@property (readonly) size_t height;

@property (nonatomic, assign) BOOL isLockedByDataProvider;

@property (nonatomic, assign) char idc;

- (id) initWithDimensions:(NSInteger)inWidth :(NSInteger)inHeight;

// Render the contents of a view as pixels. Returns TRUE
// is successful, otherwise FALSE. Note that the view
// must be opaque and render all of its pixels. 

- (BOOL) renderView:(UIView*)view;

// Render a CGImageRef directly into the pixels

- (BOOL) renderCGImage:(CGImageRef)cgImageRef;

// Create a Core Graphics image from the pixel data
// in this buffer. The hasDataProvider property
// will be TRUE while the CGImageRef is in use.
// This name is upper case to avoid warnings from the analyzer.

- (CGImageRef) createCGImageRef CF_RETURNS_RETAINED;

// Defines the pixel layout, could be overloaded in a derived class

- (CGBitmapInfo) getBitmapInfo;

- (BOOL) isLockedByImageRef:(CGImageRef)cgImageRef;

// Copy data from another framebuffer into this one

- (void) copyPixels:(CGFrameBuffer *)anotherFrameBuffer;

@end
