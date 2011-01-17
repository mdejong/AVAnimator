//
//  MovieControlsViewController.h
//
//  Created by Moses DeJong on 4/8/09.
//
//  License terms defined in License.txt.

#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>

@class MPVolumeView;
@class MovieControlsView;

// The 4 state notifications supported by movie controls.
// The play state notification is delivered when changing
// from the pause state to the playing state. The pause
// state notification is delivered when changing from
// the playing state to the pause state. The done notification
// is delivered when the Done button is pressed. The rewind
// notification indicates that the movie should be started
// over at the begining.

#define MovieControlsDoneNotification @"MovieControlsDoneNotification"
#define MovieControlsPlayNotification @"MovieControlsPlayNotification"
#define MovieControlsPauseNotification @"MovieControlsPauseNotification"
#define MovieControlsRewindNotification @"MovieControlsRewindNotification"
#define MovieControlsFastForwardNotification @"MovieControlsFastForwardNotification"

@interface MovieControlsViewController : UIViewController {
  UIWindow *m_mainWindow;
  
	// Custom view subclass that manages event propagation
	MovieControlsView *movieControlsView;

	// The view that this movie controller floats over

	UIView *overView;

	// Elements in nav subview at top of window

	UINavigationController *navController;
	UIBarButtonItem *doneButton;

	// Elements in floating "controls" subview

	UIView *controlsSubview;
	UIImageView *controlsImageView;
	UIImage *controlsBackgroundImage;

	UIButton *playPauseButton;
	UIButton *m_rewindButton;
	UIButton *m_fastForwardButton;
	UIImage *playImage;
	UIImage *pauseImage;
	UIImage *m_rewindImage;
	UIImage *m_fastForwardImage;

	UIView *volumeSubview;
	MPVolumeView *volumeView;

	NSTimer *hideControlsTimer;
	NSTimer *hideControlsFromPlayTimer;

	CFAbsoluteTime lastEventTime;
  
  CGRect portraitFrame;
  CATransform3D portraitTransform;

	BOOL controlsVisable;
	BOOL isPlaying;
	BOOL isPaused;
	BOOL touchBeganInSelfView;
}

@property (nonatomic, assign) UIWindow *mainWindow;
@property (nonatomic, retain) MovieControlsView *movieControlsView;
@property (nonatomic, retain) UIView *overView;

@property (nonatomic, retain) UINavigationController *navController;
@property (nonatomic, retain) UIBarButtonItem *doneButton;

@property (nonatomic, retain) UIView *controlsSubview;
@property (nonatomic, retain) UIImageView *controlsImageView;
@property (nonatomic, retain) UIImage *controlsBackgroundImage;

@property (nonatomic, retain) UIView *volumeSubview;
@property (nonatomic, retain) UIButton *playPauseButton;
@property (nonatomic, retain) UIButton *rewindButton;
@property (nonatomic, retain) UIButton *fastForwardButton;
@property (nonatomic, retain) UIImage *playImage;
@property (nonatomic, retain) UIImage *pauseImage;
@property (nonatomic, retain) UIImage *rewindImage;
@property (nonatomic, retain) UIImage *fastForwardImage;

@property (nonatomic, retain) MPVolumeView *volumeView;

@property (nonatomic, retain) NSTimer *hideControlsTimer;
@property (nonatomic, retain) NSTimer *hideControlsFromPlayTimer;

// static ctor
+ (MovieControlsViewController*) movieControlsViewController;

- (void) pressPlayPause:(id)sender;
- (void) pressDone:(id)sender;
- (void) pressOutsideControls:(id)sender;
- (void) pressRewind:(id)sender;

- (void) showControls;
- (void) hideControls;

// FIXME: make these private
- (void) addNavigationControlerAsSubviewOf:(UIWindow*)window;
- (void) removeNavigationControlerAsSubviewOf:(UIWindow*)window;

- (void) setMainWindow:(UIWindow*)mainWindow;

- (void) touchesAnyEvent;

- (void) disableUserInteraction;

- (void) enableUserInteraction;

@end

