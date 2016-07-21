//
//  AV7zAppResourceLoader.m
//
//  Created by Moses DeJong on 4/22/11.
//
//  License terms defined in License.txt.
//

#import "AV7zAppResourceLoader.h"

#import "AVFileUtil.h"

#import "LZMAExtractor.h"

#import "AVMvidFrameDecoder.h"
#import "AVMvidFileWriter.h"
#import "AVFrame.h"
#import "CGFramebuffer.h"

#include "AVStreamEncodeDecode.h"

#define LOGGING

@implementation AV7zAppResourceLoader

@synthesize archiveFilename = m_archiveFilename;
@synthesize outPath = m_outPath;
@synthesize flattenMvid = m_flattenMvid;

#if defined(HAS_LIB_COMPRESSION_API)
@synthesize compressed = m_compressed;
#endif // HAS_LIB_COMPRESSION_API

- (void) dealloc
{
  self.archiveFilename = nil;
  self.outPath = nil;
#if __has_feature(objc_arc)
#else
  [super dealloc];
#endif // objc_arc
}

+ (AV7zAppResourceLoader*) aV7zAppResourceLoader
{
  AV7zAppResourceLoader *obj = [[AV7zAppResourceLoader alloc] init];
#if __has_feature(objc_arc)
  return obj;
#else
  return [obj autorelease];
#endif // objc_arc
}

// This method is invoked in the secondary thread to decode the contents of the archive entry
// and write it to an output file (typically in the tmp dir).

+ (void) decodeThreadEntryPoint:(NSArray*)arr {  
  @autoreleasepool {
  
  NSAssert([arr count] == 7, @"arr count");
  
  // Pass 7 arguments : ARCHIVE_PATH ARCHIVE_ENTRY_NAME PHONY_PATH TMP_PATH SERIAL FLATTEN_PATH COMPRESS
  
  NSString *archivePath = [arr objectAtIndex:0];
  NSString *archiveEntry = [arr objectAtIndex:1];
  NSString *phonyOutPath = [arr objectAtIndex:2];
  NSString *outPath = [arr objectAtIndex:3];
  NSNumber *serialLoadingNum = [arr objectAtIndex:4];
  NSString *flattenOutPath = [arr objectAtIndex:5];
  NSNumber *compressNum = [arr objectAtIndex:6];
    
  BOOL compress = [compressNum boolValue];
  
  if ([serialLoadingNum boolValue]) {
    [self grabSerialResourceLoaderLock];
  }

  // Check to see if the output file already exists. If the resource exists at this
  // point, then there is no reason to kick off another decode operation. For example,
  // in the serial loading case, a previous load could have loaded the resource.

  BOOL fileExists = [AVFileUtil fileExists:outPath];
  
  if (fileExists) {
#ifdef LOGGING
    NSLog(@"no 7zip extraction needed for %@", archiveEntry);
#endif // LOGGING
  } else {
#ifdef LOGGING
    NSLog(@"start 7zip extraction %@", archiveEntry);
#endif // LOGGING  
    
    BOOL worked;
    worked = [LZMAExtractor extractArchiveEntry:archivePath archiveEntry:archiveEntry outPath:phonyOutPath];
    NSAssert(worked, @"extractArchiveEntry failed");
    
#ifdef LOGGING
    NSLog(@"done 7zip extraction %@", archiveEntry);
#endif // LOGGING
    
    if ([flattenOutPath isEqualToString:@""]) {
      // Move phony tmp filename to the expected filename once writes are complete
      
      [AVFileUtil renameFile:phonyOutPath toPath:outPath];
    } else {
      // If the caller explicitly indicated that non-keyframes is .mvid should be
      // converted to all keyframes then do that now. Note that the AVMvidFrameDecoder
      // class expects to find a path that ends in "*.mvid" so rename the file
      // before opening.
      
      NSString *phonyOutMvidPath = [NSString stringWithFormat:@"%@.mvid", phonyOutPath];
      
      [AVFileUtil renameFile:phonyOutPath toPath:phonyOutMvidPath];
      
      worked = [self.class flattenMvidImpl:phonyOutMvidPath outputMvidPath:flattenOutPath compress:compress];
      
      NSAssert(worked, @"flattenMvid failed for \"%@\"", phonyOutMvidPath);
      
      // Delete phony .mvid file
      
      worked = [[NSFileManager defaultManager] removeItemAtPath:phonyOutMvidPath error:nil];
      NSAssert(worked, @"could not remove tmp file");
      
      // Rename flat output file to final output path
      
      [AVFileUtil renameFile:flattenOutPath toPath:outPath];
    }
#ifdef LOGGING
    NSLog(@"wrote %@", outPath);
#endif // LOGGING
  }
  
  if ([serialLoadingNum boolValue]) {
    [self releaseSerialResourceLoaderLock];
  }
  
  }
}

- (void) _detachNewThread:(NSString*)archivePath
            archiveEntry:(NSString*)archiveEntry
            phonyOutPath:(NSString*)phonyOutPath
                 outPath:(NSString*)outPath
           flattenOutPath:(NSString*)flattenOutPath
                 compress:(BOOL)compress
{
  NSNumber *serialLoadingNum = [NSNumber numberWithBool:self.serialLoading];
  
  NSNumber *compressNum = [NSNumber numberWithBool:compress];
  
  NSArray *arr = [NSArray arrayWithObjects:archivePath, archiveEntry, phonyOutPath, outPath, serialLoadingNum, flattenOutPath, compressNum, nil];
  NSAssert([arr count] == 7, @"arr count");
  
  [NSThread detachNewThreadSelector:@selector(decodeThreadEntryPoint:) toTarget:self.class withObject:arr];  
}

- (void) load
{
  // Avoid kicking off mutliple sync load operations. This method should only
  // be invoked from a main thread callback, so there should not be any chance
  // of a race condition involving multiple invocations of this load mehtod.
  
  if (startedLoading) {
    return;
  } else {
    self->startedLoading = TRUE;    
  }

  // Superclass load method asserts that self.movieFilename is not nil
  [super load];

  NSString *qualPath = [AVFileUtil getQualifiedFilenameOrResource:self.archiveFilename];
  NSAssert(qualPath, @"qualPath");

  NSString *archiveEntry = self.movieFilename;
  NSString *outPath = self.outPath;
  NSAssert(outPath, @"outPath not defined");

  // Generate phony tmp path that data will be written to as it is extracted.
  // This avoids thread race conditions and partial writes. Note that the filename is
  // generated in this method, and this method should only be invoked from the main thread.

  NSString *phonyOutPath = [AVFileUtil generateUniqueTmpPath];
  
  NSString *flattenOutPath = @"";
  
  BOOL isCompressed = FALSE;
#if defined(HAS_LIB_COMPRESSION_API)
  isCompressed = self.compressed;
#endif // HAS_LIB_COMPRESSION_API
  
  if (self.flattenMvid || isCompressed) {
    flattenOutPath = [AVFileUtil generateUniqueTmpPath];
  }

  [self _detachNewThread:qualPath archiveEntry:archiveEntry phonyOutPath:phonyOutPath outPath:outPath flattenOutPath:flattenOutPath compress:isCompressed];
  
  return;
}

// Output movie filename must be redefined

- (NSString*) _getMoviePath
{
 return self.outPath;
}

// Util method that will read an input .mvid and write an output .mvid with the same size and BPP
// settings but with delta frames flattened out as keyframes.

+ (BOOL) flattenMvidImpl:(NSString*)inputMvidPath
          outputMvidPath:(NSString*)outputMvidPath
                compress:(BOOL)compress
{
  BOOL worked;
  
  AVMvidFrameDecoder *frameDecoder = [AVMvidFrameDecoder aVMvidFrameDecoder];
  NSAssert(frameDecoder, @"frameDecoder");
  
  worked = [frameDecoder openForReading:inputMvidPath];
  
  if (!worked) {
    NSAssert(worked, @"openForReading failed for \"%@\"", inputMvidPath);
  }
  
  // If the input .mvid is already all keyframes then generate a DEBUG assert.
  
#if defined(DEBUG)
  if ((compress == FALSE) && [frameDecoder isAllKeyframes]) {
    NSAssert(FALSE, @"decompressed .mvid contains only keyframes \"%@\"", inputMvidPath);
  }
#endif // DEBUG
  
  MVFileHeader *mvidHeader = frameDecoder.header;
  
  worked = [frameDecoder allocateDecodeResources];
  
  if (worked == FALSE) {
    // Use RETURN in possible fail cases, not assert
    NSAssert(worked, @"error: cannot allocate decode resources for filename \"%@\"", inputMvidPath);
    //        NSLog(@"error: cannot allocate decode resources for filename \"%@\"", inputMvidPath);
    //        return FALSE;
  }
  
  AVMvidFileWriter *avMvidFileWriter = [AVMvidFileWriter aVMvidFileWriter];
  
  // Write to flattenOutPath
  
  avMvidFileWriter.mvidPath = outputMvidPath;
  
  // 32, 24, or 16 bpp
  
  avMvidFileWriter.bpp = mvidHeader->bpp;
  
  avMvidFileWriter.frameDuration = frameDecoder.frameDuration;
  avMvidFileWriter.totalNumFrames = (int) frameDecoder.numFrames;
  
  avMvidFileWriter.genV3 = TRUE;
  
  avMvidFileWriter.movieSize = CGSizeMake(frameDecoder.width, frameDecoder.height);
  
#if defined(DEBUG)
  if (1) {
    avMvidFileWriter.genAdler = TRUE;
  }
#endif // DEBUG
  
  worked = [avMvidFileWriter open];
  if (worked == FALSE) {
    NSAssert(0, @"error: Could not open .mvid output file \"%@\"", avMvidFileWriter.mvidPath);
  }
  
  // Decode each frame and write as keyframes
  
  for (NSUInteger frameIndex = 0; frameIndex < avMvidFileWriter.totalNumFrames; frameIndex++) @autoreleasepool {
#ifdef LOGGING
    NSLog(@"reading frame %d", (int)frameIndex);
#endif // LOGGING
    
    AVFrame *frame = [frameDecoder advanceToFrame:frameIndex];
    assert(frame);
    
    CGFrameBuffer *cgFrameBuffer = frame.cgFrameBuffer;
    
#if defined(DEBUG)
    NSAssert(cgFrameBuffer.bitsPerPixel == avMvidFileWriter.bpp, @"bpp");
#endif // DEBUG
    
    int numBytesInBuffer = (int) cgFrameBuffer.numBytes;
    
    char *pixelsPtr = (char*)cgFrameBuffer.pixels;
    
#if defined(HAS_LIB_COMPRESSION_API)
    // If compression is used, then generate a compressed buffer and write it as
    // a keyframe.
    
    if (compress) {
      NSData *pixelData = [NSData dataWithBytesNoCopy:pixelsPtr length:numBytesInBuffer freeWhenDone:NO];
      
      // FIXME: make this mutable data a member so that it is not allocated
      // in every loop.
      
      NSMutableData *mEncodedData = [NSMutableData data];
      
      [AVStreamEncodeDecode streamDeltaAndCompress:pixelData
                                       encodedData:mEncodedData
                                               bpp:avMvidFileWriter.bpp
                                         algorithm:COMPRESSION_LZ4];
      
      //int src_size = bufferSize;
      assert(mEncodedData.length > 0);
      assert(mEncodedData.length < 0xFFFFFFFF);
      int dst_size = (int) mEncodedData.length;
      
      //printf("compressed frame size %d kB down to %d kB\n", (int)src_size/1000, (int)dst_size/1000);
      
      // Calculate adler based on original pixels (not the compressed representation)
      
      uint32_t adler = 0;
      adler = maxvid_adler32(0, (unsigned char*)pixelsPtr, numBytesInBuffer);
      
      worked = [avMvidFileWriter writeKeyframe:(char*)mEncodedData.bytes bufferSize:(int)dst_size adler:adler isCompressed:TRUE];
    } else {
      worked = [avMvidFileWriter writeKeyframe:pixelsPtr bufferSize:numBytesInBuffer];
    }
#else
    worked = [avMvidFileWriter writeKeyframe:pixelsPtr bufferSize:numBytesInBuffer];
#endif // HAS_LIB_COMPRESSION_API
    
    if (worked == FALSE) {
      NSAssert(0, @"error: Could not write keyframe to file \"%@\"", avMvidFileWriter.mvidPath);
    }
  }
  
  // Update header at front of image data
  
  worked = [avMvidFileWriter rewriteHeader];
  
  if (worked == FALSE) {
    NSAssert(0, @"error: Could not rewrite header file \"%@\"", avMvidFileWriter.mvidPath);
  }
  
  [avMvidFileWriter close];
  
  return TRUE;
}

@end
