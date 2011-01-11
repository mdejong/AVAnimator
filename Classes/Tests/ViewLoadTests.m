//
//  ViewLoadTests.m
//
//  Created by Moses DeJong on 11/8/09.
//
//  License terms defined in License.txt.

#import "RegressionTests.h"

@interface ViewLoadTests : NSObject {}
+ (void) testApp;
@end

@interface ViewLoadTests_SubviewController1 : UIViewController {
@public
	BOOL viewDidLoadFlag;
}
+ (ViewLoadTests_SubviewController1*) subviewController1;
@end


@implementation ViewLoadTests

// Define a method named "testApp", it will be invoked dynamically from
// RegressionTest.m at runtime

+ (void) testApp {
	id appDelegate = [[UIApplication sharedApplication] delegate];	
	UIWindow *window = [appDelegate window];
	NSAssert(window, @"window");

	// Create a UIView and add it as a subview of the main app window

	ViewLoadTests_SubviewController1 *subview = [ViewLoadTests_SubviewController1 subviewController1];
	[window addSubview:subview.view];

	// Spin event loop for a bit so view will be created

	[[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];

	// Check that viewDidLoad was invoked

	NSAssert(subview->viewDidLoadFlag, @"viewDidLoad was not invoked");

	return;
}

@end

// SubviewController1

@implementation ViewLoadTests_SubviewController1

// Instance allocator for SubviewController1

+ (ViewLoadTests_SubviewController1*) subviewController1 {
	ViewLoadTests_SubviewController1 *vc = [[ViewLoadTests_SubviewController1 alloc] init];
	if (vc == nil)
		return nil;
	return [vc autorelease];
}

- (void)loadView {
	CGRect frame = CGRectMake(0,0,10,10);
	self.view = [[[UIView alloc] initWithFrame:frame] autorelease];
	NSAssert(self.view, @"view is nil");	
}

- (void) viewDidLoad {
	[super viewDidLoad];
	self->viewDidLoadFlag = TRUE;
}

@end // SubviewController1

