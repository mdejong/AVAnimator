//
//  AVFrameDecoder.m
//
//  Created by Moses DeJong on 12/30/10.
//
//  License terms defined in License.txt.

#import "AVFrameDecoder.h"

@implementation AVFrameDecoder

- (void) dealloc
{
  [super dealloc];
}

- (BOOL) openForReading:(NSString*)path
{
  [self doesNotRecognizeSelector:_cmd];
	return FALSE;
}

- (void) close
{
  [self doesNotRecognizeSelector:_cmd];
	return;
}

- (void) rewind
{
  [self doesNotRecognizeSelector:_cmd];
	return;
}

- (AVFrame*) advanceToFrame:(NSUInteger)newFrameIndex
{
  [self doesNotRecognizeSelector:_cmd];
	return FALSE;
}

- (BOOL) allocateDecodeResources
{
  [self doesNotRecognizeSelector:_cmd];
	return FALSE;
}

- (void) releaseDecodeResources
{
  [self doesNotRecognizeSelector:_cmd];
	return;
}

- (BOOL) isResourceUsageLimit
{
  [self doesNotRecognizeSelector:_cmd];
	return FALSE;
}

- (AVFrame*) duplicateCurrentFrame
{
  [self doesNotRecognizeSelector:_cmd];
	return nil;
}

// Properties

- (NSUInteger) width
{
  [self doesNotRecognizeSelector:_cmd];
	return 0;
}

- (NSUInteger) height
{
  [self doesNotRecognizeSelector:_cmd];
	return 0;
}

- (BOOL) isOpen
{
  [self doesNotRecognizeSelector:_cmd];
	return FALSE;
}

- (NSUInteger) numFrames
{
  [self doesNotRecognizeSelector:_cmd];
	return 0;
}

- (NSInteger) frameIndex
{
  [self doesNotRecognizeSelector:_cmd];
	return 0;
}

- (NSTimeInterval) frameDuration
{
  [self doesNotRecognizeSelector:_cmd];
	return 0;
}

- (BOOL) hasAlphaChannel
{
  [self doesNotRecognizeSelector:_cmd];
	return FALSE;
}

- (BOOL) isAllKeyframes
{
  [self doesNotRecognizeSelector:_cmd];
	return FALSE;
}

@end
