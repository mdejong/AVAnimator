//
//  AV7zAppResourceLoader.m
//
//  Created by Moses DeJong on 4/22/11.
//
//  License terms defined in License.txt.
//

#import "AV7zAppResourceLoader.h"

#import "LZMAExtractor.h"

@implementation AV7zAppResourceLoader

@synthesize archiveFilename = m_archiveFilename;

- (void) dealloc
{
  self.archiveFilename = nil;
  [super dealloc];
}

+ (AV7zAppResourceLoader*) aV7zAppResourceLoader
{
  return [[[AV7zAppResourceLoader alloc] init] autorelease];
}

- (void) load
{
  // Superclass load method asserts that self.movieFilename is not nil
  [super load];
  
  if (self.archiveFilename == nil) {
    // If no archive filename is indicated, but an entry filename is, then assume
    // the archive name. For example, if movieFilename is "2x2_black_blue_16BPP.mov"
    // then assume an archive filename of "2x2_black_blue_16BPP.mov.7z"
    self.archiveFilename = [NSString stringWithFormat:@"%@.7z", self.movieFilename];
  }
  
  // FIXME: impl async load, also ignore multiple calls to "load" via a flag or
  // a file exists test or something.

  // Blocking decode of 7z archive entry, this should be done in another
  // thread.
    
  NSString *archiveFilename = self.archiveFilename;
  NSString *archivePath = [self _getResourcePath:archiveFilename];
  NSString *archiveEntry = self.movieFilename;
  
  NSString *tmpDir = NSTemporaryDirectory();  
  NSString *outPath = [tmpDir stringByAppendingPathComponent:archiveEntry];

  // FIXME: Does load not get invoked if already extracted?
  // If entry has been extracted already, no need to extract it again ???
  
  BOOL worked;
  worked = [LZMAExtractor extractArchiveEntry:archivePath archiveEntry:archiveEntry outPath:outPath];
  assert(worked);
  
  return;
}

// Given a filename (typically an archive entry name), return the filename
// in the tmp dir that corresponds to the entry. For example,
// "2x2_black_blue_16BPP.mov" -> "/tmp/2x2_black_blue_16BPP.mov" where "/tmp"
// is the app tmp dir.

- (NSString*) _getTmpDirPath:(NSString*)filename
{
  NSString *tmpDir = NSTemporaryDirectory();
  NSAssert(tmpDir, @"tmpDir");
  NSString *outPath = [tmpDir stringByAppendingPathComponent:filename];
  NSAssert(outPath, @"outPath");
  return outPath;
}

// Define isMovieReady so that TRUE is returned if the mov file
// has been decompressed already.

- (BOOL) isMovieReady
{
  BOOL isMovieReady = FALSE;
  
  NSAssert(self.movieFilename, @"movieFilename is nil");
  
  // Return TRUE if the decoded mov file exists in the tmp dir
  
  NSString *tmpMoviePath = [self _getTmpDirPath:self.movieFilename];
  
  if ([self _fileExists:tmpMoviePath]) {
    isMovieReady = TRUE;
  }
  
  return isMovieReady;
}

@end
