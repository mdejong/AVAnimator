//
//  QTFileParserAppViewController.h
//
//  Created by Moses DeJong on 12/17/10.
//
//  License terms defined in License.txt.

#import <UIKit/UIKit.h>

@interface QTFileParserAppViewController : UIViewController {
  UISegmentedControl *m_segControl;
}

@property (nonatomic, retain) IBOutlet UISegmentedControl *segControl;

- (IBAction) runExampleOne:(id) sender;

- (IBAction) runExampleTwo:(id) sender;

- (IBAction) runExampleThree:(id) sender;

- (IBAction) runExampleFour:(id) sender;

- (IBAction) runExampleFive:(id) sender;

@end

