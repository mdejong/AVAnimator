//
//  AVAnimatorOpenGLViewPrivate.h
//
//  Created by Moses DeJong on 7/29/13.
//
// This file defines the private members of the AVAnimatorOpenGLView.
// These fields would typically be used only by the implementation
// of AVAnimatorOpenGLView, but could be needed for regression tests.
//
//  License terms defined in License.txt.

#import <Foundation/Foundation.h>

#import <QuartzCore/QuartzCore.h>

#import "AVAnimatorOpenGLView.h"

// private properties declaration for AVAnimatorOpenGLView class

@interface AVAnimatorOpenGLView ()

@property (nonatomic, assign) CGSize renderSize;

@property (nonatomic, retain) AVAnimatorMedia *mediaObj;

@property (nonatomic, retain) AVFrame *frameObj;

@end
