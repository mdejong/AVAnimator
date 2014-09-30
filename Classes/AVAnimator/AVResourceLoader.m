//
//  AVResourceLoader.m
//  AVAnimatorDemo
//
//  Created by Moses DeJong on 4/7/09.
//
//  License terms defined in License.txt.

#import "AVResourceLoader.h"

static NSLock *serialResourceLoaderLock = nil;

@implementation AVResourceLoader

@synthesize isReady = m_isReady;
@synthesize serialLoading = m_serialLoading;

// This static method is invoked when this class or a subclass is loaded.
// The goal here is to only invoke the lock init logic one time so that
// only a single lock ever exists.

+ (void) initialize
{
  if (self == [AVResourceLoader class]) {
    if (serialResourceLoaderLock == nil) {
      NSLock *obj = [[NSLock alloc] init];
      NSAssert(obj, @"NSLock could not be allocated");
      serialResourceLoaderLock = obj;
      [serialResourceLoaderLock setName:@"serialResourceLoaderLock"];
#if __has_feature(objc_arc)
#else
      [serialResourceLoaderLock retain];
      [obj release];
#endif // objc_arc
    }
  }
}

+ (void) freeSerialResourceLoaderLock
{
#if __has_feature(objc_arc)
  serialResourceLoaderLock = nil;
#else
  NSLock *obj = serialResourceLoaderLock;
  serialResourceLoaderLock = nil;
  [obj release];
#endif // objc_arc
}

+ (void) grabSerialResourceLoaderLock
{
  NSAssert(serialResourceLoaderLock, @"serialResourceLoaderLock");
  [serialResourceLoaderLock lock];
}

+ (void) releaseSerialResourceLoaderLock
{
  NSAssert(serialResourceLoaderLock, @"serialResourceLoaderLock");
  [serialResourceLoaderLock unlock];
}

- (BOOL) isReady
{
	[self doesNotRecognizeSelector:_cmd];
	return FALSE;
}

- (void) load
{
	[self doesNotRecognizeSelector:_cmd];
}

- (NSArray*) getResources
{
	[self doesNotRecognizeSelector:_cmd];
	return nil;
}

@end
