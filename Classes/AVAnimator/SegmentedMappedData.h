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

@class RefCountedFD;

@interface SegmentedMappedData : NSData
{
  NSString           *m_filePath;
  
  NSMutableArray     *m_mappedDataSegments;
  
  void               *m_mappedData;
  off_t               m_mappedOffset;
  size_t              m_mappedLen;
  
  RefCountedFD       *m_refCountedFD;
}

+ (SegmentedMappedData*) segmentedMappedData:(NSString*)filename;

// Create a series of mapped segment objects. Each segment
// maps a specific range of the file into memory. Note that
// the actual mapping is not created until the bytes pointer
// is accessed for a specific segment.

- (NSArray*) makeSegmentedMappedDataObjects:(NSArray*)segInfo;

// This method will invoke mmap to actually map a segment into a memory buffer.
// If the memory was successfully mapped, then TRUE is returned. Otherwise FALSE.

- (BOOL) mapSegment;

// This method will unmap a currently mapped segment, if
// not currently mapped then a no-op.

- (void) unmapSegment;

// Return the starting address of this specific segment mapping.
// The container will assert if bytes is invoked on it.

- (const void*) bytes;

// For a segment this returns the number of bytes in a segment.
// For the container, this returns the length of the whole file in bytes.

- (NSUInteger) length;

@end
