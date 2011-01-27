//
//  AVAnimatorView.m
//
//  Created by Moses DeJong on 3/18/09.
//
//  License terms defined in License.txt.

#import "AVAnimatorView.h"

#import <QuartzCore/QuartzCore.h>

#import <AVFoundation/AVAudioPlayer.h>

#import <AudioToolbox/AudioFile.h>
#import "AudioToolbox/AudioServices.h"

#import "CGFrameBuffer.h"
#import "AVResourceLoader.h"
#import "AVFrameDecoder.h"

#import "AVAnimatorMedia.h"

// private properties declaration for AVAnimatorView class
#include "AVAnimatorViewPrivate.h"

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
  
  if (self.mediaObj) {
    [self.mediaObj detachFromRenderer:self];
    self.mediaObj = nil;
  }
  
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
  if (self = [super initWithFrame:frame]) {
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

// This method is invoked once resources have been loaded by the media

- (void) mediaDidLoad
{
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
  
	return;
}

// FIXME: remove, since loading of window is unrelated to loading of resources!

- (BOOL) isReadyToRender
{
  if (self.window == nil) {
    return FALSE;
  } else {
    return TRUE;    
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
  if (inMedia == nil) {
    // Detach case
    
    [self.mediaObj detachFromRenderer:self];
    self.mediaObj = nil;
    return;
  }
  
  // Attach case
  
  NSAssert(self.window, @"AVAnimatorView must have been added to a window before media can be attached");

  [self.mediaObj detachFromRenderer:self];
  self.mediaObj = inMedia;
  [self.mediaObj attachToRenderer:self];
}

// Implement read-only property for use outside this class

- (AVAnimatorMedia*) media
{
  return self->m_mediaObj;
}

@end
