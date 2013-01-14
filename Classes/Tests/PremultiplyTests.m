//
//  PremultiplyTests.m
//
//  Created by Moses DeJong on 1/3/13.
//
//  Tests related to pixel premultiply and unpremultiply
//  operations.

#import <Foundation/Foundation.h>

#import "RegressionTests.h"

#import "CGFrameBuffer.h"

#import "AVFileUtil.h"

#import "movdata.h"

@interface PremultiplyTests : NSObject {
}
@end

@implementation PremultiplyTests

// Util to dump PNG to filesystem

+ (void) writePNG:(NSString*)filename
       uiImageRef:(UIImage*)uiImageRef
{
  NSString *tmpDir = NSTemporaryDirectory();
  NSString *tmpPNGPath = [tmpDir stringByAppendingFormat:@"%@", filename];
  NSData *data = [NSData dataWithData:UIImagePNGRepresentation(uiImageRef)];
  [data writeToFile:tmpPNGPath atomically:YES];
  NSLog(@"wrote %@", tmpPNGPath);
}

// This test method uses CoreGraphics to generate an image that is 256x256
// with all white pixels. The alpha values are defined in a second grayscale
// image, these grayscale pixel values become the alpha channel values
// in the result image. Since all the pixels in the buffer are white, the
// image goes from translucent to all white fading in as rows increase
// from 0 to 255.

+ (void) testPremultiplyBasicValuesWithCG
{
  CGImageRef imageRef;
  
  int width = 256;
  int height = 256;
  
  CGFrameBuffer *framebufferAlpha = [CGFrameBuffer cGFrameBufferWithBppDimensions:24 width:width height:height];
  
  uint32_t *pixelPtr = (uint32_t*)framebufferAlpha.pixels;
  
  for (uint32_t rowi = 0; rowi < height; rowi++) {
    for (uint32_t coli = 0; coli < width; coli++) {
      uint32_t pixel = (0xFF << 24) | (rowi << 16) | (rowi << 8) | rowi;
      *pixelPtr++ = pixel;
    }
  }
  
  imageRef = [framebufferAlpha createCGImageRef];
  
  UIImage *alphaImage = [UIImage imageWithCGImage:imageRef];
  
  assert(alphaImage);
  
  CGImageRelease(imageRef);
  
  // Create another framebuffer that contains only white pixels at 24BPP
  
  CGFrameBuffer *framebufferWhite = [CGFrameBuffer cGFrameBufferWithBppDimensions:24 width:width height:height];
  
  memset(framebufferWhite.pixels, 0xFF, framebufferWhite.numBytes);
  
  imageRef = [framebufferWhite createCGImageRef];
  
  UIImage *whiteImage = [UIImage imageWithCGImage:imageRef];
  
  assert(whiteImage);
  
  CGImageRelease(imageRef);
  
  // Use CoreGraphics to render the buffer but use the alpha channel defined in the grayscale buffer
  
  CGFrameBuffer *combinedBuffer = [CGFrameBuffer cGFrameBufferWithBppDimensions:32 width:width height:height];

  CGContextRef context = [combinedBuffer createBitmapContext];

  assert(context);
  
  CGRect bounds = CGRectMake( 0.0f, 0.0f, width, height );
  
  // Define "alpha mask" using image
  
  CGContextClipToMask(context, bounds, alphaImage.CGImage);

  // Render all white image, each pixel is premultipled.
  
	CGContextDrawImage(context, bounds, whiteImage.CGImage);
  
	CGContextRelease(context);
    
  uint32_t *pixels = (uint32_t*)combinedBuffer.pixels;
  
  int row;
  uint32_t pixel;
  
  row = 0;
  pixel = pixels[row*width];
  assert(pixel == 0);
  
  row = 1;
  pixel = pixels[row*width];
  assert(pixel == 0x01010101);

  row = 255;
  pixel = pixels[row*width];
  assert(pixel == 0xFFFFFFFF);

  // Iterate over all the rows and verify that each component matches
  
  for (row = 0; row < height; row++) {
    pixel = pixels[row*width];
    uint32_t expectedPixel = (row << 24) | (row << 16) | (row << 8) | row;
    assert(pixel == expectedPixel);
  }
 
  if (FALSE) {
    imageRef = [combinedBuffer createCGImageRef];
    
    UIImage *combinedImage = [UIImage imageWithCGImage:imageRef];
    
    assert(combinedImage);
    
    CGImageRelease(imageRef);
    
    [self writePNG:@"White_256x256_AlphaFadeIn.png" uiImageRef:combinedImage];
  }
  
  return;
}

// This example will construct a 256x256 image like the one above, except that
// the pixels in the rows increase in value from 0 to 255. The result is that
// this image is basically a 2D lookup table for premultiplied alpha values.
// Premultiplied values can be looked up by first finding the row that corresponds
// to a specific alpha value, then the column is looked up to convert a
// specific non-premultiplied alpha value to the premultiplied value.

+ (void) testPremultiplyAllValuesWithCG
{
  CGImageRef imageRef;
  
  int width = 256;
  int height = 256;
  
  CGFrameBuffer *framebufferAlpha = [CGFrameBuffer cGFrameBufferWithBppDimensions:24 width:width height:height];
  
  uint32_t *pixelPtr = (uint32_t*)framebufferAlpha.pixels;
  
  for (uint32_t rowi = 0; rowi < height; rowi++) {
    for (uint32_t coli = 0; coli < width; coli++) {
      uint32_t pixel = (0xFF << 24) | (rowi << 16) | (rowi << 8) | rowi;
      *pixelPtr++ = pixel;
    }
  }
  
  imageRef = [framebufferAlpha createCGImageRef];
  
  UIImage *alphaImage = [UIImage imageWithCGImage:imageRef];
  
  assert(alphaImage);
  
  CGImageRelease(imageRef);
  
  // Create another framebuffer that contains only white pixels at 24BPP
  
  CGFrameBuffer *framebufferWhite = [CGFrameBuffer cGFrameBufferWithBppDimensions:24 width:width height:height];
  
  pixelPtr = (uint32_t*)framebufferWhite.pixels;
  
  for (uint32_t rowi = 0; rowi < height; rowi++) {
    for (uint32_t coli = 0; coli < width; coli++) {
      uint32_t pixel = (0xFF << 24) | (coli << 16) | (coli << 8) | coli;
      *pixelPtr++ = pixel;
    }
  }
  
  imageRef = [framebufferWhite createCGImageRef];
  
  UIImage *whiteImage = [UIImage imageWithCGImage:imageRef];
  
  assert(whiteImage);
  
  CGImageRelease(imageRef);
  
  // Use CoreGraphics to render the buffer but use the alpha channel defined in the grayscale buffer
  
  CGFrameBuffer *combinedBuffer = [CGFrameBuffer cGFrameBufferWithBppDimensions:32 width:width height:height];
  
  CGContextRef context = [combinedBuffer createBitmapContext];
  
  assert(context);
  
  CGRect bounds = CGRectMake( 0.0f, 0.0f, width, height );
  
  // Define "alpha mask" using image
  
  CGContextClipToMask(context, bounds, alphaImage.CGImage);
  
  // Render all white image, each pixel is premultipled.
  
	CGContextDrawImage(context, bounds, whiteImage.CGImage);
  
	CGContextRelease(context);
  
  uint32_t *pixels = (uint32_t*)combinedBuffer.pixels;
  
  int row;
  uint32_t pixel;
  
  // Verify that table[i][j] maps to i = alpha, then j = value
  // and the value at that mapping is the alpha value once premultiplication
  // has been applied. Input is always in the range 0 -> 255 and
  // corresponds to one of the RGB values, the alpha is always in
  // the 0 -> 255 range also.
  
  row = 0;
  pixel = pixels[row*width];
  assert(pixel == 0);
  
  pixel = pixels[row*width + 255];
  assert(pixel == 0);

  row = 127;
  pixel = pixels[row*width];
  assert(pixel == 0x7F000000);
  
  pixel = pixels[row*width + 255];
  assert(pixel == 0x7F7F7F7F);
  
  row = 255;
  pixel = pixels[row*width];
  assert(pixel == 0xFF000000);
  
  pixel = pixels[row*width + 255];
  assert(pixel == 0xFFFFFFFF);
  
  // Iterate over all the rows and verify that each component matches
  
  NSMutableString *buffer = [NSMutableString string];
  
  [buffer appendString:@"uint8_t alphaPremultiplyTable[] = {"];
  
  for (uint32_t rowi = 0; rowi < height; rowi++) {
    [buffer appendString:@"\n"];
    [buffer appendString:@"\t"];
    [buffer appendFormat:@"// Alpha %d ", rowi];

    [buffer appendString:@"\n"];
    [buffer appendString:@"\t"];
    
    for (uint32_t coli = 0; coli < width; coli++) {
      uint32_t pixel = pixels[rowi * width + coli];
      
      // Alpha corresponds to alpha value for this row
      
      uint32_t pixelAlpha = (pixel >> 24) & 0xFF;
      uint32_t pixelRed = (pixel >> 16) & 0xFF;
      uint32_t pixelGreen = (pixel >> 8) & 0xFF;
      uint32_t pixelBlue = (pixel >> 0) & 0xFF;
      
      assert(pixelAlpha == rowi);
      assert(pixelRed == pixelGreen);
      assert(pixelRed == pixelBlue);
      
      [buffer appendFormat:@"%d, ", pixelRed];
    }
  }
  
  NSRange endRange;
  endRange.location = [buffer length] - 2;
  endRange.length = 2;
  [buffer deleteCharactersInRange:endRange];
  
  [buffer appendString:@"\n}\n"];

  if (FALSE) {
    NSLog(@"%@", [buffer description]);
  }
  
  if (FALSE) {
    imageRef = [combinedBuffer createCGImageRef];
    
    UIImage *combinedImage = [UIImage imageWithCGImage:imageRef];
    
    assert(combinedImage);
    
    CGImageRelease(imageRef);
    
    [self writePNG:@"Black_2_White_Gradient_256x256_FadeIn.png" uiImageRef:combinedImage];
  }
  
  return;
}

// Test logic to premultiply pixels and then revese the process. This
// basically makes sure that the lookup tables are mathmatically
// inverses of each other in a lossless way.

+ (void) testPremultiplyAndThenReverse
{
  int width = 256;
  int height = 256;
  
  CGFrameBuffer *nonPremultBuffer = [CGFrameBuffer cGFrameBufferWithBppDimensions:32 width:width height:height];
  
  uint32_t *nonPremultBufferPtr = (uint32_t*)nonPremultBuffer.pixels;
  
  for (uint32_t rowi = 0; rowi < height; rowi++) {
    for (uint32_t coli = 0; coli < width; coli++) {
      uint32_t alpha = rowi;
      uint32_t gray = coli;
      
      uint32_t pixel = (alpha << 24) | (gray << 16) | (gray << 8) | gray;
      
      *nonPremultBufferPtr++ = pixel;
      
      if (rowi == 0 && (coli == 0 || coli == 1)) {
        NSLog(@"nonPremultBuffer[%d][%d] = 0x%X from ALPHA = %d, GRAY = %d", rowi, coli, pixel, alpha, gray);
      }
    }
  }
  
  // Now premultiply each pixel and store in another buffer
  
  CGFrameBuffer *premultBuffer = [CGFrameBuffer cGFrameBufferWithBppDimensions:32 width:width height:height];

  nonPremultBufferPtr = (uint32_t*)nonPremultBuffer.pixels;
  uint32_t *premultBufferPtr = (uint32_t*)premultBuffer.pixels;
  
  for (uint32_t rowi = 0; rowi < height; rowi++) {
    for (uint32_t coli = 0; coli < width; coli++) {
      uint32_t pixel = *nonPremultBufferPtr++;
      
      uint32_t pixelAlpha = (pixel >> 24) & 0xFF;
      uint32_t pixelRed = (pixel >> 16) & 0xFF;
      uint32_t pixelGreen = (pixel >> 8) & 0xFF;
      uint32_t pixelBlue = (pixel >> 0) & 0xFF;
      
      // Premultiply pixel
      pixel = premultiply_bgra_inline(pixelRed, pixelGreen, pixelBlue, pixelAlpha);
      
      uint32_t pixelAlphaAfter = (pixel >> 24) & 0xFF;
      // If the input alpha was zero, then the premultiplied alpha must be zero too.
      if (pixelAlpha == 0) {
        assert(pixelAlphaAfter == 0);
      } else if (pixelAlpha == 255) {
        assert(pixelAlphaAfter == 255);
      }
      
      uint32_t pixelRedAfter = (pixel >> 16) & 0xFF;
      uint32_t pixelGreenAfter = (pixel >> 8) & 0xFF;
      uint32_t pixelBlueAfter = (pixel >> 0) & 0xFF;
      assert(pixelRedAfter == pixelGreenAfter || pixelRedAfter == pixelBlueAfter);
      
      if (rowi == 0 && (coli == 0 || coli == 1)) {
        NSLog(@"premultBufferPtr[%d][%d] = 0x%X from ALPHA = %d, GRAY = %d", rowi, coli, pixel, pixelAlphaAfter, pixelRedAfter);
      }
      
      *premultBufferPtr++ = pixel;
    }
  }

  // Now reverse the premultiplication step and verify that the reverse operation
  // generates the same result as the original input.

  nonPremultBufferPtr = (uint32_t*)nonPremultBuffer.pixels;
  premultBufferPtr = (uint32_t*)premultBuffer.pixels;
  
  for (uint32_t rowi = 0; rowi < height; rowi++) {
    for (uint32_t coli = 0; coli < width; coli++) {
      uint32_t pixel = *premultBufferPtr++;

      uint32_t premultPixelAlpha = (pixel >> 24) & 0xFF;
      uint32_t premultPixelRed = (pixel >> 16) & 0xFF;
      uint32_t premultPixelGreen = (pixel >> 8) & 0xFF;
      uint32_t premultPixelBlue = (pixel >> 0) & 0xFF;
      assert(premultPixelAlpha == premultPixelAlpha);
      assert(premultPixelRed == premultPixelGreen && premultPixelGreen == premultPixelBlue);
      
      // Undo the premultiply step
      
      uint32_t unPixel = unpremultiply_bgra(pixel);
      
      uint32_t unpremultPixelAlpha = (unPixel >> 24) & 0xFF;
      uint32_t unpremultPixelRed = (unPixel >> 16) & 0xFF;
      uint32_t unpremultPixelGreen = (unPixel >> 8) & 0xFF;
      uint32_t unpremultPixelBlue = (unPixel >> 0) & 0xFF;
      assert(unpremultPixelAlpha == unpremultPixelAlpha);
      assert(unpremultPixelRed == unpremultPixelGreen && unpremultPixelGreen == unpremultPixelBlue);
      
      if (rowi == 0 && (coli == 0 || coli == 1)) {
        NSLog(@"unPremult[%d][%d] = 0x%X from ALPHA = %d, GRAY = %d", rowi, coli, unPixel, unpremultPixelAlpha, unpremultPixelRed);
      }
      
      // Compare to original unpremultiplied pixel
      
      uint32_t originalUnPixel = *nonPremultBufferPtr++;
      
      uint32_t originalUnpremultPixelAlpha = (originalUnPixel >> 24) & 0xFF;
      uint32_t originalUnpremultPixelRed = (originalUnPixel >> 16) & 0xFF;
      uint32_t originalUnpremultPixelGreen = (originalUnPixel >> 8) & 0xFF;
      uint32_t originalUnpremultPixelBlue = (originalUnPixel >> 0) & 0xFF;
      assert(originalUnpremultPixelAlpha == originalUnpremultPixelAlpha);
      assert(originalUnpremultPixelRed == originalUnpremultPixelGreen && originalUnpremultPixelGreen == originalUnpremultPixelBlue);
     
      // Special case where alpha is zero, since this loses information as compared to the original because the RGB values
      // are converted to zero. But, once the input is then converted back to premultiplied pixels, then the result
      // is the same pixel values.
      
      if (originalUnpremultPixelAlpha == 0) {
        assert(unPixel == 0);
      } else {
        assert(unPixel == originalUnPixel);
      }
    }
  }

  return;
}


/*
 
 uint32_t expectedAdler = 3784927541;
 uint32_t adler;
 
 adler = maxvid_adler32(0L, (const unsigned char*)framebuffer.pixels, numBytes);
 
 NSAssert(adler == expectedAdler, @"adler");

 */

@end
