//
//  QTFileParserAppAppDelegate.h
//  QTFileParserApp
//
//  Created by Moses DeJong on 12/17/10.
//  Copyright 2010 __MyCompanyName__. All rights reserved.
//

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

- (void) startAnimator;

- (void) stopAnimator;

- (void) loadDemoArchive;

@end

