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
//  the on screen display when media data is updated.

#import <Foundation/Foundation.h>

@protocol AVAnimatorMediaRendererProtocol

// Invoked with TRUE argument once renderer has been attached to loaded media,
// otherwise FALSE is passed to indicate the renderer could not be attached

- (void) mediaAttached:(BOOL)worked;

// setter for obj.image property

- (void) setImage:(UIImage*)inImage;

// getter for obj.image property

- (UIImage*) image;

@end
