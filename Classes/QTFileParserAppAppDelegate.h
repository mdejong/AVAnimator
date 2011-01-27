//
//  QTFileParserAppAppDelegate.h
//
//  Created by Moses DeJong on 12/17/10.
//
//
//  License terms defined in License.txt.

#import <UIKit/UIKit.h>

@class QTFileParserAppViewController;
@class AVAnimatorView;
@class MovieControlsViewController;
@class MovieControlsAdaptor;
@class AVAnimatorLayer;

@interface QTFileParserAppAppDelegate : NSObject <UIApplicationDelegate> {
  UIWindow *m_window;
  
  QTFileParserAppViewController *m_viewController;
  
  MovieControlsViewController *m_movieControlsViewController;
  
  AVAnimatorView *m_animatorView;
  
  MovieControlsAdaptor *m_movieControlsAdaptor;
  
  // Used in a couple of examples.
  UIView *m_plainView;
  AVAnimatorLayer *m_animatorLayer;
}

@property (nonatomic, retain) IBOutlet UIWindow *window;

@property (nonatomic, retain) IBOutlet QTFileParserAppViewController *viewController;

@property (nonatomic, retain) MovieControlsViewController *movieControlsViewController;

@property (nonatomic, retain) AVAnimatorView *animatorView;

@property (nonatomic, retain) MovieControlsAdaptor *movieControlsAdaptor;

@property (nonatomic, retain) UIView *plainView;

@property (nonatomic, retain) AVAnimatorLayer *animatorLayer;

- (void) stopAnimator;

- (void) loadIndexedExample:(NSUInteger)index
                        fps:(NSInteger)fps;

@end

