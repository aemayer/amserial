//
//  AMSerialPort.m
//
//  Created by Andreas Mayer on 2002-04-24.
//  Copyright (c) 2001-2018 Andreas Mayer. All rights reserved.
//
//  2002-09-18 Andreas Mayer
//  - added available & owner
//  2002-10-10 Andreas Mayer
//  - some log messages changed
//  2002-10-17 Andreas Mayer
//  - countWriteInBackgroundThreads and countWriteInBackgroundThreadsLock added
//  2002-10-25 Andreas Mayer
//  - additional locks and other changes for reading and writing in background
//  2003-11-26 James Watson
//  - in dealloc [self close] reordered to execute before releasing closeLock
//  2004-02-10 Andreas Mayer
//    - added delegate for background reading/writing
//  2005-04-04 Andreas Mayer
//  - added setDTR and clearDTR
//  2006-07-28 Andreas Mayer
//  - added -canonicalMode, -endOfLineCharacter and friends
//    (code contributed by Randy Bradley)
//  - cleaned up accessor methods; moved deprecated methods to "Deprecated" category
//  - -setSpeed: does support arbitrary values on 10.4 and later; returns YES on success, NO otherwiese
//  2006-08-16 Andreas Mayer
//  - cleaned up the code and removed some (presumably) unnecessary locks
//  2007-05-22 Nick Zitzmann
//  - added -hash and -isEqual: methods
//  2007-07-18 Sean McBride
//  - behaviour change: -open and -close must now always be matched, -dealloc checks this
//  - added -debugDescription so gdb's 'po' command gives something useful
//  2007-07-25 Andreas Mayer
//  - replaced -debugDescription by -description; works for both, gdb's 'po' and NSLog()
//  2007-10-26 Sean McBride
//  - made code 64 bit and garbage collection clean
//  2008-10-21 Sean McBride
//  - Added an API to open a serial port for exclusive use
//  - fixed some memory management issues
//  2009-08-06 Sean McBride
//  - no longer compare BOOL against YES (dangerous!)
//  - renamed method to start with lowercase letter, as per Cocoa convention
//  2011-10-14 Sean McBride
//  - very minor cleanup
//  2011-10-18 Andreas Mayer
//  - added ARC compatibility
//  - added accessors for ISIG, ECHOE, XON/XOFF as well as Start and Stop characters
//  - options dictionary will cover more settings; fixed handling of some flags
//  2011-10-19 Sean McBride
//  - code review of ARC changes
//  - changed delegate semantics to match Cocoa conventions: the delegate is no longer retained!
//  2012-06-20 Sean McBride
//  - fixed possible out of range exception and compiler warning
//  2016-03-17 Sean McBride
//  - added nullability support
//  2016-03-18 Sean McBride
//  - setDelegate: no longer caches respondsToSelector: results of delegate, insteads checks before messaging it
//  2018-01-08 Sean McBride
//  - Added new openWithFlags:error: API to be able to pass custom flags and get an NSError back

#import "AMSDKCompatibility.h"

#import <sys/ioctl.h>

#import "AMSerialPort.h"
#import "AMSerialErrors.h"

#import <IOKit/serial/IOSerialKeys.h>
#import <IOKit/serial/ioss.h>

NSString *const AMSerialErrorDomain = @"de.harmless.AMSerial.ErrorDomain";


@implementation AMSerialPort

// Cover the superclass' designated initializer
- (instancetype)init NS_UNAVAILABLE
{
	assert(0);
	return nil;
}

// Designated initializer
- (instancetype)init:(NSString *)path withName:(NSString *)name type:(NSString *)type
	// path is a bsdPath
	// name is an IOKit service name
{
	assert(path);
	assert(name);
	assert(type);
	
	self = [super init];
	if (self) {
		_bsdPath = [path copy];
		_serviceName = [name copy];
		_serviceType = [type copy];
		_optionsDictionary = [[NSMutableDictionary alloc] initWithCapacity:8];
		
		_options = (struct termios *)malloc(sizeof(*_options));
		_originalOptions = (struct termios *)malloc(sizeof(*_originalOptions));
		_buffer = (char *)malloc(AMSER_MAXBUFSIZE);
		_readfds = (fd_set *)malloc(sizeof(*_readfds));
		_fileDescriptor = -1;
		
		_writeLock = [[NSLock alloc] init];
		_readLock = [[NSLock alloc] init];
		_closeLock = [[NSLock alloc] init];
		
		// By default blocking read attempts will timeout after 1 second
		_readTimeout = 1.0;
		
		// These are used by the AMSerialPortAdditions category only; pretend to use them here to silence warnings by the clang static analyzer.
		(void)_am_readTarget;
		(void)_am_readSelector;
		(void)_stopWriteInBackground;
		(void)_countWriteInBackgroundThreads;
		(void)_stopReadInBackground;
		(void)_countReadInBackgroundThreads;
	}
	return self;
}

#ifndef __OBJC_GC__

- (void)dealloc
{
#ifdef AMSerialDebug
	if (_fileDescriptor != -1) {
		NSLog(@"It is a programmer error to have not called -close on an AMSerialPort you have opened");
	}
#endif
	assert (_fileDescriptor == -1);

	free(_readfds); _readfds = NULL;
	free(_buffer); _buffer = NULL;
	free(_originalOptions); _originalOptions = NULL;
	free(_options); _options = NULL;
	
#if !__has_feature(objc_arc)
	[_readLock release]; _readLock = nil;
	[_writeLock release]; _writeLock = nil;
	[_closeLock release]; _closeLock = nil;
	[_am_readTarget release]; _am_readTarget = nil;
	
	[_optionsDictionary release]; _optionsDictionary = nil;
	[_serviceName release]; _serviceName = nil;
	[_serviceType release]; _serviceType = nil;
	[_bsdPath release]; _bsdPath = nil;
	[super dealloc];
#endif
}

#else

- (void)finalize
{
#ifdef AMSerialDebug
	if (_fileDescriptor != -1) {
		NSLog(@"It is a programmer error to have not called -close on an AMSerialPort you have opened");
	}
#endif
	assert (_fileDescriptor == -1);

	free(_readfds); _readfds = NULL;
	free(_buffer); _buffer = NULL;
	free(_originalOptions); _originalOptions = NULL;
	free(_options); _options = NULL;
	[super finalize];
}

#endif

// So NSLog and gdb's 'po' command give something useful
- (NSString *)description
{
	NSString *result= [NSString stringWithFormat:@"<%@: address: %p, name: %@, path: %@, type: %@, fileHandle: %@, fileDescriptor: %d>", NSStringFromClass([self class]), self, _serviceName, _bsdPath, _serviceType, _fileHandle, _fileDescriptor];
	return result;
}

- (NSUInteger)hash
{
	return [[self bsdPath] hash];
}

- (BOOL)isEqual:(nullable id)otherObject
{
	if ([otherObject isKindOfClass:[AMSerialPort class]]) {
		return [[self bsdPath] isEqualToString:[otherObject bsdPath]];
	}
	return NO;
}


- (nullable id<AMSerialDelegate>)delegate
{
	return _delegate;
}

- (void)setDelegate:(nullable id<AMSerialDelegate>)newDelegate
{
	// As per Cocoa conventions, delegates are not retained.
	_delegate = newDelegate;
}


- (NSString *)bsdPath
{
	return _bsdPath;
}

- (NSString *)name
{
	return _serviceName;
}

- (NSString *)type
{
	return _serviceType;
}

- (nullable NSDictionary *)properties
{
	NSDictionary *result = nil;
	kern_return_t kernResult; 
	CFMutableDictionaryRef matchingDictionary;
	io_service_t serialService;
	
	matchingDictionary = IOServiceMatching(kIOSerialBSDServiceValue);
#if __has_feature(objc_arc)
	CFDictionarySetValue(matchingDictionary, CFSTR(kIOTTYDeviceKey), (__bridge CFStringRef)[self name]);
#else
	CFDictionarySetValue(matchingDictionary, CFSTR(kIOTTYDeviceKey), (CFStringRef)[self name]);
#endif
	if (matchingDictionary != NULL) {
		CFRetain(matchingDictionary);
		// This function decrements the refcount of the dictionary passed it
		serialService = IOServiceGetMatchingService(kIOMasterPortDefault, matchingDictionary);
		
		if (serialService) {
			CFMutableDictionaryRef propertiesDict = NULL;
			kernResult = IORegistryEntryCreateCFProperties(serialService, &propertiesDict, kCFAllocatorDefault, 0);
			if (kernResult == KERN_SUCCESS) {
#if __has_feature(objc_arc)
				result = [(__bridge NSDictionary*)propertiesDict copy];
#else
				result = [[(NSDictionary*)propertiesDict copy] autorelease];
#endif
			}
			if (propertiesDict) {
				CFRelease(propertiesDict);
			}
			// We have sucked this service dry of information so release it now.
			(void)IOObjectRelease(serialService);
		} else {
#ifdef AMSerialDebug
			NSLog(@"properties: no matching service for %@", matchingDictionary);
#endif
		}
		CFRelease(matchingDictionary);
	}
	return result;
}


- (BOOL)isOpen
{
	// YES if port is open
	return (_fileDescriptor >= 0);
}

- (nullable AMSerialPort *)obtainBy:(id)sender
{
	// get this port exclusively; nil if it's not free
	if (_owner == nil) {
		// Don't retain, like delegates.
		_owner = sender;
		return self;
	} else {
		return nil;
	}
}

- (void)free
{
	// give it back
	_owner = nil;
	[self close];	// you never know ...
}

- (BOOL)available
{
	// check if port is free and can be obtained
	return (_owner == nil);
}

- (nullable id)owner
{
	// who obtained the port?
	return _owner;
}

// use returned file handle to read and write
- (nullable NSFileHandle *)openWithFlags:(int)flags error:(NSError**)error
{
	NSFileHandle *result = nil;
	NSError *localErr = nil;
	
#ifdef __OBJC_GC__
	__strong const char *path = [_bsdPath fileSystemRepresentation];
#else
	const char *path = [_bsdPath fileSystemRepresentation];
#endif
	assert(path);
	_fileDescriptor = open(path, flags);

#ifdef AMSerialDebug
	NSLog(@"open %@ (%d)\n", _bsdPath, _fileDescriptor);
#endif
	
	if (_fileDescriptor < 0)	{
		localErr = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];
#ifdef AMSerialDebug
		NSLog(@"Error opening serial port %@ - %s(%d).\n", _bsdPath, strerror(errno), errno);
#endif
	} else {
		/*
		 if (fcntl(fileDescriptor, F_SETFL, fcntl(fileDescriptor, F_GETFL, 0) & !O_NONBLOCK) == -1)
		 {
			 NSLog(@"Error clearing O_NDELAY %@ - %s(%d).\n", bsdPath, strerror(errno), errno);
		 } // ... else
		 */
		// get the current options and save them for later reset
		if (tcgetattr(_fileDescriptor, _originalOptions) == -1) {
			localErr = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];
#ifdef AMSerialDebug
			NSLog(@"Error getting tty attributes %@ - %s(%d).\n", _bsdPath, strerror(errno), errno);
#endif
		} else {
			// Make an exact copy of the options struct
			*_options = *_originalOptions;
			
			// This object (not the NSFileHandle) owns the fileDescriptor and must dispose it later
			// In other words, you must balance calls to -open/openExclusively/openWithFlags:error: with -close
			_fileHandle = [[NSFileHandle alloc] initWithFileDescriptor:_fileDescriptor];
			result = _fileHandle;
		}
	}
	if (!result) { // failure
		if (_fileDescriptor >= 0) {
			close(_fileDescriptor);
		}
		_fileDescriptor = -1;
		
		assert(localErr);
		if (error) {
			*error = localErr;
		}
	}
	return result;
}

// TODO: Sean: why is O_NONBLOCK commented?  Do we want it or not?

// use returned file handle to read and write
- (nullable NSFileHandle *)open
{
	int flags = (O_RDWR | O_NOCTTY); // | O_NONBLOCK);
	return [self openWithFlags:flags error:nil];
}

// use returned file handle to read and write
- (nullable NSFileHandle *)openExclusively
{
	int flags = (O_RDWR | O_NOCTTY | O_EXLOCK | O_NONBLOCK); // | O_NONBLOCK);
	return [self openWithFlags:flags error:nil];
}

- (void)close
{
	// Traditionally it is good to reset a serial port back to
	// the state in which you found it.  Let's continue that tradition.
	if (_fileDescriptor >= 0) {
		//NSLog(@"close - attempt closeLock");
		[_closeLock lock];
		//NSLog(@"close - closeLock locked");
		
		// kill pending read by setting O_NONBLOCK
		if (fcntl(_fileDescriptor, F_SETFL, fcntl(_fileDescriptor, F_GETFL, 0) | O_NONBLOCK) == -1) {
#ifdef AMSerialDebug
			NSLog(@"Error clearing O_NONBLOCK %@ - %s(%d).\n", _bsdPath, strerror(errno), errno);
#endif
		}
		if (tcsetattr(_fileDescriptor, TCSANOW, _originalOptions) == -1) {
#ifdef AMSerialDebug
			NSLog(@"Error resetting tty attributes - %s(%d).\n", strerror(errno), errno);
#endif
		}
		
		// Disallows further access to the communications channel
		[_fileHandle closeFile];

		// Release the fileHandle
#if !__has_feature(objc_arc)
		[_fileHandle release];
#endif
		_fileHandle = nil;
		
#ifdef AMSerialDebug
		NSLog(@"close (%d)\n", _fileDescriptor);
#endif
		// Close the fileDescriptor, that is our responsibility since the fileHandle does not own it
		close(_fileDescriptor);
		_fileDescriptor = -1;
		
		[_closeLock unlock];
		//NSLog(@"close - closeLock unlocked");
	}
}

- (BOOL)drainInput
{
	BOOL result = (tcdrain(_fileDescriptor) != -1);
	return result;
}

- (BOOL)flushInput:(BOOL)fIn output:(BOOL)fOut	// (fIn or fOut) must be YES
{
	int mode = 0;
	if (fIn) {
		mode = TCIFLUSH;
	}
	if (fOut) {
		mode = TCOFLUSH;
	}
	if (fIn && fOut) {
		mode = TCIOFLUSH;
	}
	
	BOOL result = (tcflush(_fileDescriptor, mode) != -1);
	return result;
}

- (BOOL)sendBreak
{
	BOOL result = (tcsendbreak(_fileDescriptor, 0) != -1);
	return result;
}

- (BOOL)setDTR
{
	BOOL result = (ioctl(_fileDescriptor, TIOCSDTR) != -1);
	return result;
}

- (BOOL)clearDTR
{
	BOOL result = (ioctl(_fileDescriptor, TIOCCDTR) != -1);
	return result;
}


// read and write serial port settings through a dictionary

- (void)buildOptionsDictionary
{
	[_optionsDictionary removeAllObjects];
	[_optionsDictionary setObject:[self name] forKey:AMSerialOptionServiceName];
	[_optionsDictionary setObject:[NSString stringWithFormat:@"%ld", [self speed]] forKey:AMSerialOptionSpeed];
	[_optionsDictionary setObject:[NSString stringWithFormat:@"%lu", [self dataBits]] forKey:AMSerialOptionDataBits];
	switch ([self parity]) {
		case kAMSerialParityOdd: {
			[_optionsDictionary setObject:@"Odd" forKey:AMSerialOptionParity];
			break;
		}
		case kAMSerialParityEven: {
			[_optionsDictionary setObject:@"Even" forKey:AMSerialOptionParity];
			break;
		}
		case kAMSerialParityNone:
		default: {
			break;
		}
	}
	
	[_optionsDictionary setObject:[NSString stringWithFormat:@"%d", [self stopBits]] forKey:AMSerialOptionStopBits];
	[_optionsDictionary setObject:@"None" forKey:AMSerialOptionInputFlowControl];
	if ([self RTSInputFlowControl]) {
		[_optionsDictionary setObject:@"RTS" forKey:AMSerialOptionInputFlowControl];
	}
	if ([self DTRInputFlowControl]) {
		[_optionsDictionary setObject:@"DTR" forKey:AMSerialOptionInputFlowControl];
	}
	
	[_optionsDictionary setObject:@"None" forKey:AMSerialOptionOutputFlowControl];
	if ([self CTSOutputFlowControl]) {
		[_optionsDictionary setObject:@"CTS" forKey:AMSerialOptionOutputFlowControl];
	}
	if ([self DSROutputFlowControl]) {
		[_optionsDictionary setObject:@"DSR" forKey:AMSerialOptionOutputFlowControl];
	}
	if ([self CAROutputFlowControl]) {
		[_optionsDictionary setObject:@"CAR" forKey:AMSerialOptionOutputFlowControl];
	}
	
	if ([self softwareFlowControl]) {
		[_optionsDictionary setObject:@"YES" forKey:AMSerialOptionSoftwareFlowControl];
	}
	
	if ([self signalsEnabled]) {
		[_optionsDictionary setObject:@"YES" forKey:AMSerialOptionSignals];
	}
	
	if ([self canonicalMode]) {
		[_optionsDictionary setObject:@"YES" forKey:AMSerialOptionCanonicalMode];
	}
	
	if ([self echoEnabled]) {
		[_optionsDictionary setObject:@"YES" forKey:AMSerialOptionEcho];
	}
	
	if ([self echoEraseEnabled]) {
		[_optionsDictionary setObject:@"YES" forKey:AMSerialOptionEchoErase];
	}
	
	if ([self softwareFlowControl]) {
		[_optionsDictionary setObject:@"YES" forKey:AMSerialOptionSoftwareFlowControl];
	}

	[_optionsDictionary setObject:[NSString stringWithFormat:@"%c", [self endOfLineCharacter]]
						   forKey:AMSerialOptionEndOfLineCharacter];
	[_optionsDictionary setObject:[NSString stringWithFormat:@"%c", [self startCharacter]]
						   forKey:AMSerialOptionStartCharacter];
	[_optionsDictionary setObject:[NSString stringWithFormat:@"%c", [self stopCharacter]]
						   forKey:AMSerialOptionStopCharacter];
}


- (NSDictionary *)options
{
	// will open the port to get options if neccessary
	if ([_optionsDictionary objectForKey:AMSerialOptionServiceName] == nil) {
		if (_fileDescriptor < 0) {
			[self open];
			[self close];
		}
		[self buildOptionsDictionary];
	}
	return [NSMutableDictionary dictionaryWithDictionary:_optionsDictionary];
}

- (void)setOptions:(NSDictionary *)newOptions
{
	assert(newOptions);
	
	// AMSerialOptionServiceName HAS to match! You may NOT switch ports using this
	// method.
	NSString *temp;
	
	if ([(NSString *)[newOptions objectForKey:AMSerialOptionServiceName] isEqualToString:[self name]]) {
		[self clearError];
		[_optionsDictionary addEntriesFromDictionary:newOptions];
		// parse dictionary
		temp = (NSString *)[_optionsDictionary objectForKey:AMSerialOptionSpeed];
		[self setSpeed:[temp intValue]];
		
		temp = (NSString *)[_optionsDictionary objectForKey:AMSerialOptionDataBits];
		[self setDataBits:[temp intValue]];
		
		temp = (NSString *)[_optionsDictionary objectForKey:AMSerialOptionParity];
		if (temp == nil || [temp isEqualToString:@"None"]) {
			[self setParity:kAMSerialParityNone];
		}
		else if ([temp isEqualToString:@"Odd"]) {
			[self setParity:kAMSerialParityOdd];
		}
		else {
			[self setParity:kAMSerialParityEven];
		}
		
		temp = (NSString *)[_optionsDictionary objectForKey:AMSerialOptionStopBits];
		int numStopBits = [temp intValue];
		[self setStopBits:(AMSerialStopBits)numStopBits];
		
		temp = (NSString *)[_optionsDictionary objectForKey:AMSerialOptionInputFlowControl];
		[self setRTSInputFlowControl:[temp isEqualToString:@"RTS"]];
		[self setDTRInputFlowControl:[temp isEqualToString:@"DTR"]];
		
		temp = (NSString *)[_optionsDictionary objectForKey:AMSerialOptionOutputFlowControl];
		[self setCTSOutputFlowControl:[temp isEqualToString:@"CTS"]];
		[self setDSROutputFlowControl:[temp isEqualToString:@"DSR"]];
		[self setCAROutputFlowControl:[temp isEqualToString:@"CAR"]];
		
		temp = (NSString *)[_optionsDictionary objectForKey:AMSerialOptionSignals];
		[self setSignalsEnabled:(temp != nil && [temp isEqualToString:@"YES"])];

		temp = (NSString *)[_optionsDictionary objectForKey:AMSerialOptionCanonicalMode];
		[self setCanonicalMode:(temp != nil && [temp isEqualToString:@"YES"])];

		temp = (NSString *)[_optionsDictionary objectForKey:AMSerialOptionEcho];
		[self setEchoEnabled:(temp != nil && [temp isEqualToString:@"YES"])];
		
		temp = (NSString *)[_optionsDictionary objectForKey:AMSerialOptionEchoErase];
		[self setEchoEraseEnabled:(temp != nil && [temp isEqualToString:@"YES"])];
		
		temp = (NSString *)[_optionsDictionary objectForKey:AMSerialOptionSoftwareFlowControl];
		[self setSoftwareFlowControl:(temp != nil && [temp isEqualToString:@"YES"])];

		temp = (NSString *)[_optionsDictionary objectForKey:AMSerialOptionEndOfLineCharacter];
		if ([temp length] > 0) {
			unichar character = [temp characterAtIndex:0];
			[self setEndOfLineCharacter:(char)character]; // this assumes that the character in question is a single byte char
		}
		temp = (NSString *)[_optionsDictionary objectForKey:AMSerialOptionStartCharacter];
		if ([temp length] > 0) {
			unichar character = [temp characterAtIndex:0];
			[self setStartCharacter:(char)character]; // this assumes that the character in question is a single byte char
		}
		temp = (NSString *)[_optionsDictionary objectForKey:AMSerialOptionStopCharacter];
		if ([temp length] > 0) {
			unichar character = [temp characterAtIndex:0];
			[self setStopCharacter:(char)character]; // this assumes that the character in question is a single byte char
		}
		
		[self commitChanges];
	} else {
#ifdef AMSerialDebug
		NSLog(@"Error setting options for port %@ (wrong port name: %@).\n", [self name], [newOptions objectForKey:AMSerialOptionServiceName]);
#endif
	}
}


- (speed_t)speed
{
	return cfgetospeed(_options);	// we should support cfgetispeed too
}

- (BOOL)setSpeed:(speed_t)speed
{
	BOOL result = YES;
	// we should support setting input and output speed separately
	int errorCode = 0;

// ***NOTE***: This code does not seem to work.  It was taken from Apple's sample code:
// <http://developer.apple.com/samplecode/SerialPortSample/listing2.html>
// and that code does not work either.  select() times out regularly if this code path is taken.
#if 0
	// Starting with Tiger, the IOSSIOSPEED ioctl can be used to set arbitrary baud rates
	// other than those specified by POSIX. The driver for the underlying serial hardware
	// ultimately determines which baud rates can be used. This ioctl sets both the input
	// and output speed. 
	
	speed_t newSpeed = speed;
	if (fileDescriptor >= 0) {
		errorCode = ioctl(fileDescriptor, IOSSIOSPEED, &newSpeed);
	} else {
		result = NO;
		gotError = YES;
		lastError = EBADF; // Bad file descriptor
	}
#else
	// set both the input and output speed
	errorCode = cfsetspeed(_options, speed);
#endif
	if (errorCode == -1) {
		result = NO;
		_gotError = YES;
		_lastError = errno;
	}
	return result;
}


- (unsigned long)dataBits
{
	return 5 + ((_options->c_cflag & CSIZE) >> 8);
	// man ... I *hate* C syntax ...
}

- (void)setDataBits:(unsigned long)bits	// 5 to 8 (5 is marked as "(pseudo)")
{
	// ?? options->c_oflag &= ~OPOST;
	_options->c_cflag &= ~CSIZE;
	switch (bits) {
		case 5:	_options->c_cflag |= CS5;	// redundant since CS5 == 0
			break;
		case 6:	_options->c_cflag |= CS6;
			break;
		case 7:	_options->c_cflag |= CS7;
			break;
		case 8:	_options->c_cflag |= CS8;
			break;
	}
}


- (AMSerialParity)parity
{
	AMSerialParity result;
	if (_options->c_cflag & PARENB) {
		if (_options->c_cflag & PARODD) {
			result = kAMSerialParityOdd;
		} else {
			result = kAMSerialParityEven;
		}
	} else {
		result = kAMSerialParityNone;
	}
	return result;
}

- (void)setParity:(AMSerialParity)newParity
{
	switch (newParity) {
		case kAMSerialParityNone: {
			_options->c_cflag &= ~PARENB;
			break;
		}
		case kAMSerialParityOdd: {
			_options->c_cflag |= PARENB;
			_options->c_cflag |= PARODD;
			break;
		}
		case kAMSerialParityEven: {
			_options->c_cflag |= PARENB;
			_options->c_cflag &= ~PARODD;
			break;
		}
	}
}


- (AMSerialStopBits)stopBits
{
	if (_options->c_cflag & CSTOPB) {
		return kAMSerialStopBitsTwo;
	}
	else {
		return kAMSerialStopBitsOne;
	}
}

- (void)setStopBits:(AMSerialStopBits)numBits
{
	if (numBits == kAMSerialStopBitsOne) {
		_options->c_cflag &= ~CSTOPB;
	}
	else if (numBits == kAMSerialStopBitsTwo) {
		_options->c_cflag |= CSTOPB;
	}
}


- (BOOL)RTSInputFlowControl
{
	return (_options->c_cflag & CRTS_IFLOW) != 0;
}

- (void)setRTSInputFlowControl:(BOOL)rts
{
	if (rts) {
		_options->c_cflag |= CRTS_IFLOW;
	}
	else {
		_options->c_cflag &= ~CRTS_IFLOW;
	}
}


- (BOOL)DTRInputFlowControl
{
	return (_options->c_cflag & CDTR_IFLOW) != 0;
}

- (void)setDTRInputFlowControl:(BOOL)dtr
{
	if (dtr) {
		_options->c_cflag |= CDTR_IFLOW;
	}
	else {
		_options->c_cflag &= ~CDTR_IFLOW;
	}
}


- (BOOL)CTSOutputFlowControl
{
	return (_options->c_cflag & CCTS_OFLOW) != 0;
}

- (void)setCTSOutputFlowControl:(BOOL)cts
{
	if (cts) {
		_options->c_cflag |= CCTS_OFLOW;
	}
	else {
		_options->c_cflag &= ~CCTS_OFLOW;
	}
}


- (BOOL)DSROutputFlowControl
{
	return (_options->c_cflag & CDSR_OFLOW) != 0;
}

- (void)setDSROutputFlowControl:(BOOL)dsr
{
	if (dsr)
		_options->c_cflag |= CDSR_OFLOW;
	else
		_options->c_cflag &= ~CDSR_OFLOW;
}


- (BOOL)CAROutputFlowControl
{
	return (_options->c_cflag & CCAR_OFLOW) != 0;
}

- (void)setCAROutputFlowControl:(BOOL)car
{
	if (car) {
		_options->c_cflag |= CCAR_OFLOW;
	}
	else {
		_options->c_cflag &= ~CCAR_OFLOW;
	}
}


- (BOOL)hangupOnClose
{
	return (_options->c_cflag & HUPCL) != 0;
}

- (void)setHangupOnClose:(BOOL)hangup
{
	if (hangup) {
		_options->c_cflag |= HUPCL;
	}
	else {
		_options->c_cflag &= ~HUPCL;
	}
}

- (BOOL)localMode
{
	return (_options->c_cflag & CLOCAL) != 0;
}

- (void)setLocalMode:(BOOL)local
{
	// YES = ignore modem status lines
	if (local) {
		_options->c_cflag |= CLOCAL;
	}
	else {
		_options->c_cflag &= ~CLOCAL;
	}
}

- (BOOL)signalsEnabled
{
	return (_options->c_lflag & ICANON) != 0;
}

- (void)setSignalsEnabled:(BOOL)signals
{
	if (signals) {
		_options->c_lflag |= ISIG;
	}
	else {
		_options->c_lflag &= ~ISIG;
	}
}

- (BOOL)canonicalMode
{
	return (_options->c_lflag & ICANON) != 0;
}

- (void)setCanonicalMode:(BOOL)flag
{
	if (flag) {
		_options->c_lflag |= ICANON;
	}
	else {
		_options->c_lflag &= ~ICANON;
	}
}

- (BOOL)echoEnabled
{
	return (_options->c_lflag & ECHO);
}

- (void)setEchoEnabled:(BOOL)echo
{
	if (echo)
		_options->c_lflag |= ECHO;
	else
		_options->c_lflag &= ~ECHO;
}

- (BOOL)echoEraseEnabled
{
	return (_options->c_lflag & ECHO);
}

- (void)setEchoEraseEnabled:(BOOL)echoE
{
	if (echoE) {
		_options->c_lflag |= ECHOE;
	}
	else {
		_options->c_lflag &= ~ECHOE;
	}
}

- (char)endOfLineCharacter
{
	return _options->c_cc[VEOL];
}

- (void)setEndOfLineCharacter:(char)eol
{
	_options->c_cc[VEOL] = eol;
}

- (char)startCharacter
{
	return _options->c_cc[VSTART];
}

- (void)setStartCharacter:(char)start
{
	_options->c_cc[VSTART] = start;
}

- (char)stopCharacter
{
	return _options->c_cc[VSTOP];
}

- (void)setStopCharacter:(char)stop
{
	_options->c_cc[VSTOP] = stop;
}

- (BOOL)softwareFlowControl
{
	BOOL xon = (_options->c_iflag & IXON) != 0;
	BOOL xoff = (_options->c_iflag & IXOFF) != 0;
	return xon || xoff;
}

- (void)setSoftwareFlowControl:(BOOL)xonxoff
{
	if (xonxoff) {
		_options->c_iflag |= (IXON | IXOFF);
	} else {
		_options->c_iflag &= ~(IXON | IXOFF);
	}
}

- (BOOL)remoteEchoEnabled
{
	BOOL icanon = (_options->c_lflag & ICANON) != 0;
	BOOL echo = (_options->c_lflag & ECHO) != 0;
	return icanon && echo;
}

- (void)setRemoteEchoEnabled:(BOOL)remoteEcho
{
	if (remoteEcho) {
		_options->c_lflag |= (ICANON | ECHO | ECHOE);
	} else {
		_options->c_lflag &= ~(ICANON | ECHO | ECHOE | ISIG);
	}
}

- (void)clearError
{
	// call this before changing any settings
	_gotError = NO;
}

- (BOOL)commitChanges
{
	// call this after using any of the setters above
	if (_gotError) {
		return NO;
	}
	
	if (tcsetattr(_fileDescriptor, TCSANOW, _options) == -1) {
		// something went wrong
		_gotError = YES;
		_lastError = errno;
		return NO;
	} else {
		[self buildOptionsDictionary];
		return YES;
	}
}

- (int)errorCode
{
	// if -commitChanges returns NO, look here for further info
	return _lastError;
}

@synthesize readTimeout = _readTimeout;

- (void)readTimeoutAsTimeval:(struct timeval*)timeout
{
	assert(timeout);
	
	NSTimeInterval timeoutInterval = [self readTimeout];
	double numSecs = trunc(timeoutInterval);
	double numUSecs = (timeoutInterval-numSecs)*1000000.0;
	timeout->tv_sec = (time_t)lrint(numSecs);
	timeout->tv_usec = (suseconds_t)lrint(numUSecs);
}

@end
