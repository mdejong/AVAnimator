//
//  AVAsset2MvidResourceLoader.m
//
//  Created by Moses DeJong on 2/24/12.
//

#import "AVAsset2MvidResourceLoader.h"

#if defined(HAS_AVASSET_CONVERT_MAXVID)

#import "AVFileUtil.h"

#import "AVAssetReaderConvertMaxvid.h"

#define LOGGING

@implementation AVAsset2MvidResourceLoader

@synthesize outPath = m_outPath;
@synthesize alwaysGenerateAdler = m_alwaysGenerateAdler;
@synthesize movieSize = m_movieSize;

#if defined(HAS_LIB_COMPRESSION_API)
@synthesize compressed = m_compressed;
#endif // HAS_LIB_COMPRESSION_API

+ (AVAsset2MvidResourceLoader*) aVAsset2MvidResourceLoader
{
  AVAsset2MvidResourceLoader *obj = [[AVAsset2MvidResourceLoader alloc] init];
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

// This method is invoked in the secondary thread to decode the contents of the archive entry
// and write it to an output file (typically in the tmp dir).

+ (void) decodeThreadEntryPoint:(NSArray*)arr {  
  @autoreleasepool {
  
  NSAssert([arr count] == 8, @"arr count");
  
  // Pass 5 arguments : ASSET_PATH PHONY_PATH TMP_PATH SERIAL ADLER RENDER_WIDTH RENDER_HEIGHT IS_COMPRESSED
  
  NSString *assetPath = [arr objectAtIndex:0];
  NSString *phonyOutPath = [arr objectAtIndex:1];
  NSString *outPath = [arr objectAtIndex:2];
  NSNumber *serialLoadingNum = [arr objectAtIndex:3];
  NSNumber *alwaysGenerateAdler = [arr objectAtIndex:4];
  NSNumber *renderWidthNum = [arr objectAtIndex:5];
  NSNumber *renderHeightNum = [arr objectAtIndex:6];
  NSNumber *isCompressedNum = [arr objectAtIndex:7];
  
  BOOL compressed = [isCompressedNum boolValue];
  compressed = compressed; // avoid compiler wanring
    
  CGSize renderSize = CGSizeMake([renderWidthNum intValue], [renderHeightNum intValue]);
  
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
    obj.movieSize = renderSize;
    
#if defined(HAS_LIB_COMPRESSION_API)
    obj.compressed = compressed;
#endif // HAS_LIB_COMPRESSION_API
    
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
    {
      // Query the file length for the container, will be returned by length getter.
      // If the file does not exist, then nil is returned.
      NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:outPath error:nil];
      if (attrs != nil) {
        unsigned long long fileSize = [attrs fileSize];
        size_t fileSizeT = (size_t) fileSize;
        NSAssert(fileSize == fileSizeT, @"assignment from unsigned long long to size_t lost bits");
        
        NSLog(@"wrote \"%@\" at size %d kB", outPath, (int)fileSizeT/1000);
      }
    }
#endif // LOGGING
  }
  
  if ([serialLoadingNum boolValue]) {
    [self releaseSerialResourceLoaderLock];
  }
  
  }
}

- (void) _detachNewThread:(NSString*)assetPath
             phonyOutPath:(NSString*)phonyOutPath
                  outPath:(NSString*)outPath
{
  NSNumber *serialLoadingNum = [NSNumber numberWithBool:self.serialLoading];
  
  uint32_t genAdler = self.alwaysGenerateAdler;
  NSNumber *genAdlerNum = [NSNumber numberWithInt:genAdler];
  NSAssert(genAdlerNum != nil, @"genAdlerNum");
  
  int renderWidth = self.movieSize.width;
  int renderHeight = self.movieSize.height;
  
#if defined(HAS_LIB_COMPRESSION_API)
  NSNumber *isCompressedNum = [NSNumber numberWithBool:self.compressed];
#else
  NSNumber *isCompressedNum = [NSNumber numberWithBool:false];
#endif // HAS_LIB_COMPRESSION_API
  
  NSArray *arr = [NSArray arrayWithObjects:assetPath, phonyOutPath, outPath, serialLoadingNum, genAdlerNum, @(renderWidth), @(renderHeight), isCompressedNum, nil];
  NSAssert([arr count] == 8, @"arr count");
  
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

#endif // HAS_AVASSET_CONVERT_MAXVID
