//
//  AppController.m
//  AMSerialTest
//
//  Copyright (c) 2001-2020 Andreas Mayer. All rights reserved.
//
//	2009-09-09		Andreas Mayer
//	- fixed memory leak in -serialPortReadData:


#import "AppController.h"
#import "AMSerialPortList.h"
#import "AMSerialPortAdditions.h"

@implementation AppController


- (void)awakeFromNib
{
	[deviceTextField setStringValue:@"/dev/cu.modem"]; // internal modem
	[inputTextField setStringValue: @"ati"]; // will ask for modem type

	// register for port add/remove notification
	NSNotificationCenter* defaultCenter = [NSNotificationCenter defaultCenter];
	[defaultCenter addObserver:self
					  selector:@selector(didAddPorts:)
						  name:AMSerialPortListDidAddPortsNotification
						object:nil];
	[defaultCenter addObserver:self
					  selector:@selector(didRemovePorts:)
						  name:AMSerialPortListDidRemovePortsNotification
						object:nil];
	
	// initialize port list to arm notifications
	(void)[AMSerialPortList sharedPortList];
}


@synthesize port = _port;

- (void)appendOutputString:(NSString *)string
{
	assert(string);
	
	[[[outputTextView textStorage] mutableString] appendString:string];
	[outputTextView setNeedsDisplay:YES];
	[outputTextView displayIfNeeded];
}

- (void)openPort
{
	NSString *deviceName = [deviceTextField stringValue];
	if (![deviceName isEqualToString:[_port bsdPath]]) {
		[_port close];

		AMSerialPort* newPort = [[AMSerialPort alloc] init:deviceName withName:deviceName type:@kIOSerialBSDModemType];
#if !__has_feature(objc_arc)
		[newPort autorelease];
#endif
		[self setPort:newPort];
		
		// register as self as delegate for port
		[_port setDelegate:self];
		
		[self appendOutputString:@"attempting to open port\r"];
		
		// open port - may take a few seconds ...
		if ([_port open]) {
			
			[self appendOutputString:@"port opened\r"];

			// listen for data in a separate thread
			[_port readDataInBackground];
			
		} else { // an error occurred while creating port
			NSString *message = [NSString stringWithFormat:@"couldn't open port for device %@\r",
								 deviceName];
			[self appendOutputString:message];
			[self setPort:nil];
		}
	}
}

- (void)serialPortReadData:(NSDictionary *)dataDictionary
{
	assert(dataDictionary);
	
	// this method is called if data arrives 
	// @"data" is the actual data, @"serialPort" is the sending port
	AMSerialPort *sendPort = [dataDictionary objectForKey:@"serialPort"];
	NSData *data = [dataDictionary objectForKey:@"data"];
	if ([data length] > 0) {
		NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
		if (text) {
			[self appendOutputString:text];
#if !__has_feature(objc_arc)
			[text release];
#endif
		}

		// continue listening
		[sendPort readDataInBackground];
	} else { // port closed
		[self appendOutputString:@"port closed\r"];
	}
}


- (void)didAddPorts:(NSNotification *)theNotification
{
	assert(theNotification);
	
	NSString *message = [NSString stringWithFormat:@"didAddPorts:\r%@\r",
						 [[theNotification userInfo] description]];
	[self appendOutputString:message];
}

- (void)didRemovePorts:(NSNotification *)theNotification
{
	assert(theNotification);
	
	NSString *message = [NSString stringWithFormat:@"didRemovePorts:\r%@\r",
						 [[theNotification userInfo] description]];
	[self appendOutputString:message];
}


- (IBAction)listDevices:(id)sender
{
	(void)sender;
	
	// get a port enumerator
	AMSerialPortList *sharedPortList = [AMSerialPortList sharedPortList];
	for (AMSerialPort *aPort in sharedPortList) {
		// print port name
		NSString *message = [NSString stringWithFormat:@"%@ : %@\r",
							 [aPort name],
							 [aPort bsdPath]];
		[self appendOutputString:message];
	}
}

- (IBAction)chooseDevice:(id)sender
{
	(void)sender;
	
	// new device selected
	[self openPort];
}

- (IBAction)send:(id)sender
{
	(void)sender;
	
	NSString *sendString = [[inputTextField stringValue] stringByAppendingString:@"\r"];

	if(!_port) {
		// open a new port if we don't already have one
		[self openPort];
	}

	if([_port isOpen]) { // in case an error occurred while opening the port
		[_port writeString:sendString usingEncoding:NSUTF8StringEncoding error:nil];
	}
}

- (IBAction)sendSerialBreak:(id)sender
{
	(void)sender;
	
	if(!_port) {
		// open a new port if we don't already have one
		[self openPort];
	}

	if([_port isOpen]) { // in case an error occurred while opening the port
		[_port sendBreak];
	}
}

@end
