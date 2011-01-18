//
//  MovieControlsAdaptor.m
//
//  Created by Moses DeJong on 12/17/10.
//
//  License terms defined in License.txt.

#import "MovieControlsAdaptor.h"

#import "AVAnimatorView.h"
#import "MovieControlsViewController.h"

@implementation MovieControlsAdaptor

@synthesize animatorView = m_animatorView;
@synthesize movieControlsViewController = m_movieControlsViewController;

// static ctor

+ (MovieControlsAdaptor*) movieControlsAdaptor
{
  MovieControlsAdaptor *obj = [[MovieControlsAdaptor alloc] init];
  [obj autorelease];
  return obj;
}

- (void)dealloc {
  self.animatorView = nil;
  self.movieControlsViewController = nil;
  [super dealloc];
}

- (void) startAnimator
{
  // Note that the movie controls view controls starts with the controls in the
  // hidden state.
  
	// Setup handlers for movie control notifications
  
	[[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(movieControlsDoneNotification:) 
                                               name:MovieControlsDoneNotification 
                                             object:self.movieControlsViewController];	
  
	// Invoke pause or play action from movie controls
  
	[[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(movieControlsPauseNotification:) 
                                               name:MovieControlsPauseNotification 
                                             object:self.movieControlsViewController];	
  
	[[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(movieControlsPlayNotification:) 
                                               name:MovieControlsPlayNotification 
                                             object:self.movieControlsViewController];
  
  // Rewind or Fast Forward actions from the movie controls

  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(movieControlsRewindNotification:) 
                                               name:MovieControlsRewindNotification 
                                             object:self.movieControlsViewController];

  [[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(movieControlsFastForwardNotification:) 
                                               name:MovieControlsFastForwardNotification 
                                             object:self.movieControlsViewController];
  
	// Register callbacks to be invoked when the animator changes from
	// states between start/stop/done. The start/stop notification
	// is done at the start and end of each loop. When all loops are
	// finished the done notification is sent.
  
	[[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(animatorPreparedNotification:) 
                                               name:AVAnimatorPreparedToAnimateNotification 
                                             object:self.animatorView];
  
	[[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(animatorDidStartNotification:) 
                                               name:AVAnimatorDidStartNotification 
                                             object:self.animatorView];	
  
	[[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(animatorDidStopNotification:) 
                                               name:AVAnimatorDidStopNotification 
                                             object:self.animatorView];

	// Kick off loading operation and disable user touch events until
	// finished loading.
  
	[self.movieControlsViewController disableUserInteraction];
  
	[self.animatorView prepareToAnimate];
}

- (void) stopAnimator
{
	// Remove notifications from movie controls
  
	[[NSNotificationCenter defaultCenter] removeObserver:self
                                                  name:MovieControlsDoneNotification
                                                object:self.movieControlsViewController];
	
	[[NSNotificationCenter defaultCenter] removeObserver:self
                                                  name:MovieControlsPauseNotification
                                                object:self.movieControlsViewController];
	
	[[NSNotificationCenter defaultCenter] removeObserver:self
                                                  name:MovieControlsPlayNotification
                                                object:self.movieControlsViewController];	
  
	[[NSNotificationCenter defaultCenter] removeObserver:self
                                                  name:MovieControlsRewindNotification
                                                object:self.movieControlsViewController];
  
  [[NSNotificationCenter defaultCenter] removeObserver:self
                                                  name:MovieControlsFastForwardNotification
                                                object:self.movieControlsViewController];

	// Remove notifications from animator
  
	[[NSNotificationCenter defaultCenter] removeObserver:self
                                                  name:AVAnimatorPreparedToAnimateNotification
                                                object:self.animatorView];	
  
	[[NSNotificationCenter defaultCenter] removeObserver:self
                                                  name:AVAnimatorDidStartNotification
                                                object:self.animatorView];
  
	[[NSNotificationCenter defaultCenter] removeObserver:self
                                                  name:AVAnimatorDidStopNotification
                                                object:self.animatorView];
    
	// Remove MovieControls and contained views, if the animator was just stopped
	// because all the loops were played then stopAnimating is a no-op.
  
	[self.animatorView stopAnimator];
}

// Invoked when the Done button in the movie controls is pressed.
// This action will stop playback and halt any looping operation.
// This action will inform the animator that it should be done
// animating, then the animator will kick off a notification
// indicating that the animation is done.

- (void)movieControlsDoneNotification:(NSNotification*)notification {
	NSLog( @"movieControlsDoneNotification" );
  
	NSAssert(![self.animatorView isInitializing], @"animatorView isInitializing");
  
	[self.animatorView doneAnimator];
}

- (void)movieControlsPauseNotification:(NSNotification*)notification {
	NSLog( @"movieControlsPauseNotification" );
  
	NSAssert(![self.animatorView isInitializing], @"animatorView isInitializing");
  
	[self.animatorView pause];
}

- (void)movieControlsPlayNotification:(NSNotification*)notification {
	NSLog( @"movieControlsPlayNotification" );
  
	NSAssert(![self.animatorView isInitializing], @"animatorView isInitializing");
  
	[self.animatorView unpause];
}

- (void)movieControlsRewindNotification:(NSNotification*)notification {
	NSLog( @"movieControlsRewindNotification" );
  
	[self.animatorView stopAnimator];
	[self.animatorView startAnimator];
}

- (void)movieControlsFastForwardNotification:(NSNotification*)notification {
	NSLog( @"movieControlsFastForwardNotification" );

	[self.animatorView stopAnimator];
	[self.animatorView startAnimator];
}

// Invoked when the animator is ready to begin, meaning all
// resources have been initialized.

- (void)animatorPreparedNotification:(NSNotification*)notification {
	NSLog( @"animatorPreparedNotification" );
  
  if (self.animatorView.hasAudio == FALSE) {
    // The animator has no associated audio track, no need to show volume
    // controls in the movie controller.
    
    self.movieControlsViewController.showVolumeControls = FALSE;
  }

	[self.movieControlsViewController enableUserInteraction];
  
	[self.animatorView startAnimator];
}

// Invoked when an animator starts, note that this method
// can be invoked multiple times for an animator that loops.

- (void)animatorDidStartNotification:(NSNotification*)notification {
	NSLog( @"animatorDidStartNotification" );
}

// Invoked when an animation ends, note that this method
// can be invoked multiple times for an animator that loops.

- (void)animatorDidStopNotification:(NSNotification*)notification {
	NSLog( @"animatorDidStopNotification" );	
}

@end


