//
//  RegressionTests.m
//
//  Created by Moses DeJong on 11/8/09.
//  Copyright 2009 __MyCompanyName__. All rights reserved.
//

#import "objc/runtime.h"

#import "RegressionTests.h"

// If RegressionTestsJustThisModule is defined, then only the tests in the
// indicated module will be executed.

//#define RegressionTestsJustThisModule @"TextTableDataTests"
//#define RegressionTestsJustThisModule @"iPracticeAppDelegateTests"

@implementation RegressionTests

// Get array of classes named "*Test" that extend NSObject and implement "testApp" class method

+ (BOOL) _classRespondsToSelector:(Class)c sel:(SEL)sel {
	Method m = class_getClassMethod(c, @selector(testApp));	
	return (m != NULL);
}

+ (void) _invokeIfClassRespondsToSelector:(Class)c sel:(SEL)sel {
	if ([self _classRespondsToSelector:c sel:sel]) {
		[c performSelector:sel];
	}
}

+ (NSArray*) _getTestClasses {
	// Find classes named "*Test" that extend NSObject and implement "testApp"
  
	NSMutableArray *muArr = [NSMutableArray arrayWithCapacity:64];
  
	Class *classes = NULL;
	int numClasses;
	
	numClasses = objc_getClassList(NULL, 0);
  
	if (numClasses == 0 )
		return nil;
  
	classes = malloc(sizeof(Class) * numClasses);
	numClasses = objc_getClassList(classes, numClasses);
	
	for (int i=0; i<numClasses; i++) {
		Class aClass = classes[i];
		const char *className = class_getName(aClass);
    
		NSString *classNameStr = [NSString stringWithFormat:@"%s", className];
    
		// If class name ends with "Tests"
    
    NSString *subStr;
    
#ifdef RegressionTestsJustThisModule
    subStr = RegressionTestsJustThisModule;
#else
    subStr = @"Tests";
#endif // RegressionTestsJustThisModule

		if ([classNameStr hasSuffix:subStr]) {
      const Class thisClass = [self class];
      
			if (aClass == thisClass) {
				// Ignore this class
				continue;
			}
      
			if ([self _classRespondsToSelector:aClass sel:@selector(testApp)]) {
				[muArr addObject:aClass];
			}
		}
	}
  
	free(classes);
  
	return [NSArray arrayWithArray:muArr];
}

+ (BOOL) waitUntilTrue:(id)object
              selector:(SEL)selector
           maxWaitTime:(NSTimeInterval)maxWaitTime
{
  NSAssert(object, @"object is nil");
  NSAssert(selector, @"selector is nil");
  NSMethodSignature *aSignature = [[object class] instanceMethodSignatureForSelector:selector];
  NSInvocation *anInvocation = [NSInvocation invocationWithMethodSignature:aSignature];
  [anInvocation setSelector:selector];
  [anInvocation setTarget:object];
  
  for (int numSeconds = (int) round(maxWaitTime) ; numSeconds > 0 ; numSeconds--) {
    BOOL state;
    
    [anInvocation invoke];
    [anInvocation getReturnValue:&state];

    if (state) {
      return TRUE;
    }
    
    NSDate *maxDate = [NSDate dateWithTimeIntervalSinceNow:1.0];
    [[NSRunLoop currentRunLoop] runUntilDate:maxDate];
  }
  
  return FALSE;
}

+ (void) cleanupAfterTest {
	id appDelegate = [[UIApplication sharedApplication] delegate];
	NSAssert(appDelegate, @"appDelegate is nil");
	UIWindow *window = [appDelegate window];
	NSAssert(window, @"window is nil");
  
	for (UIView *subview in window.subviews) {
		[subview removeFromSuperview];
	}
}

// Find classes named "*Test" that extend NSObject and implement "testApp" and
// invoke testApp on each one.

+ (void) _testApp {
  for (Class c in [self _getTestClasses]) {
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    
    const char *className = class_getName(c);
    NSString *classNameStr = [NSString stringWithFormat:@"%s", className];
    NSLog(@"%@.testApp:", classNameStr);
    
    [self _invokeIfClassRespondsToSelector:c sel:@selector(testApp)];
    
    [pool release];
    
    [self cleanupAfterTest];
	}
  
  id appDelegate = [[UIApplication sharedApplication] delegate];
	NSAssert(appDelegate, @"appDelegate is nil");
    
	return;
}

+ (void) testApp {
	// Add testing event to the event loop and return so that the
	// callers
  
	NSTimer *_testAppTimer = [NSTimer timerWithTimeInterval: 1.0
                                                   target: self
                                                 selector: @selector(_testApp)
                                                 userInfo: NULL
                                                  repeats: FALSE];
  
  [[NSRunLoop currentRunLoop] addTimer: _testAppTimer forMode: NSDefaultRunLoopMode];
  
	return;
}

@end
