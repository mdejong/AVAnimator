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

- (NSString*) _getResourcePath:(NSString*)movieFilename
{
	NSBundle* appBundle = [NSBundle mainBundle];
	NSString* movieFilePath = [appBundle pathForResource:movieFilename ofType:nil];
  NSAssert(movieFilePath, @"movieFilePath is nil");
	return movieFilePath;
}

- (NSString*) _getMoviePath:(NSString*)movieFilename
{
  return [self _getResourcePath:movieFilename];
}

- (NSString*) _getAudioPath:(NSString*)audioFilename
{
  return [self _getResourcePath:audioFilename];
}

- (BOOL) isMovieReady
{
  BOOL isMovieReady = FALSE;
  
  NSAssert(self.movieFilename, @"movieFilename is nil");
  
  // Return TRUE if the mov file exists in the app resources

  NSString *tmpMoviePath = [self _getMoviePath:self.movieFilename];
  
  if ([self _fileExists:tmpMoviePath]) {
    isMovieReady = TRUE;
  }
  
  return isMovieReady;
}

- (BOOL) isAudioReady
{
  BOOL isAudioReady = FALSE;
  
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
  
  return isAudioReady;
}


- (BOOL) isReady
{
  BOOL isMovieReady = FALSE;
  BOOL isAudioReady = FALSE;
  
  isMovieReady = [self isMovieReady];
  isAudioReady = [self isAudioReady];
    
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

  // audioFilename can be nil
  //NSAssert(self.audioFilename, @"audioFilename is nil");
  
  // No-op since the movie must exist as a resource

  return;
}

@end
