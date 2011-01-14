//
//  QTFileParserAppViewController.m
//
//  Created by Moses DeJong on 12/17/10.
//
//  License terms defined in License.txt.

#import "QTFileParserAppViewController.h"

#import "QTFileParserAppAppDelegate.h"

#import "AutoPropertyRelease.h"

@implementation QTFileParserAppViewController

@synthesize segControl = m_segControl;

- (void) dealloc
{
  [AutoPropertyRelease releaseProperties:self thisClass:QTFileParserAppViewController.class]; 
  [super dealloc];
}

- (NSInteger) getFPS
{
  NSAssert(self.segControl, @"segControl is nil");
  int index = [self.segControl selectedSegmentIndex];
  
  if (index == UISegmentedControlNoSegment) {
    return -1;
  } else if (index == 0) {
    return -1;
  } else if (index == 1) {
    return 10;
  } else if (index == 2) {
    return 15;
  } else if (index == 3) {
    return 24;
  } else if (index == 4) {
    return 30;
  } else if (index == 5) {
    return 60;
  } else {
    return -1;
  }
}

- (IBAction) runExampleOne:(id) sender
{
  id delegate = [[UIApplication sharedApplication] delegate];
	NSAssert(delegate, @"delegate is nil");
  QTFileParserAppAppDelegate *appDelegate = (QTFileParserAppAppDelegate*)delegate;
  [appDelegate loadIndexedExample:1 fps:[self getFPS]];
}

- (IBAction) runExampleTwo:(id) sender
{
  id delegate = [[UIApplication sharedApplication] delegate];
	NSAssert(delegate, @"delegate is nil");
  QTFileParserAppAppDelegate *appDelegate = (QTFileParserAppAppDelegate*)delegate;
  [appDelegate loadIndexedExample:2 fps:[self getFPS]];
}

- (IBAction) runExampleThree:(id) sender
{
  id delegate = [[UIApplication sharedApplication] delegate];
	NSAssert(delegate, @"delegate is nil");
  QTFileParserAppAppDelegate *appDelegate = (QTFileParserAppAppDelegate*)delegate;
  [appDelegate loadIndexedExample:3 fps:[self getFPS]];
}

- (IBAction) runExampleFour:(id) sender
{
  id delegate = [[UIApplication sharedApplication] delegate];
	NSAssert(delegate, @"delegate is nil");
  QTFileParserAppAppDelegate *appDelegate = (QTFileParserAppAppDelegate*)delegate;
  [appDelegate loadIndexedExample:4 fps:[self getFPS]];
}

- (IBAction) runExampleFive:(id) sender
{
  id delegate = [[UIApplication sharedApplication] delegate];
	NSAssert(delegate, @"delegate is nil");
  QTFileParserAppAppDelegate *appDelegate = (QTFileParserAppAppDelegate*)delegate;
  [appDelegate loadIndexedExample:5 fps:[self getFPS]];
}

@end
