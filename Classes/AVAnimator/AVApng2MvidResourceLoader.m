//
//  AVApng2MvidResourceLoader.h
//
//  Created by Moses DeJong on 5/2/11.
//
//  License terms defined in License.txt.
//

#import "AVApng2MvidResourceLoader.h"

#import "apng_convert_maxvid.h"

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
  return [[[AVApng2MvidResourceLoader alloc] init] autorelease];
}

- (void) dealloc
{
  self.outPath = nil;
  [super dealloc];
}

// Output movie filename must be redefined

- (NSString*) _getMoviePath
{
  return self.outPath;
}

// This method is invoked in the secondary thread to decode the contents of the archive entry
// and write it to an output file (typically in the tmp dir).

//#define LOGGING

+ (void) decodeThreadEntryPoint:(NSArray*)arr {  
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  
  NSAssert([arr count] == 4, @"arr count");
  
  // Pass RESOURCE_PATH PHONY_TMP_PATH TMP_PATH GEN_ADLER
  
  NSString *resPath = [arr objectAtIndex:0];
  NSString *phonyOutPath = [arr objectAtIndex:1];
  NSString *outPath = [arr objectAtIndex:2];
  NSString *genAdlerNum = [arr objectAtIndex:3];
  
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
  assert(retcode == 0);
    
  // The temp filename holding the maxvid data is now completely written, rename it to "XYZ.mvid"
  
  if ([[NSFileManager defaultManager] fileExistsAtPath:outPath]) {
    [[NSFileManager defaultManager] removeItemAtPath:outPath error:NULL];
  }
  
  BOOL worked = [[NSFileManager defaultManager] moveItemAtPath:phonyOutPath toPath:outPath error:nil];
  NSAssert(worked, @"moveItemAtPath failed for decode result");
  
#ifdef LOGGING
  NSLog(@"done converting .apng to .mvid \"%@\"", [outPath lastPathComponent]);
#endif // LOGGING
  
  [pool drain];
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
  
  NSArray *arr = [NSArray arrayWithObjects:resPath, phonyOutPath, outPath, genAdlerNum, nil];
  NSAssert([arr count] == 4, @"arr count");
  
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
  
  NSString *resPath = [AVFileUtil getResourcePath:self.movieFilename];
  NSString *outPath = self.outPath;
  NSAssert(outPath, @"outPath not defined");
  
  // Generate phony tmp path that data will be written to as it is extracted.
  // This avoids thread race conditions and partial writes. Note that the filename is
  // generated in this method, and this method should only be invoked from the main thread.
  
  NSString *phonyOutPath = [AVFileUtil generateUniqueTmpPath];
  
  [self _detachNewThread:resPath phonyOutPath:phonyOutPath outPath:outPath];
  
  return;
}

@end
