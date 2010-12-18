//
//  QTFileParserAppAppDelegate.h
//  QTFileParserApp
//
//  Created by Moses DeJong on 12/17/10.
//  Copyright 2010 __MyCompanyName__. All rights reserved.
//

#import <UIKit/UIKit.h>

@class QTFileParserAppViewController;

@interface QTFileParserAppAppDelegate : NSObject <UIApplicationDelegate> {
    UIWindow *window;
    QTFileParserAppViewController *viewController;
}

@property (nonatomic, retain) IBOutlet UIWindow *window;
@property (nonatomic, retain) IBOutlet QTFileParserAppViewController *viewController;

@end

