//
//  Created by Moses DeJong on 1/22/12.
//
//  License terms defined in License.txt.
//
// A segmented mapped data object extends NSData so that the lifetime of a set
// of mapped file segments can be managed as a group of objects. If the container
// SegmentedMappedData is deallocated, then each segmented mapping it contains
// it deallocated assuming there are no other active references.
//
// Unlike a plain mapped file, a SegmentedMappedData will put off creating
// a specific mapping until the data for a specific segment is accessed.

#import <Foundation/Foundation.h>

@interface SegmentedMappedData : NSData
{
  NSString           *m_filePath;
  
  NSMutableArray     *m_mappedDataSegments;

  void               *m_mappedData;
  size_t              m_mappedLen;
}

+ (SegmentedMappedData*) segmentedMappedData:(NSString*)filename;

// Create a series of mapped segments, each represented by
// different NSData objects.

- (NSArray*) makeSegmentedMappedDataObjects:(NSArray*)segInfo;

// These standard accessors for NSData are defined

- (const void*) bytes;   
- (NSUInteger) length;

@end
