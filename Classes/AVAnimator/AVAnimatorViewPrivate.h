//
//  AVAnimatorViewPrivate.h
//
//  Created by Moses DeJong on 1/8/11.
//
// This file defines the private members of the AVAnimatorView.
// These fields would typically be used only by the implementation
// of AVAnimatorView, but could be needed for regression tests.
//
//  License terms defined in License.txt.

#import <Foundation/Foundation.h>

#import <QuartzCore/QuartzCore.h>

#import "AVAnimatorView.h"

// private properties declaration for AVAnimatorView class

@interface AVAnimatorView ()

@property (nonatomic, assign) CGSize renderSize;

@property (nonatomic, retain) AVAnimatorMedia *mediaObj;

@property (nonatomic, retain) AVFrame *frameObj;

// private methods

- (void) rotateToPortrait;

- (void) rotateToLandscape;

- (void) rotateToLandscapeRight;

- (void) rotateToUpsidedown;

@end
