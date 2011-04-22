//
//  LZMAExtractor.h
//  lzmaSDK
//
//  Created by Brian Chaikelson on 11/19/09.
//  Copyright 2009 __MyCompanyName__. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface LZMAExtractor : NSObject {	
}

// Extract all the contents of a .7z archive into the indicated temp dir
// and return an array of the fully qualified filenames.

+ (NSArray*) extract7zArchive:(NSString*)archivePath
                   tmpDirName:(NSString*)tmpDirName;

// Extract just one entry from an archive and save it at the
// path indicated by outPath.

+ (BOOL) extractArchiveEntry:(NSString*)archivePath
                archiveEntry:(NSString*)archiveEntry
                     outPath:(NSString*)outPath;

@end

