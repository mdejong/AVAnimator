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

@end
