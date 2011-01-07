//
//  AVAppResourceLoader.h
//
//  Created by Moses DeJong on 7/13/10.
//
//  License terms defined in License.txt.

#import <Foundation/Foundation.h>

#import "AVResourceLoader.h"

@interface AVAppResourceLoader : AVResourceLoader {
	NSString *m_movieFilename;
	NSString *m_audioFilename;
  BOOL m_isReady;
}

@property (nonatomic, copy) NSString *movieFilename;
@property (nonatomic, copy) NSString *audioFilename;

+ (AVAppResourceLoader*) aVAppResourceLoader;

- (BOOL) isReady;

// Note that invoking load multiple times is not going to cause problems,
// multiple requests will be ignored since the cached file would already
// exist when the next request comes in.

- (void) load;

@end
