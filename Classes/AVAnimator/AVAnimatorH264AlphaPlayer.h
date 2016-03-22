//
//  AVAnimatorH264AlphaPlayer.h
//
//  Created by Moses DeJong on 2/27/16.
//
//  License terms defined in License.txt.
//
// The AVAnimatorH264AlphaPlayer class provides a self contained player
// for a mixed H264 video that contains both RGB + Alpha channels of
// data encoded as interleaved frames. This class extends GLKView
// and provides functionality that decodes video data from a resource
// file or regular file and then sends the video data to the view.
// Any audio data contained in the asset is ignored.
//
// Because of the way iOS implements asset loading, it is not possible
// to seamlessly loop an asset video. The prepareToAnimate method must be
// invoked in order to kick off an animation loop, then the startAnimator
// method should be invoked in the AVAnimatorPreparedToAnimateNotification
// callback. The asset must be loaded on a background thread to avoid
// blocking the main thread before each animation cycle can begin.
//
// Note that playback on iOS supports only video data encoded at
// 30 FPS (the standard 29.97 FPS is close enough). Playback will
// smoothly render at exactly 30 FPS via a display link timed
// OpenGL render and a high prio background thread. Note that the
// caller should be careful to invoke stopAnimator when the view
// is going away or the whole app is going into the background.

#import "AVAssetConvertCommon.h"

#if defined(HAS_AVASSET_READ_COREVIDEO_BUFFER_AS_TEXTURE)

#import <UIKit/UIKit.h>
#import <GLKit/GLKit.h>

#import "AVAssetFrameDecoder.h"

// These notifications are delived from the AVAnimatorH264AlphaPlayer

#define AVAnimatorPreparedToAnimateNotification @"AVAnimatorPreparedToAnimateNotification"
#define AVAnimatorFailedToLoadNotification @"AVAnimatorFailedToLoadNotification"

#define AVAnimatorDidStartNotification @"AVAnimatorDidStartNotification"
#define AVAnimatorDidStopNotification @"AVAnimatorDidStopNotification"


@interface AVAnimatorH264AlphaPlayer : GLKView

// static ctor : create view that has the screen dimensions
+ (AVAnimatorH264AlphaPlayer*) aVAnimatorH264AlphaPlayer;

// static ctor : create view with the given dimensions
+ (AVAnimatorH264AlphaPlayer*) aVAnimatorH264AlphaPlayerWithFrame:(CGRect)viewFrame;

// Set this property to indicate the name of the asset to be
// loaded as a result of calling startAnimator.

@property (atomic, copy) NSString *assetFilename;

@property (atomic, retain) AVAssetFrameDecoder *frameDecoder;

// In DEBUG mode, this property can be set to a directory and each rendered
// output frame will be captured as BGRA and saved in a PNG.

#if defined(DEBUG)
@property (nonatomic, copy) NSString *captureDir;
#endif // DEBUG

// Invoke this metho to read from the named asset and being loading initial data

- (void) prepareToAnimate;

// After an animator has been prepared and the AVAnimatorPreparedToAnimateNotification has
// been delivered this startAnimator API can be invoked to actually kick off the playback loop.

- (void) startAnimator;

// Stop playback of animator, nop is not currently animating

- (void) stopAnimator;

@end

#endif // HAS_AVASSET_READ_COREVIDEO_BUFFER_AS_TEXTURE
