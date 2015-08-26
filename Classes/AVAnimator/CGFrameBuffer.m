//
//  CGFrameBuffer.m
//
//  Created by Moses DeJong on 2/13/09.
//
//  License terms defined in License.txt.

#import "CGFrameBuffer.h"

#import <QuartzCore/QuartzCore.h>

#import <ImageIO/ImageIO.h>

#import <MobileCoreServices/UTCoreTypes.h>

#ifndef __OPTIMIZE__
// Automatically define EXTRA_CHECKS when not optimizing (in debug mode)
# define EXTRA_CHECKS
#endif // DEBUG

// Alignment is not an issue, makes no difference in performance
//#define USE_ALIGNED_VALLOC 1

// Using page copy makes a huge diff, 24 bpp goes from 15->20 FPS to 30 FPS!
#define USE_MACH_VM_ALLOCATE 1

#if defined(USE_ALIGNED_VALLOC) || defined(USE_MACH_VM_ALLOCATE)
#import <unistd.h> // getpagesize()
#endif

#if defined(USE_MACH_VM_ALLOCATE)
#import <mach/mach.h>
#endif

//#define DEBUG_LOGGING

void CGFrameBufferProviderReleaseData (void *info, const void *data, size_t size);

// Private API

@interface CGFrameBuffer ()

// This property indicates the actual size of the allocated buffer pointed to
// by the pixels property. It is possible that the actual allocated size
// is larger than the value returned by the numBytes property, but this
// is an implementation detail of this class and would not need to be known
// outside this module.

@property (readonly) size_t numBytesAllocated;

// This tricky ref to self is needed in ARC mode, since an object cannot invoke retain
// to retain itself. Instead, hold a property that is set to self so that ARC will
// do the retain.

#if __has_feature(objc_arc)
@property (nonatomic, retain) NSObject *arcRefToSelf;
#endif // objc_arc

@end

// class CGFrameBuffer

@implementation CGFrameBuffer

@synthesize pixels = m_pixels;
@synthesize zeroCopyPixels = m_zeroCopyPixels;
@synthesize zeroCopyMappedData = m_zeroCopyMappedData;
@synthesize numBytes = m_numBytes;
@synthesize numBytesAllocated = m_numBytesAllocated;
@synthesize width = m_width;
@synthesize height = m_height;
@synthesize bitsPerPixel = m_bitsPerPixel;
@synthesize bytesPerPixel = m_bytesPerPixel;
//@synthesize isLockedByDataProvider = m_isLockedByDataProvider;
@synthesize lockedByImageRef = m_lockedByImageRef;
@synthesize colorspace = m_colorspace;

#if __has_feature(objc_arc)
@synthesize arcRefToSelf = m_arcRefToSelf;
#endif // objc_arc

+ (CGFrameBuffer*) cGFrameBufferWithBppDimensions:(NSInteger)bitsPerPixel
                                            width:(NSInteger)width
                                           height:(NSInteger)height
{
  CGFrameBuffer *obj = [[CGFrameBuffer alloc] initWithBppDimensions:bitsPerPixel width:width height:height];
#if __has_feature(objc_arc)
  return obj;
#else
  return [obj autorelease];
#endif // objc_arc
}

- (id) initWithBppDimensions:(NSInteger)bitsPerPixel
                       width:(NSInteger)width
                      height:(NSInteger)height;
{
	// Ensure that memory is allocated in terms of whole words, the
	// bitmap context won't make use of the extra half-word.

	size_t numPixels = width * height;
	size_t numPixelsToAllocate = numPixels;

	if ((numPixels % 2) != 0) {
		numPixelsToAllocate++;
	}

  // 16bpp -> 2 bytes per pixel, 24bpp and 32bpp -> 4 bytes per pixel
  
  size_t bytesPerPixel;
  if (bitsPerPixel == 16) {
    bytesPerPixel = 2;
  } else if (bitsPerPixel == 24 || bitsPerPixel == 32) {
    bytesPerPixel = 4;
  } else {
    bytesPerPixel = 0;
    NSAssert(FALSE, @"bitsPerPixel is invalid");
  }
  
	size_t inNumBytes = numPixelsToAllocate * bytesPerPixel;

  // FIXME: if every frame is a key frame, then don't use the kernel memory interface
  // since it would not help at all in terms of performance. Would be faster to
  // just use different buffers.
  
  // FIXME: implement runtime switch for mode, so that code can be compiled once to
  // test out both modes!

	char* buffer;
  size_t allocNumBytes;
  
#if defined(USE_MACH_VM_ALLOCATE)
  size_t pagesize = (size_t)getpagesize();
  size_t numpages = (inNumBytes / pagesize);
  if (inNumBytes % pagesize) {
    numpages++;
  }
  
  kern_return_t ret;
  mach_vm_size_t size = (mach_vm_size_t)(numpages * pagesize);
  allocNumBytes = (size_t)size;
  
  ret = vm_allocate((vm_map_t) mach_task_self(), (vm_address_t*) &buffer, size, VM_FLAGS_ANYWHERE);
  
  if (ret != KERN_SUCCESS) {
    buffer = NULL;
  }
  
  // Note that the returned memory is not zeroed, the first frame is a keyframe, so it will completely
  // fill the framebuffer. Additional frames will be created from a copy of the initial frame.
#else
  // Regular malloc(), or page aligned malloc()
# if defined(USE_ALIGNED_VALLOC)
  size_t pagesize = getpagesize();
  size_t numpages = (inNumBytes / pagesize);
  if (inNumBytes % pagesize) {
    numpages++;
  }
  allocNumBytes = numpages * pagesize;
  buffer = (char*) valloc(allocNumBytes);
  if (buffer) {
    bzero(buffer, allocNumBytes);
  }  
# else
  allocNumBytes = inNumBytes;
  buffer = (char*) malloc(allocNumBytes);
  if (buffer) {
    bzero(buffer, allocNumBytes);
  }  
# endif // USE_ALIGNED_MALLOC
#endif

	if (buffer == NULL) {
		return nil;
  }

  // Verify page alignemnt of the image buffer. The self.pixels pointer must be page
  // aligned to properly support zero copy blit and whole page copy optimizations.

  if (1) {
    uint32_t i32val = (uint32_t)buffer;
    uint32_t pagesize = getpagesize();
    uint32_t mod = i32val % pagesize;
    
    if (mod != 0) {
      NSAssert(0, @"framebuffer is not page aligned : pagesize %d : ptr %p : ptr32 0x%08X : ptr32 mod pagesize %d",
               pagesize,
               buffer,
               i32val,
               mod);
      // Just in case NSAssert() was disabled in opt mode
      assert(0);
    }
  }
  
  if ((self = [super init])) {
    self->m_bitsPerPixel = bitsPerPixel;
    self->m_bytesPerPixel = bytesPerPixel;
    self->m_pixels = buffer;
    self->m_numBytes = inNumBytes;
    self->m_numBytesAllocated = allocNumBytes;
    self->m_width = width;
    self->m_height = height;
  } else {
    free(buffer);
  }

	return self;
}

// Getter for the self.pixels property. Normally, this
// just returns what self.pixels was set to, but in
// the case of the "zero copy mode", this method
// returns the pointer to the read only mapped zero
// copy memory.

- (char*) pixels
{
  char *ptr;
  
  ptr = self.zeroCopyPixels;
  
  if (ptr != NULL) {
    // The framebuffer is in zero copy mode
    return ptr;
  }
  
  return self->m_pixels;
}

- (BOOL) renderView:(UIView*)view
{
  [self doneZeroCopyPixels];
  
	// Capture the pixel content of the View that contains the
	// UIImageView. A view that displays at the full width and
	// height of the screen will be captured in a 320x480
	// bitmap context. Note that any transformations applied
	// to the UIImageView will be captured *after* the
	// transformation has been applied. Once the bitmap
	// context has been captured, it should be rendered with
	// no transformations. Also note that the colorspace
	// is always ARGB with no alpha, the bitmap capture happens
	// *after* any colors in the image have been converted to RGB pixels.

	size_t w = view.layer.bounds.size.width;
	size_t h = view.layer.bounds.size.height;

//	if ((self.width != w) || (self.height != h)) {
//		return FALSE;
//	}

//	BOOL isRotated;

	if ((self.width == w) && (self.height == h)) {
//		isRotated = FALSE;
	} else if ((self.width == h) || (self.height != w)) {
		// view must have created a rotation transformation
//		isRotated = TRUE;
	} else {
		return FALSE;
	}
  
  size_t bitsPerComponent = 0;
  size_t numComponents = 0;
  size_t bitsPerPixel = 0;
  size_t bytesPerRow = 0;
  
  if (self.bitsPerPixel == 16) {
    bitsPerComponent = 5;
//    numComponents = 3;
    bitsPerPixel = 16;
    bytesPerRow = self.width * (bitsPerPixel / 8);    
  } else if (self.bitsPerPixel == 24 || self.bitsPerPixel == 32) {
    bitsPerComponent = 8;
    numComponents = 4;
    bitsPerPixel = bitsPerComponent * numComponents;
    bytesPerRow = self.width * (bitsPerPixel / 8);
  } else {
    NSAssert(FALSE, @"unmatched bitsPerPixel");
  }

	CGBitmapInfo bitmapInfo = [self getBitmapInfo];

  CGColorSpaceRef colorSpace = self.colorspace;
  if (colorSpace) {
    CGColorSpaceRetain(colorSpace);
  } else {
    colorSpace = CGColorSpaceCreateDeviceRGB();
  }
  
	NSAssert(self.pixels != NULL, @"pixels must not be NULL");

	NSAssert(self.isLockedByDataProvider == FALSE, @"renderView: pixel buffer locked by data provider");

	CGContextRef bitmapContext =
		CGBitmapContextCreate(self.pixels, self.width, self.height, bitsPerComponent, bytesPerRow, colorSpace, bitmapInfo);

	CGColorSpaceRelease(colorSpace);

	if (bitmapContext == NULL) {
		return FALSE;
	}

	// Translation matrix that maps CG space to view space

	CGContextTranslateCTM(bitmapContext, 0.0, self.height);
	CGContextScaleCTM(bitmapContext, 1.0, -1.0);

	[view.layer renderInContext:bitmapContext];

	CGContextRelease(bitmapContext);

	return TRUE;
}

- (BOOL) renderCGImage:(CGImageRef)cgImageRef
{
  [self doneZeroCopyPixels];
  
	// Render the contents of an image to pixels.

	size_t w = CGImageGetWidth(cgImageRef);
	size_t h = CGImageGetHeight(cgImageRef);
	
	BOOL isRotated = FALSE;

	if ((w != h) && (h == self.width) && (w == self.height)) {
    // Assume image is rotated to portrait, so rotate and then render
		isRotated = TRUE;
  } else {
    // If sizes do not match, then resize input image to fit into this framebuffer
  }
	
  size_t bitsPerComponent = 0;
  size_t numComponents = 0;
  size_t bitsPerPixel = 0;
  size_t bytesPerRow = 0;
  
  if (self.bitsPerPixel == 16) {
    bitsPerComponent = 5;
//    numComponents = 3;
    bitsPerPixel = 16;
    bytesPerRow = self.width * (bitsPerPixel / 8);    
  } else if (self.bitsPerPixel == 24 || self.bitsPerPixel == 32) {
    bitsPerComponent = 8;
    numComponents = 4;
    bitsPerPixel = bitsPerComponent * numComponents;
    bytesPerRow = self.width * (bitsPerPixel / 8);
  } else {
    NSAssert(FALSE, @"unmatched bitsPerPixel");
  }
  
	CGBitmapInfo bitmapInfo = [self getBitmapInfo];
	
  CGColorSpaceRef colorSpace = self.colorspace;
  if (colorSpace) {
    CGColorSpaceRetain(colorSpace);
  } else {
    colorSpace = CGColorSpaceCreateDeviceRGB();
  }

	NSAssert(self.pixels != NULL, @"pixels must not be NULL");
	NSAssert(self.isLockedByDataProvider == FALSE, @"renderCGImage: pixel buffer locked by data provider");

	CGContextRef bitmapContext =
		CGBitmapContextCreate(self.pixels, self.width, self.height, bitsPerComponent, bytesPerRow, colorSpace, bitmapInfo);
	
	CGColorSpaceRelease(colorSpace);
	
	if (bitmapContext == NULL) {
		return FALSE;
	}
	
	// Translation matrix that maps CG space to view space

	if (isRotated) {
		// To landscape : 90 degrees CCW

		CGContextRotateCTM(bitmapContext, M_PI / 2);		
	}

	CGRect bounds = CGRectMake( 0.0f, 0.0f, self.width, self.height );

	CGContextDrawImage(bitmapContext, bounds, cgImageRef);
	
	CGContextRelease(bitmapContext);
	
	return TRUE;
}

- (CGContextRef) createBitmapContext
{
  [self doneZeroCopyPixels];
	
  size_t bitsPerComponent = 0;
  size_t numComponents = 0;
  size_t bitsPerPixel = 0;
  size_t bytesPerRow = 0;
  
  if (self.bitsPerPixel == 16) {
    bitsPerComponent = 5;
    //    numComponents = 3;
    bitsPerPixel = 16;
    bytesPerRow = self.width * (bitsPerPixel / 8);    
  } else if (self.bitsPerPixel == 24 || self.bitsPerPixel == 32) {
    bitsPerComponent = 8;
    numComponents = 4;
    bitsPerPixel = bitsPerComponent * numComponents;
    bytesPerRow = self.width * (bitsPerPixel / 8);
  } else {
    NSAssert(FALSE, @"unmatched bitsPerPixel");
  }
  
	CGBitmapInfo bitmapInfo = [self getBitmapInfo];
	
  CGColorSpaceRef colorSpace = self.colorspace;
  if (colorSpace) {
    CGColorSpaceRetain(colorSpace);
  } else {
    colorSpace = CGColorSpaceCreateDeviceRGB();
  }
  
	NSAssert(self.pixels != NULL, @"pixels must not be NULL");
	NSAssert(self.isLockedByDataProvider == FALSE, @"createBitmapContext: pixel buffer locked by data provider");
  
	CGContextRef bitmapContext =
    CGBitmapContextCreate(self.pixels, self.width, self.height, bitsPerComponent, bytesPerRow, colorSpace, bitmapInfo);
	
	CGColorSpaceRelease(colorSpace);
	
	if (bitmapContext == NULL) {
		return NULL;
	}
	
	return bitmapContext;
}

- (CGImageRef) createCGImageRef
{
	// Load pixel data as a core graphics image object.

  NSAssert(self.width > 0 && self.height > 0, @"width or height is zero");

  size_t bitsPerComponent = 0;
  size_t numComponents = 0;
  size_t bitsPerPixel = 0;
  size_t bytesPerRow = 0;
  
  if (self.bitsPerPixel == 16) {
    bitsPerComponent = 5;
//    numComponents = 3;
    bitsPerPixel = 16;
    bytesPerRow = self.width * (bitsPerPixel / 8);    
  } else if (self.bitsPerPixel == 24 || self.bitsPerPixel == 32) {
    bitsPerComponent = 8;
    numComponents = 4;
    bitsPerPixel = bitsPerComponent * numComponents;
    bytesPerRow = self.width * (bitsPerPixel / 8);
  } else {
    NSAssert(FALSE, @"unmatched bitsPerPixel");
  }  

	CGBitmapInfo bitmapInfo = [self getBitmapInfo];

	CGDataProviderReleaseDataCallback releaseData = CGFrameBufferProviderReleaseData;

  void *pixelsPtr = self.pixels; // Will return zero copy pointer in zero copy mode. Otherwise self.pixels
  
	CGDataProviderRef dataProviderRef = CGDataProviderCreateWithData(
#if __has_feature(objc_arc)
																	 (__bridge void *)self,
#else
																	 self,
#endif // objc_arc
																	 pixelsPtr,
																	 self.width * self.height * (bitsPerPixel / 8),
																	 releaseData);

	BOOL shouldInterpolate = FALSE; // images at exact size already

	CGColorRenderingIntent renderIntent = kCGRenderingIntentDefault;

  CGColorSpaceRef colorSpace = self.colorspace;
  if (colorSpace) {
    CGColorSpaceRetain(colorSpace);
  } else {
    colorSpace = CGColorSpaceCreateDeviceRGB();
  }

	CGImageRef inImageRef = CGImageCreate(self.width, self.height, bitsPerComponent, bitsPerPixel, bytesPerRow,
										  colorSpace, bitmapInfo, dataProviderRef, NULL,
										  shouldInterpolate, renderIntent);

	CGDataProviderRelease(dataProviderRef);

	CGColorSpaceRelease(colorSpace);

	if (inImageRef != NULL) {
		self.isLockedByDataProvider = TRUE;
		self->m_lockedByImageRef = inImageRef; // Don't retain, just save pointer
	}

	return inImageRef;
}

- (BOOL) isLockedByImageRef:(CGImageRef)cgImageRef
{
	if (! self->m_isLockedByDataProvider)
		return FALSE;

	return (self->m_lockedByImageRef == cgImageRef);
}

- (CGBitmapInfo) getBitmapInfo
{
	CGBitmapInfo bitmapInfo = 0;
  if (self.bitsPerPixel == 16) {
    bitmapInfo = kCGBitmapByteOrder16Host | kCGImageAlphaNoneSkipFirst;
  } else if (self.bitsPerPixel == 24) {
    bitmapInfo |= kCGBitmapByteOrder32Host | kCGImageAlphaNoneSkipFirst;
  } else if (self.bitsPerPixel == 32) {
    bitmapInfo |= kCGBitmapByteOrder32Host | kCGImageAlphaPremultipliedFirst;
  } else {
    assert(0);
  }
	return bitmapInfo;
}

// These properties are implemented explicitly to aid
// in debugging of read/write operations. These method
// are used to set values that could be set in one thread
// and read or set in another. The code must take care to
// use these fields correctly to remain thread safe.

- (BOOL) isLockedByDataProvider
{
	return self->m_isLockedByDataProvider;
}

#if __has_feature(objc_arc)

// The arc impl uses a property of type NSObject to hold a ref to itself
// during the time that the buffer is locked by CoreGraphics.

- (void) setIsLockedByDataProvider:(BOOL)newValue
{
	NSAssert(m_isLockedByDataProvider == !newValue,
           @"isLockedByDataProvider property can only be switched");
  
	self->m_isLockedByDataProvider = newValue;
  
	if (self->m_isLockedByDataProvider) {
    self.arcRefToSelf = self;
	} else {
    self.arcRefToSelf = nil;
	}
}

#else

// non-arc impl the explicitly invokes retain/release and does some tricky logging

- (void) setIsLockedByDataProvider:(BOOL)newValue
{
	NSAssert(m_isLockedByDataProvider == !newValue,
			 @"isLockedByDataProvider property can only be switched");

	self->m_isLockedByDataProvider = newValue;

	if (m_isLockedByDataProvider) {
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

#endif // objc_arc

// Set all pixels to 0x0

- (void) clear
{
  [self doneZeroCopyPixels];
  bzero(self.pixels, self.numBytes);
}

- (void) osCopyImpl:(void*)srcPtr
{  
#if defined(USE_MACH_VM_ALLOCATE)
  kern_return_t ret;
  vm_address_t src = (vm_address_t) srcPtr;
  vm_address_t dst = (vm_address_t) self->m_pixels;
  
#if defined(EXTRA_CHECKS)
  // Do extra checking to ensure that the zero copy region is
  // properly page aligned and that the number of bytes to
  // copy is an exact multiple of the page size.
  
  size_t s = getpagesize();

  if ((self.numBytesAllocated % s) != 0) {
    assert(0);
  }
  
  if ((dst % s) != 0) {
    assert(0);
  }
  if ((src % s) != 0) {
    assert(0);
  }
#endif // EXTRA_CHECKS
  
  ret = vm_copy((vm_map_t) mach_task_self(), src, (vm_size_t) self.numBytesAllocated, dst);
  if (ret != KERN_SUCCESS) {
    assert(0);
  }
#else
  // FIXME: add assert here to check num bytes
  // FIXME: this code will not compile if USE_MACH_VM_ALLOCATE is not defined
  memcpy(self->m_pixels, anotherFrameBufferPixelsPtr, anotherFrameBuffer.numBytes);
#endif  
}

- (void) copyPixels:(CGFrameBuffer *)anotherFrameBuffer
{
  assert(self.numBytes == anotherFrameBuffer.numBytes);

  [self doneZeroCopyPixels];
  void *anotherFrameBufferPixelsPtr = anotherFrameBuffer.zeroCopyPixels;

  if (anotherFrameBufferPixelsPtr) {
    // other framebuffer has a zero copy pixel buffer, this happes when a keyframe
    // is followed by a delta frame. Use the original zero copy pointer as the
    // source for a OS level page copy operation, but don't modify the state of
    // the other frame buffer in any way since it could be used by the graphics
    // subsystem currently.
  } else {
    // copy bytes from other framebuffer
    anotherFrameBufferPixelsPtr = anotherFrameBuffer.pixels;
  }
  
  [self osCopyImpl:anotherFrameBufferPixelsPtr];
}

// Explicitly memcopy pixels instead of an OS level page copy,
// this is useful only when we want to deallocate the mapped
// memory and an os copy would keep that memory mapped.

- (void) memcopyPixels:(CGFrameBuffer *)anotherFrameBuffer
{
  [self doneZeroCopyPixels];
  assert(self.zeroCopyMappedData == nil);
  assert(self.zeroCopyPixels == NULL);
  assert(self.numBytes == anotherFrameBuffer.numBytes);
  
  void *anotherFrameBufferPixelsPtr = anotherFrameBuffer.zeroCopyPixels;
  
  if (anotherFrameBufferPixelsPtr) {
    // other framebuffer has a zero copy pixel buffer, this happes when a keyframe
    // is followed by a delta frame. Use the original zero copy pointer as the
    // source for a OS level page copy operation, but don't modify the state of
    // the other frame buffer in any way since it could be used by the graphics
    // subsystem currently.
  } else {
    // copy bytes from other framebuffer
    anotherFrameBufferPixelsPtr = anotherFrameBuffer.pixels;
  }
  
  memcpy(self.pixels, anotherFrameBufferPixelsPtr, anotherFrameBuffer.numBytes);
}

// Copy the contents of the zero copy buffer to the allocated framebuffer and
// release the zero copy bytes.

- (void) zeroCopyToPixels
{
  if (self.zeroCopyPixels == NULL) {
    // No zero copy pixels in use, so this is a no-op
    return;
  }
    
  [self osCopyImpl:self.zeroCopyPixels];
  
  // Release zero copy buffer
  
  [self doneZeroCopyPixels];
}

- (void)dealloc {
	NSAssert(self.isLockedByDataProvider == FALSE, @"dealloc: buffer still locked by data provider");
  [self doneZeroCopyPixels];

	self.colorspace = NULL;
  
#if defined(USE_MACH_VM_ALLOCATE)
	if (self.pixels != NULL) {
    kern_return_t ret;
    ret = vm_deallocate((vm_map_t) mach_task_self(), (vm_address_t) self.pixels, (vm_size_t) self.numBytesAllocated);
    if (ret != KERN_SUCCESS) {
      assert(0);
    }
  }  
#else
	if (self.pixels != NULL) {
		free(self.pixels);
  }
#endif

#ifdef DEBUG_LOGGING
	NSLog(@"deallocate CGFrameBuffer");
#endif

  self.zeroCopyMappedData = nil;
  
#if __has_feature(objc_arc)
  // It should not actually be possible for this method to be invoked if arcRefToSelf is non-nil
  self.arcRefToSelf = nil;
#else
  [super dealloc];
#endif // objc_arc
}

// Save a "zero copy" pointer and a ref to the mapped data. Invoking this function
// means that the self.pixels getter will return the value of the self.zeroCopyPixels
// and the data in the frame buffer will be ignored until doneZeroCopyPixels is invoked.

- (void) zeroCopyPixels:(void*)zeroCopyPtr
             mappedData:(NSData*)mappedData
{
#if defined(EXTRA_CHECKS)
  // Do extra checking to ensure that the zero copy region is
  // properly page aligned and that the number of bytes to
  // copy is an exact multiple of the page size.
  
  size_t ptr = zeroCopyPtr;
  size_t s = getpagesize();
  
  if ((ptr % s) != 0) {
    assert(0);
  }
#endif // EXTRA_CHECKS
  
  self->m_zeroCopyPixels = zeroCopyPtr;
  self.zeroCopyMappedData = mappedData;
}

// Exit zero copy mode.

- (void) doneZeroCopyPixels
{
  NSAssert(self.isLockedByDataProvider == FALSE, @"isLockedByDataProvider");
  self->m_zeroCopyPixels = NULL;
  self.zeroCopyMappedData = nil;
}

- (NSString*) description
{
  return [NSString stringWithFormat:@"CGFrameBuffer %p, pixels %p, %d x %d, %d BPP, isLocked %d", self, self.pixels,
          (int)self.width, (int)self.height, (int)self.bitsPerPixel, (int)self.isLockedByDataProvider];
}

// Setter for self.colorspace property. While this property is declared as assign,
// it will actually retain a ref to the colorspace.

- (void) setColorspace:(CGColorSpaceRef)colorspace
{
  if (colorspace) {
    CGColorSpaceRetain(colorspace);
  }
  
  if (self->m_colorspace) {
    CGColorSpaceRelease(self->m_colorspace);
  }
  
  self->m_colorspace = colorspace;
}

- (void) clearAlphaChannel
{
  assert(self.isLockedByDataProvider == FALSE);
  //assert(self.bitsPerPixel == 24);
  
  uint32_t *pixelsPtr  = (uint32_t*) self.pixels;
  uint32_t numPixels = (uint32_t)(self.width * self.height);
  
  for (int i = 0; i < numPixels; i++) {
    uint32_t value = pixelsPtr[i];
    assert((value >> 24) == 0xFF || (value >> 24) == 0x0);
    // Throw out alpha values
    value = value & 0xFFFFFF;
    pixelsPtr[i] = value;
  }
}

// This method resets the alpha channel for each pixel to be fully opaque.

- (void) resetAlphaChannel
{
  assert(self.isLockedByDataProvider == FALSE);
  //assert(self.bitsPerPixel == 24);
  
  uint32_t *pixelsPtr  = (uint32_t*) self.pixels;
  uint32_t numPixels = (uint32_t)(self.width * self.height);
  
  for (int i = 0; i < numPixels; i++) {
    uint32_t value = pixelsPtr[i];
    value = (0xFF << 24) | value;
    pixelsPtr[i] = value;
  }
}

// Convert pixels to a PNG image format that can be easily saved to disk.

- (NSData*) formatAsPNG
{
  NSMutableData *mData = [NSMutableData data];
  
  @autoreleasepool {
    
    // Render buffer as a PNG image
    
    CFStringRef type = kUTTypePNG;
    size_t count = 1;
    CGImageDestinationRef dataDest;
    dataDest = CGImageDestinationCreateWithData(
#if __has_feature(objc_arc)
                                                (__bridge CFMutableDataRef)mData,
#else
                                                (CFMutableDataRef)mData,
#endif // objc_arc
                                                type,
                                                count,
                                                NULL);
    assert(dataDest);
    
    CGImageRef imgRef = [self createCGImageRef];
    
    CGImageDestinationAddImage(dataDest, imgRef, NULL);
    CGImageDestinationFinalize(dataDest);
    
    CGImageRelease(imgRef);
    CFRelease(dataDest);
    
    // Return instance object that was allocated outside the scope of pool
    
  }
  
  return [NSData dataWithData:mData];
}

@end

// C callback invoked by core graphics when done with a buffer, this is tricky
// since an extra ref is held on the buffer while it is locked by the
// core graphics layer.

void CGFrameBufferProviderReleaseData (void *info, const void *data, size_t size) {
#ifdef DEBUG_LOGGING
	NSLog(@"CGFrameBufferProviderReleaseData() called");
#endif

  	CGFrameBuffer *cgBuffer;
#if __has_feature(objc_arc)
  cgBuffer = (__bridge CGFrameBuffer *) info;
#else
	cgBuffer = (CGFrameBuffer *) info;
#endif // objc_arc

	cgBuffer.isLockedByDataProvider = FALSE;

	// Note that the cgBuffer just deallocated itself, so the
	// pointer no longer points to valid memory.
}
