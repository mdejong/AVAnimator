//
//  AVAsset2MvidResourceLoader.m
//
//  Created by Moses DeJong on 2/24/12.
//

#import "AVAsset2MvidResourceLoader.h"

#import "AVFileUtil.h"

#import "AVAssetReaderConvertMaxvid.h"

#define LOGGING

@implementation AVAsset2MvidResourceLoader

@synthesize outPath = m_outPath;
@synthesize alwaysGenerateAdler = m_alwaysGenerateAdler;

+ (AVAsset2MvidResourceLoader*) aVAsset2MvidResourceLoader
{
  AVAsset2MvidResourceLoader *obj = [[AVAsset2MvidResourceLoader alloc] init];
  return [obj autorelease];
}

- (void) dealloc
{
  self.outPath = nil;
  [super dealloc];
}

// This method is invoked in the secondary thread to decode the contents of the archive entry
// and write it to an output file (typically in the tmp dir).

+ (void) decodeThreadEntryPoint:(NSArray*)arr {  
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  
  NSAssert([arr count] == 5, @"arr count");
  
  // Pass 5 arguments : ASSET_PATH PHONY_PATH TMP_PATH SERIAL ADLER
  
  NSString *assetPath = [arr objectAtIndex:0];
  NSString *phonyOutPath = [arr objectAtIndex:1];
  NSString *outPath = [arr objectAtIndex:2];
  NSNumber *serialLoadingNum = [arr objectAtIndex:3];
  NSNumber *alwaysGenerateAdler = [arr objectAtIndex:4];
  
  if ([serialLoadingNum boolValue]) {
    [self grabSerialResourceLoaderLock];
  }
  
  // Check to see if the output file already exists. If the resource exists at this
  // point, then there is no reason to kick off another decode operation. For example,
  // in the serial loading case, a previous load could have loaded the resource.
  
  BOOL fileExists = [AVFileUtil fileExists:outPath];
  
  if (fileExists) {
#ifdef LOGGING
    NSLog(@"no asset decompression needed for %@", [assetPath lastPathComponent]);
#endif // LOGGING
  } else {
#ifdef LOGGING
    NSLog(@"start asset decompression %@", [assetPath lastPathComponent]);
#endif // LOGGING  
    
    BOOL worked;
    
    AVAssetReaderConvertMaxvid *obj = [AVAssetReaderConvertMaxvid aVAssetReaderConvertMaxvid];
    obj.assetURL = [NSURL fileURLWithPath:assetPath];
    obj.mvidPath = phonyOutPath;
    
    if ([alwaysGenerateAdler intValue]) {
      obj.genAdler = TRUE;
    }
    
    worked = [obj blockingDecode];
    NSAssert(worked, @"blockingDecode");

#ifdef LOGGING
    NSLog(@"done asset decompression %@", [assetPath lastPathComponent]);
#endif // LOGGING
    
    // Move phony tmp filename to the expected filename once writes are complete
    
    [AVFileUtil renameFile:phonyOutPath toPath:outPath];
    
#ifdef LOGGING
    NSLog(@"wrote %@", outPath);
#endif // LOGGING
  }
  
  if ([serialLoadingNum boolValue]) {
    [self releaseSerialResourceLoaderLock];
  }
  
  [pool drain];
}

- (void) _detachNewThread:(NSString*)assetPath
             phonyOutPath:(NSString*)phonyOutPath
                  outPath:(NSString*)outPath
{
  NSNumber *serialLoadingNum = [NSNumber numberWithBool:self.serialLoading];
  
  uint32_t genAdler = self.alwaysGenerateAdler;
  NSNumber *genAdlerNum = [NSNumber numberWithInt:genAdler];
  NSAssert(genAdlerNum != nil, @"genAdlerNum");
  
  NSArray *arr = [NSArray arrayWithObjects:assetPath, phonyOutPath, outPath, serialLoadingNum, genAdlerNum, nil];
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
    startedLoading = TRUE;
  }
  
  // Superclass load method asserts that self.movieFilename is not nil
  [super load];
  
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

// Output movie filename must be redefined

- (NSString*) _getMoviePath
{
  return self.outPath;
}

@end
