//
//  AMSerialPort.h
//
//  Created by Andreas Mayer on 2002-04-24.
//  SPDX-FileCopyrightText: Copyright (c) 2001-2020 Andreas Mayer. All rights reserved.
//  SPDX-License-Identifier: BSD-3-Clause
//

#import "AMSDKCompatibility.h"

#import <termios.h>

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

#define	AMSerialOptionServiceName @"AMSerialOptionServiceName"
#define	AMSerialOptionSpeed @"AMSerialOptionSpeed"
#define	AMSerialOptionDataBits @"AMSerialOptionDataBits"
#define	AMSerialOptionParity @"AMSerialOptionParity"
#define	AMSerialOptionStopBits @"AMSerialOptionStopBits"
#define	AMSerialOptionInputFlowControl @"AMSerialOptionInputFlowControl"
#define	AMSerialOptionOutputFlowControl @"AMSerialOptionOutputFlowControl"
#define	AMSerialOptionSignals @"AMSerialOptionSignals"
#define	AMSerialOptionCanonicalMode @"AMSerialOptionCanonicalMode"
#define	AMSerialOptionEcho @"AMSerialOptionEcho"
#define	AMSerialOptionEchoErase @"AMSerialOptionEchoErase"
#define	AMSerialOptionSoftwareFlowControl @"AMSerialOptionSoftwareFlowControl"
#define	AMSerialOptionRemoteEcho @"AMSerialOptionRemoteEcho"
#define	AMSerialOptionEndOfLineCharacter @"AMSerialOptionEndOfLineCharacter"
#define	AMSerialOptionStartCharacter @"AMSerialOptionStartCharacter"
#define	AMSerialOptionStopCharacter @"AMSerialOptionStopCharacter"

// By default, debug code is preprocessed out.  If you would like to compile with debug code enabled,
// "#define AMSerialDebug" before including any AMSerialPort headers, as in your prefix header

typedef NS_ENUM(int, AMSerialParity) {
	kAMSerialParityNone = 0,
	kAMSerialParityOdd = 1,
	kAMSerialParityEven = 2
};

typedef NS_ENUM(int, AMSerialStopBits) {
	kAMSerialStopBitsOne = 1,
	kAMSerialStopBitsTwo = 2
};

// Private constant
#define AMSER_MAXBUFSIZE  (4096UL)

extern NSString *const AMSerialErrorDomain;

@protocol AMSerialDelegate <NSObject>
@optional
- (void)serialPortReadData:(NSDictionary *)dataDictionary;
- (void)serialPortWriteProgress:(NSDictionary *)dataDictionary;
@end

@interface AMSerialPort : NSObject
{
@private
	NSString *_bsdPath;
	NSString *_serviceName;
	NSString *_serviceType;
	int _fileDescriptor;
	struct termios * _options;
	struct termios * _originalOptions;
	NSMutableDictionary *_optionsDictionary;
	NSFileHandle *_fileHandle;
	BOOL _gotError;
	int	_lastError;
	id _owner;
	char * _buffer;
	NSTimeInterval _readTimeout; // for public blocking read methods and doRead
	fd_set * _readfds;
#if !__has_feature(objc_arc)
	NSObject<AMSerialDelegate>* _delegate;
#endif
	NSLock *_writeLock;
	NSLock *_readLock;
	NSLock *_closeLock;
	
	// used by AMSerialPortAdditions only:
	id _am_readTarget;
	SEL _am_readSelector;
	BOOL _stopWriteInBackground;
	int _countWriteInBackgroundThreads;
	BOOL _stopReadInBackground;
	int _countReadInBackgroundThreads;
}

- (instancetype)init:(NSString *)path withName:(NSString *)name type:(NSString *)serialType NS_DESIGNATED_INITIALIZER;
// Designated initializer
// initializes port
// path is a bsdPath
// name is an IOKit service name
// type is an IOKit service type

- (NSString *)bsdPath;
// bsdPath (e.g. '/dev/cu.modem')

- (NSString *)name;
// IOKit service name (e.g. 'modem')

- (NSString *)type;
// IOKit service type (kIOSerialBSDAllTypes, kIOSerialBSDModemType, kIOSerialBSDRS232Type)

- (nullable NSDictionary *)properties;
// IORegistry entry properties - see IORegistryEntryCreateCFProperties()


- (BOOL)isOpen;
// YES if port is open

- (nullable AMSerialPort *)obtainBy:(id)sender;
// get this port exclusively; nil if it's not free

- (void)free;
// give it back (and close the port if still open)

- (BOOL)available;
// check if port is free and can be obtained

- (nullable id)owner;
// who obtained the port?


- (nullable NSFileHandle *)openWithFlags:(int)flags error:(NSError**)error;
// opens port for read and write operations, passing the given flags to open().
// Returns nil upon error and an NSError by reference.
// You must balance a successful invocation with a call to close.
// To actually read or write data, use the methods provided by NSFileHandle
// (alternatively you may use those from AMSerialPortAdditions)

- (nullable NSFileHandle *)open;
// invokes openWithFlags:error: with flags to allow shared access of port

- (nullable NSFileHandle *)openExclusively;
// invokes openWithFlags:error: with flags to insist on exclusive access to port

- (void)close;
// close port - no more read or write operations allowed

- (BOOL)drainInput;
- (BOOL)flushInput:(BOOL)fIn output:(BOOL)fOut;	// (fIn or fOut) must be YES
- (BOOL)sendBreak;

- (BOOL)setDTR;
// set DTR - not yet tested!

- (BOOL)clearDTR;
// clear DTR - not yet tested!

// read and write serial port settings through a dictionary

- (NSDictionary *)options;
// will open the port to get options if neccessary

- (void)setOptions:(NSDictionary *)options;
// AMSerialOptionServiceName HAS to match! You may NOT switch ports using this
// method.

// Use the speeds defined in termios.h
// reading and setting parameters is only useful if the serial port is already open
- (speed_t)speed;
- (BOOL)setSpeed:(speed_t)speed;

- (unsigned long)dataBits;
- (void)setDataBits:(unsigned long)bits;	// 5 to 8 (5 may not work)

- (AMSerialParity)parity;
- (void)setParity:(AMSerialParity)newParity;

- (AMSerialStopBits)stopBits;
- (void)setStopBits:(AMSerialStopBits)numBits;

- (BOOL)RTSInputFlowControl;
- (void)setRTSInputFlowControl:(BOOL)rts;

- (BOOL)DTRInputFlowControl;
- (void)setDTRInputFlowControl:(BOOL)dtr;

- (BOOL)CTSOutputFlowControl;
- (void)setCTSOutputFlowControl:(BOOL)cts;

- (BOOL)DSROutputFlowControl;
- (void)setDSROutputFlowControl:(BOOL)dsr;

- (BOOL)CAROutputFlowControl;
- (void)setCAROutputFlowControl:(BOOL)car;

- (BOOL)hangupOnClose;
- (void)setHangupOnClose:(BOOL)hangup;

- (BOOL)localMode;
- (void)setLocalMode:(BOOL)local;	// YES = ignore modem status lines

- (BOOL)signalsEnabled;			// (ISIG)
- (void)setSignalsEnabled:(BOOL)signals;

- (BOOL)canonicalMode;			// (ICANON)
- (void)setCanonicalMode:(BOOL)flag;

- (BOOL)echoEnabled;			// (ECHO)
- (void)setEchoEnabled:(BOOL)echoE;

- (BOOL)echoEraseEnabled;		// echo erase character as BS-SP-BS (ECHOE)
- (void)setEchoEraseEnabled:(BOOL)echo;

- (char)endOfLineCharacter;
- (void)setEndOfLineCharacter:(char)eol;

- (char)startCharacter;	// XON character - normally DC1 (021)
- (void)setStartCharacter:(char)start;

- (char)stopCharacter;	// XOFF character - normally DC3 (023)
- (void)setStopCharacter:(char)stop;

- (BOOL)softwareFlowControl;	// YES = uses XON/XOFF software flow control
- (void)setSoftwareFlowControl:(BOOL)xonxoff;	// sets or clears XON and XOFF

// these are shortcuts for getting/setting the mentioned flags separately
- (BOOL)remoteEchoEnabled;	// YES if ICANON and ECHO are set
- (void)setRemoteEchoEnabled:(BOOL)remoteEcho;	//	YES: set ICANON, ECHO and ECHOE
													//	NO: clear ICANON, ECHO, ECHOE and ISIG

- (void)clearError;			// call this before changing any settings
- (BOOL)commitChanges;	// call this after using any of the above set... functions
- (int)errorCode;				// if -commitChanges returns NO, look here for further info

// the delegate (for background reading/writing)
#if __has_feature(objc_arc)
@property(readwrite, weak, nullable, atomic) NSObject<AMSerialDelegate>* delegate;
#else
@property(readwrite, assign, nullable, nonatomic) NSObject<AMSerialDelegate>* delegate;
#endif

// time out for blocking reads in seconds. Honoured as best a possible, but is not an upper or lower bound. Must be finite and non-negative.
@property(readwrite, atomic) NSTimeInterval readTimeout;

- (void)readTimeoutAsTimeval:(struct timeval*)timeout;


@end

NS_ASSUME_NONNULL_END
