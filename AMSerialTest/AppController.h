//
//  AppController.h
//  AMSerialTest
//
//  Copyright (c) 2001-2016 Andreas Mayer. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "AMSerialPort.h"


@interface AppController : NSObject <AMSerialDelegate> {
	IBOutlet NSTextField *inputTextField;
	IBOutlet NSTextField *deviceTextField;
	IBOutlet NSTextView *outputTextView;
	AMSerialPort *_port;
}

- (AMSerialPort *)port;
- (void)setPort:(AMSerialPort *)newPort;


- (IBAction)listDevices:(id)sender;

- (IBAction)chooseDevice:(id)sender;

- (IBAction)send:(id)sender;

- (IBAction)sendSerialBreak:(id)sender;


@end
