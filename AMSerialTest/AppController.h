//
//  AppController.h
//  AMSerialTest
//
//  Copyright (c) 2001-2020 Andreas Mayer. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import "AMSerialPort.h"

NS_ASSUME_NONNULL_BEGIN

@interface AppController : NSObject <AMSerialDelegate>
{
@private
	IBOutlet NSTextField *inputTextField;
	IBOutlet NSTextField *deviceTextField;
	IBOutlet NSTextView *outputTextView;
	AMSerialPort *_port;
}

@property(readwrite, retain, atomic, nullable) AMSerialPort *port;

@end

NS_ASSUME_NONNULL_END
