//
//  AppController.m
//  AMSerialTest
//
//  Copyright (c) 2001-2014 Andreas Mayer. All rights reserved.
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
	[defaultCenter addObserver:self selector:@selector(didAddPorts:) name:AMSerialPortListDidAddPortsNotification object:nil];
	[defaultCenter addObserver:self selector:@selector(didRemovePorts:) name:AMSerialPortListDidRemovePortsNotification object:nil];
	[AMSerialPortList sharedPortList]; // initialize port list to arm notifications
}


- (AMSerialPort *)port
{
    return _port;
}

- (void)setPort:(AMSerialPort *)newPort
{
#if !__has_feature(objc_arc)
    id old = nil;

    if (newPort != _port) {
        old = _port;
        _port = [newPort retain];
        [old release];
    }
#else
	port = newPort;
#endif
}


- (void)initPort
{
	NSString *deviceName = [deviceTextField stringValue];
	if (![deviceName isEqualToString:[_port bsdPath]]) {
		[_port close];

		AMSerialPort* newPort = [[AMSerialPort alloc] init:deviceName withName:deviceName type:(NSString*)CFSTR(kIOSerialBSDModemType)];
#if !__has_feature(objc_arc)
		[newPort autorelease];
#endif
		[self setPort:newPort];
		
		// register as self as delegate for port
		[_port setDelegate:self];
		
		[outputTextView insertText:@"attempting to open port\r"];
		[outputTextView setNeedsDisplay:YES];
		[outputTextView displayIfNeeded];
		
		// open port - may take a few seconds ...
		if ([_port open]) {
			
			[outputTextView insertText:@"port opened\r"];
			[outputTextView setNeedsDisplay:YES];
			[outputTextView displayIfNeeded];

			// listen for data in a separate thread
			[_port readDataInBackground];
			
		} else { // an error occured while creating port
			[outputTextView insertText:@"couldn't open port for device "];
			[outputTextView insertText:deviceName];
			[outputTextView insertText:@"\r"];
			[outputTextView setNeedsDisplay:YES];
			[outputTextView displayIfNeeded];
			[self setPort:nil];
		}
	}
}

- (void)serialPortReadData:(NSDictionary *)dataDictionary
{
	// this method is called if data arrives 
	// @"data" is the actual data, @"serialPort" is the sending port
	AMSerialPort *sendPort = [dataDictionary objectForKey:@"serialPort"];
	NSData *data = [dataDictionary objectForKey:@"data"];
	if ([data length] > 0) {
		NSString *text = [[NSString alloc] initWithData:data encoding:NSASCIIStringEncoding];
		[outputTextView insertText:text];
#if !__has_feature(objc_arc)
		[text release];
#endif
		// continue listening
		[sendPort readDataInBackground];
	} else { // port closed
		[outputTextView insertText:@"port closed\r"];
	}
	[outputTextView setNeedsDisplay:YES];
	[outputTextView displayIfNeeded];
}


- (void)didAddPorts:(NSNotification *)theNotification
{
	[outputTextView insertText:@"didAddPorts:"];
	[outputTextView insertText:@"\r"];
	[outputTextView insertText:[[theNotification userInfo] description]];
	[outputTextView insertText:@"\r"];
	[outputTextView setNeedsDisplay:YES];
}

- (void)didRemovePorts:(NSNotification *)theNotification
{
	[outputTextView insertText:@"didRemovePorts:"];
	[outputTextView insertText:@"\r"];
	[outputTextView insertText:[[theNotification userInfo] description]];
	[outputTextView insertText:@"\r"];
	[outputTextView setNeedsDisplay:YES];
}


- (IBAction)listDevices:(id)sender
{
	(void)sender;
	
	// get an port enumerator
	NSEnumerator *enumerator = [AMSerialPortList portEnumerator];
	AMSerialPort *aPort;
	while ((aPort = [enumerator nextObject])) {
		// print port name
		[outputTextView insertText:[aPort name]];
		[outputTextView insertText:@":"];
		[outputTextView insertText:[aPort bsdPath]];
		[outputTextView insertText:@"\r"];
	}
	[outputTextView setNeedsDisplay:YES];
}

- (IBAction)chooseDevice:(id)sender
{
	(void)sender;
	
	// new device selected
	[self initPort];
}

- (IBAction)send:(id)sender
{
	(void)sender;
	
	NSString *sendString = [[inputTextField stringValue] stringByAppendingString:@"\r"];

	if(!_port) {
		// open a new port if we don't already have one
		[self initPort];
	}

	if([_port isOpen]) { // in case an error occured while opening the port
		[_port writeString:sendString usingEncoding:NSUTF8StringEncoding error:NULL];
	}
}

- (IBAction)sendSerialBreak:(id)sender
{
	(void)sender;
	
	if(!_port) {
		// open a new port if we don't already have one
		[self initPort];
	}

	if([_port isOpen]) { // in case an error occured while opening the port
		[_port sendBreak];
	}
}

@end
