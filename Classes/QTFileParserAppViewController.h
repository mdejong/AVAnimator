//
//  QTFileParserAppViewController.h
//
//  Created by Moses DeJong on 12/17/10.
//
//  License terms defined in License.txt.

#import <UIKit/UIKit.h>

@interface QTFileParserAppViewController : UIViewController {
  UISegmentedControl *m_segControl;
  UIScrollView *m_scrollView;
}

@property (nonatomic, retain) IBOutlet UISegmentedControl *segControl;
@property (nonatomic, retain) IBOutlet UIScrollView *scrollView;

- (IBAction) runExampleOne:(id) sender;

- (IBAction) runExampleTwo:(id) sender;

- (IBAction) runExampleThree:(id) sender;

- (IBAction) runExampleFour:(id) sender;

- (IBAction) runExampleFive:(id) sender;

- (IBAction) runExampleSix:(id) sender;

- (IBAction) runExampleSeven:(id) sender;

- (IBAction) runExampleEight:(id) sender;

- (IBAction) runExampleNine:(id) sender;

- (IBAction) runExampleTen:(id) sender;

- (IBAction) runExampleEleven:(id) sender;

- (IBAction) runExampleTwelve:(id) sender;

- (IBAction) runExampleThirteen:(id) sender;

- (IBAction) runExampleFourteen:(id) sender;

- (IBAction) runExampleFifteen:(id) sender;

- (IBAction) runExampleSixteen:(id) sender;

- (IBAction) runExampleSeventeen:(id) sender;

- (IBAction) runExampleEighteen:(id) sender;

@end

