//
//  AutoPropertyRelease.m
//
//  Created by Moses DeJong on 11/11/09.
//  Placed in the public domain.
//

#if __has_feature(objc_arc)
// No-op
#else

#import "AutoPropertyRelease.h"

#import <objc/runtime.h>
#import <objc/message.h>

//#define LOGGING

@implementation AutoPropertyRelease

+ (void)releaseProperties:(NSObject*)obj thisClass:(Class)thisClass
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  
	unsigned int count;
	objc_property_t *properties = class_copyPropertyList(thisClass, &count);

#if defined(LOGGING)
	NSLog(@"class \"%s\" has %d properties",
		   class_getName(thisClass), count);
#endif

	for (int i=0; i<count; i++) {
		objc_property_t property = properties[i];
		const char *attrs = property_getAttributes(property);

#if defined(LOGGING)
		NSLog(@"property \"%s\" [%s]",
			   property_getName(property),
			   attrs);
#endif

		// Ignore properties for non-retained types like int or float.
		// Release a retained id as indicated by the "retain" or "copy"
		// attribute on the property.
		//
		// @property int intDefault; -> [Ti,VintDefault] (IGNORE)
		// @property id idDefault; -> [T@,VidDefault"] (IGNORE)
		// @property (nonatomic) NSMutableString* mstr2; -> [T@"NSMutableString",N,V_mstr2] (IGNORE)
		// @property(retain) id idRetain; -> "T@,&,VidRetain" (release ref with & component)
		// @property(copy) id idCopy; -> "T@,C,VidCopy" (release ref with C component)
		// @property (nonatomic, copy, setter=mySetterStr:) NSString* setterStr; ->
		//		[T@"NSString",C,N,SmySetterStr:,V_setterStr] (release C via "mySetterStr:")
		// @property (nonatomic, copy) NSString* prop1; (but no @synthesize) ->
		//		[T@"NSString",C,N] (should still release via setProp1:nil)

		if (attrs[0] != 'T' || attrs[1] != '@') {
			// attrs does not start with string "T@"
			continue;
		}

		/*
		 Table 7-1  Declared property type encodings
		 Code
		 Meaning
		 R
		 The property is read-only (readonly).
		 C
		 The property is a copy of the value last assigned (copy).
		 &
		 The property is a reference to the value last assigned (retain).
		 N
		 The property is non-atomic (nonatomic).
		 G<name>
		 The property defines a custom getter selector name. The name follows the G (for example, GcustomGetter,).
		 S<name>
		 The property defines a custom setter selector name. The name follows the S (for example, ScustomSetter:,).
		 D
		 The property is dynamic (@dynamic).
		 W
		 The property is a weak reference (__weak).
		 P
		 The property is eligible for garbage collection.
		 t<encoding>
		 Specifies the type using old-style encoding.
		 */

		NSString *attrsStr = [NSString stringWithFormat:@"%s", attrs];
		NSArray *components = [attrsStr componentsSeparatedByCharactersInSet:
							   [NSCharacterSet characterSetWithCharactersInString:@","]];
		
		NSMutableArray *mComponents = [NSMutableArray arrayWithArray:components];
		
		NSString *namePart = [mComponents objectAtIndex:0];
		NSAssert([namePart length] >= 2 && [namePart characterAtIndex:0] == 'T',
				 @"namePart part must begin with letter T");
		
		NSString *ivarPart = [mComponents lastObject];
		
    // A property should have an associated ivar, but it is possible that
    // a property can be declared and then be implemented with a getter
    // and a setter but without using @synthesize. Handle this case
    // by looking at the last element in the components array and
    // treating it as a ivar if it looks like "Vprop1".

    BOOL iVarSynthesizeFound = FALSE;
    
    if ([ivarPart length] > 1 && [ivarPart characterAtIndex:0] == 'V') {
      iVarSynthesizeFound = TRUE;
      [mComponents removeLastObject];
      ivarPart = [ivarPart substringFromIndex:1];
    }

		[mComponents removeObjectAtIndex:0];
		NSArray *typeComponents = [NSArray arrayWithArray:mComponents];

		BOOL isReadOnly = FALSE;
		BOOL releaseObject = FALSE;
		NSString *propSetterMethodName = nil;

		// This is an object property, if either retain or copy
		// are found then release the held ref count.

		for (NSString *comp in typeComponents) {
			const int len = (int) [comp length];
			unichar c = (len == 0 ? '\0' : [comp characterAtIndex:0]);

			if ((len == 1) && (c == '&' || c == 'C')) {
				// Release ref to object for & (retain) or C (copy)
				releaseObject = TRUE;
			} else if ((len == 1) && (c == 'R')) {
				// This is the weird case of a readonly object property,
				// we can't release it by invoking a setter because
				// the compiler does not generate a setter.
				isReadOnly = TRUE;
			} else if ((len > 1) && (c == 'S')) {
				// ScustomSetter: -> "customSetter:"
				propSetterMethodName = [comp substringFromIndex:1];
			}
		}

		if (isReadOnly && releaseObject) {
			// Weird case of a readonly property, we can't set it to nil
			// because the compiler does not generate a setter. It is
			// very bad to leak memory, so to address this we lookup
			// the id currently in the ivar and release it explicitly.
			// We also need to set the ivar to nil after releasing the
			// object so that this logic can be invoked twice.

      if (iVarSynthesizeFound == FALSE) {
#if defined(LOGGING)
        NSLog(@"skipping property \"%s\" since associated ivar was not declared in @synthesize",
              property_getName(property));
#endif
        continue;
      }
      
			void *ivarObj = NULL;
			Ivar ivar = object_getInstanceVariable(obj, [ivarPart UTF8String], &ivarObj);
			NSAssert(ivar, @"ivar not returned by object_getInstanceVariable");
			[(id)ivarObj release];
			object_setIvar(obj, ivar, nil);

#if defined(LOGGING)
			NSLog(@"released readonly id obj->%s and set to nil", ivar_getName(ivar));
#endif
		} else if (releaseObject) {
			if (propSetterMethodName == nil) {
				// Invoke self.prop = nil; via [self setProp:nil]
				
				const char *name = property_getName(property);
				NSAssert(strlen(name) >= 1, @"invalid property name");
				char first = toupper(name[0]);
				const char *rest = &name[1];

				propSetterMethodName = [NSString stringWithFormat:@"set%c%s:", first, rest];				
			}
			
			SEL setPropertySelector = NSSelectorFromString(propSetterMethodName);
			NSAssert(setPropertySelector, @"property setter selector is invalid");
      
      // If a property was not synthesized, then it is possible that the class might not
      // implement a setter. A class like this will still compile, even though it will
      // not function properly.
      
      if (iVarSynthesizeFound == FALSE) {
        if (class_respondsToSelector(thisClass, setPropertySelector) == FALSE) {
#if defined(LOGGING)
          NSLog(@"skipping property \"%s\" since it does not respond to the selector \"%@\"", 
                property_getName(property),
                propSetterMethodName);
#endif			
          continue;
        }
      }
      
            #if __LP64__
			((void(*)(id, SEL, id))objc_msgSend)(obj, setPropertySelector, nil);
            #else
			objc_msgSend(obj, setPropertySelector, nil);
            #endif // __LP64__

#if defined(LOGGING)
			NSLog(@"invoked %@%@", propSetterMethodName, @"nil");
#endif
		}
	}

	free(properties);
 [pool drain];
	return;
}

@end

#endif // objc_arc
