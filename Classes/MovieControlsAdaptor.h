//
//  MovieControlsAdaptor.h
//
//  Created by Moses DeJong on 12/17/10.
//
//  This class provides a default implementation that connects an AVAnimatorViewController
//  and a MovieControlsViewController. The movie controller can then control the function
//  of the animator via notifications. This is a util class that keeps most of the notification
//  logic out of the app delegate.

#import <UIKit/UIKit.h>

@class AVAnimatorView;
@class MovieControlsViewController;

@interface MovieControlsAdaptor : NSObject <UIApplicationDelegate> {
  AVAnimatorView *m_animatorView;
  MovieControlsViewController *m_movieControlsViewController;
}

@property (nonatomic, retain) AVAnimatorView *animatorView;
@property (nonatomic, retain) MovieControlsViewController *movieControlsViewController;

// static ctor

+ (MovieControlsAdaptor*) movieControlsAdaptor;

- (void) startAnimator;

- (void) stopAnimator;

@end

