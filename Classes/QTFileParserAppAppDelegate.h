//
//  QTFileParserAppAppDelegate.h
//  QTFileParserApp
//
//  Created by Moses DeJong on 12/17/10.
//  Copyright 2010 __MyCompanyName__. All rights reserved.
//

#import <UIKit/UIKit.h>

@class QTFileParserAppViewController;
@class AVAnimatorViewController;
@class MovieControlsViewController;

@interface QTFileParserAppAppDelegate : NSObject <UIApplicationDelegate> {
  UIWindow *window;
  
  QTFileParserAppViewController *viewController;
  
  MovieControlsViewController *movieControlsViewController;
  
  AVAnimatorViewController *animatorViewController;
}

@property (nonatomic, retain) IBOutlet UIWindow *window;

@property (nonatomic, retain) IBOutlet QTFileParserAppViewController *viewController;

@property (nonatomic, retain) MovieControlsViewController *movieControlsViewController;

@property (nonatomic, retain) AVAnimatorViewController *animatorViewController;

- (void) startAnimator;

- (void) testAnimator;

- (void) stopAnimator;

- (void) loadDemoArchive;

@end

