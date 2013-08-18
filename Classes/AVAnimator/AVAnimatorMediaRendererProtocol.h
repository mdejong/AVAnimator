//
//  AVAnimatorMediaRendererProtocol.h
//
//  Created by Moses DeJong on 1/20/10.
//
//  License terms defined in License.txt.
//
//  This class defines the protocol that a media render must implement.
//  The object that contains a AVAnimatorMedia object must set the
//  media.renderer reference so that the media is able to update
//  the on screen display when media data is updated. Each time a frame
//  of video data is ready, the setFrame setter method is invoked.

#import <Foundation/Foundation.h>

@class AVFrame;

@protocol AVAnimatorMediaRendererProtocol

// Invoked with TRUE argument once renderer has been attached to loaded media,
// otherwise FALSE is passed to indicate the renderer could not be attached

- (void) mediaAttached:(BOOL)worked;

// setter for obj.AVFrame property

- (void) setAVFrame:(AVFrame*)inFrame;

// getter for obj.AVFrame property

- (AVFrame*) AVFrame;

@end
