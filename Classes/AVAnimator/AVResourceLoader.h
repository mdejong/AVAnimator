//
//  AVResourceLoader.h
//  AVAnimatorDemo
//
//  Created by Moses DeJong on 4/7/09.
//
//  License terms defined in License.txt.

#import <Foundation/Foundation.h>

// Create a resource loader and attach it to the media
// object to implement a specific type of resource loading.
// The type of resource might be a URL or a file, but the
// exact method used to load the resource is defined by
// a specific implementation.

@interface AVResourceLoader : NSObject {
@private
  BOOL m_isReady;
  BOOL m_serialLoading;
}

// TRUE if if resource(s) have already been created
// and are ready to be loaded without a long delay. This
// method can be invoked before a call to load.

@property (nonatomic, assign) BOOL isReady;

// If this property is set to TRUE before the loading
// process begins, then secondary loading threads will
// be run one at a time. This means resources will load
// one at a time, so if decoding multiple resources
// would consume too much CPU or memory resources, this
// flag provides a way to limit resource usage by loading
// one resource at a time.

@property (nonatomic, assign) BOOL serialLoading;

// Invoked to load resources, this call assumes that
// isReady has been invoked to check if the resources
// actually need to be loaded. This call must be
// non-blocking and return right away. If a loading
// operation will take time to execute, it should be
// implemented as a secondary thread.

- (void) load;

// Return an array that contains 1 to N resources. The
// contents of the array depends on the implementation
// of the resource loaded, but typically the array
// contains NString* that contains the filename of
// a resource in the tmp dir.

- (NSArray*) getResources;

// Use these methods to implement serial resource loading
// logic in subclasses of AVResourceLoader.

+ (void) grabSerialResourceLoaderLock;

+ (void) releaseSerialResourceLoaderLock;

// This method will deallocate the shared global memory
// associated with the serial resource loader lock.
// This method is provided for completeness, it would
// not typically be invoked at runtime.

+ (void) freeSerialResourceLoaderLock;

@end
