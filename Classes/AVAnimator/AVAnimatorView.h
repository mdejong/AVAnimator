//
//  AVAnimatorView.h
//
//  Created by Moses DeJong on 3/18/09.
//
//  License terms defined in License.txt.

#import <UIKit/UIKit.h>

#import "AVAnimatorMediaRendererProtocol.h"

@class AVAnimatorMedia;

@interface AVAnimatorView : UIImageView <AVAnimatorMediaRendererProtocol> {
@private
	UIImageOrientation m_animatorOrientation;
	CGSize m_renderSize;
	AVAnimatorMedia *m_mediaObj;
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

// Invoked once media is loaded

- (void) mediaDidLoad;

// Invoked by media protocol to test if renderer is ready

- (BOOL) isReadyToRender;

// Note that the superclass implicitly defines setImage

@end
