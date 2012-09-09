//
//  AVFrame.h
//
//  Created by Moses DeJong on 9/2/12.
//
//  License terms defined in License.txt.
//
//  This class defines a platform specific "frame" object that "contains" visual
//  information for one specific frame in an animaton or movie. Code that executes
//  only on one platform may access platform specific properties, but general
//  purpose code can safely pass around a reference to a AVFrame without platform
//  specific concerns.

#import <Foundation/Foundation.h>

#if TARGET_OS_IPHONE
#import <UIKit/UIKit.h>
#else
#import <Cocoa/Cocoa.h>
#endif

@class CGFrameBuffer;

@interface AVFrame : NSObject
{
#if TARGET_OS_IPHONE
  UIImage *m_image;
#else
  NSImage *m_image;
#endif // TARGET_OS_IPHONE

  CGFrameBuffer *m_cgFrameBuffer;
  BOOL m_isDuplicate;
}

#if TARGET_OS_IPHONE
@property (nonatomic, retain) UIImage *image;
#else
@property (nonatomic, retain) NSImage *image;
#endif // TARGET_OS_IPHONE

// If the frame data is already formatted as a pixel buffer, then
// this field is non-nil. A pixel buffer can be wrapped into
// platform specific image data.

@property (nonatomic, retain) CGFrameBuffer *cgFrameBuffer;

@property (nonatomic, assign) BOOL     isDuplicate;

// Constructor

+ (AVFrame*) aVFrame;

// If the image property is nil but the cgFrameBuffer is not nil, then
// create the image object from the contents of the cgFrameBuffer. This
// method attempts to verify that the image object is created and initialized
// as much as possible, though some image operations may still be deferred
// until the render cycle.

- (void) makeImageFromFramebuffer;

@end
