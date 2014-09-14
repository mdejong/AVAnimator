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
@synthesize cvBufferRef = m_cvBufferRef;
@synthesize isDuplicate = m_isDuplicate;

// Constructor

+ (AVFrame*) aVFrame
{
  AVFrame *obj = [[AVFrame alloc] init];
#if __has_feature(objc_arc)
  return obj;
#else
  return [obj autorelease];
#endif // objc_arc
}

- (void) dealloc
{
  self.image = nil;
  self.cgFrameBuffer = nil;
  self.cvBufferRef = NULL;
  
#if __has_feature(objc_arc)
#else
  [super dealloc];
#endif // objc_arc
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
  
  @autoreleasepool {
  
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
  
  }
  
  NSAssert(cgFrameBuffer.isLockedByDataProvider, @"image buffer should be locked by frame image");  
}

// Setter for self.cvBufferRef, this logic holds on to a retain for the CoreVideo buffer

- (void) setCvBufferRef:(CVImageBufferRef)cvBufferRef
{
  if (cvBufferRef) {
    CFRetain(cvBufferRef);
  }
  if (self->m_cvBufferRef) {
    CFRelease(self->m_cvBufferRef);
  }
  self->m_cvBufferRef = cvBufferRef;
}

- (NSString*) description
{
  return [NSString stringWithFormat:@"AVFrame %p (isDuplicate = %d), self.image %p, self.cgFrameBuffer %p, self.cvBufferRef %p",
          self,
          self.isDuplicate,
          self.image,
          self.cgFrameBuffer,
          self.cvBufferRef];
}

@end
