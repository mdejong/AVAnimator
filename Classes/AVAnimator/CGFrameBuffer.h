//
//  CGFrameBuffer.h
//  AVAnimatorDemo
//
//  Created by Moses DeJong on 2/13/09.
//  Copyright 2009 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface CGFrameBuffer : NSObject {

@public
	char *pixels;
	size_t numBytes;
	size_t width;
	size_t height;
	NSUInteger frameIndex;
	char idc;

@private
	int32_t _isLockedByDataProvider;
	CGImageRef lockedByImageRef;
}

@property (readonly) char *pixels;
@property (readonly) size_t numBytes;
@property (readonly) size_t width;
@property (readonly) size_t height;
@property (readonly) NSUInteger frameIndex;

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

- (CGImageRef) createCGImageRef;

// Defines the pixel layout, could be overloaded in a derived class

- (CGBitmapInfo) getBitmapInfo;

- (BOOL) isLockedByImageRef:(CGImageRef)cgImageRef;

// Copy data from another framebuffer into this one

- (void) copyPixels:(CGFrameBuffer *)anotherFrameBuffer;

@end
