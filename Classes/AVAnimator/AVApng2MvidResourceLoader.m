//
//  AVApng2MvidResourceLoader.h
//
//  Created by Moses DeJong on 5/2/11.
//
//  License terms defined in License.txt.
//

#import "AVApng2MvidResourceLoader.h"

#import "ApngConvertMaxvid.h"

#import "AVFileUtil.h"

#ifndef __OPTIMIZE__
// Automatically define EXTRA_CHECKS when not optimizing (in debug mode)
# define EXTRA_CHECKS
#endif // DEBUG

@implementation AVApng2MvidResourceLoader

@synthesize outPath = m_outPath;
@synthesize alwaysGenerateAdler = m_alwaysGenerateAdler;

+ (AVApng2MvidResourceLoader*) aVApng2MvidResourceLoader
{
  AVApng2MvidResourceLoader *obj = [[AVApng2MvidResourceLoader alloc] init];
#if __has_feature(objc_arc)
  return obj;
#else
  return [obj autorelease];
#endif // objc_arc
}

- (void) dealloc
{
  self.outPath = nil;
  
#if __has_feature(objc_arc)
#else
  [super dealloc];
#endif // objc_arc
}

// Output movie filename must be redefined

- (NSString*) _getMoviePath
{
  return self.outPath;
}

// This method is invoked in the secondary thread to decode the contents of the archive entry
// and write it to an output file (typically in the tmp dir).

#define LOGGING

+ (void) decodeThreadEntryPoint:(NSArray*)arr {  
  @autoreleasepool {
  
  NSAssert([arr count] == 5, @"arr count");
  
  // Pass 5 args : RESOURCE_PATH PHONY_TMP_PATH TMP_PATH GEN_ADLER SERIAL
  
  NSString *resPath = [arr objectAtIndex:0];
  NSString *phonyOutPath = [arr objectAtIndex:1];
  NSString *outPath = [arr objectAtIndex:2];
  NSString *genAdlerNum = [arr objectAtIndex:3];
  NSNumber *serialLoadingNum = [arr objectAtIndex:4];
  
  if ([serialLoadingNum boolValue]) {
    [self grabSerialResourceLoaderLock];
  }
  
  // Check to see if the output file already exists. If the resource exists at this
  // point, then there is no reason to kick off another decode operation. For example,
  // in the serial loading case, a previous load could have loaded the resource.
  
  BOOL fileExists = [AVFileUtil fileExists:outPath];
  
  if (fileExists) {
#ifdef LOGGING
    NSLog(@"no .apng -> .mvid conversion needed for %@", [resPath lastPathComponent]);
#endif // LOGGING
  } else {
    
#ifdef LOGGING
    NSLog(@"start .apng -> .mvid conversion \"%@\"", [resPath lastPathComponent]);
#endif // LOGGING
    
    uint32_t retcode;
    
    uint32_t genAdler = 0;
#ifdef EXTRA_CHECKS
    genAdler = 1;
#endif // EXTRA_CHECKS
    if ([genAdlerNum intValue]) {
      genAdler = 1;
    }
    
    char *resPathCstr = (char*) [resPath UTF8String];
    char *phonyOutPathCstr = (char*) [phonyOutPath UTF8String];
    
    retcode = apng_convert_maxvid_file(resPathCstr, phonyOutPathCstr, genAdler);
    if (retcode != 0) {
      NSAssert(retcode == 0, @"apng_convert_maxvid_file");
    }
    
    // The temp filename holding the maxvid data is now completely written, rename it to "XYZ.mvid"
    
    [AVFileUtil renameFile:phonyOutPath toPath:outPath];
    
#ifdef LOGGING
    NSLog(@"done converting .apng to .mvid \"%@\"", [outPath lastPathComponent]);
#endif // LOGGING    
  }
  
  if ([serialLoadingNum boolValue]) {
    [self releaseSerialResourceLoaderLock];
  }
  
  }
}

- (void) _detachNewThread:(NSString*)resPath
             phonyOutPath:(NSString*)phonyOutPath
                  outPath:(NSString*)outPath
{
  // Use the same paths defined in the superclass, but pass 1 additional temp filename that will contain
  // the intermediate results of the conversion.
  
  uint32_t genAdler = self.alwaysGenerateAdler;
  NSNumber *genAdlerNum = [NSNumber numberWithInt:genAdler];
  NSAssert(genAdlerNum != nil, @"genAdlerNum");
  
  NSNumber *serialLoadingNum = [NSNumber numberWithBool:self.serialLoading];
  
  NSArray *arr = [NSArray arrayWithObjects:resPath, phonyOutPath, outPath, genAdlerNum, serialLoadingNum, nil];
  NSAssert([arr count] == 5, @"arr count");
  
  [NSThread detachNewThreadSelector:@selector(decodeThreadEntryPoint:) toTarget:self.class withObject:arr];  
}

- (void) load
{
  // Avoid kicking off mutliple sync load operations. This method should only
  // be invoked from a main thread callback, so there should not be any chance
  // of a race condition involving multiple invocations of this load mehtod.
  
  if (startedLoading) {
    return;
  } else {
    self->startedLoading = TRUE;    
  }
  
  // Superclass load method asserts that self.movieFilename is not nil
  [super load];
  
  // If movie filename is already fully qualified, then don't qualify it as a resource path
  
  NSString *qualPath = [AVFileUtil getQualifiedFilenameOrResource:self.movieFilename];
  NSAssert(qualPath, @"qualPath");
  
  NSString *outPath = self.outPath;
  NSAssert(outPath, @"outPath not defined");
  
  // Generate phony tmp path that data will be written to as it is extracted.
  // This avoids thread race conditions and partial writes. Note that the filename is
  // generated in this method, and this method should only be invoked from the main thread.
  
  NSString *phonyOutPath = [AVFileUtil generateUniqueTmpPath];
  
  [self _detachNewThread:qualPath phonyOutPath:phonyOutPath outPath:outPath];
  
  return;
}

@end
