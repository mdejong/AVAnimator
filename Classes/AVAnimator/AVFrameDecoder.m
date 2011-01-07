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

- (UIImage*) advanceToFrame:(NSUInteger)newFrameIndex
{
  [self doesNotRecognizeSelector:_cmd];
	return FALSE;
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

@end
