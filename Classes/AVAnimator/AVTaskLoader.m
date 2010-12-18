//
//  AVTaskLoader.m
//  iPractice
//
//  Created by Moses DeJong on 7/13/10.
//  Copyright 2010 __MyCompanyName__. All rights reserved.
//

#import "AVTaskLoader.h"

#import "AudioTasks.h"
#import "MovieTasks.h"

@implementation AVTaskLoader

@synthesize movieFilename = m_movieFilename;
@synthesize audioFilename = m_audioFilename;

- (void) dealloc
{
  self.movieFilename = nil;
  self.audioFilename = nil;
  [super dealloc];
}

+ (AVTaskLoader*) aVTaskLoader
{
  return [[[AVTaskLoader alloc] init] autorelease];
}

- (BOOL) _fileExists:(NSString*)path
{
	return [[NSFileManager defaultManager] fileExistsAtPath:path];
}

- (NSString*) _getMoviePath:(NSString*)movieFilename
{
  NSString *tmpDir = NSTemporaryDirectory();
  NSString *tmpAnimationsDirname = [MovieTasks animationsDirname];  
  NSString *tmpAnimationsDir = [tmpDir stringByAppendingPathComponent:tmpAnimationsDirname];
  NSString *tmpAnimationsPath = [tmpAnimationsDir stringByAppendingPathComponent:self.movieFilename];
  NSAssert(tmpAnimationsPath, @"tmpAnimationsPath is nil");
  return tmpAnimationsPath;
}

- (NSString*) _getAudioPath:(NSString*)audioFilename
{
  NSString *tmpDir = NSTemporaryDirectory();
  NSString *tmpTracksDirname = [AudioTasks tracksDirname];  
  NSString *tmpTracksDir = [tmpDir stringByAppendingPathComponent:tmpTracksDirname];
  NSString *tmpTracksPath = [tmpTracksDir stringByAppendingPathComponent:self.audioFilename];
  NSAssert(tmpTracksPath, @"tmpTracksPath is nil");  
  return tmpTracksPath;
}

- (BOOL) isReady
{
  BOOL isMovieReady = FALSE;
  BOOL isAudioReady = FALSE;
  
  NSAssert(self.movieFilename, @"movieFilename is nil");
  NSAssert(self.audioFilename, @"audioFilename is nil");
  
  // Check for movie file in tmp dir
  NSString *tmpAnimationsPath = [self _getMoviePath:self.movieFilename];
  
  if ([self _fileExists:tmpAnimationsPath]) {
    isMovieReady = TRUE;
  }
  
  // Check for audio file in tmp dir
  NSString *tmpTracksPath = [self _getAudioPath:self.audioFilename];
  NSAssert(tmpTracksPath, @"tmpTracksPath is nil");

  if ([self _fileExists:tmpTracksPath]) {
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
  NSString *tmpAnimationsPath = [self _getMoviePath:self.movieFilename];
  NSString *tmpTracksPath = [self _getAudioPath:self.audioFilename];
	return [NSArray arrayWithObjects:tmpAnimationsPath, tmpTracksPath, nil];
}

- (void) load
{
  NSAssert(self.movieFilename, @"movieFilename is nil");
  NSAssert(self.audioFilename, @"audioFilename is nil");
  
  [MovieTasks enqueueTask:self.movieFilename];
  [AudioTasks enqueueTask:self.audioFilename];

  return;
}

@end
