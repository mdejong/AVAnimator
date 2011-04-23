//
//  Created by Moses DeJong on 4/22/11.
//
//  License terms defined in License.txt.

#import "AVFileUtil.h"

@implementation AVFileUtil

// Given a filename (typically an archive entry name), return the filename
// in the tmp dir that corresponds to the entry. For example,
// "2x2_black_blue_16BPP.mov" -> "/tmp/2x2_black_blue_16BPP.mov" where "/tmp"
// is the app tmp dir.

+ (NSString*) getTmpDirPath:(NSString*)filename
{
  NSString *tmpDir = NSTemporaryDirectory();
  NSAssert(tmpDir, @"tmpDir");
  NSString *outPath = [tmpDir stringByAppendingPathComponent:filename];
  NSAssert(outPath, @"outPath");
  return outPath;
}

+ (BOOL) fileExists:(NSString*)path
{
	return [[NSFileManager defaultManager] fileExistsAtPath:path];
}

+ (NSString*) getResourcePath:(NSString*)resFilename
{
	NSBundle* appBundle = [NSBundle mainBundle];
	NSString* movieFilePath = [appBundle pathForResource:resFilename ofType:nil];
  NSAssert(movieFilePath, @"movieFilePath is nil");
	return movieFilePath;
}

+ (NSString*) generateUniqueTmpPath
{
  NSString *tmpDir = NSTemporaryDirectory();
  
  NSDate *nowDate = [NSDate date];  
  NSTimeInterval ti = [nowDate timeIntervalSinceReferenceDate];
  
  // Format number of seconds as a string with a decimal separator
  NSString *doubleString = [NSString stringWithFormat:@"%f", ti];

  // Remove the decimal point so that the file name consists of
  // numeric characters only.
  
  NSRange range = NSMakeRange(0, [doubleString length]);
  
  NSString *noDecimalString = [doubleString stringByReplacingOccurrencesOfString:@"."
                                                                      withString:@""
                                                                         options:0
                                                                           range:range];

  NSString *tmpPath = [tmpDir stringByAppendingPathComponent:noDecimalString];

  return tmpPath;
}

@end
