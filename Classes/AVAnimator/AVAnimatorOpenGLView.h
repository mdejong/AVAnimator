//
//  AVAnimatorOpenGLView.h
//
//  Created by Moses DeJong on 7/29/13.
//
//  License terms defined in License.txt.
//
// The AVAnimatorOpenGLView class provides a view implementation that
// is able to render CoreVideo pixel buffers directly without costly
// framebuffer copy operations. This implementation is based on use of
// AVAsset to decode h.264 video in hardware and then OpenGL to
// actually present the hardware decoded frame on screen in an optimal
// way. This implementation depends on CoreVideo APIs introdued in iOS
// 5.0, so it will not function on earlier versions of iOS.

#import "AVAssetConvertCommon.h"

#if defined(HAS_AVASSET_READ_COREVIDEO_BUFFER_AS_TEXTURE)

#import <UIKit/UIKit.h>
#import <GLKit/GLKit.h>

#import "AVAnimatorMediaRendererProtocol.h"

@class AVAnimatorMedia;

@interface AVAnimatorOpenGLView : GLKView <AVAnimatorMediaRendererProtocol>

// public properties

@property (nonatomic, readonly) AVAnimatorMedia *media;

// static ctor : create view that has the screen dimensions
+ (AVAnimatorOpenGLView*) aVAnimatorOpenGLView;

// static ctor : create view with the given dimensions
+ (AVAnimatorOpenGLView*) aVAnimatorOpenGLViewWithFrame:(CGRect)viewFrame;

// A media item is attached to the view to indicate that the media will
// render to this view.

- (void) attachMedia:(AVAnimatorMedia*)inMedia;

// Implement AVAnimatorMediaRendererProtocol protocol

// Invoked with TRUE argument once renderer has been attached to loaded media,
// otherwise FALSE is passed to indicate the renderer could not be attached

- (void) mediaAttached:(BOOL)worked;

// Note that the superclass implicitly defines setImage

@end

#endif // HAS_AVASSET_READ_COREVIDEO_BUFFER_AS_TEXTURE
