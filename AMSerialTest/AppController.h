//
//  AppController.h
//  AMSerialTest
//
//  Copyright (c) 2001-2016 Andreas Mayer. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "AMSerialPort.h"

NS_ASSUME_NONNULL_BEGIN

@interface AppController : NSObject <AMSerialDelegate> {
	IBOutlet NSTextField *inputTextField;
	IBOutlet NSTextField *deviceTextField;
	IBOutlet NSTextView *outputTextView;
	AMSerialPort *_port;
}

@property(readwrite, retain, atomic, nullable) AMSerialPort *port;

- (IBAction)listDevices:(id)sender;

- (IBAction)chooseDevice:(id)sender;

- (IBAction)send:(id)sender;

- (IBAction)sendSerialBreak:(id)sender;

@end

NS_ASSUME_NONNULL_END
