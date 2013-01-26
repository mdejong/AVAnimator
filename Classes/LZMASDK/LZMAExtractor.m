//
//  LZMAExtractor.m
//  flipbooks
//
//  Created by Mo DeJong on 11/19/09.
//  Copyright 2009 __MyCompanyName__. All rights reserved.
//

#import "LZMAExtractor.h"

int do7z_extract_entry(char *archivePath, char *archiveCachePath, char *entryName, char *entryPath);

@implementation LZMAExtractor

// Return a fully qualified random filename in the tmp dir. The filename is based on the
// exact time offset since 1970 so it should be unique.

+ (NSString*) generateUniqueTmpCachePath
{
  NSString *tmpDir = NSTemporaryDirectory();
  
  NSDate *nowDate = [NSDate date];
  NSTimeInterval ti = [nowDate timeIntervalSinceReferenceDate];
  
  // Format number of seconds as a string with a decimal separator
  NSString *doubleString = [NSString stringWithFormat:@"%f", ti];
  
  // Remove the decimal point so that the file name consists of
  // numeric characters only.
  
  NSRange range;
  range = NSMakeRange(0, [doubleString length]);
  NSString *noDecimalString = [doubleString stringByReplacingOccurrencesOfString:@"."
                                                                      withString:@""
                                                                         options:0
                                                                           range:range];
  
  range = NSMakeRange(0, [noDecimalString length]);
  NSString *noMinusString = [noDecimalString stringByReplacingOccurrencesOfString:@"-"
                                                                      withString:@""
                                                                         options:0
                                                                           range:range];

  NSString *filename = [NSString stringWithFormat:@"%@%@", noMinusString, @".cache"];
  
  NSString *tmpPath = [tmpDir stringByAppendingPathComponent:filename];
  
  return tmpPath;
}

// Extract all the contents of a .7z archive into the indicated temp dir
// and return an array of the fully qualified filenames.

+ (NSArray*) extract7zArchive:(NSString*)archivePath
                   tmpDirName:(NSString*)tmpDirName
{
  NSAssert(archivePath, @"archivePath");
  NSAssert(tmpDirName, @"tmpDirName");
  
	NSString *tmpDir = NSTemporaryDirectory();    
  BOOL worked, isDir, existsAlready;
  
  NSString *myTmpDir = [tmpDir stringByAppendingPathComponent:tmpDirName];
  existsAlready = [[NSFileManager defaultManager] fileExistsAtPath:myTmpDir isDirectory:&isDir];
  
  if (existsAlready && !isDir) {
    worked = [[NSFileManager defaultManager] removeItemAtPath:myTmpDir error:nil];
    NSAssert(worked, @"could not remove existing file with same name as tmp dir");
    // create the directory below
  }
  
  if (existsAlready && isDir) {
    // Remove all the files in the named tmp dir
    NSArray *contents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:myTmpDir error:nil];
    NSAssert(contents, @"contentsOfDirectoryAtPath failed");
    for (NSString *path in contents) {
      NSLog(@"found existing dir path: %@", path);
      NSString *myTmpDirPath = [myTmpDir stringByAppendingPathComponent:path];
      worked = [[NSFileManager defaultManager] removeItemAtPath:myTmpDirPath error:nil];
      NSAssert(worked, @"could not remove existing file");
    }
  } else {
    worked = [[NSFileManager defaultManager] createDirectoryAtPath:myTmpDir withIntermediateDirectories:YES attributes:nil error:nil];    
    NSAssert(worked, @"could not create tmp dir");
  }
  
  worked = [[NSFileManager defaultManager] changeCurrentDirectoryPath:myTmpDir];
  NSAssert(worked, @"cd to tmp 7z dir failed");
  NSLog(@"cd to %@", myTmpDir);
  
  char *archivePathPtr = (char*) [archivePath UTF8String];
  NSString *archiveCachePath = [self generateUniqueTmpCachePath];
  char *archiveCachePathPtr = (char*) [archiveCachePath UTF8String];
  char *entryNamePtr = NULL; // Extract all entries by passing NULL
  char *entryPathPtr = NULL;
  
  int result = do7z_extract_entry(archivePathPtr, archiveCachePathPtr, entryNamePtr, entryPathPtr);
  NSAssert(result == 0, @"could not extract files from 7z archive");
  
  // Examine the contents of the current directory to see what was extracted
  
  NSMutableArray *fullPathContents = [NSMutableArray array];
  
  NSArray *contents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:myTmpDir error:nil];
  NSAssert(contents, @"contentsOfDirectoryAtPath failed");
  for (NSString *path in contents) {
    NSLog(@"found existing dir path: %@", path);
    NSString *myTmpDirPath = [myTmpDir stringByAppendingPathComponent:path];
    [fullPathContents addObject:myTmpDirPath];
  }
  
  return [NSArray arrayWithArray:fullPathContents];
}

// Extract just one entry from an archive and save it at the
// path indicated by outPath.

+ (BOOL) extractArchiveEntry:(NSString*)archivePath
                archiveEntry:(NSString*)archiveEntry
                     outPath:(NSString*)outPath
{
  NSAssert(archivePath, @"archivePath");
  NSAssert(archiveEntry, @"archiveEntry");
  NSAssert(outPath, @"outPath");
  
  char *archivePathPtr = (char*) [archivePath UTF8String];
  NSString *archiveCachePath = [self generateUniqueTmpCachePath];
  char *archiveCachePathPtr = (char*) [archiveCachePath UTF8String];
  char *archiveEntryPtr = (char*) [archiveEntry UTF8String];
  char *outPathPtr = (char*) [outPath UTF8String];
    
  int result = do7z_extract_entry(archivePathPtr, archiveCachePathPtr, archiveEntryPtr, outPathPtr);
  return (result == 0);
}

@end
