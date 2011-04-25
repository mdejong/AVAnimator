//
//  AV7zQT2MvidResourceLoader.h
//
//  Created by Moses DeJong on 4/22/11.
//
//  License terms defined in License.txt.
//

#import "AV7zQT2MvidResourceLoader.h"

#import "LZMAExtractor.h"

#import "movdata_convert_maxvid.h"

#import "AVFileUtil.h"

@implementation AV7zQT2MvidResourceLoader

+ (AV7zQT2MvidResourceLoader*) aV7zQT2MvidResourceLoader
{
  return [[[AV7zQT2MvidResourceLoader alloc] init] autorelease];
}

// This method is invoked in the secondary thread to decode the contents of the archive entry
// and write it to an output file (typically in the tmp dir).

#define LOGGING

+ (void) decodeThreadEntryPoint:(NSArray*)arr {  
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  
  NSAssert([arr count] == 5, @"arr count");
  
  // Pass ARCHIVE_PATH ARCHIVE_ENTRY_NAME TMP_PATH
  
  NSString *archivePath = [arr objectAtIndex:0];
  NSString *archiveEntry = [arr objectAtIndex:1];
  NSString *phonyOutPath = [arr objectAtIndex:2];
  NSString *phonyOutPath2 = [arr objectAtIndex:3];
  NSString *outPath = [arr objectAtIndex:4];
  
#ifdef LOGGING
  NSLog(@"start 7zip extraction %@", archiveEntry);
#endif // LOGGING
  
  BOOL worked;
  worked = [LZMAExtractor extractArchiveEntry:archivePath archiveEntry:archiveEntry outPath:phonyOutPath];
  assert(worked);
  
  // The archive .mov file is extracted to a phony tmp path like "/tmp/15354345345", convert the
  // animation codec data to a maxvid file (another tmp path).

  NSData *mappedData = [NSData dataWithContentsOfMappedFile:phonyOutPath];
  NSAssert(mappedData, @"could not map .mov data");
  
  char *movPathCstr = (char*) [phonyOutPath UTF8String];
  char *movData = (char*) [mappedData bytes];
  uint32_t movNumBytes = [mappedData length];
  char *phonyOutPath2Cstr = (char*) [phonyOutPath2 UTF8String];
  
  assert(strcmp(movPathCstr, phonyOutPath2Cstr) != 0);
  
#ifdef LOGGING
  NSLog(@"done 7zip extraction %@, start encode", archiveEntry);
#endif // LOGGING  
  
  uint32_t retcode;
  retcode = movdata_convert_maxvid_file(movPathCstr, movData, movNumBytes, phonyOutPath2Cstr);
  assert(retcode == 0);
  
  // Remove tmp file that contains the .mov data
  
  worked = [[NSFileManager defaultManager] removeItemAtPath:phonyOutPath error:nil];
  NSAssert(worked, @"could not remove tmp file");
  
  // The temp filename holding the maxvid data is now completely written, rename it to "XYZ.mvid"
  
  worked = [[NSFileManager defaultManager] moveItemAtPath:phonyOutPath2 toPath:outPath error:nil];
  NSAssert(worked, @"moveItemAtPath failed for decode result");
  
#ifdef LOGGING
  NSLog(@"done encode %@", [outPath lastPathComponent]);
#endif // LOGGING
  
  [pool drain];
}

- (void) _detachNewThread:(NSString*)archivePath
             archiveEntry:(NSString*)archiveEntry
             phonyOutPath:(NSString*)phonyOutPath
                  outPath:(NSString*)outPath
{
  // Use the same paths defined in the superclass, but pass 1 additional temp filename that will contain
  // the intermediate results of the conversion.
  
  NSString *phonyOutPath2 = [AVFileUtil generateUniqueTmpPath];
  
  NSAssert(![phonyOutPath isEqualToString:phonyOutPath2], @"tmp out paths can't be the same");
  
  NSArray *arr = [NSArray arrayWithObjects:archivePath, archiveEntry, phonyOutPath, phonyOutPath2, outPath, nil];
  NSAssert([arr count] == 5, @"arr count");
  
  [NSThread detachNewThreadSelector:@selector(decodeThreadEntryPoint:) toTarget:self.class withObject:arr];  
}

@end
