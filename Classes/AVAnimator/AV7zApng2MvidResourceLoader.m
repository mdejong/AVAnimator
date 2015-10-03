//
//  AV7zApng2MvidResourceLoader.m
//
//  Created by Moses DeJong on 5/2/11.
//

#import "AV7zApng2MvidResourceLoader.h"

#import "ApngConvertMaxvid.h"

#import "AVFileUtil.h"

#import "LZMAExtractor.h"

#ifndef __OPTIMIZE__
// Automatically define EXTRA_CHECKS when not optimizing (in debug mode)
# define EXTRA_CHECKS
#endif // DEBUG

@implementation AV7zApng2MvidResourceLoader

@synthesize alwaysGenerateAdler = m_alwaysGenerateAdler;

+ (AV7zApng2MvidResourceLoader*) aV7zApng2MvidResourceLoader
{
  AV7zApng2MvidResourceLoader *obj = [[AV7zApng2MvidResourceLoader alloc] init];
#if __has_feature(objc_arc)
  return obj;
#else
  return [obj autorelease];
#endif // objc_arc
}

// This method is invoked in the secondary thread to decode the contents of the archive entry
// and write it to an output file (typically in the tmp dir).

#define LOGGING

+ (void) decodeThreadEntryPoint:(NSArray*)arr {  
  @autoreleasepool {
  
  NSAssert([arr count] == 7, @"arr count");
  
  // Pass 7 args : ARCHIVE_PATH ARCHIVE_ENTRY_NAME PHONY_TMP_PATH1 PHONY_TMP_PATH2 TMP_PATH GEN_ADLER SERIAL
  
  NSString *archivePath = [arr objectAtIndex:0];
  NSString *archiveEntry = [arr objectAtIndex:1];
  NSString *phonyOutPath = [arr objectAtIndex:2];
  NSString *phonyOutPath2 = [arr objectAtIndex:3];
  NSString *outPath = [arr objectAtIndex:4];
  NSString *genAdlerNum = [arr objectAtIndex:5];
  NSNumber *serialLoadingNum = [arr objectAtIndex:6];

  if ([serialLoadingNum boolValue]) {
    [self grabSerialResourceLoaderLock];
  }
  
  // Check to see if the output file already exists. If the resource exists at this
  // point, then there is no reason to kick off another decode operation. For example,
  // in the serial loading case, a previous load could have loaded the resource.
  
  BOOL fileExists = [AVFileUtil fileExists:outPath];
  
  if (fileExists) {
#ifdef LOGGING
    NSLog(@"no 7z .apng -> .mvid conversion needed for %@", archiveEntry);
#endif // LOGGING
  } else {
    
#ifdef LOGGING
    NSLog(@"start 7zip extraction %@", archiveEntry);
#endif // LOGGING
    
    BOOL worked;
    worked = [LZMAExtractor extractArchiveEntry:archivePath archiveEntry:archiveEntry outPath:phonyOutPath];
    NSAssert(worked, @"extractArchiveEntry");
    
    // The .apng from the archive is extracted to a phony tmp path like "/tmp/15354345345", convert the
    // APNG data and save into another tmp path.
    
    char *apngPathCstr = (char*) [phonyOutPath UTF8String];
    char *phonyOutPath2Cstr = (char*) [phonyOutPath2 UTF8String];
    
    assert(strcmp(apngPathCstr, phonyOutPath2Cstr) != 0);
    
#ifdef LOGGING
    NSLog(@"done 7zip extraction %@, start encode", archiveEntry);
#endif // LOGGING
    
    uint32_t retcode;
    
    uint32_t genAdler = 0;
#ifdef EXTRA_CHECKS
    genAdler = 1;
#endif // EXTRA_CHECKS
    if ([genAdlerNum intValue]) {
      genAdler = 1;
    }
    
    retcode = apng_convert_maxvid_file(apngPathCstr, phonyOutPath2Cstr, genAdler);  
    NSAssert(retcode == 0, @"apng_convert_maxvid_file");
    
    // Remove tmp file that contains the .apng data
    
    worked = [[NSFileManager defaultManager] removeItemAtPath:phonyOutPath error:nil];
    NSAssert(worked, @"could not remove tmp file");
    
    // The temp filename holding the maxvid data is now completely written, rename it to "XYZ.mvid"
    
    [AVFileUtil renameFile:phonyOutPath2 toPath:outPath];
    
#ifdef LOGGING
    NSLog(@"done encode %@", [outPath lastPathComponent]);
#endif // LOGGING    
  }

  if ([serialLoadingNum boolValue]) {
    [self releaseSerialResourceLoaderLock];
  }

  }
}

- (void) _detachNewThread:(NSString*)archivePath
             archiveEntry:(NSString*)archiveEntry
             phonyOutPath:(NSString*)phonyOutPath
                  outPath:(NSString*)outPath
           flattenOutPath:(NSString*)flattenOutPath
{
  // Use the same paths defined in the superclass, but pass 1 additional temp filename that will contain
  // the intermediate results of the conversion.
  
  NSString *phonyOutPath2 = [AVFileUtil generateUniqueTmpPath];
  
  NSAssert(![phonyOutPath isEqualToString:phonyOutPath2], @"tmp out paths can't be the same");
  
  uint32_t genAdler = self.alwaysGenerateAdler;
  NSNumber *genAdlerNum = [NSNumber numberWithInt:genAdler];
  NSAssert(genAdlerNum != nil, @"genAdlerNum");
    
  NSNumber *serialLoadingNum = [NSNumber numberWithBool:self.serialLoading];

  NSArray *arr = [NSArray arrayWithObjects:archivePath,
                  archiveEntry,
                  phonyOutPath,
                  phonyOutPath2,
                  outPath,
                  genAdlerNum,
                  serialLoadingNum,
                  nil];
  NSAssert([arr count] == 7, @"arr count");
  
  [NSThread detachNewThreadSelector:@selector(decodeThreadEntryPoint:) toTarget:self.class withObject:arr];
}

@end
