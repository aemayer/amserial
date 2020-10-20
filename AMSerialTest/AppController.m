//
//  AppController.m
//  AMSerialTest
//
//  Copyright (c) 2001-2020 Andreas Mayer. All rights reserved.
//
//	2009-09-09		Andreas Mayer
//	- fixed memory leak in -serialPortReadData:
//	2020-08-03		Sean McBride
//  - the device textfield no longer sends an action message, instead there are Open and Close push buttons
//	- added a Send Serial Break push button


#import "AppController.h"
#import "AMSerialPortList.h"
#import "AMSerialPortAdditions.h"

@implementation AppController


- (void)awakeFromNib
{
	[deviceTextField setStringValue:@"/dev/cu.modem"]; // internal modem
	[inputTextField setStringValue:@"ati"]; // will ask for modem type

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

#if !__has_feature(objc_arc)
- (void)dealloc
{
	[_port release];
	[super dealloc];
}
#endif

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
	if ([deviceName length] <= 0) {
		[self appendOutputString:@"no port to open\r"];
		
		return;
	}

	AMSerialPort *oldPort = [self port];
	NSString *oldPortPath = [oldPort bsdPath];
	if (deviceName && oldPortPath && [deviceName isEqualToString:oldPortPath]) {
		[self appendOutputString:@"that port already open\r"];
		
		return;
	}

	[oldPort setDelegate:nil];
	[oldPort close];
	oldPort = nil;

	AMSerialPort* newPort = [[AMSerialPort alloc] init:deviceName
											  withName:deviceName
												  type:@kIOSerialBSDModemType];
#if !__has_feature(objc_arc)
	[newPort autorelease];
#endif
	[self setPort:newPort];

	// register self as delegate of port
	[newPort setDelegate:self];

	NSString *message = [NSString stringWithFormat:@"attempting to open port %@\r", deviceName];
	[self appendOutputString:message];

	// open port - may take a few seconds ...
	if ([newPort open]) {

		[self appendOutputString:@"port opened\r"];

		// listen for data in a separate thread
		[newPort readDataInBackground];

	} else { // an error occurred while creating port
		[self appendOutputString:@"couldn't open port\r"];

		[self setPort:nil];
	}
}

- (void)closePort
{
	AMSerialPort *port = [self port];
	if (port) {
		[port setDelegate:nil];
		[port close];
		[self setPort:nil];

		[self appendOutputString:@"port closed\r"];
	} else {
		[self appendOutputString:@"no port to close\r"];
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

- (IBAction)chooseOpen:(id)sender
{
	(void)sender;
	
	// open the named port, if any
	[self openPort];
}

- (IBAction)chooseClose:(id)sender
{
	(void)sender;
	
	// close the current port, if any
	[self closePort];
}

- (IBAction)send:(id)sender
{
	(void)sender;
	
	AMSerialPort *port = [self port];
	if ([port isOpen]) {
		NSString *sendString = [[inputTextField stringValue] stringByAppendingString:@"\r"];

		NSError *error = nil;
		BOOL success = [port writeString:sendString usingEncoding:NSUTF8StringEncoding error:&error];
		if (!success) {
			NSString *message = [NSString stringWithFormat:@"writing to port failed with: %@\r", error];
			[self appendOutputString:message];
		}
	}
	else {
		[self appendOutputString:@"no port is open\r"];
	}
}

- (IBAction)sendSerialBreak:(id)sender
{
	(void)sender;
	
	AMSerialPort *port = [self port];
	if ([port isOpen]) {
		BOOL success = [port sendBreak];
		if (success) {
			[self appendOutputString:@"sendBreak successful\r"];
		}
		else {
			[self appendOutputString:@"sendBreak failed\r"];
		}
	}
	else {
		[self appendOutputString:@"no port is open\r"];
	}
}

@end
