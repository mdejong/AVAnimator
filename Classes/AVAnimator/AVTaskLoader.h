//
//  AVTaskLoader.h
//  iPractice
//
//  Created by Moses DeJong on 7/13/10.
//  Copyright 2010 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "AVResourceLoader.h"

@interface AVTaskLoader : AVResourceLoader {
	NSString *m_movieFilename;
	NSString *m_audioFilename;
  BOOL m_isReady;
}

@property (nonatomic, copy) NSString *movieFilename;
@property (nonatomic, copy) NSString *audioFilename;

+ (AVTaskLoader*) aVTaskLoader;

- (BOOL) isReady;

// Note that invoking load multiple times is not going to cause problems,
// multiple requests will be ignored since the cached file would already
// exist when the next request comes in.

- (void) load;

@end
