//
//  ColorspaceTests.m
//
//  Created by Moses DeJong on 10/8/12.
//
//  Tests for colorspace conversion logic on the iOS device.
//  By default, iOS assumes that all color information is
//  encoded in the sRGB colorspace, so it is critical that
//  authoring tools on the desktop convert to sRGB instead
//  or retaining the default RGB values. PNG files attached
//  to the project would implicitly be converted to sRGB, so
//  the only problem that would come up in color representation
//  would be if the encoded movie was not actually converting
//  to a sRGB representation.

#import <Foundation/Foundation.h>

#import "RegressionTests.h"

#import "CGFrameBuffer.h"

#import "AVFileUtil.h"

#import "maxvid_file.h"

@interface ColorspaceTests : NSObject {
}
@end

@implementation ColorspaceTests

// Decode pixels from PNG that contains sRGB data. This test will decode sRGB data contained
// in a .png file tagged as sRGB and compare the decoded bytes to a known adler for the
// same data decoded on the desktop. The raw bytes are decoded using the sRGB colorspace
// by default on iOS, so this test is just a basic verification that the default colorspace
// is actually the sRGB colorspace.

+ (void) testDecodePNGInSRGB
{
  NSString *resourceName = nil;
  NSString *resPath = nil;
  BOOL worked;

  resourceName = @"Colorbands_sRGB.png";
  resPath = [AVFileUtil getResourcePath:resourceName];
  
  UIImage *image = [UIImage imageWithContentsOfFile:resPath];
  NSAssert(image, @"image");

  // Render the pixels from the image into a buffer with no colorspace. On
  // iOS, this should default to sRGB colorspace, so there should be no
  // conversion of RGB data values.
  
  int width = image.size.width;
  int height = image.size.height;
  CGFrameBuffer *framebuffer = [CGFrameBuffer cGFrameBufferWithBppDimensions:24 width:width height:height];
  NSAssert(framebuffer, @"framebuffer");
  
  CGImageRef cgImage = image.CGImage;
  CGColorSpaceRef colorspace = CGImageGetColorSpace(cgImage);
  NSAssert(colorspace, @"colorspace");
  
  worked = [framebuffer renderCGImage:cgImage];
  NSAssert(worked, @"worked");
  
  // FIXME: adler should always include padding zero bytes.
  
  // Size should not include extra padding in numBytes
  
  uint32_t expectedNumBytes = 3041280;
  //uint32_t numBytes = framebuffer.numBytes;
  uint32_t numBytes = width * height * sizeof(uint32_t);
  
  NSAssert(numBytes == expectedNumBytes, @"adler");
  
  // Known adler32 for fully decompressed sRGB pixels
  
  /*
   if (TRUE) {
   NSData *data = [NSData dataWithBytes:buffer length:numBytesInBuffer];
   NSString *tmpFile = @"out.data";
   BOOL worked = [data writeToFile:tmpFile atomically:FALSE];
   assert(worked);
   
   // Generate adler32 for this data bufer
   
   uint32_t adler32 = maxvid_adler32(0L, (char*)buffer, numBytesInBuffer);
   
   // Write adler32 as an integer
   NSLog(@"adler32 %d", adler32);
   }
   */
  
  uint32_t expectedAdler = 3784927541;
  uint32_t adler;
  
  adler = maxvid_adler32(0L, (const unsigned char*)framebuffer.pixels, numBytes);
  
  NSAssert(adler == expectedAdler, @"adler");
  
  return;
}

/*

// This approach never really worked, SRGB conversion needs to be done on the desktop
 
// This test case will attempt to explicitly load a sRGB colorspace and set the
// colospace for a frame buffer before rendering into it. This test basically
// checks to see if the emitted sRGB pixels are exactly the same as the
// input sRGB pixels defined as being in the default colorspace.

+ (void) testDecodePNGInExplicitSRGB
{
  NSString *resourceName = nil;
  NSString *resPath = nil;
  BOOL worked;
  
  resourceName = @"Colorbands_sRGB.png";
  resPath = [AVFileUtil getResourcePath:resourceName];
  
  UIImage *image = [UIImage imageWithContentsOfFile:resPath];
  NSAssert(image, @"image");
  
  // Render the pixels from the image into a buffer with no colorspace. On
  // iOS, this should default to sRGB colorspace, so there should be no
  // conversion of RGB data values.
  
  int width = image.size.width;
  int height = image.size.height;
  CGFrameBuffer *framebuffer = [CGFrameBuffer cGFrameBufferWithBppDimensions:24 width:width height:height];
  NSAssert(framebuffer, @"framebuffer");
  
  CGImageRef cgImage = image.CGImage;
  CGColorSpaceRef colorspace = CGImageGetColorSpace(cgImage);
  NSAssert(colorspace, @"colorspace");
  
  // Set colorspace from icc profile attached to the debug project
  
  {
    // http://www.pupuweb.com/blog/wwdc-2012-session-523-practices-color-management-ken-greenebaum-luke-wallis/
    
    CGColorSpaceRef colorSpace;
    
    // FIXME: remove icc profile from project file and this test case.
    NSString *iccProfilePath = [[NSBundle mainBundle] pathForResource:@"sRGB Profile" ofType:@"icc"];
    NSAssert(iccProfilePath, @"Cannot find \"sRGB Profile.icc\" in app resources");
    
    CGDataProviderRef iccProfile = CGDataProviderCreateWithFilename([iccProfilePath UTF8String]);
    NSAssert(iccProfile, @"Cannot load \"sRGB Profile.icc\" from app resources");
    
    const CGFloat range[] = {0.0f, 1.0f, 0.0f, 1.0f, 1.0f};
    
    CGColorSpaceRef alternate = CGColorSpaceCreateDeviceRGB();
    colorSpace = CGColorSpaceCreateICCBased(3, range, iccProfile, alternate);
    
    NSAssert(colorSpace, @"Cannot create sRGB profile from profile data");
    
    CGColorSpaceRelease(alternate);
    
    framebuffer.colorspace = colorSpace;
    
    CGColorSpaceRelease(colorSpace);
    
    CGDataProviderRelease(iccProfile);
  }
  
  worked = [framebuffer renderCGImage:cgImage];
  NSAssert(worked, @"worked");
  
  // Size should not include extra padding in numBytes
  
  uint32_t expectedNumBytes = 3041280;
  //uint32_t numBytes = framebuffer.numBytes;
  uint32_t numBytes = width * height * sizeof(uint32_t);
  
  NSAssert(numBytes == expectedNumBytes, @"adler");
  
  // Known adler32 for fully decompressed sRGB pixels
  
   if (TRUE) {
   NSData *data = [NSData dataWithBytes:buffer length:numBytesInBuffer];
   NSString *tmpFile = @"out.data";
   BOOL worked = [data writeToFile:tmpFile atomically:FALSE];
   assert(worked);
   
   // Generate adler32 for this data bufer
   
   uint32_t adler32 = maxvid_adler32(0L, (char*)buffer, numBytesInBuffer);
   
   // Write adler32 as an integer
   NSLog(@"adler32 %d", adler32);
   }
  
  uint32_t expectedAdler = 3784927541;
  uint32_t adler;
  
  adler = maxvid_adler32(0L, (const unsigned char*)framebuffer.pixels, numBytes);
  
  NSAssert(adler == expectedAdler, @"adler");
  
  return;
}

 */

@end
