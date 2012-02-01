//
//  Created by Moses DeJong on 1/22/12.
//
//  License terms defined in License.txt.

#import "SegmentedMappedData.h"
#import "AutoPropertyRelease.h"

#include <sys/mman.h>
#include <fcntl.h>

#define SM_PAGESIZE 4096

// This private class is used to implement a ref counted
// file descriptor container. The held file descriptor
// is closed once all the mapped objects have been released.

@interface RefCountedFD : NSObject
{
@public
  int                 m_fd;
}

+ (RefCountedFD*) refCountedFD:(int)fd;

- (void) dealloc;

@end

@implementation RefCountedFD

+ (RefCountedFD*) refCountedFD:(int)fd
{
  RefCountedFD *obj = [[RefCountedFD alloc] init];
  obj->m_fd = fd;
  return [obj autorelease];
}

- (void) dealloc
{
  int close_result = close(m_fd);
  NSAssert(close_result == 0, @"close_result");
  [super dealloc];
}

@end // RefCountedFD


// SegmentedMappedData Private API

@interface SegmentedMappedData ()

@property (nonatomic, copy)   NSString *filePath;

@property (nonatomic, retain) RefCountedFD *refCountedFD;

// Create an object that will map a specific segment into memory.
// The object stores the file offset, the FD, the offset, and the length in bytes.

+ (SegmentedMappedData*) segmentedMappedDataWithDeferredMapping:(NSString*)filePath
                                                   refCountedFD:(RefCountedFD*)refCountedFD
                                                         offset:(off_t)offset
                                                            len:(size_t)len;

@end

// SegmentedMappedData implementation

@implementation SegmentedMappedData

@synthesize mappedDataSegments = m_mappedDataSegments;
@synthesize filePath = m_filePath;
@synthesize refCountedFD = m_refCountedFD;

@synthesize mappedOffset = m_mappedOffset;
@synthesize mappedLen = m_mappedLen;

@synthesize mappedOSOffset = m_mappedOSOffset;
@synthesize mappedOSLen = m_mappedOSLen;

+ (SegmentedMappedData*) segmentedMappedData:(NSString*)filePath
{
  // Query the file length for the container, will be returned by length getter.
  // If the file does not exist, then nil is returned.
  NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:filePath error:nil];
  if (attrs == nil) {
    // File does not exist or can't be accessed
    return nil;
  }
  unsigned long long fileSize = [attrs fileSize];
  size_t fileSizeT = (size_t) fileSize;
  NSAssert(fileSize == fileSizeT, @"assignment from unsigned long long to size_t lost bits");
  
  // The length of the file can't be zero bytes
  
  if (fileSizeT == 0) {
    return nil;
  }
  
  // Double check that we can actually open the file and read 1 byte of data from it.
  
  char aByte[1];
  const char *cStr = [filePath UTF8String];
  FILE* fp = fopen(cStr, "rb");
  if (fp) {
    int numRead = fread(&aByte[0], 1, 1, fp);
    fclose(fp);
    if (numRead != 1) {
      return nil;
    }
  } else {
    return nil;
  }
  
  SegmentedMappedData *obj = [[SegmentedMappedData alloc] init];
  obj.filePath = filePath;
  obj->m_mappedLen = fileSizeT;  
  return [obj autorelease];
}

+ (SegmentedMappedData*) segmentedMappedDataWithDeferredMapping:(NSString*)filePath
                                                   refCountedFD:(RefCountedFD*)refCountedFD
                                                         offset:(off_t)offset
                                                            len:(size_t)len
{
  SegmentedMappedData *obj = [[SegmentedMappedData alloc] init];

  NSAssert(offset >= 0, @"offset");
  obj->m_mappedOffset = offset;

  NSAssert(len > 0, @"len");
  obj->m_mappedLen = len;

  NSAssert(filePath, @"filePath");
  obj.filePath = filePath;
  
  NSAssert(refCountedFD, @"refCountedFD");
  obj.refCountedFD = refCountedFD;

  off_t osOffset = offset % SM_PAGESIZE;
  obj->m_mappedOSOffset = offset - osOffset;

  // Calculate number of bytes in mapping in terms of whole pages
  
  size_t osLength = len + osOffset;
  
  size_t offsetToPageBound = SM_PAGESIZE - (osLength % SM_PAGESIZE);
  if (offsetToPageBound == SM_PAGESIZE) {
    offsetToPageBound = 0;
  }
  if (offsetToPageBound > 0) {
    osLength += offsetToPageBound;
  }
  
  obj->m_mappedOSLen = osLength;
  
  return [obj autorelease];
}

- (void) dealloc
{
  if (self->m_mappedData) {
    // This branch will only be taken in a mapped segment object after the parent
    // has been deallocated.
    
    [self unmapSegment];
    NSAssert(self->m_mappedData == NULL, @"m_mappedData");
  }
  
  [AutoPropertyRelease releaseProperties:self thisClass:SegmentedMappedData.class];
  [super dealloc];
}

- (const void*) bytes
{
  // FIXME: should bytes implicitly attempt to map and return nil if there
  // was a failure to map? Unclear if existing code expects bytes to
  // return the correct pointer, might need to add mapSegment but
  // not really clear on how to detect error condition?
  
  //if (self->m_mappedData == NULL) {
  //  BOOL worked = [self mapSegment];
  //  NSAssert(worked, @"");
  //}
  
  NSAssert(self->m_mappedData != NULL, @"data not mapped");
  
  NSAssert(self->m_mappedOffset >= self->m_mappedOSOffset, @"os offset must be same or smaller than result offset");
  NSUInteger offset = (self->m_mappedOffset - self->m_mappedOSOffset);
  
  if (offset > 0) {
    char *ptr = (char*)self->m_mappedData;
    return ptr + offset;
  } else {
    return self->m_mappedData;
  }
}

// Note that it is perfectly fine to query the mapping length even if the file range
// has not actually be mapped into memory at this point.

- (NSUInteger) length
{
  return self->m_mappedLen;
}

- (BOOL) mapSegment
{
  if (self->m_mappedData != NULL) {
    // Already mapped
    return TRUE;
  }
  
  int fd = self.refCountedFD->m_fd;
  off_t offset = self->m_mappedOSOffset;
  size_t len = self->m_mappedOSLen;
  
  NSAssert((offset % SM_PAGESIZE) == 0, @"offset");
  NSAssert((len % SM_PAGESIZE) == 0, @"len");
  
  void *mappedData = mmap(NULL, len, PROT_READ, MAP_FILE | MAP_SHARED, fd, offset);
  
  if (mappedData == MAP_FAILED) {
    int errnoVal = errno;
    
    // Check for known fatal errors
    
    if (errnoVal == EACCES) {
      NSAssert(FALSE, @"munmap result EACCES : file not opened for reading");
    } else if (errnoVal == EBADF) {
      NSAssert(FALSE, @"munmap result EBADF : bad file descriptor");
    } else if (errnoVal == EINVAL) {
      NSAssert(FALSE, @"munmap result EINVAL");
    } else if (errnoVal == ENODEV) {
      NSAssert(FALSE, @"munmap result ENODEV : page does not support mapping");
    } else if (errnoVal == ENXIO) {
      NSAssert(FALSE, @"munmap result ENXIO : invalid addresses");
    } else if (errnoVal == EOVERFLOW) {
      NSAssert(FALSE, @"munmap result EOVERFLOW : addresses exceed the maximum offset");
    }
    
    // Note that ENOMEM is not checked here since it is actually likely to happen
    // due to running out of memory that could be mapped.
    
    NSAssert(self->m_mappedData == NULL, @"m_mappedData");
    
    return FALSE;
  }
  
  self->m_mappedData = mappedData;
  NSAssert(self->m_mappedData != NULL, @"m_mappedData");
  return TRUE;
}

- (void) unmapSegment
{
  // Can't be invoked on container data object

  NSAssert(self.mappedDataSegments == nil, @"unmapSegment can't be invoked on container");
  
  if (self->m_mappedData == NULL) {
    // Already unmapped, no-op
    return;
  }

  size_t len = self->m_mappedOSLen;
  int result = munmap(self->m_mappedData, len);
  if (result != 0) {
    int errnoVal = errno;
    if (errnoVal == EINVAL) {
      NSAssert(FALSE, @"munmap result EINVAL");      
    }
    NSAssert(result == 0, @"munmap result");
  }
  
  self->m_mappedData = NULL;
  
  return;
}

- (NSMutableArray*) makeSegmentedMappedDataObjects:(NSArray*)segInfo
{
  self.mappedDataSegments = [NSMutableArray array];
  NSAssert(self.mappedDataSegments, @"mappedDataSegments");
  self.refCountedFD = nil;

  // Open the file once, then keep the open file descriptor around so that each call
  // to mmap() need not also open the file descriptor.
  
  const char *cStr = [self.filePath UTF8String];
  int fd = open(cStr, O_RDONLY);
  if (fd == -1) {
    return nil;
  }
  
  RefCountedFD *rcFD = [RefCountedFD refCountedFD:fd];
  self.refCountedFD = rcFD;
  
  for (NSValue *value in segInfo) {
    NSRange range = [value rangeValue];
    
    NSUInteger offset = range.location;
    NSUInteger len = range.length;

    // Check for no-op case where null is added to the segments array
    
    if (offset == 0 && len == 0) {
      [self.mappedDataSegments addObject:[NSNull null]];
      continue;
    }
    NSAssert(len > 0, @"len");
    
    SegmentedMappedData *seg = [SegmentedMappedData segmentedMappedDataWithDeferredMapping:self.filePath
                                                                              refCountedFD:rcFD
                                                                                    offset:offset
                                                                                       len:len];
    [self.mappedDataSegments addObject:seg];
  }

  return self.mappedDataSegments;
}

- (NSString*) description
{
  NSString *name = self.filePath.lastPathComponent;
  NSString *formatted = [NSString stringWithFormat:@"%@: (%d %d) [%d %d] at %p",
                         name,
                         (int)m_mappedOffset, (int)m_mappedLen,
                         (int)m_mappedOSOffset, (int)m_mappedOSLen,
                         m_mappedData];
  return formatted;
}

@end
