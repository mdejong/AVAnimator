//
//  MovieControlsAdaptor.m
//
//  Created by Moses DeJong on 12/17/10.
//
//  License terms defined in License.txt.

#import "MovieControlsAdaptor.h"

#import "AVAnimatorView.h"

#import "AVAnimatorMedia.h"

#import "MovieControlsViewController.h"

@implementation MovieControlsAdaptor

@synthesize animatorView = m_animatorView;
@synthesize movieControlsViewController = m_movieControlsViewController;

// static ctor

+ (MovieControlsAdaptor*) movieControlsAdaptor
{
  MovieControlsAdaptor *obj = [[MovieControlsAdaptor alloc] init];
#if __has_feature(objc_arc)
  return obj;
#else
  return [obj autorelease];
#endif // objc_arc
}

- (void)dealloc {
  self.animatorView = nil;
  self.movieControlsViewController = nil;
  
#if __has_feature(objc_arc)
#else
  [super dealloc];
#endif // objc_arc
}

- (void) startAnimator
{
  // Note that the movie controls view controls starts with the controls in the
  // hidden state.
  
  NSAssert(self.animatorView.media, @"media is nil");
  
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
                                             object:self.animatorView.media];
  
	[[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(animatorDidStartNotification:) 
                                               name:AVAnimatorDidStartNotification 
                                             object:self.animatorView.media];	
  
	[[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(animatorDidStopNotification:) 
                                               name:AVAnimatorDidStopNotification 
                                             object:self.animatorView.media];

  // This final notification would only be invoked if the loading process failed.
  
	[[NSNotificationCenter defaultCenter] addObserver:self
                                           selector:@selector(animatorFailedToLoadNotification:)
                                               name:AVAnimatorFailedToLoadNotification
                                             object:self.animatorView.media];
  
	// Kick off loading operation and disable user touch events until
	// finished loading.
  
	[self.movieControlsViewController disableUserInteraction];
  
	[self.animatorView.media prepareToAnimate];
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
                                                object:self.animatorView.media];	
  
	[[NSNotificationCenter defaultCenter] removeObserver:self
                                                  name:AVAnimatorDidStartNotification
                                                object:self.animatorView.media];
  
	[[NSNotificationCenter defaultCenter] removeObserver:self
                                                  name:AVAnimatorDidStopNotification
                                                object:self.animatorView.media];

	[[NSNotificationCenter defaultCenter] removeObserver:self
                                                  name:AVAnimatorFailedToLoadNotification
                                                object:self.animatorView.media];
    
	// Remove MovieControls and contained views, if the animator was just stopped
	// because all the loops were played then stopAnimating is a no-op.
  
	[self.animatorView.media stopAnimator];
}

// Invoked when the Done button in the movie controls is pressed.
// This action will stop playback and halt any looping operation.
// This action will inform the animator that it should be done
// animating, then the animator will kick off a notification
// indicating that the animation is done.

- (void)movieControlsDoneNotification:(NSNotification*)notification {
	NSLog( @"movieControlsDoneNotification" );
  
	NSAssert(![self.animatorView.media isInitializing], @"animatorView isInitializing");
  
	[self.animatorView.media doneAnimator];
}

- (void)movieControlsPauseNotification:(NSNotification*)notification {
	NSLog( @"movieControlsPauseNotification" );
  
	NSAssert(![self.animatorView.media isInitializing], @"animatorView isInitializing");
  
	[self.animatorView.media pause];
}

- (void)movieControlsPlayNotification:(NSNotification*)notification {
	NSLog( @"movieControlsPlayNotification" );
  
	NSAssert(![self.animatorView.media isInitializing], @"animatorView isInitializing");
  
	[self.animatorView.media unpause];
}

- (void)movieControlsRewindNotification:(NSNotification*)notification {
	NSLog( @"movieControlsRewindNotification" );
  
	[self.animatorView.media stopAnimator];
	[self.animatorView.media startAnimator];
}

- (void)movieControlsFastForwardNotification:(NSNotification*)notification {
	NSLog( @"movieControlsFastForwardNotification" );

	[self.animatorView.media stopAnimator];
	[self.animatorView.media startAnimator];
}

// Invoked when the animator is ready to begin, meaning all
// resources have been initialized.

- (void)animatorPreparedNotification:(NSNotification*)notification {
	NSLog( @"animatorPreparedNotification" );
  
  if (self.animatorView.media.hasAudio == FALSE) {
    // The animator has no associated audio track, no need to show volume
    // controls in the movie controller.
    
    self.movieControlsViewController.showVolumeControls = FALSE;
  }

	[self.movieControlsViewController enableUserInteraction];
  
	[self.animatorView.media startAnimator];
}

// Invoked when an animator starts, note that this method
// can be invoked multiple times for an animator that loops.

- (void)animatorDidStartNotification:(NSNotification*)notification {
//	NSLog( @"animatorDidStartNotification" );
}

// Invoked when an animation ends, note that this method
// can be invoked multiple times for an animator that loops.

- (void)animatorDidStopNotification:(NSNotification*)notification {
//	NSLog( @"animatorDidStopNotification" );	
}

// Invoked if the loading process failed. For example, when a movie
// file is not in the proper format, or shared memory could not be
// allocated for the frame decoder.

- (void)animatorFailedToLoadNotification:(NSNotification*)notification {
	NSLog( @"animatorFailedToLoadNotification" );  
}

@end


