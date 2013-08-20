//
//  AVAssetConvertCommon.h
//
//  Created by Moses DeJong on 7/8/12.
//
//  License terms defined in License.txt.

#import <Foundation/Foundation.h>

#if __IPHONE_OS_VERSION_MIN_REQUIRED >= __IPHONE_4_1 // iOS 4.1 or newer (iOS Deployment Target)

#define HAS_AVASSET_CONVERT_MAXVID

#endif // iOS 4.1 or newer

#if __IPHONE_OS_VERSION_MIN_REQUIRED >= __IPHONE_5_0 // iOS 5.0 or newer (iOS Deployment Target)

// Note that one can comment out this define and then the project would not
// need to link to GLKit or OpenGLES frameworks. The only class that depends
// on these two frameworks is AVAnimatorOpenGLView

#define HAS_AVASSET_READ_COREVIDEO_BUFFER_AS_TEXTURE

#endif // iOS 5.0 or newer
