//
//  Created by Moses DeJong on 4/22/11.
//
//  License terms defined in License.txt.
//
// File related utility functions.

#import <Foundation/Foundation.h>

@interface AVFileUtil : NSObject {

}

// Given a filename like "foo.txt", return the fully qualified path
// in the temp dir (like "/tmp/foo.txt"). The tmp dir is the app defined
// temp directory.

+ (NSString*) getTmpDirPath:(NSString*)filename;

// Return TRUE if a file exists with the indicated path, FALSE otherwise.

+ (BOOL) fileExists:(NSString*)path;

// Return the path for a resource file

+ (NSString*) getResourcePath:(NSString*)resFilename;

// Return a fully qualified path to a unique filename in the tmp dir.
// This filename will not be the same as a previously used filename
// and it will not conflict with an existing file in the tmp dir.
// This method should only be invoked from the main thread, in order
// to ensure that there are no thread race conditions present when
// generating the tmp filename.

+ (NSString*) generateUniqueTmpPath;

// If the filename is fully qualified, then check that the file
// exists and return nil if it does not exist. If the filename
// is a simple filename, then check that a resource file with
// that filename exists and return nil if the resource does not exist.
// In either case, a fully qualified path of a file that is known
// to exist is returned, otherwise nil.

+ (NSString*) getQualifiedFilenameOrResource:(NSString*)filename;

// Rename the file at path to the file indicated by toPath.
// This util method will remove an existing file at toPath
// and assert that the move operation was successful.

+ (void) renameFile:(NSString*)path toPath:(NSString*)toPath;

@end
