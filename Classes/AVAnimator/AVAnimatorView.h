//
//  AVAnimatorView.h
//
//  Created by Moses DeJong on 3/18/09.
//
//  License terms defined in License.txt.
//
// The AVAnimatorView class provides a view that an animator can
// render into. The view renders UIImage objects generated
// by an attached media object. When the media renders an image
// that is the exact same size as the view, the image will be
// displayed at exact pixel resolution. Otherwise, the rendered
// image will be scaled to fit into the view in the ways supported
// by the UIImageView class. Media frames with whole or partial
// transparency are supported automatically.

#import <UIKit/UIKit.h>

#import "AVAnimatorMediaRendererProtocol.h"

@class AVAnimatorMedia;

@interface AVAnimatorView : UIImageView <AVAnimatorMediaRendererProtocol> {
@private
	UIImageOrientation m_animatorOrientation;
	CGSize m_renderSize;
	AVAnimatorMedia *m_mediaObj;
	AVFrame *m_frameObj;
	BOOL mediaDidLoad;
}

// public properties

// UIImageOrientationUp, UIImageOrientationDown, UIImageOrientationLeft, UIImageOrientationRight
// defaults to UIImageOrientationUp
@property (nonatomic, assign) UIImageOrientation animatorOrientation;

@property (nonatomic, readonly) AVAnimatorMedia *media;

// static ctor : create view that has the screen dimensions
+ (AVAnimatorView*) aVAnimatorView;

// static ctor : create view with the given dimensions
+ (AVAnimatorView*) aVAnimatorViewWithFrame:(CGRect)viewFrame;

// A media item is attached to the view to indicate that the media will
// render to this view.

- (void) attachMedia:(AVAnimatorMedia*)inMedia;

// Implement AVAnimatorMediaRendererProtocol protocol

// Invoked with TRUE argument once renderer has been attached to loaded media,
// otherwise FALSE is passed to indicate the renderer could not be attached

- (void) mediaAttached:(BOOL)worked;

// Note that the superclass implicitly defines setImage

@end
