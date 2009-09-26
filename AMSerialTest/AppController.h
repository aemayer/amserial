//
//  AppController.h
//  AMSerialTest
//

#import <Cocoa/Cocoa.h>
#import "AMSerialPort.h"


@interface AppController : NSObject {
	IBOutlet NSTextField *inputTextField;
	IBOutlet NSTextField *deviceTextField;
	IBOutlet NSTextView *outputTextView;
	AMSerialPort *port;
}

- (AMSerialPort *)port;
- (void)setPort:(AMSerialPort *)newPort;


- (IBAction)listDevices:(id)sender;

- (IBAction)chooseDevice:(id)sender;

- (IBAction)send:(id)sender;


@end
