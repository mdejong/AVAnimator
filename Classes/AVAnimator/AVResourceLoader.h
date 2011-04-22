//
//  AVResourceLoader.h
//  AVAnimatorDemo
//
//  Created by Moses DeJong on 4/7/09.
//
//  License terms defined in License.txt.

#import <Foundation/Foundation.h>

// A resource loader is created by the the AVAnimatorView class
// to support loading of a resource from a URL or memory. The
// AVAnimatorView class creates a view widget and then
// prepares to load the resources for a specific instance of
// a AVResourceLoader. The resource might exist already, or it
// may need to be generated which could take some time.

@interface AVResourceLoader : NSObject {
}

// Return TRUE if resource(s) have already been created
// and are ready to be loaded without a long delay. This
// method can be invoked before a call to load.

- (BOOL) isReady;

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

@end
