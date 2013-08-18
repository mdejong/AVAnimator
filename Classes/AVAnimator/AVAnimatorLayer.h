//
//  AVAnimatorLayer.h
//
//  Created by Moses DeJong on 3/18/09.
//
//  License terms defined in License.txt.
//
// The AVAnimatorLayer class provides a way to render
// media frames into a CALayer object. Media frames
// with whole or partial transparency are supported
// automatically. One would allocate an AVAnimatorLayer
// and pass the CALayer ref that will be the target
// of the rendering operation.

#import <UIKit/UIKit.h>

#import "AVAnimatorMediaRendererProtocol.h"

@class AVAnimatorMedia;

@interface AVAnimatorLayer : NSObject <AVAnimatorMediaRendererProtocol> {
@private
  CALayer *m_layerObj;
	AVAnimatorMedia *m_mediaObj;
	AVFrame *m_frameObj;
	BOOL mediaDidLoad;
}

// public properties

@property (nonatomic, readonly) CALayer *layer;
@property (nonatomic, readonly) AVAnimatorMedia *media;

// static ctor : create view that renders to the core animation layer
+ (AVAnimatorLayer*) aVAnimatorLayer:(CALayer*)layer;

// A media item is attached to the view to indicate that the media will
// render to this view.

- (void) attachMedia:(AVAnimatorMedia*)inMedia;

// Implement AVAnimatorMediaRendererProtocol protocol

// Invoked with TRUE argument once renderer has been attached to loaded media,
// otherwise FALSE is passed to indicate the renderer could not be attached

- (void) mediaAttached:(BOOL)worked;

// setter for obj.AVFrame property

- (void) setAVFrame:(AVFrame*)inFrame;

// getter for obj.AVFrame property

- (AVFrame*) AVFrame;

@end
