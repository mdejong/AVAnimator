//
//  SegmentedMappedDataTests.m
//
//  Created by Moses DeJong on 1/22/12.
//
//  License terms defined in License.txt.

#import <Foundation/Foundation.h>

#import <UIKit/UIKit.h>

#import "AVFileUtil.h"

#import "SegmentedMappedData.h"

#include <sys/types.h>
#include <sys/stat.h>

@interface SegmentedMappedDataTests : NSObject

@end

#define AV_PAGESIZE 4096

@implementation SegmentedMappedDataTests

// Create a file that is two pages long and map with two different segments

#if defined(USE_SEGMENTED_MMAP)

// This test case creates a file that is one page long and then maps the
// contents of the file using a single segment that is a single page.

+ (void) testMapFileWithSingleSegment
{
  NSMutableData *mData = [NSMutableData data];
  
  int sumOfAllData = 0;
  
  for (int i=0; i < AV_PAGESIZE / sizeof(int); i++) {
    NSData *val = [NSData dataWithBytes:&i length:sizeof(int)];
    [mData appendData:val];
    sumOfAllData += i;
  }
  NSAssert([mData length] == AV_PAGESIZE, @"length");
  
  NSString *filePath = [AVFileUtil generateUniqueTmpPath]; 
  
  BOOL worked = [mData writeToFile:filePath options:NSDataWritingAtomic error:nil];
  NSAssert(worked, @"worked");
  NSAssert([AVFileUtil fileExists:filePath], @"fileExists");

  // The parent object contains the filename and the set of mappings
  
  SegmentedMappedData *parentData = [SegmentedMappedData segmentedMappedData:filePath];
  NSAssert(parentData, @"parentData");
#if __has_feature(objc_arc)
#else
  NSAssert([parentData retainCount] == 1, @"retainCount");
#endif // objc_arc

  NSAssert([parentData length] == AV_PAGESIZE, @"container length");
  
  NSRange range;
  range.location = 0;
  range.length = [mData length];
  
  SegmentedMappedData *segmentData = [parentData subdataWithRange:range];  
  NSAssert(segmentData != nil, @"segmentData");
  
#if __has_feature(objc_arc)
#else
  NSAssert([segmentData retainCount] == 1, @"retainCount");
#endif // objc_arc
  
  NSAssert([segmentData length] == AV_PAGESIZE, @"mapped data length");

  NSAssert(segmentData.mappedOffset == 0, @"mappedOffset");
  NSAssert(segmentData.mappedOSOffset == 0, @"mappedOSOffset");

  NSAssert(segmentData.mappedLen == AV_PAGESIZE, @"mappedLen");
  NSAssert(segmentData.mappedOSLen == AV_PAGESIZE, @"mappedOSLen");
  
  // Actually map the segment into memory, note that bytes will assert
  // if the data had not been mapped previously. This mapping is deferred
  // since a single file could have lots of mappings but the developer
  // might want to only map one of two into memory at once.
  
  worked = [segmentData mapSegment];
  NSAssert(worked, @"mapping into memory failed");
  
  // Verify that the values in the mapped data match the generated data.
  
  int sumOfMappedData = 0;
  
  for (int i=0; i < [segmentData length] / sizeof(int); i++) {
    int *iPtr = ((int*)[segmentData bytes]) + i;
    int iVal = *iPtr;
    sumOfMappedData += iVal;
  }
  
  NSAssert(sumOfAllData == sumOfMappedData, @"sum mismatch");
  
  return;
}

+ (void) testMapFileWithTwoSegments
{
  NSMutableData *mData = [NSMutableData data];
  
  int sumOfAllData = 0;
  
  for (int i=0; i < (AV_PAGESIZE / sizeof(int)) * 2; i++) {
    NSData *val = [NSData dataWithBytes:&i length:sizeof(int)];
    [mData appendData:val];
    sumOfAllData += i;
  }
  NSAssert([mData length] == AV_PAGESIZE * 2, @"length");
  
  NSString *filePath = [AVFileUtil generateUniqueTmpPath]; 
  
  BOOL worked = [mData writeToFile:filePath options:NSDataWritingAtomic error:nil];
  NSAssert(worked, @"worked");
  NSAssert([AVFileUtil fileExists:filePath], @"fileExists");
  
  // The parent object contains the filename and the set of mappings
  
  SegmentedMappedData *parentData = [SegmentedMappedData segmentedMappedData:filePath];
  NSAssert(parentData, @"parentData");
  
#if __has_feature(objc_arc)
#else
  NSAssert([parentData retainCount] == 1, @"retainCount");
#endif // objc_arc
  
  NSAssert([parentData length] == AV_PAGESIZE * 2, @"container length");
  
  NSRange range;
  
  // Segment 1
  
  range.location = 0;
  range.length = AV_PAGESIZE;
  
  SegmentedMappedData *segmentData1 = [parentData subdataWithRange:range];
  NSAssert(segmentData1 != nil, @"segmentData1");
  
  // Segment 2
  
  range.location = AV_PAGESIZE;
  range.length = AV_PAGESIZE;

  SegmentedMappedData *segmentData2 = [parentData subdataWithRange:range];
  NSAssert(segmentData1 != nil, @"segmentData1");

#if __has_feature(objc_arc)
#else
  NSAssert([segmentData1 retainCount] == 1, @"retainCount");
#endif // objc_arc
  
  NSAssert([segmentData1 length] == AV_PAGESIZE, @"mapped data length");
  
  NSAssert(segmentData1.mappedOffset == 0, @"mappedOffset");
  NSAssert(segmentData1.mappedOSOffset == 0, @"mappedOSOffset");
  
  NSAssert(segmentData1.mappedLen == AV_PAGESIZE, @"mappedLen");
  NSAssert(segmentData1.mappedOSLen == AV_PAGESIZE, @"mappedOSLen");
  
#if __has_feature(objc_arc)
#else
  NSAssert([segmentData2 retainCount] == 1, @"retainCount");
#endif // objc_arc

  NSAssert([segmentData2 length] == AV_PAGESIZE, @"mapped data length");
  
  NSAssert(segmentData2.mappedOffset == AV_PAGESIZE, @"mappedOffset");
  NSAssert(segmentData2.mappedOSOffset == AV_PAGESIZE, @"mappedOSOffset");
  
  NSAssert(segmentData2.mappedLen == AV_PAGESIZE, @"mappedLen");
  NSAssert(segmentData2.mappedOSLen == AV_PAGESIZE, @"mappedOSLen");
  
  // Actually map the segment into memory, note that bytes will assert
  // if the data had not been mapped previously. This mapping is deferred
  // since a single file could have lots of mappings but the developer
  // might want to only map one of two into memory at once.
  
  worked = [segmentData1 mapSegment];
  NSAssert(worked, @"mapping into memory failed");

  worked = [segmentData2 mapSegment];
  NSAssert(worked, @"mapping into memory failed");
  
  // Verify that the values in the mapped data match the generated data.
  
  int sumOfMappedData = 0;
  
  for (int i=0; i < [segmentData1 length] / sizeof(int); i++) {
    int *iPtr = ((int*)[segmentData1 bytes]) + i;
    int iVal = *iPtr;
    sumOfMappedData += iVal;
  }

  for (int i=0; i < [segmentData2 length] / sizeof(int); i++) {
    int *iPtr = ((int*)[segmentData2 bytes]) + i;
    int iVal = *iPtr;
    sumOfMappedData += iVal;
  }
  
  NSAssert(sumOfAllData == sumOfMappedData, @"sum mismatch");
  
  // Explicitly unmap each segment
  
  [segmentData1 unmapSegment];
  [segmentData2 unmapSegment];
  
  // Invoke unmap again, shold no-op

  [segmentData1 unmapSegment];
  [segmentData2 unmapSegment];
  
  return;
}

// Map a file with 3 whole page segments. The first page is mapped in 1 segment
// and the second two pages are mapped in a second segment.

+ (void) testMapFileWithThreePagesAndTwoSegments
{
  NSMutableData *mData = [NSMutableData data];
  
  int sumOfAllData = 0;
  
  for (int i=0; i < (AV_PAGESIZE / sizeof(int)) * 3; i++) {
    NSData *val = [NSData dataWithBytes:&i length:sizeof(int)];
    [mData appendData:val];
    sumOfAllData += i;
  }
  NSAssert([mData length] == AV_PAGESIZE * 3, @"length");
  
  NSString *filePath = [AVFileUtil generateUniqueTmpPath]; 
  
  BOOL worked = [mData writeToFile:filePath options:NSDataWritingAtomic error:nil];
  NSAssert(worked, @"worked");
  NSAssert([AVFileUtil fileExists:filePath], @"fileExists");
  
  // The parent object contains the filename and the set of mappings
  
  SegmentedMappedData *parentData = [SegmentedMappedData segmentedMappedData:filePath];
  NSAssert(parentData, @"parentData");
  
#if __has_feature(objc_arc)
#else
  NSAssert([parentData retainCount] == 1, @"retainCount");
#endif // objc_arc
  
  NSAssert([parentData length] == AV_PAGESIZE * 3, @"container length");
  
  NSRange range;
  
  // Segment 1
  
  range.location = 0;
  range.length = AV_PAGESIZE;

  SegmentedMappedData *segmentData1 = [parentData subdataWithRange:range];
  NSAssert(segmentData1 != nil, @"segmentData1");
  
  // Segment 2
  
  range.location = AV_PAGESIZE;
  range.length = AV_PAGESIZE * 2;
  
  SegmentedMappedData *segmentData2 = [parentData subdataWithRange:range];
  NSAssert(segmentData2 != nil, @"segmentData2");
  
#if __has_feature(objc_arc)
#else
  NSAssert([segmentData1 retainCount] == 1, @"retainCount");
#endif // objc_arc
  
  NSAssert([segmentData1 length] == AV_PAGESIZE, @"mapped data length");
  
  NSAssert(segmentData1.mappedOffset == 0, @"mappedOffset");
  NSAssert(segmentData1.mappedOSOffset == 0, @"mappedOSOffset");
  
  NSAssert(segmentData1.mappedLen == AV_PAGESIZE, @"mappedLen");
  NSAssert(segmentData1.mappedOSLen == AV_PAGESIZE, @"mappedOSLen");

#if __has_feature(objc_arc)
#else
  NSAssert([segmentData2 retainCount] == 1, @"retainCount");
#endif // objc_arc

  NSAssert([segmentData2 length] == AV_PAGESIZE*2, @"mapped data length");
  
  NSAssert(segmentData2.mappedOffset == AV_PAGESIZE, @"mappedOffset");
  NSAssert(segmentData2.mappedOSOffset == AV_PAGESIZE, @"mappedOSOffset");
  
  NSAssert(segmentData2.mappedLen == AV_PAGESIZE*2, @"mappedLen");
  NSAssert(segmentData2.mappedOSLen == AV_PAGESIZE*2, @"mappedOSLen");
  
  // Actually map the segment into memory, note that bytes will assert
  // if the data had not been mapped previously. This mapping is deferred
  // since a single file could have lots of mappings but the developer
  // might want to only map one of two into memory at once.
  
  worked = [segmentData1 mapSegment];
  NSAssert(worked, @"mapping into memory failed");
  
  worked = [segmentData2 mapSegment];
  NSAssert(worked, @"mapping into memory failed");
  
  // Verify that the values in the mapped data match the generated data.
  
  int sumOfMappedData = 0;
  
  for (int i=0; i < [segmentData1 length] / sizeof(int); i++) {
    int *iPtr = ((int*)[segmentData1 bytes]) + i;
    int iVal = *iPtr;
    sumOfMappedData += iVal;
  }
  
  for (int i=0; i < [segmentData2 length] / sizeof(int); i++) {
    int *iPtr = ((int*)[segmentData2 bytes]) + i;
    int iVal = *iPtr;
    sumOfMappedData += iVal;
  }
  
  NSAssert(sumOfAllData == sumOfMappedData, @"sum mismatch");
  
  // Explicitly unmap each segment
  
  [segmentData1 unmapSegment];
  [segmentData2 unmapSegment];
  
  // Invoke unmap again, shold no-op
  
  [segmentData1 unmapSegment];
  [segmentData2 unmapSegment];
  
  return;
}

// Create a mapped file that is a single byte long, then map it.
// This should create a mapping that is one page long and zero filled.
// This test also checks for a no-op when mapping twice.

+ (void) testMapFileOneByteLong
{  
  int allBitsOn = 0xFF;
  NSData *bytesData = [NSData dataWithBytes:&allBitsOn length:1];
  NSAssert([bytesData length] == 1, @"length");
  
  NSString *filePath = [AVFileUtil generateUniqueTmpPath]; 
  
  BOOL worked = [bytesData writeToFile:filePath options:NSDataWritingAtomic error:nil];
  NSAssert(worked, @"worked");
  NSAssert([AVFileUtil fileExists:filePath], @"fileExists");
  
  // The parent object contains the filename and the set of mappings
  
  SegmentedMappedData *parentData = [SegmentedMappedData segmentedMappedData:filePath];
  NSAssert(parentData, @"parentData");
  
#if __has_feature(objc_arc)
#else
  NSAssert([parentData retainCount] == 1, @"retainCount");
#endif // objc_arc
  
  NSAssert([parentData length] == 1, @"container length");
  
  NSRange range;
  range.location = 0;
  range.length = 1;

  SegmentedMappedData *segmentData = [parentData subdataWithRange:range];
  NSAssert(segmentData != nil, @"segmentData");
  
#if __has_feature(objc_arc)
#else
  NSAssert([segmentData retainCount] == 1, @"retainCount");
#endif // objc_arc
  
  NSAssert([segmentData length] == 1, @"mapped data length");
  
  NSAssert(segmentData.mappedOffset == 0, @"mappedOffset");
  NSAssert(segmentData.mappedOSOffset == 0, @"mappedOSOffset");
  
  NSAssert(segmentData.mappedLen == 1, @"mappedLen");
  NSAssert(segmentData.mappedOSLen == AV_PAGESIZE, @"mappedOSLen");
  
  // Actually map the segment into memory, note that bytes will assert
  // if the data had not been mapped previously. This mapping is deferred
  // since a single file could have lots of mappings but the developer
  // might want to only map one of two into memory at once.
  
  worked = [segmentData mapSegment];
  NSAssert(worked, @"mapping into memory failed");
  
  // Map it again just to make sure this acts as a no-op
  worked = [segmentData mapSegment];
  NSAssert(worked, @"mapping into memory failed");
  
  // First byte should be 0xFF and the second should be 0x0

  char *ptr = (char*) [segmentData bytes];
  
  uint8_t byte1 = *ptr;
  uint8_t byte2 = *(ptr + 1);
    
  NSAssert(byte1 == 0xFF, @"byte1");
  NSAssert(byte2 == 0x0, @"byte2");
  
  [segmentData unmapSegment]; 
  
  return;
}

// Write a whole page, but map only the second half of the page. In actual
// practice, this will map the whole page but return a pointer that starts
// halfway into the page.

+ (void) testMapFileAsHalfPage
{
  NSMutableData *mData = [NSMutableData data];
  
  int sumOfAllData = 0;
  
  for (int i=0; i < AV_PAGESIZE / sizeof(int); i++) {
    int ival = 1;
    if (i < (AV_PAGESIZE / sizeof(int) / 2)) {
      ival = 1;
    } else {
      ival = 3;
      sumOfAllData += ival;
    }
    
    NSData *val = [NSData dataWithBytes:&ival length:sizeof(int)];
    [mData appendData:val];
  }
  NSAssert([mData length] == AV_PAGESIZE, @"length");
  
  NSString *filePath = [AVFileUtil generateUniqueTmpPath]; 
  
  BOOL worked = [mData writeToFile:filePath options:NSDataWritingAtomic error:nil];
  NSAssert(worked, @"worked");
  NSAssert([AVFileUtil fileExists:filePath], @"fileExists");
  
  // The parent object contains the filename and the set of mappings
  
  SegmentedMappedData *parentData = [SegmentedMappedData segmentedMappedData:filePath];
  NSAssert(parentData, @"parentData");
  
#if __has_feature(objc_arc)
#else
  NSAssert([parentData retainCount] == 1, @"retainCount");
#endif // objc_arc
  
  NSAssert([parentData length] == AV_PAGESIZE, @"container length");
  
  NSRange range;
  range.location = (AV_PAGESIZE/2);
  range.length = (AV_PAGESIZE/2);

  SegmentedMappedData *segmentData = [parentData subdataWithRange:range];
  NSAssert(segmentData != nil, @"segmentData");

#if __has_feature(objc_arc)
#else
  NSAssert([segmentData retainCount] == 1, @"retainCount");
#endif // objc_arc
  
  NSAssert([segmentData length] == (AV_PAGESIZE/2), @"mapped data length");
  
  NSAssert(segmentData.mappedOffset == (AV_PAGESIZE/2), @"mappedOffset");
  NSAssert(segmentData.mappedOSOffset == 0, @"mappedOSOffset");
  
  NSAssert(segmentData.mappedLen == (AV_PAGESIZE/2), @"mappedLen");
  NSAssert(segmentData.mappedOSLen == AV_PAGESIZE, @"mappedOSLen");
  
  // Actually map the segment into memory, note that bytes will assert
  // if the data had not been mapped previously. This mapping is deferred
  // since a single file could have lots of mappings but the developer
  // might want to only map one of two into memory at once.
  
  worked = [segmentData mapSegment];
  NSAssert(worked, @"mapping into memory failed");
  
  // Verify that the values in the mapped data match the generated data.
  
  int sumOfMappedData = 0;
  
  for (int i=0; i < [segmentData length] / sizeof(int); i++) {
    int *iPtr = ((int*)[segmentData bytes]) + i;
    int iVal = *iPtr;
    sumOfMappedData += iVal;
  }
  
  NSAssert(sumOfAllData == sumOfMappedData, @"sum mismatch");
  
  [segmentData unmapSegment];
  
  return;
}

// Test case that starts at offset 1 and length is a whole page.
// This will map two OS pages.

+ (void) testMapFileAsTwoPagesPartial
{
  NSMutableData *mData = [NSMutableData data];
  
  int sumOfAllData = 0;
  
  // Page of 1, then page of 2
  
  for (int i=0; i < (AV_PAGESIZE * 2); i++) {
    uint8_t ival;
    if (i < AV_PAGESIZE) {
      ival = 1;
    } else {
      ival = 2;
    }
    
    NSData *val = [NSData dataWithBytes:&ival length:1];
    [mData appendData:val];
    sumOfAllData += ival;
  }
  NSAssert([mData length] == AV_PAGESIZE*2, @"length");
  
  NSString *filePath = [AVFileUtil generateUniqueTmpPath]; 
  
  BOOL worked = [mData writeToFile:filePath options:NSDataWritingAtomic error:nil];
  NSAssert(worked, @"worked");
  NSAssert([AVFileUtil fileExists:filePath], @"fileExists");
  
  // The parent object contains the filename and the set of mappings
  
  SegmentedMappedData *parentData = [SegmentedMappedData segmentedMappedData:filePath];
  NSAssert(parentData, @"parentData");
  
#if __has_feature(objc_arc)
#else
  NSAssert([parentData retainCount] == 1, @"retainCount");
#endif // objc_arc
  
  NSAssert([parentData length] == AV_PAGESIZE*2, @"container length");
  
  NSRange range;
  range.location = 1;
  range.length = AV_PAGESIZE;
  
  SegmentedMappedData *segmentData = [parentData subdataWithRange:range];
  NSAssert(segmentData != nil, @"segmentData");
  
#if __has_feature(objc_arc)
#else
  NSAssert([segmentData retainCount] == 1, @"retainCount");
#endif // objc_arc
  
  NSAssert([segmentData length] == AV_PAGESIZE, @"mapped data length");
  
  NSAssert(segmentData.mappedOffset == 1, @"mappedOffset");
  NSAssert(segmentData.mappedOSOffset == 0, @"mappedOSOffset");
  
  NSAssert(segmentData.mappedLen == AV_PAGESIZE, @"mappedLen");
  NSAssert(segmentData.mappedOSLen == AV_PAGESIZE*2, @"mappedOSLen");
  
  // Actually map the segment into memory, note that bytes will assert
  // if the data had not been mapped previously. This mapping is deferred
  // since a single file could have lots of mappings but the developer
  // might want to only map one of two into memory at once.
  
  worked = [segmentData mapSegment];
  NSAssert(worked, @"mapping into memory failed");
  
  // Verify that the values in the mapped data match the generated data.
  
  int sumOfMappedData = 0;
  
  for (int i=0; i < [segmentData length]; i++) {
    char *ptr = ((char*)[segmentData bytes]) + i;
    char cVal = *ptr;
    sumOfMappedData += cVal;
  }
  
  int expected = (1 * (AV_PAGESIZE - 1)) + 2;
  
  NSAssert(expected == sumOfMappedData, @"sum mismatch");
  
  [segmentData unmapSegment];
  
  return;
}

// Write two pages and then create a mapping that extends over both
// pages. The create a second mapping that maps over the second page.
// Map and then unmap both files to make sure the mapping do not conflict.

+ (void) testMapFileWithOverlappingPage
{
  NSMutableData *mData = [NSMutableData data];
  
  int sumOfAllData = 0;
  
  // Page of 1, then page of 2
  
  for (int i=0; i < (AV_PAGESIZE * 2); i++) {
    uint8_t ival;
    if (i < AV_PAGESIZE) {
      ival = 1;
    } else {
      ival = 2;
    }
    
    NSData *val = [NSData dataWithBytes:&ival length:1];
    [mData appendData:val];
    sumOfAllData += ival;
  }
  NSAssert([mData length] == AV_PAGESIZE*2, @"length");
  
  NSString *filePath = [AVFileUtil generateUniqueTmpPath]; 
  
  BOOL worked = [mData writeToFile:filePath options:NSDataWritingAtomic error:nil];
  NSAssert(worked, @"worked");
  NSAssert([AVFileUtil fileExists:filePath], @"fileExists");
  
  // The parent object contains the filename and the set of mappings
  
  SegmentedMappedData *parentData = [SegmentedMappedData segmentedMappedData:filePath];
  NSAssert(parentData, @"parentData");
  
#if __has_feature(objc_arc)
#else
  NSAssert([parentData retainCount] == 1, @"retainCount");
#endif // objc_arc
  
  NSAssert([parentData length] == AV_PAGESIZE*2, @"container length");
  
  NSRange range;
  range.location = 0;
  range.length = AV_PAGESIZE * 2;

  SegmentedMappedData *segmentData1 = [parentData subdataWithRange:range];
  NSAssert(segmentData1 != nil, @"segmentData1");

  range.location = AV_PAGESIZE;
  range.length = AV_PAGESIZE;
  
  SegmentedMappedData *segmentData2 = [parentData subdataWithRange:range];
  NSAssert(segmentData2 != nil, @"segmentData2");
    
  NSAssert(segmentData1.mappedOffset == 0, @"mappedOffset");
  NSAssert(segmentData1.mappedOSOffset == 0, @"mappedOSOffset");
  
  NSAssert(segmentData1.mappedLen == AV_PAGESIZE*2, @"mappedLen");
  NSAssert(segmentData1.mappedOSLen == AV_PAGESIZE*2, @"mappedOSLen");

  NSAssert(segmentData2.mappedOffset == AV_PAGESIZE, @"mappedOffset");
  NSAssert(segmentData2.mappedOSOffset == AV_PAGESIZE, @"mappedOSOffset");
  
  NSAssert(segmentData2.mappedLen == AV_PAGESIZE, @"mappedLen");
  NSAssert(segmentData2.mappedOSLen == AV_PAGESIZE, @"mappedOSLen");
  
  // Actually map the segment into memory, note that bytes will assert
  // if the data had not been mapped previously. This mapping is deferred
  // since a single file could have lots of mappings but the developer
  // might want to only map one of two into memory at once.
  
  worked = [segmentData1 mapSegment];
  NSAssert(worked, @"mapping into memory failed");

  worked = [segmentData2 mapSegment];
  NSAssert(worked, @"mapping into memory failed");
  
  // Read value from first segment

  char *ptr;
  ptr = (char*)[segmentData1 bytes];
  
  int val1 = *ptr;
  NSAssert(val1 == 1, @"val1");
  
  ptr = (char*)[segmentData2 bytes];

  int val2 = *ptr;
  NSAssert(val2 == 2, @"val2");
  
  [segmentData1 unmapSegment];
  [segmentData2 unmapSegment];
  
  return;
}

// The test passes the name of a file that does not exist.

+ (void) testMapFileDoesNotExist
{  
  NSString *filePath = [AVFileUtil generateUniqueTmpPath]; 
  
  SegmentedMappedData *parentData = [SegmentedMappedData segmentedMappedData:filePath];
  NSAssert(parentData == nil, @"must be nil");
  
  // Create a zero length file
  
  BOOL worked = [[NSData data] writeToFile:filePath options:NSDataWritingAtomic error:nil];
  NSAssert(worked, @"worked");
  NSAssert([AVFileUtil fileExists:filePath], @"fileExists");
  
  parentData = [SegmentedMappedData segmentedMappedData:filePath];
  NSAssert(parentData == nil, @"must be nil");

  // Attempt to map a file that does not have read permissions

  int result;

  int allBitsOn = 0xFF;
  NSData *bytesData = [NSData dataWithBytes:&allBitsOn length:1];
  NSAssert([bytesData length] == 1, @"length");
  
  worked = [bytesData writeToFile:filePath options:NSDataWritingAtomic error:nil];
  NSAssert(worked, @"worked");
  NSAssert([AVFileUtil fileExists:filePath], @"fileExists");  
  
  result = chmod([filePath UTF8String], S_IWUSR);
  NSAssert(result == 0, @"chmod");

  parentData = [SegmentedMappedData segmentedMappedData:filePath];
  NSAssert(parentData == nil, @"must be nil");
  
  result = chmod([filePath UTF8String], S_IRUSR | S_IWUSR);
  NSAssert(result == 0, @"chmod");
  
  [[NSFileManager defaultManager] removeItemAtPath:filePath error:nil];
  
  return;
}

// This test case maps a file that is one page in length and then
// checks the subdataWithRange API to ensure that the proper range
// checks are made while mapping.

+ (void) testMapFileSubdataWithRange
{
  NSMutableData *mData = [NSMutableData data];
  
  int sumOfAllData = 0;
  
  for (int i=0; i < AV_PAGESIZE / sizeof(int); i++) {
    NSData *val = [NSData dataWithBytes:&i length:sizeof(int)];
    [mData appendData:val];
    sumOfAllData += i;
  }
  NSAssert([mData length] == AV_PAGESIZE, @"length");
  
  NSString *filePath = [AVFileUtil generateUniqueTmpPath]; 
  
  BOOL worked = [mData writeToFile:filePath options:NSDataWritingAtomic error:nil];
  NSAssert(worked, @"worked");
  NSAssert([AVFileUtil fileExists:filePath], @"fileExists");
  
  // The parent object contains the filename and the set of mappings
  
  SegmentedMappedData *parentData = [SegmentedMappedData segmentedMappedData:filePath];
  NSAssert(parentData, @"parentData");
  
#if __has_feature(objc_arc)
#else
  NSAssert([parentData retainCount] == 1, @"retainCount");
#endif // objc_arc
  
  NSAssert([parentData length] == AV_PAGESIZE, @"container length");
  
  NSRange range;
  range.location = 0;
  range.length = [mData length];

  SegmentedMappedData *segmentData = nil;
  
  // Map the exact size of the page (location is zero), success
  
  segmentData = [parentData subdataWithRange:range];
  NSAssert(segmentData != nil, @"segmentData");

  // Passing length of zero will return nil to indicate an error

  range.location = 0;
  range.length = 0;

  segmentData = [parentData subdataWithRange:range];
  NSAssert(segmentData == nil, @"segmentData");
  
  // If offset is larger than largest page starting offset, then nil

  range.location = AV_PAGESIZE;
  range.length = 1;
  
  segmentData = [parentData subdataWithRange:range];
  NSAssert(segmentData == nil, @"segmentData");
  
  // If offset + length is larger than end of file, return nil

  range.location = AV_PAGESIZE - 1;
  range.length = 2;
  
  segmentData = [parentData subdataWithRange:range];
  NSAssert(segmentData == nil, @"segmentData");
  
  return;
}


// This test case pushes the limts of the size of files that can be mapped into memory. It should be
// possible to map a very large number of files into memory, but the virtual memory manager in
// iOS could crash with very large mappings.

+ (void) writeLargeFile:(NSString*)filename numBytes:(int)numBytes
{
  if ([AVFileUtil fileExists:filename]) {
    return;
  }
  
  char *cStr = (char*) [filename UTF8String];
  FILE *fd = fopen(cStr, "wb");
  for (int i=0; i < numBytes; i++) {
    fputc((int)'1', fd);
  }
  fclose(fd);
}

+ (void) DISABLED_testMappingLargeFiles
{
  NSArray *filenames = [NSArray arrayWithObjects:
                        @"large1", @"large2", @"large3", @"large4", @"large5",
                        @"large6", @"large7", @"large8", @"large9", @"large10",
                        nil];
  NSMutableArray *tmpFilenames = [NSMutableArray array];

  NSMutableArray *mappedFileDatas = [NSMutableArray array];

  NSMutableArray *unmappedFileNames = [NSMutableArray array];
  NSMutableArray *unmappedFileDatas = [NSMutableArray array];
  
  for (NSString *filename in filenames) {
    NSString *path = [AVFileUtil getTmpDirPath:filename];
    [tmpFilenames addObject:path];
  }
  
  // Generate 100 megs of data in each file
  
  for (NSString *path in tmpFilenames) {
    // Page = 4K, Meg = 1000K, 100 Megs = 100000K
    int numBytes = 1024 * 1000 * 100;
    NSAssert((numBytes % 1024) == 0, @"numBytes not page sized");
    
    NSLog(@"Writing %@", [path lastPathComponent]);
    [self writeLargeFile:path numBytes:numBytes];
  }

  // Map large 100M files into memory 
  
  for (NSString *path in tmpFilenames) {
    NSLog(@"Mapping %@", [path lastPathComponent]);
    
    NSData *data = [NSData dataWithContentsOfMappedFile:path];
    if (data == nil) {
      NSLog(@"Failed to map %@", [path lastPathComponent]);
      [unmappedFileNames addObject:path];
      //[unmappedFileDatas addObject:data];
      continue;
    }
    [mappedFileDatas addObject:data];
    
    // Wait a few seconds in event loop
    
    NSDate *maxDate = [NSDate dateWithTimeIntervalSinceNow:2];
    [[NSRunLoop currentRunLoop] runUntilDate:maxDate];
  }
  
  // Now walk over all the bytes in the mapping, one mapping at a time.
  // This should bring all the pages into memory by swapping.

  for (NSData *data in mappedFileDatas) {
    NSLog(@"Processing1");

    char *ptr = (char*) [data bytes];
    int len = (int) [data length];
    
    int sum = 0;
    
    for (char *data = ptr; data < (ptr + len); data++) {
      char c = *data;
      sum += c;
    }
    
    NSAssert(sum > 0, @"sum");
    
    // Wait a few seconds in event loop
    
    NSDate *maxDate = [NSDate dateWithTimeIntervalSinceNow:1];
    [[NSRunLoop currentRunLoop] runUntilDate:maxDate];
  }

  // Now walk over all the bytes in the mapping, one mapping at a time.
  // This should bring all the pages into memory by swapping.
  
  for (NSData *data in mappedFileDatas) {
    NSLog(@"Processing2");
    
    char *ptr = (char*) [data bytes];
    int len = (int) [data length];
    
    int sum = 0;
    
    for (char *data = ptr; data < (ptr + len); data++) {
      char c = *data;
      sum += c;
    }
    
    NSAssert(sum > 0, @"sum");
    
    // Wait a few seconds in event loop
    
    NSDate *maxDate = [NSDate dateWithTimeIntervalSinceNow:1];
    [[NSRunLoop currentRunLoop] runUntilDate:maxDate];
  }
  
  // Attempt to map failed memory again
    
  for (NSString *path in unmappedFileNames) {
    NSLog(@"Mapping %@", [path lastPathComponent]);
    
    NSData *data = [NSData dataWithContentsOfMappedFile:path];
    if (data == nil) {
      NSLog(@"Failed to map %@", [path lastPathComponent]);
      continue;
    }
    [unmappedFileDatas addObject:data];
    
    // Wait a few seconds in event loop
    
    NSDate *maxDate = [NSDate dateWithTimeIntervalSinceNow:20];
    [[NSRunLoop currentRunLoop] runUntilDate:maxDate];
  }
  
  // Now walk over all the bytes in the mapping, one mapping at a time.
  // This should bring all the pages into memory by swapping out pages.
  
  for (NSData *data in mappedFileDatas) {
    NSLog(@"Processing3");
    
    char *ptr = (char*) [data bytes];
    int len = (int) [data length];
    
    int sum = 0;
    
    for (char *data = ptr; data < (ptr + len); data++) {
      char c = *data;
      sum += c;
    }
    
    NSAssert(sum > 0, @"sum");
    
    // Wait a few seconds in event loop
    
    NSDate *maxDate = [NSDate dateWithTimeIntervalSinceNow:1];
    [[NSRunLoop currentRunLoop] runUntilDate:maxDate];
  }
  
  // Wait for 5 minutes in event loop
  
  NSDate *maxDate = [NSDate dateWithTimeIntervalSinceNow:(60 * 5)];
  [[NSRunLoop currentRunLoop] runUntilDate:maxDate];
  
  return;
}

// This test pushes the system to the limits of mapped file size using
// 10 meg files. The results of this test indicate that mapped memory
// starts to fail at about 700 megs. So, shoot for about 680 megs to
// provide some 20 megs of wiggle room so that other code will not just
// fail because of a lack of available virtual memory while this 680
// megs of memory is mapped.

+ (void) DISABLED_testMappingLargeFilesWithTenMegFiles
{
  {
	id appDelegate = [[UIApplication sharedApplication] delegate];
	UIWindow *window = [appDelegate window];
	NSAssert(window, @"window");
  window.backgroundColor = [UIColor redColor];
    
  NSDate *maxDate = [NSDate dateWithTimeIntervalSinceNow:1];
  [[NSRunLoop currentRunLoop] runUntilDate:maxDate];
  }
  
  BOOL doWaits = FALSE;
  
//  int targetMegs = 700;
  int targetMegs = 650; // should be safe to map 650 megs without possibility of failure
  int largeSizeMegs = 10;
  //int numFiles = 10 - 1;
  int numFiles = targetMegs / largeSizeMegs;
  
  NSMutableArray *mArr = [NSMutableArray array];
  
  for (int i=0; i < numFiles; i++) {
    NSString *filename = [NSString stringWithFormat:@"large%d", i];
    [mArr addObject:filename];
  }
  
  NSArray *filenames = [NSArray arrayWithArray:mArr];

  NSMutableArray *tmpFilenames = [NSMutableArray array];
  
  NSMutableArray *mappedFileDatas = [NSMutableArray array];
  
  NSMutableArray *unmappedFileNames = [NSMutableArray array];
  NSMutableArray *unmappedFileDatas = [NSMutableArray array];
  
  for (NSString *filename in filenames) {
    NSString *path = [AVFileUtil getTmpDirPath:filename];
    [tmpFilenames addObject:path];
  }
  
  // Generate file that are 10 megabytes each. Note that the
  // file size is in terms of actual bytes
  
  for (NSString *path in tmpFilenames) {
    // 1 meg = 1024 (1K) * 1024
    int numBytes = (1024 * 1024) * largeSizeMegs; // 10 megabytes
    NSAssert((numBytes % 4096) == 0, @"numBytes not page sized");
    
    NSLog(@"Writing %@", [path lastPathComponent]);
    [self writeLargeFile:path numBytes:numBytes];
  }
  
  // Map large files into memory
  
  for (NSString *path in tmpFilenames) {
    NSLog(@"Mapping %@, total %d megs", [path lastPathComponent], (int)([mappedFileDatas count] * largeSizeMegs));
    
    NSData *data = [NSData dataWithContentsOfMappedFile:path];
    if (data == nil) {
      NSLog(@"Failed to map %@", [path lastPathComponent]);
      [unmappedFileNames addObject:path];
      //[unmappedFileDatas addObject:data];
      continue;
    }
    [mappedFileDatas addObject:data];
    
    // Wait a few seconds in event loop
    
    if (doWaits) {
    NSDate *maxDate = [NSDate dateWithTimeIntervalSinceNow:2];
    [[NSRunLoop currentRunLoop] runUntilDate:maxDate];
    }
  }
  
  // Now walk over all the bytes in the mapping, one mapping at a time.
  // This should bring all the pages into memory by swapping.
  
  int numMappedFiles = (int) [mappedFileDatas count];
  
  for (int i=0; i < numMappedFiles; i++) {
    NSString *filename = [tmpFilenames objectAtIndex:i];
    NSData *data = [mappedFileDatas objectAtIndex:i];
    
    NSLog(@"Accessing : %@", [filename lastPathComponent]);
    
    char *ptr = (char*) [data bytes];
    int len = (int) [data length];
    
    int sum = 0;
    
    for (char *data = ptr; data < (ptr + len); data++) {
      char c = *data;
      sum += c;
    }
    
    NSAssert(sum > 0, @"sum");
    
    // Wait a few seconds in event loop
    
    if (doWaits) {
    NSDate *maxDate = [NSDate dateWithTimeIntervalSinceNow:1];
    [[NSRunLoop currentRunLoop] runUntilDate:maxDate];
    }
  }
  
  // Now walk over all the bytes in the mapping, one mapping at a time.
  // This should bring all the pages into memory by swapping.
  
  for (NSData *data in mappedFileDatas) {
    NSLog(@"Processing2");
    
    char *ptr = (char*) [data bytes];
    int len = (int) [data length];
    
    int sum = 0;
    
    for (char *data = ptr; data < (ptr + len); data++) {
      char c = *data;
      sum += c;
    }
    
    NSAssert(sum > 0, @"sum");
    
    // Wait a few seconds in event loop
    
    if (doWaits) {
    NSDate *maxDate = [NSDate dateWithTimeIntervalSinceNow:1];
    [[NSRunLoop currentRunLoop] runUntilDate:maxDate];
    }
  }
  
  // Attempt to map failed memory again
  
  for (NSString *path in unmappedFileNames) {
    NSLog(@"Mapping %@", [path lastPathComponent]);
    
    NSData *data = [NSData dataWithContentsOfMappedFile:path];
    if (data == nil) {
      NSLog(@"Failed to map %@", [path lastPathComponent]);
      continue;
    }
    [unmappedFileDatas addObject:data];
    
    // Wait a few seconds in event loop
    
    if (doWaits) {
    NSDate *maxDate = [NSDate dateWithTimeIntervalSinceNow:1];
    [[NSRunLoop currentRunLoop] runUntilDate:maxDate];
    }
  }
  
  // Now walk over all the bytes in the mapping, one mapping at a time.
  // This should bring all the pages into memory by swapping out pages.
  
  for (NSData *data in mappedFileDatas) {
    NSLog(@"Processing3");
    
    char *ptr = (char*) [data bytes];
    int len = (int) [data length];
    
    int sum = 0;
    
    for (char *data = ptr; data < (ptr + len); data++) {
      char c = *data;
      sum += c;
    }
    
    NSAssert(sum > 0, @"sum");
    
    // Wait a few seconds in event loop
    
    if (doWaits) {
    NSDate *maxDate = [NSDate dateWithTimeIntervalSinceNow:1];
    [[NSRunLoop currentRunLoop] runUntilDate:maxDate];
    }
  }
  
  {
    id appDelegate = [[UIApplication sharedApplication] delegate];
    UIWindow *window = [appDelegate window];
    NSAssert(window, @"window");
    window.backgroundColor = [UIColor greenColor];
    
    NSDate *maxDate = [NSDate dateWithTimeIntervalSinceNow:1];
    [[NSRunLoop currentRunLoop] runUntilDate:maxDate];
  }

  // Wait for 5 minutes in event loop
  
  if (doWaits) {
    NSDate *maxDate = [NSDate dateWithTimeIntervalSinceNow:(60 * 5)];
    [[NSRunLoop currentRunLoop] runUntilDate:maxDate];
  }
  
  return;
}


#endif // USE_SEGMENTED_MMAP

@end
