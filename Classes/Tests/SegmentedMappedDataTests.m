//
//  SegmentedMappedDataTests.m
//
//  Created by Moses DeJong on 1/22/12.
//
//  License terms defined in License.txt.

#import <Foundation/Foundation.h>

#import "AVFileUtil.h"

#import "SegmentedMappedData.h"

@interface SegmentedMappedDataTests : NSObject

@end

#define AV_PAGESIZE 4096

@implementation SegmentedMappedDataTests

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
  NSAssert([parentData retainCount] == 1, @"retainCount");

  NSMutableArray *segInfo = [NSMutableArray array];
  
  NSRange range;
  range.location = 0;
  range.length = [mData length];
  
  NSValue *rangeValue = [NSValue valueWithRange:range];
  [segInfo addObject:rangeValue];
  
  NSArray *segments = [parentData makeSegmentedMappedDataObjects:segInfo];
  NSAssert(segments != nil, @"segments");
  NSAssert([segments count] == 1, @"length");
  
  SegmentedMappedData *segmentData = [segments objectAtIndex:0];
  NSAssert(segmentData, @"segmentData");
  
  // An additional ref is held by the parent mapped data object
  NSAssert([segmentData retainCount] == 2, @"retainCount");
  
  NSAssert([segmentData length] == AV_PAGESIZE, @"mapped data length");
  
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

// Create a file that is two pages long and map with two different segments

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
  NSAssert([parentData retainCount] == 1, @"retainCount");
  
  NSMutableArray *segInfo = [NSMutableArray array];
  
  NSRange range;
  NSValue *rangeValue;
  
  // Segment 1
  
  range.location = 0;
  range.length = AV_PAGESIZE;
  
  rangeValue = [NSValue valueWithRange:range];
  [segInfo addObject:rangeValue];

  // Segment 2
  
  range.location = AV_PAGESIZE;
  range.length = AV_PAGESIZE;
  
  rangeValue = [NSValue valueWithRange:range];
  [segInfo addObject:rangeValue];

  // Make segment objects
  
  NSArray *segments = [parentData makeSegmentedMappedDataObjects:segInfo];
  NSAssert(segments != nil, @"segments");
  NSAssert([segments count] == 2, @"length");
  
  SegmentedMappedData *segmentData1 = [segments objectAtIndex:0];
  NSAssert(segmentData1, @"segmentData1");
  
  // An additional ref is held by the parent mapped data object
  NSAssert([segmentData1 retainCount] == 2, @"retainCount");  
  NSAssert([segmentData1 length] == AV_PAGESIZE, @"mapped data length");

  SegmentedMappedData *segmentData2 = [segments objectAtIndex:1];
  NSAssert(segmentData2, @"segmentData2");
  
  // An additional ref is held by the parent mapped data object
  NSAssert([segmentData2 retainCount] == 2, @"retainCount");  
  NSAssert([segmentData2 length] == AV_PAGESIZE, @"mapped data length");
  
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

// FIXME: test map when already mapped (no-op)

@end
