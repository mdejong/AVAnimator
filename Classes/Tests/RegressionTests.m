//
//  RegressionTests.m
//
//  Created by Moses DeJong on 11/8/09.
//
//  License terms defined in License.txt.

#import "objc/runtime.h"

#import "RegressionTests.h"

// If RegressionTestsJustThisModule is defined, then only the tests in the
// indicated module will be executed.

//#define RegressionTestsJustThisModule @"SegmentedMappedDataTests"

@implementation RegressionTests

// Get array of classes named "*Test" that extend NSObject and implement "testApp" class method

+ (BOOL) _classRespondsToSelector:(Class)c sel:(SEL)sel {
	Method m = class_getClassMethod(c, sel);	
	return (m != NULL);
}

// Return TRUE for class test method.
// TRUE for "test1" "testABC".
// FALSE for "test" "testWithArgs:..."

+ (BOOL) _isClassTestMethod:(SEL)selector
{
  const char* methodName = sel_getName(selector);
  char *pat = "test";
  if ((strlen(methodName) > strlen(pat)) &&
      (strncmp(methodName, pat, strlen(pat)) == 0) &&
      (strchr(methodName, ':') == NULL)) {
    return TRUE;
  } else {
    return FALSE;
  }
}

// Return array of Method pointers that match the class method "test*"
// with no arguments.

+ (Method*) _classTestMethods:(Class)c
                     outCount:(unsigned int*)outCount
{
  unsigned int classCount;
  unsigned int matchCount = 0;
  Method *methods = class_copyMethodList(object_getClass(c), &classCount);
  
  for (int i=0; i < classCount; i++) {
    SEL selector = method_getName(methods[i]);
    if ([self _isClassTestMethod:selector]) {
      matchCount++;
    }
  }
  
  if (matchCount == 0) {
    return NULL;
  }
  
  Method *testMethods = malloc(sizeof(Method*) * matchCount);
  int j = 0;
  for (int i=0; i < classCount; i++) {
    SEL selector = method_getName(methods[i]);
    if ([self _isClassTestMethod:selector]) {
      testMethods[j++] = methods[i];
    }
  }  
  
  free(methods);
  *outCount = matchCount;
  return testMethods;  
}

// Returns TRUE if 1 or more methods named "test*"

+ (BOOL) _classHasTestMethods:(Class)c {
  unsigned int count;
  Method *methods = [self _classTestMethods:c outCount:&count];
  if (methods == NULL) {
    return FALSE;
  }
  free(methods);
  return TRUE;
}

+ (void) _invokeIfClassRespondsToSelector:(Class)c sel:(SEL)sel {
	if ([self _classRespondsToSelector:c sel:sel]) {
		[c performSelector:sel];
	}
}

+ (NSArray*) _getTestClasses {
	// Find classes named "*Test" that extend NSObject and implement "test*"
  
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
  
      // Iterate over each selector and see if there is at least 1
      // class method that matches "test*".
      
			if ([self _classHasTestMethods:aClass]) {
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
  
  // Invoke test condition method once before the timing loop is entered, so that the
  // event loop will not be entered if the condition is initially TRUE.

  BOOL state;
  
  [anInvocation invoke];
  [anInvocation getReturnValue:&state];

  if (state) {
    return TRUE;
  }

  // The condition is FALSE, so enter the event loop and wait for 1 second
  // each iteration through the loop. The logic below makes sure that the
  // 1 second wait will be done at least once, even if wait time is less
  // than a full second.
  
  int numSeconds = (int) round(maxWaitTime);
  if (numSeconds < 1) {
    numSeconds = 1;
  }
  
  for ( ; numSeconds > 0 ; numSeconds--) {
    NSDate *maxDate = [NSDate dateWithTimeIntervalSinceNow:1.0];
    [[NSRunLoop currentRunLoop] runUntilDate:maxDate];

    [anInvocation invoke];
    [anInvocation getReturnValue:&state];

    if (state) {
      return TRUE;
    }    
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

// Find classes named "*Test" that extend NSObject and implement
// 1 to N methods that match "test*".

+ (void) _testApp {
  for (Class c in [self _getTestClasses]) {
    NSAutoreleasePool *outer_pool = [[NSAutoreleasePool alloc] init];
    
    const char *className = class_getName(c);
    NSString *classNameStr = [NSString stringWithFormat:@"%s", className];

    unsigned int count;
    Method *methods = [self _classTestMethods:c outCount:&count];
      
    for (int i=0; i < count; i++) {
      NSAutoreleasePool *inner_pool = [[NSAutoreleasePool alloc] init];
      
      SEL selector = method_getName(methods[i]);
      
      NSString *methodNameStr = [NSString stringWithFormat:@"%s", sel_getName(selector)];
      
      NSLog(@"RegressionTest %@.%@:", classNameStr, methodNameStr);
      
      [self _invokeIfClassRespondsToSelector:c sel:selector];
      
      [self cleanupAfterTest];
      
      [inner_pool drain];
    }
    
    free(methods);
    
    [outer_pool drain];
	}
  
  NSLog(@"RegressionTest DONE");
  
//  id appDelegate = [[UIApplication sharedApplication] delegate];
//	NSAssert(appDelegate, @"appDelegate is nil");
    
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
