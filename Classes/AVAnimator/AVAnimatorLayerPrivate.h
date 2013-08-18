//
//  AVAnimatorLayerPrivate.h
//
//  Created by Moses DeJong on 1/8/11.
//
// This file defines the private members of the AVAnimatorLayer.
// These fields would typically be used only by the implementation
// of AVAnimatorLayer, but could be needed for regression tests.
//
//  License terms defined in License.txt.

#import <Foundation/Foundation.h>

#import <QuartzCore/QuartzCore.h>

#import "AVAnimatorLayer.h"

// private properties declaration for AVAnimatorLayer class

@interface AVAnimatorLayer ()

@property (nonatomic, retain) CALayer *layerObj;

@property (nonatomic, retain) AVAnimatorMedia *mediaObj;

@property (nonatomic, retain) AVFrame *frameObj;

@end
