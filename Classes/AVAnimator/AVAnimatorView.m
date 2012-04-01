//
//  AVAnimatorView.m
//
//  Created by Moses DeJong on 3/18/09.
//
//  License terms defined in License.txt.

#import "AVAnimatorView.h"

#import <QuartzCore/QuartzCore.h>

#import "AVFrameDecoder.h"

#import "AVAnimatorMedia.h"

#import "AutoPropertyRelease.h"

// private properties declaration for AVAnimatorView class
#include "AVAnimatorViewPrivate.h"

// private method in Media class
#include "AVAnimatorMediaPrivate.h"

// AVAnimatorView class

@implementation AVAnimatorView

// public properties

@synthesize animatorOrientation = m_animatorOrientation;
@synthesize renderSize = m_renderSize;
@synthesize mediaObj = m_mediaObj;

- (void) dealloc {
	// Explicitly release image inside the imageView, the
	// goal here is to get the imageView to drop the
	// ref to the CoreGraphics image and avoid a memory
	// leak. This should not be needed, but it is.
  
	self.image = nil;
  
  // Detach but don't bother making a copy of the final image
  
  if (self.mediaObj) {
    [self.mediaObj detachFromRenderer:self copyFinalFrame:FALSE];
  }
  
  [AutoPropertyRelease releaseProperties:self thisClass:AVAnimatorView.class];
  [super dealloc];
}

// static ctor

+ (AVAnimatorView*) aVAnimatorView
{
  return [AVAnimatorView aVAnimatorViewWithFrame:[UIScreen mainScreen].applicationFrame];
}

+ (AVAnimatorView*) aVAnimatorViewWithFrame:(CGRect)viewFrame
{
  AVAnimatorView *obj = [[AVAnimatorView alloc] initWithFrame:viewFrame];
  [obj autorelease];
  return obj;
}

- (id) initWithFrame:(CGRect)frame
{
  if ((self = [super initWithFrame:frame])) {
    // Defaults for opacity related properties. We expect the view to be
    // fully opaque since the image renders all the pixels in the view.
    // Unless in 32bpp mode, in that case pixels can be partially transparent.
    
    self.opaque = TRUE;
    self.clearsContextBeforeDrawing = FALSE;
    self.backgroundColor = nil;
  }
  return self;
}

// This loadViewImpl method is not the atomatically invoked loadView from the view controller class.
// It needs to be explicitly invoked after the view widget has been created.

- (void) _loadViewImpl {
	BOOL isRotatedToLandscape = FALSE;
	size_t renderWidth, renderHeight;

  // If loadViewImpl was already invoked, ignore.
  
  if (self.renderSize.width > 0) {
    return;
  }
  
	if (self.animatorOrientation == UIImageOrientationUp) {
		isRotatedToLandscape = FALSE;
	} else if (self.animatorOrientation == UIImageOrientationLeft) {
		// 90 deg CCW for Landscape Orientation
		isRotatedToLandscape = TRUE;
	} else if (self.animatorOrientation == UIImageOrientationRight) {
		// 90 deg CW for Landscape Right Orientation
		isRotatedToLandscape = TRUE;
	} else if (self.animatorOrientation == UIImageOrientationDown) {
		// 180 deg CW rotation
		isRotatedToLandscape = FALSE;    
	} else {
		NSAssert(FALSE,@"Unsupported animatorOrientation");
	}
	
	if (!isRotatedToLandscape) {
		if (self.animatorOrientation == UIImageOrientationDown) {
      [self rotateToUpsidedown];
    }
	} else  {
		if (self.animatorOrientation == UIImageOrientationLeft) {
			[self rotateToLandscape];
		} else {
			[self rotateToLandscapeRight];
    }
	}
  
  // FIXME: order of operations condition here between container setting frame and
  // this method getting invoked! Make sure frame change is not processed after this!
  
	if (isRotatedToLandscape) {
		renderWidth = self.frame.size.height;
		renderHeight = self.frame.size.width;
	} else {
		renderWidth = self.frame.size.width;
		renderHeight = self.frame.size.height;
	}
  
	//	renderWidth = applicationFrame.size.width;
	//	renderHeight = applicationFrame.size.height;
  
	CGSize rs;
	rs.width = renderWidth;
	rs.height = renderHeight;
	self.renderSize = rs;
    
	// User events to this layer are ignored
  
	self.userInteractionEnabled = FALSE;
  
  return;
}

- (void) _setOpaqueFromDecoder
{
  NSAssert(self->mediaDidLoad, @"mediaDidLoad must be TRUE");
  NSAssert(self.media, @"media is nil");
  NSAssert(self.media.frameDecoder, @"frameDecoder is nil");
  
  // Query alpha channel support in frame decoder
  
  if ([self.media.frameDecoder hasAlphaChannel]) {
    // This view will blend with other views when pixels are transparent
    // or partially transparent.
    self.opaque = FALSE;
  } else {
    self.opaque = TRUE;
  }  
}

// Invoked with TRUE argument once renderer has been attached to loaded media,
// otherwise FALSE is passed to indicate the renderer could not be attached

- (void) mediaAttached:(BOOL)worked
{
  if (worked) {
    NSAssert(self.media, @"media is nil");
    self->mediaDidLoad = TRUE;
    [self _setOpaqueFromDecoder];
  } else {
    self.mediaObj = nil;
    self->mediaDidLoad = FALSE;
  }
  
	return;
}

//- (void) setOpaque:(BOOL)newValue
//{
//  [super setOpaque:newValue];
//}

//- (BOOL) isOpaque
//{
//  return [super isOpaque];
//}

// This method is invoked as part of the AVAnimatorMediaRendererProtocol,
// the property is defined by the UIImageView class, but that class seems
// to implicitly set the opaque property to FALSE each time the image
// property is changed. The result of this implementation is sub-optimal
// rendering because the view does not know that all pixels are rendered.

- (void) setImage:(UIImage*)image
{
  if (image == nil) {
    [super setImage:image];
  } else {
    BOOL opaqueBefore = [super isOpaque];
    [super setImage:image];
    // Explicitly set the opaque property only when we know the media was loaded.
    // This makes it possible to set the image to a resource image while waiting
    // for the media to load.
    if (self->mediaDidLoad) {
      [self _setOpaqueFromDecoder];
      BOOL opaqueAfter = [super isOpaque];
      NSAssert(opaqueBefore == opaqueAfter, @"opaque");
    }    
  }
}

- (void) rotateToPortrait
{
	self.layer.transform = CATransform3DIdentity;
}

- (void) rotateToUpsidedown
{
  float angle = M_PI;  //rotate CCW 180°, or π radians
	self.layer.transform = CATransform3DMakeRotation(angle, 0, 0.0, 1.0);
}

- (void) landscapeCenterAndRotate:(UIView*)viewToRotate
                            angle:(float)angle
{
  float portraitWidth = self.frame.size.height;
  float portraitHeight = self.frame.size.width;
  float landscapeWidth = portraitHeight;
  float landscapeHeight = portraitWidth;
  
	float landscapeHalfWidth = landscapeWidth / 2.0;
	float landscapeHalfHeight = landscapeHeight / 2.0;
	
	int portraitHalfWidth = portraitWidth / 2.0;
	int portraitHalfHeight = portraitHeight / 2.0;
	
	int xoff = landscapeHalfWidth - portraitHalfWidth;
	int yoff = landscapeHalfHeight - portraitHalfHeight;	
  
	CGRect frame = CGRectMake(-xoff, -yoff, landscapeWidth, landscapeHeight);
	viewToRotate.frame = frame;

  viewToRotate.layer.transform = CATransform3DMakeRotation(angle, 0, 0.0, 1.0);
}

- (void) rotateToLandscape
{
	float angle = M_PI / 2;  //rotate CCW 90°, or π/2 radians
  [self landscapeCenterAndRotate:self angle:angle];
}

- (void) rotateToLandscapeRight
{
	float angle = -1 * (M_PI / 2);  //rotate CW 90°, or -π/2 radians
  [self landscapeCenterAndRotate:self angle:angle];
}

// Invoked when UIView is added to a window. This is typically invoked at some idle
// time when the windowing system is pepared to handle reparenting.

- (void)willMoveToWindow:(UIWindow *)newWindow
{
  [super willMoveToWindow:newWindow];
  if (newWindow != nil) {
    [self _loadViewImpl];
  }
}

- (void) attachMedia:(AVAnimatorMedia*)inMedia
{
  if (self.mediaObj == inMedia) {
    // Detaching and the reattaching the same media is a no-op
    return;
  }
  
  if (inMedia == nil) {
    // Detach case, not attaching another media object so copy
    // the last rendered frame.
    
    [self.mediaObj detachFromRenderer:self copyFinalFrame:TRUE];
    self.mediaObj = nil;
    self->mediaDidLoad = FALSE;
    return;
  }
  
  // Attach case
  
  NSAssert(self.window, @"AVAnimatorView must have been added to a window before media can be attached");
  
  [self.mediaObj detachFromRenderer:self copyFinalFrame:FALSE];
  self.mediaObj = inMedia;
  self->mediaDidLoad = FALSE;
  [self.mediaObj attachToRenderer:self];
}

// Implement read-only property for use outside this class

- (AVAnimatorMedia*) media
{
  return self->m_mediaObj;
}

// Implement these methods to raise an error if they are accidently invoked by the user of this class.
// These methods should not be used since they are part of the UIImageView animation logic.

- (void) startAnimation
{
  NSAssert(FALSE, @"should invoke startAnimation on media object instead");
}

- (void) stopAnimation
{
  NSAssert(FALSE, @"should invoke stopAnimator on media object instead");
}

@end
