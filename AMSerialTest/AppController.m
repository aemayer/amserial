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
		
		[[[outputTextView textStorage] mutableString] appendString:@"attempting to open port\r"];
		[outputTextView setNeedsDisplay:YES];
		[outputTextView displayIfNeeded];
		
		// open port - may take a few seconds ...
		if ([_port open]) {
			
			[[[outputTextView textStorage] mutableString] appendString:@"port opened\r"];
			[outputTextView setNeedsDisplay:YES];
			[outputTextView displayIfNeeded];

			// listen for data in a separate thread
			[_port readDataInBackground];
			
		} else { // an error occurred while creating port
			[[[outputTextView textStorage] mutableString] appendString:@"couldn't open port for device "];
			[[[outputTextView textStorage] mutableString] appendString:deviceName];
			[[[outputTextView textStorage] mutableString] appendString:@"\r"];
			[outputTextView setNeedsDisplay:YES];
			[outputTextView displayIfNeeded];
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
			[[[outputTextView textStorage] mutableString] appendString:text];
#if !__has_feature(objc_arc)
			[text release];
#endif
		}

		// continue listening
		[sendPort readDataInBackground];
	} else { // port closed
		[[[outputTextView textStorage] mutableString] appendString:@"port closed\r"];
	}
	[outputTextView setNeedsDisplay:YES];
	[outputTextView displayIfNeeded];
}


- (void)didAddPorts:(NSNotification *)theNotification
{
	assert(theNotification);
	
	[[[outputTextView textStorage] mutableString] appendString:@"didAddPorts:"];
	[[[outputTextView textStorage] mutableString] appendString:@"\r"];
	[[[outputTextView textStorage] mutableString] appendString:[[theNotification userInfo] description]];
	[[[outputTextView textStorage] mutableString] appendString:@"\r"];
	[outputTextView setNeedsDisplay:YES];
}

- (void)didRemovePorts:(NSNotification *)theNotification
{
	assert(theNotification);
	
	[[[outputTextView textStorage] mutableString] appendString:@"didRemovePorts:"];
	[[[outputTextView textStorage] mutableString] appendString:@"\r"];
	[[[outputTextView textStorage] mutableString] appendString:[[theNotification userInfo] description]];
	[[[outputTextView textStorage] mutableString] appendString:@"\r"];
	[outputTextView setNeedsDisplay:YES];
}


- (IBAction)listDevices:(id)sender
{
	(void)sender;
	
	// get an port enumerator
	AMSerialPortList *sharedPortList = [AMSerialPortList sharedPortList];
	for (AMSerialPort *aPort in sharedPortList) {
		// print port name
		[[[outputTextView textStorage] mutableString] appendString:[aPort name]];
		[[[outputTextView textStorage] mutableString] appendString:@":"];
		[[[outputTextView textStorage] mutableString] appendString:[aPort bsdPath]];
		[[[outputTextView textStorage] mutableString] appendString:@"\r"];
	}
	[outputTextView setNeedsDisplay:YES];
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
