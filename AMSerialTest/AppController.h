//
//  AppController.h
//  AMSerialTest
//
//  SPDX-FileCopyrightText: Copyright (c) 2001-2020 Andreas Mayer. All rights reserved.
//  SPDX-License-Identifier: BSD-3-Clause
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
