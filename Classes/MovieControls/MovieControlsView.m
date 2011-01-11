//
//  MovieControlsView.m
//
//  License terms defined in License.txt.

#import "MovieControlsView.h"
#import "MovieControlsViewController.h"

@implementation MovieControlsView

@synthesize viewController;

- (id)initWithFrame:(CGRect)frame {
	self = [super initWithFrame:frame];
	if (self == nil)
		return nil;

	// Init code

	return self;
}

- (void)dealloc {
	// Note that we don't release self.viewController here because
	// we don't hold a ref to it.
	[super dealloc];
}

// override hitTest so that this view can detect when a
// button press event is recieved and passed to one of
// the contained views.

- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event
{
	NSLog(@"hitTest in MovieControlsView");

	[viewController	touchesAnyEvent];

	return [super hitTest:point withEvent:event];
}

// This implementation does not invoke [viewController touchesAnyEvent]
// it is invoked only from the view controller.

- (UIView *)hitTestSuper:(CGPoint)point withEvent:(UIEvent *)event
{
//	NSLog(@"hitTestSuper in MovieControlsView");

	return [super hitTest:point withEvent:event];
}

@end
