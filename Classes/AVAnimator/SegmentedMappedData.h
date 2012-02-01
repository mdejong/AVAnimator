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
// a specific mapping until the data for a specific segment is needed.
// The segment objets support and explicit mapSegment/unmapSegment API
// that is used to map the segment into memory before use of the data.

#import <Foundation/Foundation.h>

@class RefCountedFD;

@interface SegmentedMappedData : NSData
{
  NSString           *m_filePath;
  
  // This pointer is that starting point where the OS
  // maps the start of a page into memory.
  
  void               *m_mappedData;
  
  // A specific segment returns a pointer and
  // length in terms of the byte offset where
  // a specific segment was indicated. These
  // are returned by the bytes and length methods.
  
  off_t               m_mappedOffset;
  size_t              m_mappedLen;
  
  // In addition, the actual page starting offset
  // and the actual length of the mapping are
  // stored. If the mapping offset does not
  // begin on a page bound, then these values+  // Indicate the OS level values.
    
  off_t               m_mappedOSOffset;
  size_t              m_mappedOSLen;
  
  RefCountedFD       *m_refCountedFD;
  
  BOOL isContainer;
}

@property (nonatomic, readonly) off_t mappedOffset;
@property (nonatomic, readonly) size_t mappedLen;

@property (nonatomic, readonly) off_t mappedOSOffset;
@property (nonatomic, readonly) size_t mappedOSLen;


+ (SegmentedMappedData*) segmentedMappedData:(NSString*)filename;

// This API will create a mapped segment subrange. A segment can be mapped
// and unmapped as needed and will automatically be unmapped when the last
// ref is dropped. Note that the actual mapping is not created until the
// mapSegment API is invoked on a specific segment.

- (SegmentedMappedData*) subdataWithRange:(NSRange)range;

// This method will invoke mmap to actually map a segment into a memory buffer.
// If the memory was successfully mapped, then TRUE is returned. Otherwise FALSE.

- (BOOL) mapSegment;

// This method will unmap a currently mapped segment, if
// not currently mapped then a no-op.

- (void) unmapSegment;

// Return the starting address of this specific segment mapping.
// The container will assert if bytes is invoked on it.
// A segment will assert if mapSegment has not been invoked.

- (const void*) bytes;

// For a segment this returns the number of bytes in a segment.
// For the container, this returns the length of the whole file in bytes.

- (NSUInteger) length;

@end
