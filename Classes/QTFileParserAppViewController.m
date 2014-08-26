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
@synthesize scrollView = m_scrollView;

- (void) viewDidLoad {
	[super viewDidLoad];
  NSAssert(self.scrollView, @"scrollView is nil");
  self.scrollView.contentSize = CGSizeMake(320, 1100);
  // Explicitly set the size of the scroll view so that
  // it can be larger in interface builder.
  //self.scrollView.bounds = CGRectMake(0, 0, 320, 431);
  self.scrollView.frame = CGRectMake(0, 49, 320, 431);
  // Explicitly set the size of the containing view
  // so that it can be bigger in IB.
  //self.view.bounds = CGRectMake(0, 0, 320, 480);
}

- (void) dealloc
{
  [AutoPropertyRelease releaseProperties:self thisClass:QTFileParserAppViewController.class]; 
  [super dealloc];
}

- (NSInteger) getFPS
{
  NSAssert(self.segControl, @"segControl is nil");
  int index = (int) [self.segControl selectedSegmentIndex];
  
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

- (IBAction) runExampleSix:(id) sender
{
  id delegate = [[UIApplication sharedApplication] delegate];
	NSAssert(delegate, @"delegate is nil");
  QTFileParserAppAppDelegate *appDelegate = (QTFileParserAppAppDelegate*)delegate;
  [appDelegate loadIndexedExample:6 fps:[self getFPS]];
}

- (IBAction) runExampleSeven:(id) sender
{
  id delegate = [[UIApplication sharedApplication] delegate];
	NSAssert(delegate, @"delegate is nil");
  QTFileParserAppAppDelegate *appDelegate = (QTFileParserAppAppDelegate*)delegate;
  [appDelegate loadIndexedExample:7 fps:[self getFPS]];
}

- (IBAction) runExampleEight:(id) sender
{
  id delegate = [[UIApplication sharedApplication] delegate];
	NSAssert(delegate, @"delegate is nil");
  QTFileParserAppAppDelegate *appDelegate = (QTFileParserAppAppDelegate*)delegate;
  [appDelegate loadIndexedExample:8 fps:[self getFPS]];
}

- (IBAction) runExampleNine:(id) sender
{
  id delegate = [[UIApplication sharedApplication] delegate];
	NSAssert(delegate, @"delegate is nil");
  QTFileParserAppAppDelegate *appDelegate = (QTFileParserAppAppDelegate*)delegate;
  [appDelegate loadIndexedExample:9 fps:[self getFPS]];
}

- (IBAction) runExampleTen:(id) sender
{
  id delegate = [[UIApplication sharedApplication] delegate];
	NSAssert(delegate, @"delegate is nil");
  QTFileParserAppAppDelegate *appDelegate = (QTFileParserAppAppDelegate*)delegate;
  [appDelegate loadIndexedExample:10 fps:[self getFPS]];
}

- (IBAction) runExampleEleven:(id) sender
{
  id delegate = [[UIApplication sharedApplication] delegate];
	NSAssert(delegate, @"delegate is nil");
  QTFileParserAppAppDelegate *appDelegate = (QTFileParserAppAppDelegate*)delegate;
  [appDelegate loadIndexedExample:11 fps:[self getFPS]];
}

- (IBAction) runExampleTwelve:(id) sender
{
  id delegate = [[UIApplication sharedApplication] delegate];
	NSAssert(delegate, @"delegate is nil");
  QTFileParserAppAppDelegate *appDelegate = (QTFileParserAppAppDelegate*)delegate;
  [appDelegate loadIndexedExample:12 fps:[self getFPS]];
}

- (IBAction) runExampleThirteen:(id) sender
{
  id delegate = [[UIApplication sharedApplication] delegate];
	NSAssert(delegate, @"delegate is nil");
  QTFileParserAppAppDelegate *appDelegate = (QTFileParserAppAppDelegate*)delegate;
  [appDelegate loadIndexedExample:13 fps:[self getFPS]];
}

- (IBAction) runExampleFourteen:(id) sender
{
  id delegate = [[UIApplication sharedApplication] delegate];
	NSAssert(delegate, @"delegate is nil");
  QTFileParserAppAppDelegate *appDelegate = (QTFileParserAppAppDelegate*)delegate;
  [appDelegate loadIndexedExample:14 fps:[self getFPS]];
}

- (IBAction) runExampleFifteen:(id) sender
{
  id delegate = [[UIApplication sharedApplication] delegate];
	NSAssert(delegate, @"delegate is nil");
  QTFileParserAppAppDelegate *appDelegate = (QTFileParserAppAppDelegate*)delegate;
  [appDelegate loadIndexedExample:15 fps:[self getFPS]];
}

- (IBAction) runExampleSixteen:(id) sender
{
  id delegate = [[UIApplication sharedApplication] delegate];
	NSAssert(delegate, @"delegate is nil");
  QTFileParserAppAppDelegate *appDelegate = (QTFileParserAppAppDelegate*)delegate;
  [appDelegate loadIndexedExample:16 fps:[self getFPS]];
}

- (IBAction) runExampleSeventeen:(id) sender
{
  id delegate = [[UIApplication sharedApplication] delegate];
	NSAssert(delegate, @"delegate is nil");
  QTFileParserAppAppDelegate *appDelegate = (QTFileParserAppAppDelegate*)delegate;
  [appDelegate loadIndexedExample:17 fps:[self getFPS]];
}

- (IBAction) runExampleEighteen:(id) sender
{
  id delegate = [[UIApplication sharedApplication] delegate];
	NSAssert(delegate, @"delegate is nil");
  QTFileParserAppAppDelegate *appDelegate = (QTFileParserAppAppDelegate*)delegate;
  [appDelegate loadIndexedExample:18 fps:[self getFPS]];
}

- (IBAction) runExampleNineteen:(id) sender
{
  id delegate = [[UIApplication sharedApplication] delegate];
	NSAssert(delegate, @"delegate is nil");
  QTFileParserAppAppDelegate *appDelegate = (QTFileParserAppAppDelegate*)delegate;
  [appDelegate loadIndexedExample:19 fps:[self getFPS]];
}

- (IBAction) runExampleTwenty:(id) sender
{
  id delegate = [[UIApplication sharedApplication] delegate];
	NSAssert(delegate, @"delegate is nil");
  QTFileParserAppAppDelegate *appDelegate = (QTFileParserAppAppDelegate*)delegate;
  [appDelegate loadIndexedExample:20 fps:[self getFPS]];
}

@end
