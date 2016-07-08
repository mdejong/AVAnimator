//
//  AVAnimatorH264AlphaPlayer.m
//
//  Created by Moses DeJong on 2/27/16.
//
//  License terms defined in License.txt.

#import "AVAnimatorH264AlphaPlayer.h"

#if defined(HAS_AVASSET_READ_COREVIDEO_BUFFER_AS_TEXTURE)

#import <QuartzCore/QuartzCore.h>

#import <OpenGLES/ES2/gl.h>
#import <OpenGLES/ES2/glext.h>

#import "CGFrameBuffer.h"

#import "AVFrameDecoder.h"

#import "AVAnimatorMedia.h"

#import "AVFrame.h"

#import "AVFileUtil.h"

#import <mach/mach.h>

#import <CoreMedia/CMSampleBuffer.h>

#if __has_feature(objc_arc)
#else
#import "AutoPropertyRelease.h"
#endif // objc_arc

// private properties declaration for AVAnimatorOpenGLView class
//#include "AVAnimatorH264AlphaPlayerPrivate.h"

// private method in Media class
#include "AVAnimatorMediaPrivate.h"

#import <QuartzCore/CAEAGLLayer.h>

// Trivial vertex and fragment shaders

enum
{
  UNIFORM_BGRA_BGR,
  UNIFORM_BGRA_A,
  NUM_UNIFORMS_BGRA
};
GLint uniformsBGRA[NUM_UNIFORMS_BGRA];

enum
{
  UNIFORM_Y,
  UNIFORM_UV,
  UNIFORM_A,
  UNIFORM_COLOR_CONVERSION_MATRIX,
  NUM_UNIFORMS
};
GLint uniforms[NUM_UNIFORMS];

// Color Conversion Constants (YUV to RGB) including adjustment from 16-235/16-240 (video range)

// BT.601, which is the standard for SDTV.
static const GLfloat kColorConversion601[] = {
  1.164,  1.164, 1.164,
  0.0, -0.392, 2.017,
  1.596, -0.813,   0.0,
};

// BT.709, which is the standard for HDTV.
static const GLfloat kColorConversion709[] = {
  1.164,  1.164, 1.164,
  0.0, -0.213, 2.112,
  1.793, -0.533,   0.0,
};

// FIXME: The input sRGB values need to be moved back to a linear
// colorspace so that the non-linear undelta result can be operated
// on with a simple floating point multiplication as opposed to
// a table based approach in the shaders.

// https://developer.apple.com/library/ios/documentation/Metal/Reference/MetalShadingLanguageGuide/numerical-comp/numerical-comp.html
// https://www.khronos.org/webgl/public-mailing-list/archives/1009/msg00028.php
// http://entropymine.com/imageworsener/srgbformula/

const static BOOL renderBGRA = FALSE;

static
const GLchar *vertShaderBGRACstr =
"attribute vec4 position; attribute mediump vec4 textureCoordinate;"
"varying mediump vec2 coordinate;"
"void main()"
"{"
"	gl_Position = position;"
"	coordinate = textureCoordinate.xy;"
"}";

static
const GLchar *fragShaderBGRACstr =
"varying highp vec2 coordinate;"
"uniform sampler2D videoframe;"
"uniform sampler2D alphaframe;"
"void main()"
"{"
"  mediump vec4 rgba;"
"  rgba = texture2D(videoframe, coordinate);"
"  rgba.a = 1.0;"
// premultiply
"  rgba = rgba * texture2D(alphaframe, coordinate).r;"
"  gl_FragColor = rgba;"
"}";

static
const GLchar *vertShaderYUVCstr =
"attribute vec4 position; attribute mediump vec4 textureCoordinate;"
"varying mediump vec2 coordinate;"
"void main()"
"{"
"	gl_Position = position;"
"	coordinate = textureCoordinate.xy;"
"}";

static
const GLchar *fragShaderYUVCstr =
"varying highp vec2 coordinate;"
"precision mediump float;"
"uniform sampler2D SamplerY;"
"uniform sampler2D SamplerUV;"
"uniform sampler2D SamplerA;"
"uniform mat3 colorConversionMatrix;"
"void main()"
"{"
"  mediump vec3 yuv;"
"  mediump vec3 rgb;"
"  mediump float alpha;"
// Subtract constants to map the video range (16, 255) to (0.0, 1.0)
"  yuv.x = (texture2D(SamplerY, coordinate).r - (16.0/255.0));"
"  yuv.yz = (texture2D(SamplerUV, coordinate).rg - vec2(0.5, 0.5));"
"  rgb = colorConversionMatrix * yuv;"
// Subtract constants to map the video range (16, 255) to (0.0, 1.0)
"  alpha = texture2D(SamplerA, coordinate).r - (16.0/255.0);"
// Scale alpha to (0, 255) like colorConversionMatrix
"  alpha = alpha * colorConversionMatrix[0][0];"
// premultiply
"  rgb = rgb * alpha;"
"  gl_FragColor = vec4(rgb, alpha);"
"}";

enum {
  ATTRIB_VERTEX,
  ATTRIB_TEXTUREPOSITON,
  NUM_ATTRIBUTES
};

// Debug render from CoreVideo

#if defined(DEBUG)

@interface AVAssetFrameDecoder ()

- (BOOL) renderCVImageBufferRefIntoFramebuffer:(CVImageBufferRef)imageBuffer frameBuffer:(CGFrameBuffer**)frameBufferPtr;

@end

#endif // DEBUG

// class declaration for AVAnimatorOpenGLView

@interface AVAnimatorH264AlphaPlayer () {
@private
	CGSize m_renderSize;
  
	int renderBufferWidth;
	int renderBufferHeight;
  
  GLuint passThroughProgram;
  
  // A texture cache ref is an opaque type that contains a specific
  // textured cache. Note that in the case where there are 2 textures
  // just one cache is needed.
  
  CVOpenGLESTextureCacheRef textureCacheRef;
  
  // Colorspace conversion
  
	const GLfloat *_preferredConversion;
  
  BOOL didSetupOpenGLMembers;
  
  AVAnimatorPlayerState m_state;
  
  // Stores the first time when a display link callback was
  // delivered. This corresponds to the time for frame 1.
  
  CFTimeInterval firstTimeInterval;
  
  // This value is set in the main thread when the display
  // link timer is fired. If the display link is running
  // behind the wall clock then this value is advanced
  // so that the decoder can tell things are falling behind.
  
  int nextDecodeFrame;
  
  // repeating GCD timer
  
  dispatch_source_t _dispatchTimer;
  dispatch_queue_t _highPrioQueue;
  
  // Timer set when a repeating dispatch timer is started
  // but with the knowledge that the value only be accessed
  // from the secondary thread.
  
  CFTimeInterval dispatchFirstTimeInterval;
  CFTimeInterval dispatchPrevTimeInterval;
  
  // The number of frames that can be accessed by the
  // decoder. This value should be thread safe to access
  // since it is only set once at load time.

  int m_dispatchMaxFrame;
}

@property (nonatomic, assign) CGSize renderSize;

// Must be atomic since this property can be accessed
// from both the main and decode threads.

@property (atomic, assign) int currentFrame;

// This atomic property stores the largest frame
// number in the RGB+Alpha frames.

@property (atomic, assign) int dispatchMaxFrame;

// This property is non-zero when waiting for the display timer
// and the decoder timer to sync.

@property (atomic, assign) uint32_t waitingForDecodeToStart;

@property (nonatomic, retain) AVFrame *rgbFrame;
@property (nonatomic, retain) AVFrame *alphaFrame;

@property (nonatomic, retain) NSTimer *animatorPrepTimer;

@property (nonatomic, assign) BOOL renderYUVFrames;

@property (nonatomic, assign) AVAnimatorPlayerState state;

@property (nonatomic, retain) CADisplayLink *displayLink;

// This NSDate object stores a projected optimal frame
// decode time for the next frame decode operation.

+ (uint32_t) timeIntervalToFrameOffset:(CFTimeInterval)elapsed
                                   fps:(CFTimeInterval)fps;

@end

// class AVAnimatorH264AlphaPlayer

@implementation AVAnimatorH264AlphaPlayer

// public properties

@synthesize renderSize = m_renderSize;
@synthesize rgbFrame = m_rgbFrame;
@synthesize alphaFrame = m_alphaFrame;
@synthesize assetFilename = m_assetFilename;
@synthesize frameDecoder = m_frameDecoder;
@synthesize animatorPrepTimer = m_animatorPrepTimer;
@synthesize currentFrame = m_currentFrame;
@synthesize state = m_state;
@synthesize dispatchMaxFrame = m_dispatchMaxFrame;

#if defined(DEBUG)
@synthesize captureDir = m_captureDir;
#endif // DEBUG

- (void) dealloc {
	// Explicitly release image inside the imageView, the
	// goal here is to get the imageView to drop the
	// ref to the CoreGraphics image and avoid a memory
	// leak. This should not be needed, but it is.
  
	self.rgbFrame = nil;
	self.alphaFrame = nil;
  self.frameDecoder = nil;
  
  if (self.animatorPrepTimer != nil) {
    [self.animatorPrepTimer invalidate];
  }
  
  // Dealloc OpenGL stuff
	
  if (passThroughProgram) {
    glDeleteProgram(passThroughProgram);
    passThroughProgram = 0;
  }
	
  if (textureCacheRef) {
    CFRelease(textureCacheRef);
    textureCacheRef = 0;
  }
  
  [self cancelDispatchTimer];
  
#if __has_feature(objc_arc)
#else
  [AutoPropertyRelease releaseProperties:self thisClass:AVAnimatorH264AlphaPlayer.class];
  [super dealloc];
#endif // objc_arc
}

// static ctor

+ (AVAnimatorH264AlphaPlayer*) aVAnimatorH264AlphaPlayer
{
  UIScreen *screen = [UIScreen mainScreen];
#if defined(TARGET_OS_TV)
  CGRect rect = screen.bounds;
#else
  CGRect rect = screen.applicationFrame;
#endif // TARGET_OS_TV
  return [AVAnimatorH264AlphaPlayer aVAnimatorH264AlphaPlayerWithFrame:rect];
}

+ (AVAnimatorH264AlphaPlayer*) aVAnimatorH264AlphaPlayerWithFrame:(CGRect)viewFrame
{
  AVAnimatorH264AlphaPlayer *obj = [[AVAnimatorH264AlphaPlayer alloc] initWithFrame:viewFrame];
#if __has_feature(objc_arc)
  return obj;
#else
  return [obj autorelease];
#endif // objc_arc
}

// Get EAGLContext with static method since the self reference is not setup yet

+ (EAGLContext*) genericInitEAGLContext1
{
  EAGLContext *context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2];
  
#if __has_feature(objc_arc)
#else
  context = [context autorelease];
#endif // objc_arc
  
  if (!context || ![EAGLContext setCurrentContext:context]) {
    NSLog(@"Problem with init of OpenGL ES2 context.");
    
    return nil;
  }
  
  return context;
}

// This init method is invoked after the self reference is valid.

- (void) genericInitEAGLContext2:(EAGLContext*)context
{
  // Defaults for opacity related properties. We expect the view to be
  // fully opaque since the image renders all the pixels in the view.
  // Unless in 32bpp mode, in that case pixels can be partially transparent.
  
  // Set GLKView.context
  self.context = context;

  // FIXME: setting opaque to FALSE significantly changes the color
  // even when the alpha is set to 1
  
  // FIXME: The opaque flag should be set to FALSE
  //self.opaque = TRUE;
  self.opaque = FALSE;
  
  self.clearsContextBeforeDrawing = FALSE;
  //self.backgroundColor = [UIColor clearColor];
  self.backgroundColor = nil;
  
  // Use 2x scale factor on Retina displays.
  self.contentScaleFactor = [[UIScreen mainScreen] scale];
  
  // Set to NO to indicate that application will force redraws
  self.enableSetNeedsDisplay = YES;
//  self.enableSetNeedsDisplay = NO;
  
  self->passThroughProgram = 0;
  self->textureCacheRef = NULL;
  
  self->didSetupOpenGLMembers = FALSE;
  
  // Set the default conversion to BT.709, which is the standard for HDTV.
  self->_preferredConversion = kColorConversion709;
  
  return;
}

- (id) initWithFrame:(CGRect)frame
{
  EAGLContext *context = [self.class genericInitEAGLContext1];
  
  if (context == nil) {
    return nil;
  }
  
  if ((self = [super initWithFrame:frame])) {
    [self genericInitEAGLContext2:context];
  }
  
  return self;
}

- (void) awakeFromNib
{
  [super awakeFromNib];
  
  EAGLContext *context = [self.class genericInitEAGLContext1];
  
  if (context) {
    [self genericInitEAGLContext2:context];
  }
}

// Setup OpenGL objects and ids that need to be created only once, the first time
// the view is being rendered. Any OpenGL state that only needs to be set once
// for this context can be set here as long as it will not change from one render
// to the next.

- (BOOL) setupOpenGLMembers
{
//	BOOL success = YES;
//	
//	glDisable(GL_DEPTH_TEST);
 
  BOOL worked;
  
  //  Create a new CVOpenGLESTexture cache
  CVReturn err = CVOpenGLESTextureCacheCreate(kCFAllocatorDefault, NULL, self.context, NULL, &self->textureCacheRef);
  if (err) {
    NSLog(@"Error at CVOpenGLESTextureCacheCreate %d", err);
    worked = FALSE;
  } else {
    worked = TRUE;
  }
  
  if (worked) {
    worked = [self compileShaders];
  }
  return worked;
}


- (void)renderWithSquareVertices:(const GLfloat*)squareVertices textureVertices:(const GLfloat*)textureVertices
{
  // Use shader program.
  glUseProgram(passThroughProgram);
  
  // Update attribute values.
	glVertexAttribPointer(ATTRIB_VERTEX, 2, GL_FLOAT, 0, 0, squareVertices);
	glEnableVertexAttribArray(ATTRIB_VERTEX);
	glVertexAttribPointer(ATTRIB_TEXTUREPOSITON, 2, GL_FLOAT, 0, 0, textureVertices);
	glEnableVertexAttribArray(ATTRIB_TEXTUREPOSITON);
  
  // Update uniform values if there are any
  
  if (renderBGRA) {
    glUniform1i(uniformsBGRA[UNIFORM_BGRA_BGR], 0);
    glUniform1i(uniformsBGRA[UNIFORM_BGRA_A], 1);
  } else {
    // 0 and 1 are the texture IDs of _lumaTexture and _chromaTexture respectively.
    glUniform1i(uniforms[UNIFORM_Y], 0);
    glUniform1i(uniforms[UNIFORM_UV], 1);
    glUniform1i(uniforms[UNIFORM_A], 2);
    glUniformMatrix3fv(uniforms[UNIFORM_COLOR_CONVERSION_MATRIX], 1, GL_FALSE, _preferredConversion);
  }
  
  // Validate program before drawing. This is a good check, but only really necessary in a debug build.
  // DEBUG macro must be defined in your debug configurations if that's not already the case.
#if defined(DEBUG)
  [self validateProgram:passThroughProgram];
#endif
	
	glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
}

- (CGRect)textureSamplingRectForCroppingTextureWithAspectRatio:(CGSize)textureAspectRatio toAspectRatio:(CGSize)croppingAspectRatio
{
	CGRect normalizedSamplingRect = CGRectZero;
	CGSize cropScaleAmount = CGSizeMake(croppingAspectRatio.width / textureAspectRatio.width, croppingAspectRatio.height / textureAspectRatio.height);
	CGFloat maxScale = fmax(cropScaleAmount.width, cropScaleAmount.height);
	CGSize scaledTextureSize = CGSizeMake(textureAspectRatio.width * maxScale, textureAspectRatio.height * maxScale);
	
	if ( cropScaleAmount.height > cropScaleAmount.width ) {
		normalizedSamplingRect.size.width = croppingAspectRatio.width / scaledTextureSize.width;
		normalizedSamplingRect.size.height = 1.0;
	}
	else {
		normalizedSamplingRect.size.height = croppingAspectRatio.height / scaledTextureSize.height;
		normalizedSamplingRect.size.width = 1.0;
	}
	// Center crop
	normalizedSamplingRect.origin.x = (1.0 - normalizedSamplingRect.size.width)/2.0;
	normalizedSamplingRect.origin.y = (1.0 - normalizedSamplingRect.size.height)/2.0;
	
	return normalizedSamplingRect;
}

// Render the RGB and Alpha textures as the view via OpenGL draw

- (void) displayFrame
{
  //NSLog(@"displayFrame %@", frame);
  
  AVFrame *rgbFrame = self.rgbFrame;
  AVFrame *alphaFrame = self.alphaFrame;
  
  // Weird case where putting app in background invokes this method and the frames are otherwise
  // valid but the buffer refs are NULL.
  
  CVImageBufferRef cvImageBufferRef = NULL;
  CVImageBufferRef cvAlphaImageBufferRef = NULL;
  
  BOOL notReady = FALSE;
  BOOL wasReadyButCoreVideoBuffersInvalidated = FALSE;
  
  if (rgbFrame == nil || alphaFrame == nil) {
    notReady = TRUE;
  }
  
  if (notReady == FALSE) {
    cvImageBufferRef = rgbFrame.cvBufferRef;
    cvAlphaImageBufferRef = alphaFrame.cvBufferRef;
    
    if ((cvImageBufferRef == NULL) || (cvAlphaImageBufferRef == NULL)) {
      notReady = TRUE;
      wasReadyButCoreVideoBuffersInvalidated = TRUE;
    }
  }
  
  if (wasReadyButCoreVideoBuffersInvalidated) {
    // Nop, leave the existing cached render result as-is
    
    return;
  } else if (notReady) {
    glClearColor(0.0, 0.0, 0.0, 0.0); // Fully transparent
    glClear(GL_COLOR_BUFFER_BIT);
    
    return;
  }
  
  NSAssert(rgbFrame.isDuplicate == FALSE, @"a duplicate frame should not cause a display update");
  NSAssert(alphaFrame.isDuplicate == FALSE, @"a duplicate frame should not cause a display update");

	size_t frameWidth;
	size_t frameHeight;
  
  size_t bytesPerRow;
  
  // This OpenGL player view is only useful when decoding CoreVideo frames, it is possible
  // that a misconfiguration could result in a normal AVFrame that contains a UIImage
  // getting passed to an OpenGL view. Simply assert here in that case instead of attempting
  // to support the non-optimal case since that would just cover up a configuration error
  // anyway.
  
  if (cvImageBufferRef == NULL) {
    NSAssert(FALSE, @"AVFrame delivered to AVAnimatorOpenGLView does not contain a CoreVideo pixel buffer");
  }
  if (cvAlphaImageBufferRef == NULL) {
    NSAssert(FALSE, @"AVFrame delivered to AVAnimatorOpenGLView does not contain a CoreVideo pixel buffer");
  }
  
  frameWidth = CVPixelBufferGetWidth(cvImageBufferRef);
  frameHeight = CVPixelBufferGetHeight(cvImageBufferRef);
  bytesPerRow = CVPixelBufferGetBytesPerRow(cvImageBufferRef);
  
#if defined(DEBUG)
  assert(frameWidth == CVPixelBufferGetWidth(cvAlphaImageBufferRef));
  assert(frameHeight == CVPixelBufferGetHeight(cvAlphaImageBufferRef));
#endif // DEBUG
  
  // Use the color attachment of the pixel buffer to determine the appropriate color conversion matrix.
  
  if (renderBGRA) {
    // BGRA is a nop
  } else {
    // YUV depends on colorspace conversion
    
    CFTypeRef colorAttachments = CVBufferGetAttachment(cvImageBufferRef, kCVImageBufferYCbCrMatrixKey, NULL);
    
#if defined(DEBUG)
    assert(colorAttachments != kCVImageBufferYCbCrMatrix_SMPTE_240M_1995);
#endif // DEBUG
    
    if (colorAttachments == kCVImageBufferYCbCrMatrix_ITU_R_601_4) {
      _preferredConversion = kColorConversion601;
    }
    else {
      _preferredConversion = kColorConversion709;
    }
  }
  
  if (self->textureCacheRef == NULL) {
    // This should not actually happen, but no specific way to deal with an error here
    return;
  }
	
  // Allocate a "texture ref" object that wraps around the existing memory allocated and written
  // by CoreVideo. As far as OpenGL is concerned, this is a new texture, but the memory that
  // backs the texture has already been fully written to at this point. The OpenGL id for the
  // texture changes from one frame to the next and CoreVideo keeps track of the specific
  // buffer used when the frame was decoded.

  CVOpenGLESTextureRef textureRef = NULL;
  
  CVOpenGLESTextureRef textureUVRef = NULL;
  
  CVOpenGLESTextureRef textureAlphaRef = NULL;
  
  CVReturn err;
  
  if (renderBGRA) {
    
    glActiveTexture(GL_TEXTURE0);
    
    // The RGB pixel values are stored in a BGRX frame
    
    err = CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                                       self->textureCacheRef,
                                                       cvImageBufferRef,
                                                       (CFDictionaryRef) NULL,
                                                       GL_TEXTURE_2D, // not GL_RENDERBUFFER
                                                       GL_RGBA,
                                                       (GLsizei)frameWidth,
                                                       (GLsizei)frameHeight,
                                                       GL_BGRA,
                                                       GL_UNSIGNED_BYTE,
                                                       0,
                                                       &textureRef);
    
    if (textureRef == NULL) {
      NSLog(@"CVOpenGLESTextureCacheCreateTextureFromImage failed and returned NULL (error: %d)", err);
      return;
    }
    
    if (err) {
      if (textureRef) {
        CFRelease(textureRef);
      }
      NSLog(@"CVOpenGLESTextureCacheCreateTextureFromImage failed (error: %d)", err);
      return;
    }
    
    // Bind texture, OpenGL already knows about the texture but it could have been created
    // in another thread and it has to be bound in this context in order to sync the
    // texture for use with this OpenGL context. The next logging line can be uncommented
    // to see the actual texture id used internally by OpenGL.
    
    //NSLog(@"bind OpenGL texture %d", CVOpenGLESTextureGetName(textureRef));
    
    glBindTexture(CVOpenGLESTextureGetTarget(textureRef), CVOpenGLESTextureGetName(textureRef));
    
    // Set texture parameters
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    
    // Second BGRA frame contains alpha channel encoded as Y component
    // where the BGR values are all identical.
    
    glActiveTexture(GL_TEXTURE1);

    err = CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                                       self->textureCacheRef,
                                                       cvAlphaImageBufferRef,
                                                       (CFDictionaryRef) NULL,
                                                       GL_TEXTURE_2D, // not GL_RENDERBUFFER
                                                       GL_RGBA,
                                                       (GLsizei)frameWidth,
                                                       (GLsizei)frameHeight,
                                                       GL_BGRA,
                                                       GL_UNSIGNED_BYTE,
                                                       0,
                                                       &textureAlphaRef);
    
    if (textureAlphaRef == NULL) {
      NSLog(@"CVOpenGLESTextureCacheCreateTextureFromImage failed and returned NULL (error: %d)", err);
      return;
    }
    
    if (err) {
      if (textureAlphaRef) {
        CFRelease(textureAlphaRef);
      }
      NSLog(@"CVOpenGLESTextureCacheCreateTextureFromImage failed (error: %d)", err);
      return;
    }
    
    // Bind texture, OpenGL already knows about the texture but it could have been created
    // in another thread and it has to be bound in this context in order to sync the
    // texture for use with this OpenGL context. The next logging line can be uncommented
    // to see the actual texture id used internally by OpenGL.
    
    //NSLog(@"bind OpenGL texture %d", CVOpenGLESTextureGetName(textureAlphaRef));
    
    glBindTexture(CVOpenGLESTextureGetTarget(textureAlphaRef), CVOpenGLESTextureGetName(textureAlphaRef));
    
    // Set texture parameters
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    
  } else {
    // Y is an 8 bit texture
    
    glActiveTexture(GL_TEXTURE0);
    
    err = CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                                       self->textureCacheRef,
                                                       cvImageBufferRef,
                                                       (CFDictionaryRef) NULL,
                                                       GL_TEXTURE_2D, // not GL_RENDERBUFFER
                                                       GL_RED_EXT,
                                                       (GLsizei)frameWidth,
                                                       (GLsizei)frameHeight,
                                                       GL_RED_EXT,
                                                       GL_UNSIGNED_BYTE,
                                                       0,
                                                       &textureRef);
    
    if (textureRef == NULL) {
      NSLog(@"CVOpenGLESTextureCacheCreateTextureFromImage failed and returned NULL (error: %d)", err);
      return;
    }
    
    if (err) {
      if (textureRef) {
        CFRelease(textureRef);
      }
      NSLog(@"CVOpenGLESTextureCacheCreateTextureFromImage failed (error: %d)", err);
      return;
    }
    
    //NSLog(@"bind OpenGL Y texture %d", CVOpenGLESTextureGetName(textureRef));
    
    glBindTexture(CVOpenGLESTextureGetTarget(textureRef), CVOpenGLESTextureGetName(textureRef));
    
    // Set texture parameters
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    
    // UV is an interleaved texture that is upsampled to the Y size in OpenGL
    
    glActiveTexture(GL_TEXTURE1);
    
    err = CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                                       self->textureCacheRef,
                                                       cvImageBufferRef,
                                                       (CFDictionaryRef) NULL,
                                                       GL_TEXTURE_2D, // not GL_RENDERBUFFER
                                                       GL_RG_EXT,
                                                       (GLsizei)frameWidth/2,
                                                       (GLsizei)frameHeight/2,
                                                       GL_RG_EXT,
                                                       GL_UNSIGNED_BYTE,
                                                       1,
                                                       &textureUVRef);
    
    if (textureUVRef == NULL) {
      NSLog(@"CVOpenGLESTextureCacheCreateTextureFromImage failed and returned NULL (error: %d)", err);
      return;
    }
    
    if (err) {
      if (textureUVRef) {
        CFRelease(textureUVRef);
      }
      NSLog(@"CVOpenGLESTextureCacheCreateTextureFromImage failed (error: %d)", err);
      return;
    }
    
    //NSLog(@"bind OpenGL Y texture %d", CVOpenGLESTextureGetName(textureUVRef));
    
    glBindTexture(CVOpenGLESTextureGetTarget(textureUVRef), CVOpenGLESTextureGetName(textureUVRef));
    
    // Set texture parameters
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    
    // Alpha texture is another Y component buffer that is the full screen size
    
    glActiveTexture(GL_TEXTURE2);
    
    err = CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                                       self->textureCacheRef,
                                                       cvAlphaImageBufferRef,
                                                       (CFDictionaryRef) NULL,
                                                       GL_TEXTURE_2D, // not GL_RENDERBUFFER
                                                       GL_RED_EXT,
                                                       (GLsizei)frameWidth,
                                                       (GLsizei)frameHeight,
                                                       GL_RED_EXT,
                                                       GL_UNSIGNED_BYTE,
                                                       0,
                                                       &textureAlphaRef);
    
    if (textureAlphaRef == NULL) {
      NSLog(@"CVOpenGLESTextureCacheCreateTextureFromImage failed and returned NULL (error: %d)", err);
      return;
    }
    
    if (err) {
      if (textureAlphaRef) {
        CFRelease(textureAlphaRef);
      }
      NSLog(@"CVOpenGLESTextureCacheCreateTextureFromImage failed (error: %d)", err);
      return;
    }
    
    //NSLog(@"bind OpenGL Y texture %d", CVOpenGLESTextureGetName(textureRef));
    
    glBindTexture(CVOpenGLESTextureGetTarget(textureAlphaRef), CVOpenGLESTextureGetName(textureAlphaRef));
    
    // Set texture parameters
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
  }
  
  static const GLfloat squareVertices[] = {
    -1.0f, -1.0f,
    1.0f, -1.0f,
    -1.0f,  1.0f,
    1.0f,  1.0f,
  };
  
	// The texture vertices are set up such that we flip the texture vertically.
	// This is so that our top left origin buffers match OpenGL's bottom left texture coordinate system.
	CGRect textureSamplingRect = [self textureSamplingRectForCroppingTextureWithAspectRatio:CGSizeMake(frameWidth, frameHeight) toAspectRatio:self.bounds.size];
	GLfloat textureVertices[] = {
		CGRectGetMinX(textureSamplingRect), CGRectGetMaxY(textureSamplingRect),
		CGRectGetMaxX(textureSamplingRect), CGRectGetMaxY(textureSamplingRect),
		CGRectGetMinX(textureSamplingRect), CGRectGetMinY(textureSamplingRect),
		CGRectGetMaxX(textureSamplingRect), CGRectGetMinY(textureSamplingRect),
	};
	
  // Draw the texture on the screen with OpenGL ES 2
  [self renderWithSquareVertices:squareVertices textureVertices:textureVertices];
  
  // Flush the CVOpenGLESTexture cache and release the texture.
  // This logic does not deallocate the "texture", it just deallocates the
  // CoreVideo object wrapper for the texture.
  
  CVOpenGLESTextureCacheFlush(self->textureCacheRef, 0);
  CFRelease(textureRef);
  
  if (textureUVRef) {
    CFRelease(textureUVRef);
  }
  
  if (textureAlphaRef) {
    CFRelease(textureAlphaRef);
  }
  
  // If capture dir is defined then grab the rendered state of the OpenGL
  // buffer and write that to a PNG. This logic is tricky because the
  // capture must be in terms of the rendered to size and it must
  // capture the state before the FBO is rendered over the existing
  // framebuffer to get the pre mixed state.

#if defined(DEBUG)
  
  if (self.captureDir != nil) @autoreleasepool {
    glFlush();
    glFinish();

    CGRect mainFrame = self.bounds;
    
    int frameX = 0;
    int frameY = 0;
    
    int frameWidth = mainFrame.size.width * self.contentScaleFactor;
    int frameHeight = mainFrame.size.height * self.contentScaleFactor;
    
    CGFrameBuffer *backwardFrameBuffer = [CGFrameBuffer cGFrameBufferWithBppDimensions:32 width:frameWidth height:frameHeight];
    GLubyte *flatPixels = (GLubyte*)backwardFrameBuffer.pixels;
    glReadPixels(frameX, frameY, frameWidth, frameHeight, GL_BGRA, GL_UNSIGNED_BYTE, flatPixels);
    
    CGFrameBuffer *forwardsFrameBuffer = [CGFrameBuffer cGFrameBufferWithBppDimensions:32 width:frameWidth height:frameHeight];
    GLubyte *flatPixels2 = (GLubyte*)forwardsFrameBuffer.pixels;

    for(int y1 = 0; y1 < frameHeight; y1++) {
      for(int x1 = 0; x1 < frameWidth * 4; x1++) {
        flatPixels2[(frameHeight - 1 - y1) * frameWidth * 4 + x1] = flatPixels[y1 * 4 * frameWidth + x1];
      }
    }
    
    NSString *tmpDir = self.captureDir;
    if (![[NSFileManager defaultManager] fileExistsAtPath:self.captureDir]) {
      [[NSFileManager defaultManager] createDirectoryAtPath:tmpDir
                                withIntermediateDirectories:FALSE attributes:nil error:nil];
    }
    
    NSString *filename = [NSString stringWithFormat:@"Frame%d.png", (int)(self.currentFrame - 2)/2];    
    NSString *tmpPNGPath = [tmpDir stringByAppendingPathComponent:filename];
    
    CGImageRef imgRef = [forwardsFrameBuffer createCGImageRef];
    NSAssert(imgRef, @"CGImageRef returned by createCGImageRef is NULL");
    
    // Render
    
    UIImage *uiImage = [UIImage imageWithCGImage:imgRef];
    CGImageRelease(imgRef);
    
    NSData *data = [NSData dataWithData:UIImagePNGRepresentation(uiImage)];
    [data writeToFile:tmpPNGPath atomically:YES];
    NSLog(@"wrote %@ at %d x %d", tmpPNGPath, (int)uiImage.size.width, (int)uiImage.size.height);
  }
  
#endif // DEBUG
}

// drawRect from UIView, this method is invoked because this view extends GLKView

- (void)drawRect:(CGRect)rect
{
  //NSLog(@"drawRect %dx%d", (int)rect.size.width, (int)rect.size.height);
  //NSLog(@"drawable width x height %dx%d", (int)self.drawableWidth, (int)self.drawableHeight);
  
  if (didSetupOpenGLMembers == FALSE) {
    didSetupOpenGLMembers = TRUE;
    BOOL worked = [self setupOpenGLMembers];
    NSAssert(worked, @"setupOpenGLMembers failed");
  }
  
  [self displayFrame];
}

#pragma mark -  OpenGL ES 2 shader compilation

// Compile OpenGL "shader" program, these shaders just pass the data through
// without doing anything special.

- (BOOL)compileShaders
{
  GLuint vertShader, fragShader;
  
  // Create shader program.
  passThroughProgram = glCreateProgram();

  if (passThroughProgram == 0) {
    NSLog(@"Failed to create vertex/fragment shader program");
    return FALSE;
  }
  
  const GLchar *vert;
  const GLchar *frag;
  
  if (renderBGRA) {
    vert = vertShaderBGRACstr;
    frag = fragShaderBGRACstr;
  } else {
    vert = vertShaderYUVCstr;
    frag = fragShaderYUVCstr;
  }
  
  // Create and compile vertex shader.
  NSString *vertShaderStr = [NSString stringWithUTF8String:vert];
  if (![self compileShader:&vertShader type:GL_VERTEX_SHADER source:vertShaderStr]) {
    NSLog(@"Failed to compile vertex shader");
    return FALSE;
  }
  
  // Create and compile fragment shader.
  NSString *fragShaderStr = [NSString stringWithUTF8String:frag];
  if (![self compileShader:&fragShader type:GL_FRAGMENT_SHADER source:fragShaderStr]) {
    NSLog(@"Failed to compile fragment shader");
    return FALSE;
  }
  
  // Attach vertex shader to program.
  glAttachShader(passThroughProgram, vertShader);
  
  // Attach fragment shader to program.
  glAttachShader(passThroughProgram, fragShader);
  
  // Bind attribute offset to name.
  // This needs to be done prior to linking.
  glBindAttribLocation(passThroughProgram, ATTRIB_VERTEX, "position");
  glBindAttribLocation(passThroughProgram, ATTRIB_TEXTUREPOSITON, "textureCoordinate");
  
  // Link program.
  if (![self linkProgram:passThroughProgram]) {
    NSLog(@"Failed to link program: %d", passThroughProgram);
    
    if (vertShader) {
      glDeleteShader(vertShader);
      vertShader = 0;
    }
    if (fragShader) {
      glDeleteShader(fragShader);
      fragShader = 0;
    }
    if (passThroughProgram) {
      glDeleteProgram(passThroughProgram);
      passThroughProgram = 0;
    }
    
    return NO;
  }
  
  // Link textures to named textures variables in the shader program
	//uniforms[UNIFORM_INDEXES] = glGetUniformLocation(passThroughProgram, "indexes");
  
  if (renderBGRA) {
    uniformsBGRA[UNIFORM_BGRA_BGR] = glGetUniformLocation(passThroughProgram, "videoframe");
    uniformsBGRA[UNIFORM_BGRA_A] = glGetUniformLocation(passThroughProgram, "alphaframe");
  } else {
    uniforms[UNIFORM_Y] = glGetUniformLocation(passThroughProgram, "SamplerY");
    uniforms[UNIFORM_UV] = glGetUniformLocation(passThroughProgram, "SamplerUV");
    uniforms[UNIFORM_A] = glGetUniformLocation(passThroughProgram, "SamplerA");
    uniforms[UNIFORM_COLOR_CONVERSION_MATRIX] = glGetUniformLocation(passThroughProgram, "colorConversionMatrix");
  }
  
  // Release vertex and fragment shaders.
  if (vertShader) {
    glDetachShader(passThroughProgram, vertShader);
    glDeleteShader(vertShader);
  }
  if (fragShader) {
    glDetachShader(passThroughProgram, fragShader);
    glDeleteShader(fragShader);
  }
  
  return YES;
}

- (BOOL)compileShader:(GLuint*)shader
                 type:(GLenum)type
                 source:(NSString*)sourceStr
{
  GLint status;
  const GLchar *source;
  
  source = [sourceStr UTF8String];
  if (!source) {
    NSLog(@"Failed to load vertex shader");
    return NO;
  }
  
  *shader = glCreateShader(type);
  glShaderSource(*shader, 1, &source, NULL);
  glCompileShader(*shader);
  
#if defined(DEBUG)
  GLint logLength;
  glGetShaderiv(*shader, GL_INFO_LOG_LENGTH, &logLength);
  if (logLength > 0) {
    GLchar *log = (GLchar *)malloc(logLength);
    glGetShaderInfoLog(*shader, logLength, &logLength, log);
    NSLog(@"Shader compile log:\n%s", log);
    free(log);
  }
#endif
  
  glGetShaderiv(*shader, GL_COMPILE_STATUS, &status);
  if (status == 0) {
    glDeleteShader(*shader);
    return NO;
  }
  
  return YES;
}

- (BOOL)linkProgram:(GLuint)prog
{
  GLint status;
  glLinkProgram(prog);
  
#if defined(DEBUG)
  GLint logLength;
  glGetProgramiv(prog, GL_INFO_LOG_LENGTH, &logLength);
  if (logLength > 0) {
    GLchar *log = (GLchar *)malloc(logLength);
    glGetProgramInfoLog(prog, logLength, &logLength, log);
    NSLog(@"Program link log:\n%s", log);
    free(log);
  }
#endif
  
  glGetProgramiv(prog, GL_LINK_STATUS, &status);
  if (status == 0) {
    return NO;
  }
  
  return YES;
}

- (BOOL)validateProgram:(GLuint)prog
{
  GLint logLength, status;
  
  glValidateProgram(prog);
  glGetProgramiv(prog, GL_INFO_LOG_LENGTH, &logLength);
  if (logLength > 0) {
    GLchar *log = (GLchar *)malloc(logLength);
    glGetProgramInfoLog(prog, logLength, &logLength, log);
    NSLog(@"Program validate log:\n%s", log);
    free(log);
  }
  
  glGetProgramiv(prog, GL_VALIDATE_STATUS, &status);
  if (status == 0) {
    return NO;
  }
  
  return YES;
}

#pragma mark -  Animation cycle

// Map a time offset to a number of frames at the end of the next frame interval
//
// Assume 2 FPS so that frame duration is 0.5s

// 0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.75 0.8 0.9 1.0
//   1   1   1   1   1   1   1   1    1   2   2   2

+ (uint32_t) timeIntervalToFrameOffset:(CFTimeInterval)elapsed
                                   fps:(CFTimeInterval)fps
{
  const BOOL debug = FALSE;

  uint32_t frameOffset;

  float frameF = elapsed * fps;
  
  if (debug) {
    NSLog(@"frameF %0.5f", frameF);
  }
  
  frameOffset = (uint32_t)round(frameF);
  
  if (debug) {
    NSLog(@"elapsed time %0.3f with frameDuration %0.3f -> frame number %d", elapsed, 1.0/fps, frameOffset);
  }
  
  if (frameOffset == 0) {
    frameOffset = 1;
  }
 
  if (debug) {
    NSLog(@"return frame offset %d", frameOffset);
  }
  
  return frameOffset;
}

// Create GCD repeating timer which is staggered so that decoding of the next
// frame starts right after the display interval.

- (void) makeDispatchTimer:(double)inInterval
                     queue:(dispatch_queue_t)queue
                     block:(dispatch_block_t)block
{
#if defined(DEBUG)
  NSAssert(queue, @"queue");
#endif // DEBUG
  
  dispatch_source_t timer = dispatch_source_create(DISPATCH_SOURCE_TYPE_TIMER, 0, 0, queue);

  self->dispatchFirstTimeInterval = 0.0;
  
  if (timer)
  {
    double firstDelayInterval = (1.0/100.0);
    
    dispatch_time_t start = dispatch_time(DISPATCH_TIME_NOW, firstDelayInterval * NSEC_PER_SEC);
    uint64_t interval = inInterval * NSEC_PER_SEC;
    uint64_t leeway = (1ull * NSEC_PER_SEC) / 10;
    
    dispatch_source_set_timer(timer, start, interval, leeway);
    dispatch_source_set_event_handler(timer, block);
    dispatch_resume(timer);
  }
  
  self->_dispatchTimer = timer;
  
  return;
}

- (void) cancelDispatchTimer
{
  if (self->_dispatchTimer) {
    dispatch_source_cancel(self->_dispatchTimer);
#if OS_OBJECT_HAVE_OBJC_SUPPORT == 0
    // Remove this if you are on a Deployment Target of iOS6 or OSX 10.8 and above
    dispatch_release(self->_dispatchTimer);
#endif // OS_OBJECT_HAVE_OBJC_SUPPORT
    self->_dispatchTimer = NULL;
  }
}

// Invoked on GCD queue at a repeating interval such that the decoding will be finished *AFTER*
// the next display interval.

- (void) dispatchTimerFired
{
  const BOOL debugPrintTimes = FALSE;
  
#if defined(DEBUG)
  assert([NSThread currentThread] != [NSThread mainThread]);
#endif // DEBUG
  
  if (self.waitingForDecodeToStart) {
    self.waitingForDecodeToStart = 0;
  }
  
  // The first and second timer invocations can be a little odd sometimes.
  // The spacing between timer callbacks should be about (1.0/30) = 0.03
  // but sometimes the second invocation is delivered right after the first
  // one at a delta like 0.01. This would push the decoder one ahead if
  // not ignored.
  
  CFTimeInterval nowTime = CACurrentMediaTime();
  
  if (self->dispatchFirstTimeInterval == 0.0) {
    self->dispatchFirstTimeInterval = nowTime;
    self->dispatchPrevTimeInterval = 0.0;
  }
  
  CFTimeInterval startTime = self->dispatchFirstTimeInterval;

  CFTimeInterval prev = self->dispatchPrevTimeInterval;
  if (prev == 0.0) {
    prev = nowTime;
  }
  
  CFTimeInterval deltaLastTime = nowTime - prev;
  CFTimeInterval elapsedTime = (nowTime - startTime);
  
  if (debugPrintTimes) {
    NSLog(@"dispatchTimerFired : now %0.3f : start %0.3f : elapsed %0.3f : since prev %0.3f", nowTime, startTime, elapsedTime, deltaLastTime);
  }
  
  self->dispatchPrevTimeInterval = nowTime;
  
  const CFTimeInterval halfExpectedInterval = (1.0/30) / 2; // About 60 FPS
  const CFTimeInterval tooSmallMaxInterval = halfExpectedInterval + (halfExpectedInterval / 8);
  
  if (m_currentFrame == 4 && elapsedTime <= tooSmallMaxInterval) {
    // Interval too small
    
    if (debugPrintTimes) {
      NSLog(@"second callback too soon");
    }
    
    return;
  }
  
//  if ((prev != 0) && ((nowTime - startTime) > 10.0)) {
//    [self stopAnimator];
//    return;
//  }
  
  BOOL done = [self dispatchDecodeFrame];

  if (done) {
    [self cancelDispatchTimer];
    
    dispatch_sync(dispatch_get_main_queue(), ^{
      [self stopAnimator];
      
      [[NSNotificationCenter defaultCenter] postNotificationName:AVAnimatorDidStopNotification object:self];
    });
  }
  
  return;
}

// This method implements the tricky thread handoff logic that determines
// the next frame to display and decodes that frame. This logic has to check
// in with state from the main thread.
//
// Returns TRUE when all frames have been decoded.

- (BOOL) dispatchDecodeFrame
{
  const BOOL debugDecodeFrames = FALSE;
  
  __block int currentFrame = self.currentFrame; // atomic

  if (debugDecodeFrames) {
    NSLog(@"dispatchDecodeFrame invoked with currentFrame %d (aka %d in combined frames)", currentFrame, currentFrame/2);
  }
  
  __block int aheadButReallyDone = 0;
  
  int maxFrame = self.dispatchMaxFrame;
  
  if (currentFrame >= maxFrame) {
    if (debugDecodeFrames) {
      NSLog(@"dispatchDecodeFrame : done processing frames at %d", currentFrame);
    }
    
    return TRUE;
  }
  
#if __has_feature(objc_arc)
  __weak
#else
#endif // objc_arc
  AVAnimatorH264AlphaPlayer *weakSelf = self;
  
  AVFrame* rgbFrame;
  AVFrame* alphaFrame;
  
  if (debugDecodeFrames) {
    NSLog(@"advanceToFrame %d of %d (aka %d in combined frames)", currentFrame, maxFrame, currentFrame/2);
  }
  
  CFTimeInterval beforeTime = CACurrentMediaTime();
  
  if ((0)) {
    NSLog(@"decode start time       %0.5f", beforeTime);
  }
  
  int nextFrame = [self.class loadFramesInBackgroundThread:currentFrame
                                     frameDecoder:self.frameDecoder
                                         rgbFrame:&rgbFrame
                                       alphaFrame:&alphaFrame];
  
  CFTimeInterval afterTime = CACurrentMediaTime();
  CFTimeInterval delta = afterTime - beforeTime;
  
  if ((0)) {
    NSLog(@"decode after time       %0.5f", afterTime);
  }

  if ((0)) {
    NSLog(@"decode delta %0.3f", delta);
  }
  
  dispatch_sync(dispatch_get_main_queue(), ^{
#if defined(DEBUG)
    NSAssert(rgbFrame, @"rgbFrame");
    NSAssert(alphaFrame, @"alphaFrame");
#endif // DEBUG
    
    __strong AVAnimatorH264AlphaPlayer *strongSelf = weakSelf;
    
    if (strongSelf.state != ANIMATING) {
      // stopAnimator invoked after startAnimator
      currentFrame = maxFrame;
    } else {
      if (debugDecodeFrames) {
        NSLog(@"deliver to main time      %0.5f", CACurrentMediaTime());
      }
      
      [strongSelf deliverRGBAndAlphaFrames:nextFrame rgbFrame:rgbFrame alphaFrame:alphaFrame];
      
      // Get the frame number for the next frame in terms of the combined frames
      
#if defined(DEBUG)
      assert((nextFrame % 2) == 0);
#endif // DEBUG
      int nextCombinedFrameToDecode = nextFrame >> 1; // div 2
      
      if (debugDecodeFrames) {
        NSLog(@"decoder nextCombinedFrameToDecode %d as compared to nextDecodeFrame %d", nextCombinedFrameToDecode, nextDecodeFrame);
      }
      
      if (nextCombinedFrameToDecode < nextDecodeFrame) {
        if (debugDecodeFrames) {
          NSLog(@"decoder current combined frame is behind by %d combined frames", nextDecodeFrame - nextCombinedFrameToDecode);
        }
        
        int lastDecodedFrame = currentFrame;
        currentFrame = nextDecodeFrame * 2;
        
        // Skip ahead, but don't skip over the last frame in the interval
        
        if (currentFrame >= maxFrame) {
          int actualLastFrame = maxFrame - 2;
          if (lastDecodedFrame == actualLastFrame) {
            // When the previously decoded frame was the last frame then
            // decode cycle is completed.
            
            aheadButReallyDone = 1;
          } else {
            // When skipping ahead, skip to the last frame in the animation cycle.
            
            currentFrame = actualLastFrame;
          }
        }
      }
      else {
        currentFrame = nextFrame;
      }
    }
  });
  
  if (aheadButReallyDone) {
    if (debugDecodeFrames) {
      NSLog(@"dispatchDecodeFrame : done processing frames at %d", currentFrame);
    }
    
    return TRUE;
  } else {
    // Write currentFrame back to self.currentFrame
    self.currentFrame = currentFrame;
    
    if (debugDecodeFrames) {
      NSLog(@"dispatchDecodeFrame : NOT done processing frames at %d", currentFrame);
    }
    return FALSE;
  }
}

// Kick off repeating GCD timer invocation

- (void) startDispatchRender {
#if defined(DEBUG)
  assert([NSThread currentThread] == [NSThread mainThread]);
#endif // DEBUG
  
#if __has_feature(objc_arc)
  __weak
#else
#endif // objc_arc
  AVAnimatorH264AlphaPlayer *weakSelf = self;
  
  // Note that the dispatch time depends on the display framerate
  // so that the decode event is always just after the frame display
  
  const CFTimeInterval kFrameDuration = 1.0 / 30.0; // 30 FPS display refresh rate
  
  [self makeDispatchTimer:kFrameDuration
                    queue:self->_highPrioQueue
                    block:^{
                      [weakSelf dispatchTimerFired];
                    }];
  
  // dispatchMaxFrame should have been set at asset load time
#if defined(DEBUG)
  assert(self.dispatchMaxFrame > 0);
#endif // DEBUG
}

// This display link callback is invoked at fixed interval while animation is running.

- (void) displayLinkCallback:(CADisplayLink*)displayLink {
  const BOOL debugDisplayLink = FALSE;
  const BOOL debugDisplayRedrawn = FALSE;
  
  // Note that frame duration is 1/60 but the interval is 2 so 1/30 a second refresh rate
  
  if (debugDisplayLink) {
    CFTimeInterval effectiveDuration = displayLink.duration * displayLink.frameInterval;
    NSLog(@"displayLinkCallback with timestamp %0.4f and frame duration %0.4f (interval %0.4f)", displayLink.timestamp, effectiveDuration, displayLink.duration);
  }
  
  // Actual framerate of the video, note that the calculated framerate might
  // be slightly different than the screen refresh rate.
  
  const CFTimeInterval kFramesPerSecond = 29.97;
  const CFTimeInterval kFrameDuration = 1.0 / kFramesPerSecond;
  
  // Note that first image can be visible for 2 cycles since the first
  // callback is invoked on a screen sync and then decoding starts
  // after that.
  
  if (firstTimeInterval == 0) {
    firstTimeInterval = displayLink.timestamp;
    [self startDispatchRender];
    
    // Do not calculate frame offset or redraw on first invocation
    
    return;
  }
  
  if (nextDecodeFrame == 0 && self.waitingForDecodeToStart) {
    // If the first call to dispatchTimerFired has not happened yet then
    // simply reset the firstTimeInterval and continue to wait for
    // a sync time between the display callback and decode thread.
    
    firstTimeInterval = displayLink.timestamp;
    
    if (debugDisplayLink) {
      NSLog(@"waiting on self.waitingForDecodeToStart");
    }

    return;
  }

  CFTimeInterval elapsed = (displayLink.timestamp - firstTimeInterval);
  
  if (debugDisplayLink) {
    NSLog(@"elapsed %0.3f", elapsed);
  }

  int prevNextDecodeFrame = nextDecodeFrame;
  
  if (debugDisplayLink) {
    NSLog(@"previous nextDecodeFrame %d", prevNextDecodeFrame);
  }
  
  int displayLinkFrameOffset;
  
  displayLinkFrameOffset = [self.class timeIntervalToFrameOffset:elapsed fps:kFramesPerSecond];
  
  // Calculate delta to next display time
  
  CFTimeInterval nextDisplayOffset = displayLinkFrameOffset * kFrameDuration;
  
  if (debugDisplayLink) {
    NSLog(@"nextDisplayOffset %0.3f for frame number %d", nextDisplayOffset, displayLinkFrameOffset);
  }
  
  if (displayLinkFrameOffset <= prevNextDecodeFrame) {
    // Special case where the same frame offset is returned twice in a row,
    // this is known to happen for frames 0 and 1.
    
    nextDecodeFrame = prevNextDecodeFrame + 1;
    
    if (debugDisplayLink) {
      NSLog(@"incr frame number to %d", nextDecodeFrame);
    }
  } else if (elapsed < nextDisplayOffset) {
    // Rounded frame number down from current time
    // Note that the case frame 1 at T = 0.0 is handled in the else
    nextDisplayOffset = (displayLinkFrameOffset + 1) * kFrameDuration;
    nextDecodeFrame = (displayLinkFrameOffset + 1);
    
    if (debugDisplayLink) {
      NSLog(@"nextDecodeFrame rounded down to %d", nextDecodeFrame);
    }
  } else {
    // Rounded frame number up from current frame
    nextDecodeFrame = displayLinkFrameOffset;
    
    if (debugDisplayLink) {
      NSLog(@"nextDecodeFrame rounded up to %d", nextDecodeFrame);
    }
  }
  
  if (debugDisplayLink && prevNextDecodeFrame == nextDecodeFrame) {
    NSLog(@"repeated decoded frame");
  }
  
  // Each display link invocation will schedule a redraw, the result is that
  // a smooth 30 FPS video rate is maintained.
  
  if (debugDisplayRedrawn) {
  NSLog(@"disp now                %0.5f", displayLink.timestamp);
  NSLog(@"nextDecodeFrame = %d", nextDecodeFrame);
  NSLog(@"called setNeedsDisplay");
  }
  
  [self setNeedsDisplay];
  
//  if (lastDisplayLinkFrameOffset > 10) {
//     NSLog(@"10");
//  }
  
  return;
}

- (void)setupDisplayLink {
#if defined(DEBUG)
  assert([NSThread currentThread] == [NSThread mainThread]);
#endif // DEBUG
  
  CADisplayLink *displayLink = self.displayLink;
  if (displayLink != nil) {
    [displayLink removeFromRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
  }
  displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(displayLinkCallback:)];
  displayLink.frameInterval = 2; // 30 FPS
  // FIXME : NSDefaultRunLoopMode vs common mode?
  [displayLink addToRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
  self.displayLink = displayLink;
  
  firstTimeInterval = 0.0;
  nextDecodeFrame = 0;
}

- (void) startAnimator
{
#if defined(DEBUG)
  assert([NSThread currentThread] == [NSThread mainThread]);
#endif // DEBUG
  
  if (self.rgbFrame == nil || self.alphaFrame == nil) {
    NSAssert(FALSE, @"player must be prepared before startAnimator can be invoked");
  }

  NSAssert(self.state == READY || self.state == STOPPED, @"player must be prepared before startAnimator can be invoked");
  
  self.state = ANIMATING;
  
  __block int currentFrame = self.currentFrame;
  __block int maxFrame = self.dispatchMaxFrame;

#if defined(DEBUG)
  NSAssert(self.dispatchMaxFrame > 0, @"player must be prepared before startAnimator can be invoked");
#endif // DEBUG
  
  if (currentFrame >= maxFrame) {
    // In the case of only 2 frames, stop straight away without kicking off background thread, useful for testing
    self.state = STOPPED;
    return;
  }
  
  [self setupDisplayLink];
  self.displayLink.paused = FALSE;
  
  self.waitingForDecodeToStart = 1;
  
#if defined(DEBUG)
  CFTimeInterval nowTime = CACurrentMediaTime();
  NSLog(@"startAnimator : now %0.3f", nowTime);
#endif // DEBUG
}

- (void) stopAnimator
{
#if defined(DEBUG)
  assert([NSThread currentThread] == [NSThread mainThread]);
#endif // DEBUG
  
  self.rgbFrame = nil;
  self.alphaFrame = nil;
  
  self.displayLink.paused = TRUE;
  
  [self cancelDispatchTimer];
  
  self.state = STOPPED;
}

// Invoke this method to read from the named asset and being loading initial data

- (void) prepareToAnimate
{
#if defined(DEBUG)
  assert([NSThread currentThread] == [NSThread mainThread]);
#endif // DEBUG
  
  self.animatorPrepTimer = [NSTimer timerWithTimeInterval: 1.0/60
                                                   target: self
                                                 selector: @selector(_prepareToAnimateTimer:)
                                                 userInfo: NULL
                                                  repeats: FALSE];
  
  [[NSRunLoop currentRunLoop] addTimer: self.animatorPrepTimer forMode: NSDefaultRunLoopMode];
  
  self.currentFrame = -1;
  
  self.state = PREPPING;
}

// This method delivers the RGB and Alpha frames to the view in the main thread

- (void) deliverRGBAndAlphaFrames:(int)nextFrame
                         rgbFrame:(AVFrame*)rgbFrame
                       alphaFrame:(AVFrame*)alphaFrame
{
  self.rgbFrame = rgbFrame;
  self.alphaFrame = alphaFrame;
  self.currentFrame = nextFrame;

//#if defined(DEBUG)
//  NSLog(@"set H264AlphaPlayer frames for (%d, %d), advance self.currentFrame to %d", self.currentFrame-2, self.currentFrame-1, self.currentFrame);
//#endif // DEBUG
  
#if defined(DEBUG) && !TARGET_IPHONE_SIMULATOR
  const int dumpRGBFrame = 0;
  const int dumpAlphaFrame = 0;
  
//  if ((nextFrame % 100) == 0) {
//    dumpRGBFrame = dumpAlphaFrame = 1;
//  }
  
  if (dumpRGBFrame) {
    // Dump input frame coming directly from CoreVideo
    
    BOOL worked;
    
    AVFrame* rgbFrame = self.rgbFrame;
    
    CVImageBufferRef cvBufferRef = rgbFrame.cvBufferRef;
    
    if (cvBufferRef) {
    
    int width = (int) CVPixelBufferGetWidth(rgbFrame.cvBufferRef);
    int height = (int) CVPixelBufferGetHeight(rgbFrame.cvBufferRef);
    
    CGFrameBuffer *cgFrameBuffer = nil;
    
    worked = [self.frameDecoder renderCVImageBufferRefIntoFramebuffer:cvBufferRef frameBuffer:&cgFrameBuffer];
    
    assert(worked);
    
    NSData *pngData;
    
    pngData = [cgFrameBuffer formatAsPNG];
    
    NSString *tmpDir = NSTemporaryDirectory();
    NSString *filename = [NSString stringWithFormat:@"RGBFrame%d.png", (int)(self.currentFrame - 2)/2];
    NSString *tmpPNGPath = [tmpDir stringByAppendingPathComponent:filename];
    
    [pngData writeToFile:tmpPNGPath atomically:YES];
    
    NSLog(@"wrote %@ at %d x %d", tmpPNGPath, width, height);
      
    }
  }
  
  if (dumpAlphaFrame) {
    // Dump input frame coming directly from CoreVideo
    
    BOOL worked;
    
    AVFrame* alphaFrame = self.alphaFrame;
    
    CVImageBufferRef cvBufferRef = alphaFrame.cvBufferRef;
    
    if (cvBufferRef) {
    
    int width = (int) CVPixelBufferGetWidth(alphaFrame.cvBufferRef);
    int height = (int) CVPixelBufferGetHeight(alphaFrame.cvBufferRef);
    
    CGFrameBuffer *cgFrameBuffer = nil;
    
    worked = [self.frameDecoder renderCVImageBufferRefIntoFramebuffer:cvBufferRef frameBuffer:&cgFrameBuffer];
    
    assert(worked);
    
    NSData *pngData;
    
    pngData = [cgFrameBuffer formatAsPNG];
    
    NSString *tmpDir = NSTemporaryDirectory();
    NSString *filename = [NSString stringWithFormat:@"AlphaFrame%d.png", (int)(self.currentFrame - 2)/2];
    NSString *tmpPNGPath = [tmpDir stringByAppendingPathComponent:filename];
    
    [pngData writeToFile:tmpPNGPath atomically:YES];
    
    NSLog(@"wrote %@ at %d x %d", tmpPNGPath, width, height);
      
    }
  }
#endif // DEBUG
  
  // [self setNeedsDisplay] when not using the display loop.
  // [self display] would be invoked when explicitly drawing.
  
  //[self setNeedsDisplay];
  //[self display];
}

// This timer callback method is invoked after the event loop is up and running in the
// case where prepareToAnimate is invoked as part of the app startup via viewDidLoad.

- (void) _prepareToAnimateTimer:(NSTimer*)timer
{
  if (self->_highPrioQueue == nil) {
    self->_highPrioQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0);
    assert(self->_highPrioQueue);
  }
  
  self.currentFrame = 0;
  self.frameDecoder = [AVAssetFrameDecoder aVAssetFrameDecoder];
  
  __block int currentFrame = self.currentFrame;
  __block Class c = self.class;

#if __has_feature(objc_arc)
  __weak
#else
#endif // objc_arc
  AVAnimatorH264AlphaPlayer *weakSelf = self;
  
  dispatch_async(self->_highPrioQueue, ^{
    // Execute on background thread with blocks API invocation
    
#if __has_feature(objc_arc)
    __strong
#else
#endif // objc_arc
    AVAnimatorH264AlphaPlayer *strongSelf = weakSelf;
    
    AVAssetFrameDecoder *frameDecoder = strongSelf.frameDecoder;
    assert(frameDecoder);
    
    // Configure frame decoder flags
    
    frameDecoder.dropFrames = FALSE;
    
    frameDecoder.produceCoreVideoPixelBuffers = TRUE;
    
    if (renderBGRA) {
    } else {
      frameDecoder.produceYUV420Buffers = TRUE;
    }
    
    // FIXME: deliver AVAnimatorFailedToLoadNotification in fail case
    
    NSAssert(strongSelf.assetFilename, @"assetFilename must be defined when prepareToAnimate is invoked");
    
    NSString *assetFullPath = [AVFileUtil getQualifiedFilenameOrResource:strongSelf.assetFilename];
    
    BOOL worked;
    worked = [frameDecoder openForReading:assetFullPath];
    
    if (worked == FALSE) {
      NSLog(@"error: cannot open RGB+Alpha mixed asset filename \"%@\"", assetFullPath);
      
      // Deliver AVAnimatorFailedToLoadNotification
      
      [[NSNotificationCenter defaultCenter] postNotificationName:AVAnimatorFailedToLoadNotification
                                                          object:strongSelf];
      return;
    }
    
    worked = [frameDecoder allocateDecodeResources];
    
    if (worked == FALSE) {
      NSLog(@"error: cannot allocate RGB+Alpha mixed decode resources for filename \"%@\"", assetFullPath);
      return;
      //    return FALSE;
    }
    
    // Verify that the total number of frames is even since RGB and ALPHA frames must be matched.
    
    int numFrames = (int) frameDecoder.numFrames;
    
    // Set the dispatchMaxFrame field. Note that in some weird cases the
    // Simulator returns a nonsense result with an odd number of frames,
    // so set the max to a specific even number of frames so that the
    // simulator is able to run something.
    
#if TARGET_IPHONE_SIMULATOR
    if ((numFrames % 2) != 0) {
      numFrames--;
    }
#endif // TARGET_IPHONE_SIMULATOR
    
    strongSelf.dispatchMaxFrame = numFrames;
#if defined(DEBUG)
    assert((strongSelf.dispatchMaxFrame % 2) == 0);
#endif // DEBUG
    
    AVFrame* rgbFrame;
    AVFrame* alphaFrame;
    
    int nextFrame = [c loadFramesInBackgroundThread:currentFrame
                                       frameDecoder:frameDecoder
                                           rgbFrame:&rgbFrame
                                         alphaFrame:&alphaFrame];
    
    dispatch_sync(dispatch_get_main_queue(), ^{
#if defined(DEBUG)
      NSAssert(rgbFrame, @"rgbFrame");
      NSAssert(alphaFrame, @"alphaFrame");
#endif // DEBUG
      
#if __has_feature(objc_arc)
      __strong
#else
#endif // objc_arc
      AVAnimatorH264AlphaPlayer *strongSelf = weakSelf;
      
      if (strongSelf.state == STOPPED) {
        // stopAnimator invoked after prepareToAnimate
      } else {
        [strongSelf deliverRGBAndAlphaFrames:nextFrame rgbFrame:rgbFrame alphaFrame:alphaFrame];
        
        [strongSelf setNeedsDisplay];
        
        strongSelf.state = READY;
        
        // Deliver AVAnimatorPreparedToAnimateNotification
        
        [[NSNotificationCenter defaultCenter] postNotificationName:AVAnimatorPreparedToAnimateNotification
                                                            object:strongSelf];
      }
    });
  });
  
  return;
}

+ (int) loadFramesInBackgroundThread:(int)currentFrame
                        frameDecoder:(AVAssetFrameDecoder*)frameDecoder
                            rgbFrame:(AVFrame**)rgbFramePtr
                          alphaFrame:(AVFrame**)alphaFramePtr
{
  AVFrame *rgbFrame;
  AVFrame *alphaFrame;
  
  rgbFrame = [frameDecoder advanceToFrame:currentFrame];
  currentFrame++;
  alphaFrame = [frameDecoder advanceToFrame:currentFrame];
  currentFrame++;

  *rgbFramePtr = rgbFrame;
  *alphaFramePtr = alphaFrame;
  
  return currentFrame;
}
                 
@end

#endif // HAS_AVASSET_READ_COREVIDEO_BUFFER_AS_TEXTURE
