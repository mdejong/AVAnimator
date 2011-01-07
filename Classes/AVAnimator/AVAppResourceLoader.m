//
//  AVAppResourceLoader.m
//
//  Created by Moses DeJong on 7/13/10.
//
//  License terms defined in License.txt.

#import "AVAppResourceLoader.h"

@implementation AVAppResourceLoader

@synthesize movieFilename = m_movieFilename;
@synthesize audioFilename = m_audioFilename;

- (void) dealloc
{
  self.movieFilename = nil;
  self.audioFilename = nil;
  [super dealloc];
}

+ (AVAppResourceLoader*) aVAppResourceLoader
{
  return [[[AVAppResourceLoader alloc] init] autorelease];
}

- (BOOL) _fileExists:(NSString*)path
{
	return [[NSFileManager defaultManager] fileExistsAtPath:path];
}

- (NSString*) _getMoviePath:(NSString*)movieFilename
{
	NSBundle* appBundle = [NSBundle mainBundle];
	NSString* movieFilePath = [appBundle pathForResource:movieFilename ofType:nil];
  NSAssert(movieFilePath, @"movieFilePath is nil");
	return movieFilePath;
}

- (NSString*) _getAudioPath:(NSString*)audioFilename
{
  return [self _getMoviePath:audioFilename];
}

- (BOOL) isReady
{
  BOOL isMovieReady = FALSE;
  BOOL isAudioReady = FALSE;
  
  NSAssert(self.movieFilename, @"movieFilename is nil");
  
  // Check for movie file in tmp dir
  NSString *tmpAnimationsPath = [self _getMoviePath:self.movieFilename];
  
  if ([self _fileExists:tmpAnimationsPath]) {
    isMovieReady = TRUE;
  }
  
  if (self.audioFilename != nil) {
    // Check for audio file in tmp dir
    NSString *tmpTracksPath = [self _getAudioPath:self.audioFilename];
    NSAssert(tmpTracksPath, @"tmpTracksPath is nil");
    
    if ([self _fileExists:tmpTracksPath]) {
      isAudioReady = TRUE;
    }    
  } else {
    isAudioReady = TRUE;
  }
  
  if (isMovieReady && isAudioReady) {
    m_isReady = TRUE;
    return TRUE;
  } else {
    return FALSE;
  }
}

- (NSArray*) getResources
{
	if (!m_isReady) {
		NSAssert(FALSE, @"resources not ready");
  }
  NSMutableArray *mArr = [NSMutableArray array];
  NSString *tmpAnimationsPath = [self _getMoviePath:self.movieFilename];
  [mArr addObject:tmpAnimationsPath];  
  if (self.audioFilename != nil) {
    NSString *tmpTracksPath = [self _getAudioPath:self.audioFilename];
    [mArr addObject:tmpTracksPath];
  }
	return [NSArray arrayWithArray:mArr];
}

- (void) load
{
  NSAssert(self.movieFilename, @"movieFilename is nil");
  NSAssert(self.audioFilename, @"audioFilename is nil");
  
  // No-op since the movie must exist as a resource

  return;
}

@end
