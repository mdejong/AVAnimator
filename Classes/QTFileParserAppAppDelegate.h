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

@interface QTFileParserAppAppDelegate : NSObject <UIApplicationDelegate> {
  UIWindow *m_window;
  
  QTFileParserAppViewController *m_viewController;
  
  MovieControlsViewController *m_movieControlsViewController;
  
  AVAnimatorView *m_animatorView;
  
  MovieControlsAdaptor *m_movieControlsAdaptor;
}

@property (nonatomic, retain) IBOutlet UIWindow *window;

@property (nonatomic, retain) IBOutlet QTFileParserAppViewController *viewController;

@property (nonatomic, retain) MovieControlsViewController *movieControlsViewController;

@property (nonatomic, retain) AVAnimatorView *animatorView;

@property (nonatomic, retain) MovieControlsAdaptor *movieControlsAdaptor;

- (void) stopAnimator;

- (void) loadIndexedExample:(NSUInteger)index
                        fps:(NSInteger)fps;

@end

