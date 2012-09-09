//
//  AVFrame.m
//
//  Created by Moses DeJong on 9/2/12.
//
//  License terms defined in License.txt.

#import "AVFrame.h"

#import "CGFrameBuffer.h"

@implementation AVFrame

@synthesize image = m_image;
@synthesize cgFrameBuffer = m_cgFrameBuffer;
@synthesize isDuplicate = m_isDuplicate;

// Constructor

+ (AVFrame*) aVFrame
{
  AVFrame *obj = [[[AVFrame alloc] init] autorelease];
  return obj;
}

- (void) dealloc
{
  self.image = nil;
  self.cgFrameBuffer = nil;
  [super dealloc];
}

- (void) makeImageFromFramebuffer
{
  // Release previous image if there was one created from this frame buffer
  
  self.image = nil;
  
  CGFrameBuffer *cgFrameBuffer = self.cgFrameBuffer;
  
  CGImageRef imgRef = [cgFrameBuffer createCGImageRef];
  NSAssert(imgRef != NULL, @"CGImageRef returned by createCGImageRef is NULL");
  
  // Note that we create a pool around the allocation of the image object
  // so that after the assignment to self.image, the only active reference
  // lives in this object. If the image object is created in the caller's
  // autorelease pool then we could not set image property to release.
  
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  
#if TARGET_OS_IPHONE
  UIImage *uiImage = [UIImage imageWithCGImage:imgRef];
  NSAssert(uiImage, @"uiImage is nil");
  
  self.image = uiImage;
#else
  // Mac OS X

  NSSize size = NSMakeSize(cgFrameBuffer.width, cgFrameBuffer.height);
  NSImage *nsImage = [[[NSImage alloc] initWithCGImage:imgRef size:size] autorelease];
  NSAssert(nsImage, @"nsImage is nil");
  
  self.image = nsImage;
#endif // TARGET_OS_IPHONE
  
  CGImageRelease(imgRef);
  
  [pool drain];
  
  NSAssert(cgFrameBuffer.isLockedByDataProvider, @"image buffer should be locked by frame image");  
}

@end
