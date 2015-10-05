//
//  AVAnimatorOpenGLView.m
//
//  Created by Moses DeJong on 7/29/13.
//
//  License terms defined in License.txt.

#import "AVAnimatorOpenGLView.h"

#if defined(HAS_AVASSET_READ_COREVIDEO_BUFFER_AS_TEXTURE)

#import <QuartzCore/QuartzCore.h>

#include <OpenGLES/ES2/gl.h>
#include <OpenGLES/ES2/glext.h>

#import "CGFrameBuffer.h"

#import "AVFrameDecoder.h"

#import "AVAnimatorMedia.h"

#import "AVFrame.h"

#import <mach/mach.h>

#if __has_feature(objc_arc)
#else
#import "AutoPropertyRelease.h"
#endif // objc_arc

// private properties declaration for AVAnimatorOpenGLView class
#include "AVAnimatorOpenGLViewPrivate.h"

// private method in Media class
#include "AVAnimatorMediaPrivate.h"

#import <QuartzCore/CAEAGLLayer.h>

// Trivial vertex and fragment shaders

const GLchar *vertShaderCstr =
"attribute vec4 position; attribute mediump vec4 textureCoordinate;"
"varying mediump vec2 coordinate;"
"void main()"
"{"
"	gl_Position = position;"
"	coordinate = textureCoordinate.xy;"
"}";

const GLchar *fragShaderCstr =
"varying highp vec2 coordinate;"
"uniform sampler2D videoframe;"
"void main()"
"{"
"	gl_FragColor = texture2D(videoframe, coordinate);"
"}";

enum {
  ATTRIB_VERTEX,
  ATTRIB_TEXTUREPOSITON,
  NUM_ATTRIBUTES
};

// class declaration for AVAnimatorOpenGLView

@interface AVAnimatorOpenGLView () {
@private
	CGSize m_renderSize;
	AVAnimatorMedia *m_mediaObj;
	AVFrame *m_frameObj;
	BOOL mediaDidLoad;
  
	int renderBufferWidth;
	int renderBufferHeight;
  
  GLuint passThroughProgram;
  
  // A texture cache ref is an opaque type that contains a specific
  // textured cache.
  CVOpenGLESTextureCacheRef textureCacheRef;
  
  BOOL didSetupOpenGLMembers;
}

@end

// class AVAnimatorOpenGLView

@implementation AVAnimatorOpenGLView

// public properties

@synthesize renderSize = m_renderSize;
@synthesize mediaObj = m_mediaObj;
@synthesize frameObj = m_frameObj;

- (void) dealloc {
	// Explicitly release image inside the imageView, the
	// goal here is to get the imageView to drop the
	// ref to the CoreGraphics image and avoid a memory
	// leak. This should not be needed, but it is.
  
	self.frameObj = nil;
  
  // Detach but don't bother making a copy of the final image
  
  if (self.mediaObj) {
    [self.mediaObj detachFromRenderer:self copyFinalFrame:FALSE];
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
  
#if __has_feature(objc_arc)
#else
  [AutoPropertyRelease releaseProperties:self thisClass:AVAnimatorOpenGLView.class];
  [super dealloc];
#endif // objc_arc
}

// static ctor

+ (AVAnimatorOpenGLView*) aVAnimatorOpenGLView
{
  return [AVAnimatorOpenGLView aVAnimatorOpenGLViewWithFrame:[UIScreen mainScreen].applicationFrame];
}

+ (AVAnimatorOpenGLView*) aVAnimatorOpenGLViewWithFrame:(CGRect)viewFrame
{
  AVAnimatorOpenGLView *obj = [[AVAnimatorOpenGLView alloc] initWithFrame:viewFrame];
#if __has_feature(objc_arc)
  return obj;
#else
  return [obj autorelease];
#endif // objc_arc
}

- (id) initWithFrame:(CGRect)frame
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
  
  if ((self = [super initWithFrame:frame])) {
    // Defaults for opacity related properties. We expect the view to be
    // fully opaque since the image renders all the pixels in the view.
    // Unless in 32bpp mode, in that case pixels can be partially transparent.
    
    // Set GLKView.context
    self.context = context;
    
    self.opaque = TRUE;
    self.clearsContextBeforeDrawing = FALSE;
    self.backgroundColor = nil;
    
		// Use 2x scale factor on Retina displays.
		self.contentScaleFactor = [[UIScreen mainScreen] scale];
    
    self.enableSetNeedsDisplay = YES;
    
    self->passThroughProgram = 0;
    self->textureCacheRef = NULL;
    
    self->didSetupOpenGLMembers = FALSE;
  }
  
  return self;
}

- (void) _setOpaqueFromDecoder
{
  NSAssert(self->mediaDidLoad, @"mediaDidLoad must be TRUE");
  NSAssert(self.media, @"media is nil");
  NSAssert(self.media.frameDecoder, @"frameDecoder is nil");
  
  // Query alpha channel support in frame decoder
  
  if ([self.media.frameDecoder hasAlphaChannel]) {
    // This view will blend with other views when pixels are transparent
    // or partially transparent.
    self.opaque = FALSE;
  } else {
    self.opaque = TRUE;
  }  
}

// Invoked with TRUE argument once renderer has been attached to loaded media,
// otherwise FALSE is passed to indicate the renderer could not be attached

- (void) mediaAttached:(BOOL)worked
{
  if (worked) {
    NSAssert(self.media, @"media is nil");
    self->mediaDidLoad = TRUE;
    [self _setOpaqueFromDecoder];
  } else {
    self.mediaObj = nil;
    self->mediaDidLoad = FALSE;
  }
  
	return;
}

//- (void) setOpaque:(BOOL)newValue
//{
//  [super setOpaque:newValue];
//}

//- (BOOL) isOpaque
//{
//  return [super isOpaque];
//}

- (void) attachMedia:(AVAnimatorMedia*)inMedia
{
  AVAnimatorMedia *currentMedia = self.mediaObj;
  
  if (currentMedia == inMedia) {
    // Detaching and the reattaching the same media is a no-op
    return;
  }
  
  if (inMedia == nil) {
    // Detach case, not attaching another media object so copy
    // the last rendered frame.
    
    [currentMedia detachFromRenderer:self copyFinalFrame:TRUE];
    self.mediaObj = nil;
    self->mediaDidLoad = FALSE;
    return;
  }
  
  // Attach case
  
  NSAssert(self.superview, @"AVAnimatorOpenGLView must have been added to a view before media can be attached");
  
  [currentMedia detachFromRenderer:self copyFinalFrame:FALSE];
  self.mediaObj = inMedia;
  self->mediaDidLoad = FALSE;
  [inMedia attachToRenderer:self];
}

// Implement read-only property for use outside this class

- (AVAnimatorMedia*) media
{
  return self->m_mediaObj;
}

// This method is invoked as part of the AVAnimatorMediaRendererProtocol when
// a new frame is generated by the media. Note that we only need to
// set the contents of the CALayer, rendering of the CGImageRef is handled
// by the CALayer class. A duplicate frame would contain the same image data
// as the previous frame and redrawing would be a serious performance issue.

// setter for obj.AVFrame property

- (void) setAVFrame:(AVFrame*)inFrame
{
  if (inFrame == nil) {
    self.frameObj = nil;
    //self.layer.contents = nil;
    // FIXME: NEED METHOD TO CLEAR OPENGL DISPLAY
  } else {
    BOOL opaqueBefore = [super isOpaque];
    
    self.frameObj = inFrame;
    
    //NSLog(@"setAVFrame %@", inFrame);
    
    if (inFrame.isDuplicate) {
      // A duplicate frame does not change the display pixels
    } else {
      [self setNeedsDisplay];
    }
    
    // FIXME: it seems like doing an alpha query over and over again on every frame
    // is a bit of a waste of CPU. Does this app up to any real exe time ?
    
    // Explicitly set the opaque property only when we know the media was loaded.
    // This makes it possible to set the image to a resource image while waiting
    // for the media to load.
    if (self->mediaDidLoad) {
      [self _setOpaqueFromDecoder];
      BOOL opaqueAfter = [super isOpaque];
      NSAssert(opaqueBefore == opaqueAfter, @"opaque");
    }
  }
}

// getter for obj.AVFrame property

- (AVFrame*) AVFrame
{
  return self.frameObj;
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

// Given an AVFrame object, map the pixels into a texture ref

- (void) displayFrame
{
  AVFrame *frame = self.frameObj;
  NSAssert(frame.isDuplicate == FALSE, @"a duplicate frame should not cause a display update");
  
  //NSLog(@"displayFrame %@", frame);
  
  CVImageBufferRef cvImageBufferRef = NULL;

	size_t frameWidth;
	size_t frameHeight;
  
  size_t bytesPerRow;
  
  // This OpenGL player view is only useful when decoding CoreVideo frames, it is possible
  // that a misconfiguration could result in a normal AVFrame that contains a UIImage
  // getting passed to an OpenGL view. Simply assert here in that case instead of attempting
  // to support the non-optimal case since that would just cover up a configuration error
  // anyway.
  
  if (frame.cvBufferRef == NULL) {
    NSAssert(FALSE, @"AVFrame delivered to AVAnimatorOpenGLView does not contain a CoreVideo pixel buffer");
  }
  

  cvImageBufferRef = frame.cvBufferRef;
  
  frameWidth = CVPixelBufferGetWidth(cvImageBufferRef);
  frameHeight = CVPixelBufferGetHeight(cvImageBufferRef);
  bytesPerRow = CVPixelBufferGetBytesPerRow(cvImageBufferRef);
  
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
  
  CVReturn err = CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
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
  // texture for use with this OpenGL context. The next loggin line can be uncommented
  // to see the actual texture id used internally by OpenGL.
  
  //NSLog(@"bind OpenGL texture %d", CVOpenGLESTextureGetName(textureRef));
  
  glBindTexture(CVOpenGLESTextureGetTarget(textureRef), CVOpenGLESTextureGetName(textureRef));
  
  // Set texture parameters
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
	
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
}

// drawRect from UIView, this method is invoked because this view extends GLKView

- (void)drawRect:(CGRect)rect
{
  if (didSetupOpenGLMembers == FALSE) {
    didSetupOpenGLMembers = TRUE;
    BOOL worked = [self setupOpenGLMembers];
    NSAssert(worked, @"setupOpenGLMembers failed");
  }
  
  if (self.frameObj != nil) {
    [self displayFrame];
  } else {
    glClearColor(0.0, 0.0, 0.0, 1.0);
    glClear(GL_COLOR_BUFFER_BIT);
  }
  return;
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
  
  // Create and compile vertex shader.
  NSString *vertShaderStr = [NSString stringWithUTF8String:vertShaderCstr];
  if (![self compileShader:&vertShader type:GL_VERTEX_SHADER source:vertShaderStr]) {
    NSLog(@"Failed to compile vertex shader");
    return FALSE;
  }
  
  // Create and compile fragment shader.
  NSString *fragShaderStr = [NSString stringWithUTF8String:fragShaderCstr];
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

@end

#endif // HAS_AVASSET_READ_COREVIDEO_BUFFER_AS_TEXTURE
