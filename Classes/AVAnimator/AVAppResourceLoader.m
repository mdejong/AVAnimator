//
//  AVAppResourceLoader.m
//
//  Created by Moses DeJong on 7/13/10.
//
//  License terms defined in License.txt.

#import "AVAppResourceLoader.h"

#import "AVFileUtil.h"

@implementation AVAppResourceLoader

@synthesize movieFilename = m_movieFilename;
@synthesize audioFilename = m_audioFilename;

- (void) dealloc
{
  self.movieFilename = nil;
  self.audioFilename = nil;
  
#if __has_feature(objc_arc)
#else
  [super dealloc];
#endif // objc_arc
}

+ (AVAppResourceLoader*) aVAppResourceLoader
{
  AVAppResourceLoader *obj = [[AVAppResourceLoader alloc] init];
#if __has_feature(objc_arc)
  return obj;
#else
  return [obj autorelease];
#endif // objc_arc
}

- (NSString*) _getMoviePath
{
  // If movieFilename is a fully qualified path that indicates an existing file,
  // the load that file directly. This makes it possible to use a file from the
  // tmp dir or some other location. If the file name is not fully qualified
  // then it must be a resource filename.
  
  NSString *qualPath = [AVFileUtil getQualifiedFilenameOrResource:self.movieFilename];
  NSAssert(qualPath, @"qualPath");  
  return qualPath;
}

- (NSString*) _getAudioPath:(NSString*)audioFilename
{
  // If audioFilename is a fully qualified path that indicates an existing file,
  // the load that file directly. This makes it possible to use a file from the
  // tmp dir or some other location. If the file name is not fully qualified
  // then it must be a resource filename.  
  
  NSString *qualPath = [AVFileUtil getQualifiedFilenameOrResource:audioFilename];
  NSAssert(qualPath, @"qualPath");  
  return qualPath;
}

- (BOOL) isMovieReady
{
  BOOL isMovieReady = FALSE;
  
  NSAssert(self.movieFilename, @"movieFilename is nil");
  
  // Return TRUE if the mov file exists in the app resources

  NSString *tmpMoviePath = [self _getMoviePath];
  
  if ([AVFileUtil fileExists:tmpMoviePath]) {
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
    
    if ([AVFileUtil fileExists:tmpTracksPath]) {
      isAudioReady = TRUE;
    }    
  } else {
    isAudioReady = TRUE;
  }
  
  return isAudioReady;
}

// Getter for isReady property defined in superclass

- (BOOL) isReady
{
  BOOL isMovieReady = FALSE;
  BOOL isAudioReady = FALSE;
  
  isMovieReady = [self isMovieReady];
  isAudioReady = [self isAudioReady];
    
  if (isMovieReady && isAudioReady) {
    self.isReady = TRUE;
    return TRUE;
  } else {
    return FALSE;
  }
}

- (NSArray*) getResources
{
	if (!self.isReady) {
		NSAssert(FALSE, @"resources not ready");
  }
  NSMutableArray *mArr = [NSMutableArray array];
  NSString *tmpAnimationsPath = [self _getMoviePath];
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
