//
//  AutoPropertyRelease.h
//
//  Created by Moses DeJong on 11/11/09.
//  Placed in the public domain.
//
// This class implements a runtime property deallocator.
// The Objective-C compiler really should implement
// automatic deallocation of properties that retain/copy.
// Until that happens, this class provides a simple way
// to ensure that all retained objects are actually released.
// Be aware that this releaseProperties method can only be
// invoked safely from the dealloc method of a class.
//
// @implementation MyClass
// @synthesize ...;
//
// - (void) dealloc {
//     [AutoPropertyRelease releaseProperties:self thisClass:[MyClass class]];
//     [super dealloc];
// }
//
// The releaseProperties method sets each object property to nil, so
// you could optionally invoke it from viewDidUnload in addition to
// dealloc in a gui class that extends NSView. Note that the usage
// below will release all the properties, not just those that extend NSView.
//
//- (void)viewDidUnload {
//    [AutoPropertyRelease releaseProperties:self thisClass:[MyClass class]];
//}

#if __has_feature(objc_arc)
// No-op
#else

#import <Foundation/Foundation.h>

@interface AutoPropertyRelease : NSObject {
}

+ (void)releaseProperties:(NSObject*)obj thisClass:(Class)thisClass;

@end

#endif // objc_arc
