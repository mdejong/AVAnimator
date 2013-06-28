//
//  MutableAttrString.h
//  Created by Moses DeJong on 1/1/10.
//
//  License terms defined in License.txt.
//
// A simple wrapper class that contains a CFMutableAttributedStringRef for use with CoreText.

#import <Foundation/Foundation.h>
#import <CoreText/CoreText.h>

@interface MutableAttrString : NSObject

// This pointer is to a C attr string object

@property (nonatomic, assign) CFMutableAttributedStringRef attrString;

// This is the range of the entire attributed string. This value is
// only valid after doneAppendingText has been invoked.

@property (nonatomic, assign) CFRange stringRange;

// Each of the following properties are reset to the default value by resetDefaults.

// The current text color.

@property (nonatomic, assign) CGColorRef color;

// The current text bold property. This property defaults to FALSE and must be
// explicitly set to TRUE. Note that this method will use the bold font only
// in the case where the self.font value is the default font.

@property (nonatomic, assign) BOOL bold;

// The current text font. This property defaults to the value indicated in setFont.
// If a specific font is needed for a specific word, then this font property
// should be set before a call to appendText.

@property (nonatomic, assign) CTFontRef font;

// contructor

+ (MutableAttrString*) mutableAttrString;

// Set the default font properties that will be used for plain and bold font types.
// Note that this method must be invoked before strings are appended with appendText.

- (void) setDefaults:(CGColorRef)textColor
            fontSize:(NSUInteger)fontSize
       plainFontName:(NSString*)plainFontName
        boldFontName:(NSString*)boldFontName;

// This method is used to reset the properties related to text rendering to the
// default values. The default values are defined by the initial settings passed
// to the setFont method. Render logic will invoke resetDefaults to ensure that
// the next string appended to the attr string will have the default properties.

- (void) resetDefaults;

// Append a string or characters with markup attributes defined by the current
// properties.

- (void) appendText:(NSString*)string;

// This method must be invoked after all textual elements have been appended.

- (void) doneAppendingText;

// Measure the height required to display the attr string given a known width.
// This logic returns a height without an upper bound. The measurement is always
// in terms of whole pixels. Be aware that this method cannot be
// safely invoked on a secondary thread since this portion of
// CoreText is not thread safe. This logic must be synced to
// the main thread.

- (NSUInteger) measureHeightForWidth:(NSUInteger)width;

// Use CoreText to render rich text into a static bounding box
// of the given context. Be aware that this method cannot be
// safely invoked on a secondary thread since this portion of
// CoreText is not thread safe. This logic must be synced to
// the main thread.

- (void) render:(CGContextRef)bitmapContext
         bounds:(CGRect)bounds;

@end
