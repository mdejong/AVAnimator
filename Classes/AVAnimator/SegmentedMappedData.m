//
//  Created by Moses DeJong on 1/22/12.
//
//  License terms defined in License.txt.

#import "SegmentedMappedData.h"

#include <sys/mman.h>
#include <fcntl.h>

#define SM_PAGESIZE ((int)getpagesize())

// This private class is used to implement a ref counted
// file descriptor container. The held file descriptor
// is closed once all the mapped objects have been released.

@interface RefCountedFD : NSObject
{
@public
  int                 m_fd;
  BOOL                m_closeFileFlag;
}

+ (RefCountedFD*) refCountedFD:(int)fd;

- (void) dealloc;

@end

@implementation RefCountedFD

+ (RefCountedFD*) refCountedFD:(int)fd
{
  RefCountedFD *obj = [[RefCountedFD alloc] init];
  obj->m_fd = fd;
  obj->m_closeFileFlag = TRUE;
#if __has_feature(objc_arc)
  // ARC enabled
  return obj;
#else
  // ARC disabled
  return [obj autorelease];
#endif
}

+ (RefCountedFD*) refCountedFDWithCloseFlag:(int)fd
                                  closeFlag:(BOOL)closeFlag
{
  RefCountedFD *obj = [RefCountedFD refCountedFD:fd];
  obj->m_closeFileFlag = closeFlag;
  return obj;
}

- (void) dealloc
{
  if (m_closeFileFlag) {
    int close_result = close(m_fd);
    NSAssert(close_result == 0, @"close_result");
  }
  
#if __has_feature(objc_arc)
  // ARC enabled
#else
  // ARC disabled
  [super dealloc];
#endif
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
  // Open the file once, then keep the open file descriptor around so that each call
  // to mmap() need not also open the file descriptor.
  
  char aByte[1];
  const char *cStr = [filePath UTF8String];
  int fd = open(cStr, O_RDONLY);
  if (fd == -1) {
    return nil;
  } else {
    ssize_t numRead = read(fd, &aByte[0], 1);
    if (numRead != 1) {
      close(fd);
      return nil;
    }
  }
  
  RefCountedFD *rcFD = [RefCountedFD refCountedFD:fd];
  
  // FIXME: examine use case for F_NOCACHE, since it seems to avoid eviction of other data that
  // is already cached. The F_RDAHEAD seems useful in any case.
  
  //fcntl(fd, F_NOCACHE, 1);
  //fcntl(fd, F_RDAHEAD, 1);
  
  SegmentedMappedData *obj = [[SegmentedMappedData alloc] init];
  obj.filePath = filePath;
  obj.refCountedFD = rcFD;
  obj->m_mappedLen = fileSizeT;
  obj->isContainer = TRUE;
  
#if __has_feature(objc_arc)
  // ARC enabled
  return obj;
#else
  // ARC disabled
  return [obj autorelease];
#endif
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
 
#if __has_feature(objc_arc)
  // ARC enabled
  return obj;
#else
  // ARC disabled
  return [obj autorelease];
#endif
}

// Create a writeable mapped memory segment at the given offset and with the
// given length.

+ (SegmentedMappedData*) segmentedMappedDataWithWriteMapping:(NSString*)filePath
                                                        file:(FILE*)file
                                                      offset:(off_t)offset
                                                         len:(size_t)len
{
  NSAssert(file, @"file");
  int fd = fileno(file);
  RefCountedFD *rcFD = [RefCountedFD refCountedFDWithCloseFlag:fd closeFlag:FALSE];
  
  SegmentedMappedData *obj = [SegmentedMappedData segmentedMappedDataWithDeferredMapping:filePath
                                                                            refCountedFD:rcFD
                                                                                  offset:offset
                                                                                     len:len];
  obj->writeMapping = TRUE;
  
  return obj;
}

// The dealloc method is invoked to release each segment of mapped memory in a larger
// file. This dealloc method avoids using AutoPropertyRelease since it is less optimal
// than directly releasing the retained objects.

- (void) dealloc
{
  if (self->m_mappedData) {
    // This branch will only be taken in a mapped segment object after the parent
    // has been deallocated.
    
    //NSLog(@"unmapSegment obj %p on dealloc : %@", self, [self description]);
    
    [self unmapSegment];
  }
  
  self.filePath = nil;
  self.refCountedFD = nil;
  
#if __has_feature(objc_arc)
  // ARC enabled
#else
  // ARC disabled
  [super dealloc];
#endif
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
  NSAssert(isContainer == FALSE, @"mapSegment can't be invoked on container");
  
  if (self->m_mappedData != NULL) {
    // Already mapped
    return TRUE;
  }
  
  int fd = self.refCountedFD->m_fd;
  off_t offset = self->m_mappedOSOffset;
  size_t len = self->m_mappedOSLen;
  
  NSAssert((offset % SM_PAGESIZE) == 0, @"offset");
  NSAssert((len % SM_PAGESIZE) == 0, @"len");
  
  int protection;
  int flags;
  
  if (writeMapping == FALSE) {
    // Normal read only shared mapping
    protection = PROT_READ;
    flags = MAP_FILE | MAP_SHARED;
  } else {
    // Special purpose write only mapping, shared indicates that
    // another process can read the result of the mapped write.
    protection = PROT_READ | PROT_WRITE;
    flags = MAP_FILE | MAP_SHARED | MAP_NOCACHE;
  }
  
  void *mappedData = mmap(NULL, len, protection, flags, fd, offset);
  
  if (mappedData == MAP_FAILED) {
    int errnoVal = errno;
    
    // Check for known fatal errors
    
    if (errnoVal == EACCES) {
      NSAssert(FALSE, @"mmap result EACCES : file not opened for reading or writing");
    } else if (errnoVal == EBADF) {
      NSAssert(FALSE, @"mmap result EBADF : bad file descriptor");
    } else if (errnoVal == EINVAL) {
      NSAssert(FALSE, @"mmap result EINVAL");
    } else if (errnoVal == ENODEV) {
      NSAssert(FALSE, @"mmap result ENODEV : page does not support mapping");
    } else if (errnoVal == ENXIO) {
      NSAssert(FALSE, @"mmap result ENXIO : invalid addresses");
    } else if (errnoVal == EOVERFLOW) {
      NSAssert(FALSE, @"mmap result EOVERFLOW : addresses exceed the maximum offset");
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

  NSAssert(isContainer == FALSE, @"unmapSegment can't be invoked on container");
  
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

- (NSData *)subdataWithRange:(NSRange)range
{
  NSAssert(isContainer == TRUE, @"subdataWithRange can only be invoked on container");
  
  NSAssert(m_refCountedFD, @"refCountedFD");
  
  NSUInteger offset = range.location;
  NSUInteger len = range.length;
  NSUInteger lastByteOffset = offset + len;
  
  if ((len == 0) || (lastByteOffset > m_mappedLen)) {
    return nil;
  }
  
  SegmentedMappedData *seg = [SegmentedMappedData segmentedMappedDataWithDeferredMapping:self.filePath
                                                                            refCountedFD:self.refCountedFD
                                                                                  offset:offset
                                                                                     len:len];
  
  return seg;
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

// Overload impl of copy so that a segmented mapped data is simply retained when
// referenced by a copy property.

- (id) copyWithZone:(NSZone*)zone
{
#if __has_feature(objc_arc)
  // ARC enabled
  return self;
#else
  // ARC disabled
  return [self retain];
#endif
}

@end
