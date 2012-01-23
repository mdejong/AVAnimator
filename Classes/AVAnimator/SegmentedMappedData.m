//
//  Created by Moses DeJong on 1/22/12.
//
//  License terms defined in License.txt.

#import "SegmentedMappedData.h"
#import "AutoPropertyRelease.h"

#include <sys/mman.h>

@interface SegmentedMappedData ()

@property (nonatomic, retain) NSMutableArray *mappedDataSegments;

@property (nonatomic, copy)   NSString *filePath;

// Create an object that maps a specific segment in the file.

+ (SegmentedMappedData*) segmentedMappedDataWithMapping:(NSString*)filePath
                                              mappedPtr:(void*)mappedPtr
                                                   size:(size_t)size;

- (void) unmapSegment;

@end


@implementation SegmentedMappedData

@synthesize mappedDataSegments = m_mappedDataSegments;
@synthesize filePath = m_filePath;

+ (SegmentedMappedData*) segmentedMappedData:(NSString*)filePath
{
  SegmentedMappedData *obj = [[SegmentedMappedData alloc] init];
  obj.filePath = filePath;
  return [obj autorelease];
}

+ (SegmentedMappedData*) segmentedMappedDataWithMapping:(NSString*)filePath
                                              mappedPtr:(void*)mappedPtr
                                                   size:(size_t)size
{
  SegmentedMappedData *obj = [[SegmentedMappedData alloc] init];
  obj.filePath = filePath;
  NSAssert(mappedPtr, @"mappedPtr");
  obj->m_mappedData = mappedPtr;
  NSAssert(size > 0, @"size");
  obj->m_mappedLen = size;
  return [obj autorelease];
}

- (void) dealloc
{
  if (self->m_mappedData) {
    // This branch will only be taken in a mapped segment object after the parent
    // has been deallocated.
    
    [self unmapSegment];
  }
  
  [AutoPropertyRelease releaseProperties:self thisClass:SegmentedMappedData.class];
  [super dealloc];
}

- (const void*) bytes
{
  NSAssert(self->m_mappedData != NULL, @"data not mapped");
  return self->m_mappedData;
}

- (NSUInteger) length
{
  NSAssert(self->m_mappedData != NULL, @"data not mapped");
  return self->m_mappedLen;
}

- (SegmentedMappedData*) mapSegment:(int)fd
                             offset:(off_t)offset
                                len:(size_t)len
{
  // FIXME: a specific segment should not be mapped until the data for that segment is accessed?
  // This means that the FILE* needs to be held onto so that the fd is valid during the lifetime
  // of the mapped segment.
  
  void *mappedData = mmap(NULL, len, PROT_READ, MAP_FILE | MAP_SHARED, fd, offset);
  
  if (mappedData == NULL) {
    return nil;
  }
  
  SegmentedMappedData *obj = [SegmentedMappedData segmentedMappedDataWithMapping:self.filePath mappedPtr:mappedData size:len];
  
  return obj;
}
          
- (void) unmapSegment
{
  // Can't be invoked for a container or an unmapped segment
  NSAssert(m_mappedData, @"mappedData");

  int result = munmap(self->m_mappedData, self->m_mappedLen);
  NSAssert(result == 0, @"munmap result");
  
  self->m_mappedData = NULL;
  
  return;
}

- (NSArray*) makeSegmentedMappedDataObjects:(NSArray*)segInfo
{
  self.mappedDataSegments = [NSMutableArray array];
  NSAssert(self.mappedDataSegments, @"mappedDataSegments");
  
  NSArray *mapped = nil;
  
  const char *cStr = [self.filePath UTF8String];
  FILE* fp = fopen(cStr, "rb");
  if (fp == NULL) {
    return nil;
  }
  
  int fd = fileno(fp);
  
  for (NSValue *value in segInfo) {
    NSRange range = [value rangeValue];
    
    NSUInteger offset = range.location;
    NSUInteger len = range.length;

    SegmentedMappedData *seg = [self mapSegment:fd offset:offset len:len];
    if (seg == nil) {
      // Mapping a specific region into memory failed.
      
      goto cleanup;
    }

    [self.mappedDataSegments addObject:seg];
  }

  mapped = self.mappedDataSegments;
  
cleanup:
  {
  int fclose_result = fclose(fp);
  NSAssert(fclose_result == 0, @"fclose_result");
  }
  return mapped;
}

@end
