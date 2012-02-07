//
//  AVAssetReaderConvertMaxvid.h
//
//  Created by Moses DeJong on 2/4/12.
//
//  License terms defined in License.txt.
//
//  This module implements a H264 to MVID decoder that can be used to
//  save the raw bits of a H264 video into a file.

#import "AVAssetReaderConvertMaxvid.h"

#import "maxvid_file.h"

#ifndef __OPTIMIZE__
// Automatically define EXTRA_CHECKS when not optimizing (in debug mode)
# define EXTRA_CHECKS
#endif // DEBUG

//#define ALWAYS_CHECK_ADLER


#if defined(HAS_AVASSET_READER_CONVERT_MAXVID)

#import <AVFoundation/AVFoundation.h>

#import <AVFoundation/AVAsset.h>
#import <AVFoundation/AVAssetReader.h>
#import <AVFoundation/AVAssetReaderOutput.h>

#import <CoreMedia/CMSampleBuffer.h>

UIImage *imageFromSampleBuffer(CMSampleBufferRef sampleBuffer);

@implementation AVAssetReaderConvertMaxvid

@synthesize filePath = m_filePath;

- (void) dealloc
{  
  self.filePath = nil;
  [super dealloc];
}

+ (AVAssetReaderConvertMaxvid*) aVAssetReaderConvertMaxvid
{
  return [[[AVAssetReaderConvertMaxvid alloc] init] autorelease];
}


// Read video data from a single track (only one video track is supported anyway)

+ (BOOL) decodeAssetURL:(NSURL*)url
{
  NSDictionary *options = [NSDictionary dictionaryWithObject:[NSNumber numberWithBool:YES]
                                                      forKey:AVURLAssetPreferPreciseDurationAndTimingKey];
  
  AVURLAsset *avUrlAsset = [[[AVURLAsset alloc] initWithURL:url options:options] autorelease];
  NSAssert(avUrlAsset, @"AVURLAsset");
  
  // FIXME: return false error code if something goes wrong
  
  // Check for DRM protected content
  
  if (avUrlAsset.hasProtectedContent) {
    NSAssert(FALSE, @"DRM");
  }
  
  if ([avUrlAsset tracks] == 0) {
    NSAssert(FALSE, @"not tracks");
  }
  
  NSError *assetError = nil;
  AVAssetReader *aVAssetReader = [AVAssetReader assetReaderWithAsset:avUrlAsset error:&assetError];
  
  NSAssert(aVAssetReader, @"aVAssetReader");
  
  if (assetError) {
    NSAssert(FALSE, @"AVAssetReader");
  }

  // This video setting indicates that native 32 bit endian pixels with a leading
  // ignored alpha channel will be emitted by the decoding process.
  
  NSDictionary *videoSettings;
  videoSettings = [NSDictionary dictionaryWithObject:
                     [NSNumber numberWithUnsignedInt:kCVPixelFormatType_32BGRA] forKey:(id)kCVPixelBufferPixelFormatTypeKey];
  
  NSArray *videoTracks = [avUrlAsset tracksWithMediaType:AVMediaTypeVideo];
  
  NSAssert([videoTracks count] == 1, @"only 1 video track can be decoded");
  
  AVAssetTrack *videoTrack = [videoTracks objectAtIndex:0];
  
  NSArray *availableMetadataFormats = videoTrack.availableMetadataFormats;
  
  NSLog(@"availableMetadataFormats %@", availableMetadataFormats);
  
  // track must be self contained
  
  NSAssert(videoTrack.isSelfContained, @"isSelfContained");
  
  // playback framerate
  
  //CMTimeScale naturalTimeScale = videoTrack.naturalTimeScale;
  
  float nominalFrameRate = videoTrack.nominalFrameRate;
  
  NSLog(@"frame rate %0.2f FPS", nominalFrameRate);
  
  AVAssetReaderTrackOutput *aVAssetReaderOutput = [[[AVAssetReaderTrackOutput alloc]
                                                    initWithTrack:videoTrack outputSettings:videoSettings] autorelease];
  
  NSAssert(aVAssetReaderOutput, @"AVAssetReaderVideoCompositionOutput failed");
  
  // Read video data from the inidicated tracks of video data
  
  [aVAssetReader addOutput:aVAssetReaderOutput];
  
  BOOL worked = [aVAssetReader startReading];
  
  if (!worked) {
    AVAssetReaderStatus status = aVAssetReader.status;
    NSError *error = aVAssetReader.error;
    
    NSLog(@"status = %d", status);
    NSLog(@"error = %@", [error description]);
  }
  
  CMSampleBufferRef sampleBuffer;
  
  int frame = 0;
  
  while ([aVAssetReader status] == AVAssetReaderStatusReading)
  {
    NSAutoreleasePool *inner_pool = [[NSAutoreleasePool alloc] init];
    
    NSLog(@"READING frame %d", frame);
    
    sampleBuffer = [aVAssetReaderOutput copyNextSampleBuffer];
    
    NSLog(@"WRITTING...");
    
    if (sampleBuffer) {
      UIImage *image = imageFromSampleBuffer(sampleBuffer);
      
      NSString *tmpDir = NSTemporaryDirectory();
      NSString *filename = [NSString stringWithFormat:@"img%d.png", frame];
      NSString *path = [tmpDir stringByAppendingPathComponent:filename];
      
      NSData *data = [NSData dataWithData:UIImagePNGRepresentation(image)];
      [data writeToFile:path atomically:YES];
      
      NSLog(@"wrote %@", path);
      
      CFRelease(sampleBuffer);
    } else if ([aVAssetReader status] == AVAssetReaderStatusReading) {
      AVAssetReaderStatus status = aVAssetReader.status;
      NSError *error = aVAssetReader.error;
      
      NSLog(@"status = %d", status);
      NSLog(@"error = %@", [error description]);
    }
    
    frame++;
    
    [inner_pool drain];
  }
  
  [aVAssetReader cancelReading];
  
  return TRUE;
}

@end


// C code


UIImage *imageFromSampleBuffer(CMSampleBufferRef sampleBuffer) {  
  
  CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
  
  // Lock the base address of the pixel buffer.
  
  CVPixelBufferLockBaseAddress(imageBuffer,0);
  
  
  // Get the number of bytes per row for the pixel buffer.
  
  size_t bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer);
  
  // Get the pixel buffer width and height.
  
  size_t width = CVPixelBufferGetWidth(imageBuffer);
  
  size_t height = CVPixelBufferGetHeight(imageBuffer);
  
  
  
  // Create a device-dependent RGB color space.
  
  static CGColorSpaceRef colorSpace = NULL;
  
  if (colorSpace == NULL) {
    
    colorSpace = CGColorSpaceCreateDeviceRGB();
    
    if (colorSpace == NULL) {
      
      // Handle the error appropriately.
      
      return nil;
      
    }
    
  }
  
  
  
  // Get the base address of the pixel buffer.
  
  void *baseAddress = CVPixelBufferGetBaseAddress(imageBuffer);
  
  // Get the data size for contiguous planes of the pixel buffer.
  
  size_t bufferSize = CVPixelBufferGetDataSize(imageBuffer);
  
  
  
  // Create a Quartz direct-access data provider that uses data we supply.
  
  CGDataProviderRef dataProvider =
  
  CGDataProviderCreateWithData(NULL, baseAddress, bufferSize, NULL);
  
  // Create a bitmap image from data supplied by the data provider.
  
  OSType pixelFormat = CVPixelBufferGetPixelFormatType (imageBuffer);
  
  assert(pixelFormat != 0);
  // prints ARGB with kCVPixelFormatType_32BGRA
  // Most optimal formal : kCGBitmapByteOrder32Host | kCGImageAlphaNoneSkipFirst (A BGR ) ??
  
  // XRGB = kCGBitmapByteOrder32Little | kCGImageAlphaNoneSkipFirst (intel is little endian)
  // ARM is a little-endian, 32-bit RISC architecture widely used by mobile devices.
  
  // Looks like 32BGRA is little with skip first!
  // FIXME: Determine the pixel layout for optimized PNG data read from a file, make
  // sure the layout used for data written to MVID is the same as this format.
  
  printf("PixelBuffer FormatType: %4.4s\n\n", (char*)&pixelFormat);
  
  
  CGImageRef cgImage =
  
  CGImageCreate(width, height, 8, 32, bytesPerRow,
                
                colorSpace, kCGImageAlphaNoneSkipFirst | kCGBitmapByteOrder32Little,
                
                dataProvider, NULL, true, kCGRenderingIntentDefault);
  
  CGDataProviderRelease(dataProvider);
  
  
  
  // Create and return an image object to represent the Quartz image.
  
  UIImage *image = [UIImage imageWithCGImage:cgImage];
  
  CGImageRelease(cgImage);
  
  CVPixelBufferUnlockBaseAddress(imageBuffer, 0);
  
  return image;  
}

#endif // HAS_AVASSET_READER_CONVERT_MAXVID
