//
//  MutableAttrString.m
//  Created by Moses DeJong on 1/1/10.
//
//  License terms defined in License.txt.
//
// A simple wrapper class that contains a CFMutableAttributedStringRef for use with CoreText.

// FIXME: add support for HTML https://github.com/johnezang/NSAttributedString-Additions-for-HTML

#import "MutableAttrString.h"

#define LOGGING 0

/*============================================================================
 PRIVATE API DECLARATION
 =============================================================================*/

@interface MutableAttrString ()

// This is the current length of the string in terms of characters

@property (nonatomic, assign) NSUInteger length;

// The plain font applied to all the text in the string

@property (nonatomic, assign) CTFontRef plainTextFont;

// The bold font applied to any bold element in the string

@property (nonatomic, assign) CTFontRef boldTextFont;

// This property holds the default text color

@property (nonatomic, assign) CGColorRef defaultTextColor;

// Is set to TRUE after doneAppendingText has been invoked.
// Note that this is used to ensure doneAppendingText is
// invoked before a render is done, since it is critical
// to getthing the font measure height correct.

@property (nonatomic, assign) BOOL isDoneAppendingText;

- (void) applyParagraphAttributes:(CFMutableAttributedStringRef)mAttributedString;

@end

@implementation MutableAttrString

@synthesize attrString = m_attrString;
@synthesize stringRange = m_stringRange;
@synthesize length = m_length;

@synthesize plainTextFont = m_plainTextFont;
@synthesize boldTextFont = m_boldTextFont;

@synthesize defaultTextColor = m_defaultTextColor;

@synthesize color = m_color;
@synthesize bold = m_bold;
@synthesize font = m_font;
@synthesize isDoneAppendingText = m_isDoneAppendingText;

+ (MutableAttrString*) mutableAttrString
{
  MutableAttrString *obj = [[MutableAttrString alloc] init];
  CFMutableAttributedStringRef ref = CFAttributedStringCreateMutable(kCFAllocatorDefault, 0);
  NSAssert(ref, @"CFAttributedStringCreateMutable() failed");
  obj->m_attrString = ref;
  
#if __has_feature(objc_arc)
  return obj;
#else
  return [obj autorelease];
#endif // objc_arc
}

- (void) dealloc
{
  CFMutableAttributedStringRef attrString = self->m_attrString;
  self.attrString = NULL;
  CFRelease(attrString);
  
  // setter will release the held ref
  self.font = NULL;

  CTFontRef font;
  
  font = self.plainTextFont;
  self.plainTextFont = NULL;
  CFRelease(font);

  font = self.boldTextFont;
  self.boldTextFont = NULL;
  CFRelease(font);

  // setter will release the held ref
  self.defaultTextColor = NULL;

  // setter will release the held ref
  self.color = NULL;
  
#if __has_feature(objc_arc)
#else
  [super dealloc];
#endif // objc_arc
}

- (void) appendText:(NSString*)string
{
  @autoreleasepool {
  
  NSAssert(self.isDoneAppendingText == FALSE, @"isDoneAppendingText");
    
  if (string == nil) {
    // Append of nil is a no-op as long as we have checked the isDoneAppendingText flag
    return;
  }
  
  int indexEndBefore = (int) [self length];
  
#if __has_feature(objc_arc)
  CFStringRef cfStr = (__bridge CFStringRef)string;
#else
  CFStringRef cfStr = (CFStringRef)string;
#endif // objc_arc
  
  CFMutableAttributedStringRef attrString = self.attrString;
  CFAttributedStringReplaceString(attrString, CFRangeMake([self length], 0), cfStr);
  
  self.length = indexEndBefore + [string length];
  int indexEndAfter = (int) self.length;
  
  CFRange range = CFRangeMake(indexEndBefore, indexEndAfter - indexEndBefore);
  
  // Note that there seems to be a memory management issue with ref counting
  // of the 4th argument to CFAttributedStringSetAttribute. Instead, collect
  // all the arguments into a dictionary and pass via CFAttributedStringSetAttributes.
  
  // Text color
  
  CGColorRef colorRef = self.color;
  NSAssert(colorRef, @"self.color");
  //CFAttributedStringSetAttribute(attrString, range, kCTForegroundColorAttributeName, colorRef);
  
  // Font
  
  CTFontRef font = self.font;
  NSAssert(font, @"self.font");
  if (self.bold && (self.font == self.plainTextFont)) {
    font = self.boldTextFont;
    NSAssert(font, @"self.boldTextFont");
  }
  
  //CFAttributedStringSetAttribute(attrString, range, kCTFontAttributeName, font);
  
  CFStringRef keys[] = { kCTForegroundColorAttributeName, kCTFontAttributeName };
  CFTypeRef values[] = { colorRef, font };
    
  CFDictionaryRef attrValues = CFDictionaryCreate(kCFAllocatorDefault,
                                                    (const void**)&keys,
                                                    (const void**)&values,
                                                    sizeof(keys) / sizeof(keys[0]),
                                                    &kCFTypeDictionaryKeyCallBacks,
                                                    &kCFTypeDictionaryValueCallBacks);
  BOOL clearOtherAttributes = TRUE;
    
  CFAttributedStringSetAttributes(attrString, range, attrValues, (Boolean)clearOtherAttributes);
  CFRelease(attrValues);
    
  if (LOGGING) {
#if __has_feature(objc_arc)
    NSString *description = [(__bridge NSAttributedString*)attrString description];
#else
    NSString *description = [(NSAttributedString*)attrString description];
#endif // objc_arc
    
    NSLog(@"post appendText (%d) : \"%@\"", (int)[self length], description);
  }
  
  } // @autoreleasepool

  return;
}

// This method must be invoked after all textual elements have been appended.

- (void) doneAppendingText
{
  NSAssert(self.isDoneAppendingText == FALSE, @"isDoneAppendingText");
  
  CFMutableAttributedStringRef attrString = self.attrString;
  
  [self applyParagraphAttributes:attrString];
  
  self.isDoneAppendingText = TRUE;
  
  if (LOGGING) {
#if __has_feature(objc_arc)
    NSString *description = [(__bridge NSAttributedString*)attrString description];
#else
    NSString *description = [(NSAttributedString*)attrString description];
#endif // objc_arc
    NSLog(@"post doneAppendingText (%d) : \"%@\"", (int)[self length], description);
  }
  
  return;
}

// When you create an attributed string the default paragraph style has a leading 
// of 0.0. Create a paragraph style that will set the line adjustment equal to
// the leading value of the font. This logic will ensure that the measured
// height for a given paragraph of attributed text will be accurate wrt the font.

- (void) applyParagraphAttributes:(CFMutableAttributedStringRef)mAttributedString
{
  CGFloat leading = CTFontGetLeading(self.plainTextFont);
  
  CTParagraphStyleSetting paragraphSettings[1] = {
    kCTParagraphStyleSpecifierLineSpacingAdjustment, sizeof (CGFloat), &leading
  };
  
  CTParagraphStyleRef  paragraphStyle = CTParagraphStyleCreate(paragraphSettings, 1);
  
  CFRange textRange = CFRangeMake(0, [self length]);
  
  // possible memory leak with CFAttributedStringSetAttribute() 4th argument
  //CFAttributedStringSetAttribute(mAttributedString, textRange, kCTParagraphStyleAttributeName, paragraphStyle);
  
  CFStringRef keys[] = { kCTParagraphStyleAttributeName };
  CFTypeRef values[] = { paragraphStyle };
  
  CFDictionaryRef attrValues = CFDictionaryCreate(kCFAllocatorDefault,
                                                  (const void**)&keys,
                                                  (const void**)&values,
                                                  sizeof(keys) / sizeof(keys[0]),
                                                  &kCFTypeDictionaryKeyCallBacks,
                                                  &kCFTypeDictionaryValueCallBacks);
  
  BOOL clearOtherAttributes = FALSE;
  CFAttributedStringSetAttributes(mAttributedString, textRange, attrValues, (Boolean)clearOtherAttributes);
  CFRelease(attrValues);
  
  CFRelease(paragraphStyle);
  
  self.stringRange = textRange;
  
  return;
}

// Measure the height required to display the attr string given a known width.
// This logic returns a height without an upper bound. Not thread safe!

- (NSUInteger) measureHeightForWidth:(NSUInteger)width
{
  NSAssert(self.isDoneAppendingText == TRUE, @"isDoneAppendingText");
  
  NSAssert(self.attrString, @"attrString");
  
  CFMutableAttributedStringRef attrString = self.attrString;
  CFRange stringRange = self.stringRange;
  
  CGFloat measuredHeight = 1.0f;
  
  // Create the framesetter with the attributed string.
  
  CTFramesetterRef framesetter = CTFramesetterCreateWithAttributedString(attrString);
  
  if (framesetter) {
    CFRange fitRange;
    CGSize constraints = CGSizeMake(width, CGFLOAT_MAX); // width, height : CGFLOAT_MAX indicates unconstrained
    
    CGSize fontMeasureFrameSize = CTFramesetterSuggestFrameSizeWithConstraints(framesetter,
                                                                               stringRange,
                                                                               (CFDictionaryRef)NULL,
                                                                               constraints,
                                                                               &fitRange);
    
    // Note that fitRange is ignored here, we only care about the measured height
    
    measuredHeight = fontMeasureFrameSize.height;
    
    CFRelease(framesetter);
  }
  
  return (NSUInteger) ceil(measuredHeight);
}


// Set the default font properties that will be used for plain and bold font types.
// Note that this method must be invoked before strings are appended.

- (void) setDefaults:(CGColorRef)textColor
            fontSize:(NSUInteger)fontSize
       plainFontName:(NSString*)plainFontName
        boldFontName:(NSString*)boldFontName
{
  NSAssert(self.length == 0, @"setDefaults must be invoked on empty attr string");
  
  CTFontRef plainFont;
  CTFontRef boldFont;
  
  plainFont = CTFontCreateWithName(
#if __has_feature(objc_arc)
                                   (__bridge CFStringRef)plainFontName,
#else
                                   (CFStringRef)plainFontName,
#endif // objc_arc
                                   fontSize, nil);
  NSAssert(plainFont, @"plainFont");
  self.plainTextFont = plainFont;
  
  // If both plain and bold are the same font name, create just 1 font.
  // This improves performance quite a bit.
  
  if ([boldFontName isEqualToString:plainFontName]) {
    boldFont = CFRetain(plainFont);
  } else {
    boldFont = CTFontCreateWithName(
#if __has_feature(objc_arc)
                                    (__bridge CFStringRef)boldFontName,
#else
                                    (CFStringRef)boldFontName,
#endif // objc_arc
                                    fontSize, nil);
  }
  NSAssert(boldFont, @"boldFont");
  self.boldTextFont = boldFont;
  
  self.defaultTextColor = textColor;
  self.color = textColor;
  
  [self resetDefaults];
  
  return;
}


// This method is used to reset the properties related to text rendering to the
// default values. The default values are defined by the initial settings passed
// to the setFont method. Render logic will invoke resetDefaults to ensure that
// the next string appended to the attr string will have the default properties.

- (void) resetDefaults
{
  self.color = self.defaultTextColor;
  self.bold = FALSE;
  self.font = self.plainTextFont;
}

// Hold incremented ref to a text color

- (void) setDefaultTextColor:(CGColorRef)defaultTextColor
{
  CGColorRef prev = self->m_defaultTextColor;
  if (defaultTextColor) {
    CGColorRetain(defaultTextColor);
  }
  self->m_defaultTextColor = defaultTextColor;
  if (prev) {
    CGColorRelease(prev);
  }
}

// Hold incremented ref to a the current text color

- (void) setColor:(CGColorRef)color
{
  CGColorRef prev = self->m_color;
  if (color) {
    CGColorRetain(color);
  }
  self->m_color = color;
  if (prev) {
    CGColorRelease(prev);
  }
}

// Hold incremented ref to a the current font

- (void) setFont:(CTFontRef)font
{
  CTFontRef prev = self->m_font;
  if (font) {
    CFRetain(font);
  }
  self->m_font = font;
  if (prev) {
    CFRelease(prev);
  }
}

// Use CoreText to render rich text into a static bounding box of the given context.
// Not thread safe!

- (void) render:(CGContextRef)bitmapContext
         bounds:(CGRect)bounds
{
  CFMutableAttributedStringRef attrString = self.attrString;
    
  CGMutablePathRef textBoundsPath = CGPathCreateMutable();
  CGRect textBounds = bounds;
  CGPathAddRect(textBoundsPath, NULL, textBounds);
  
  // FIXME: drop shadow: http://stackoverflow.com/questions/4388384/adding-a-drop-shadow-to-nsstring-text-in-a-drawrect-method-without-using-uilabe
  
  // Create the framesetter with the attributed string and then render into the graphics context.
  // Note the use of if blocks to deal with the weird case of memory running low and NULL being returned.
  
  CTFramesetterRef framesetter = CTFramesetterCreateWithAttributedString(attrString);
  
  if (framesetter) {
    CTFrameRef textRenderFrame = CTFramesetterCreateFrame(framesetter, CFRangeMake(0, 0), textBoundsPath, NULL);
    
    if (textRenderFrame) {
      CTFrameDraw(textRenderFrame, bitmapContext);
      
      CFRelease(textRenderFrame);
    }
    
    CFRelease(framesetter);
  }
  
  CGPathRelease(textBoundsPath);
  
  return;
}

// Print the mutable attributed string as a single string with no attributes.
// This is useful for debugging purposes.

- (NSString*) description
{
  CFMutableAttributedStringRef attrString = self->m_attrString;
  NSString *str = (NSString*) CFAttributedStringGetString(attrString);
  NSString *ret = [NSString stringWithString:str];
  return ret;
}

@end
