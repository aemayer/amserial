//
//  AMSerialPortAdditions.h
//
//  Created by Andreas Mayer on 2002-05-02.
//  Copyright (c) 2001-2020 Andreas Mayer. All rights reserved.
//

#import "AMSDKCompatibility.h"

#import <Foundation/Foundation.h>
#import "AMSerialPort.h"

NS_ASSUME_NONNULL_BEGIN

@interface AMSerialPort (AMSerialPortAdditions)

// returns the number of bytes available in the input buffer, or -1 upon error
// Be careful how you use this information, it may be out of date just after you get it
- (int)bytesAvailable;

- (void)waitForInput:(id)target selector:(SEL)selector;


// all blocking reads returns after [self readTimout] seconds elapse, at the latest
- (nullable NSData *)readAndReturnError:(NSError **)error;

// returns after 'bytes' bytes are read
- (nullable NSData *)readBytes:(NSUInteger)bytes
						 error:(NSError **)error;

// returns when 'stopChar' is encountered at the end of the read buffer.
// the 'stopChar' value is treated as a byte, there is no regard for character/string encoding.
// NOTE: this doesn't necessarily stop at the first encountered such character,
// but rather once a chunk it reads ends with the given character.
- (nullable NSData *)readUpToChar:(char)stopChar
							error:(NSError **)error;

// returns after 'bytes' bytes are read or if 'stopChar' is encountered, whatever comes first
- (nullable NSData *)readBytes:(NSUInteger)bytes
					  upToChar:(char)stopChar
						 error:(NSError **)error;

// data read will be converted into an NSString, using the given encoding
// NOTE: encodings that take up more than one byte per character may fail if only a part of the final string was received
- (nullable NSString *)readStringUsingEncoding:(NSStringEncoding)encoding
										 error:(NSError **)error;

- (nullable NSString *)readBytes:(NSUInteger)bytes
				   usingEncoding:(NSStringEncoding)encoding
						   error:(NSError **)error;

// same as readUpToChar:error: except attempts to convert the resulting data
// into a string of the given encoding.
- (nullable NSString *)readUpToChar:(char)stopChar
					  usingEncoding:(NSStringEncoding)encoding
							  error:(NSError **)error;

- (nullable NSString *)readBytes:(NSUInteger)bytes
						upToChar:(char)stopChar
				   usingEncoding:(NSStringEncoding)encoding
						   error:(NSError **)error;

// write to the serial port. Returns NO if an error occurred or if data is nil or empty.
- (BOOL)writeData:(nullable NSData *)data
			error:(NSError **)error;

// converts string to data of the given encoding (giving nil on failure), then invokes writeData:error:.
- (BOOL)writeString:(nullable NSString *)string
	  usingEncoding:(NSStringEncoding)encoding
			  error:(NSError **)error;

// wraps the given buffer as NSData, then invokes writeData:error:.
- (BOOL)writeBytes:(nullable const void *)bytes
			length:(NSUInteger)length
			 error:(NSError **)error;


- (void)readDataInBackground;
//
// Will send serialPortReadData: to delegate
// the dataDictionary object will contain these entries:
// 1. "serialPort": the AMSerialPort object that sent the message
// 2. "data": (NSData *)data - received data

- (void)stopReadInBackground;

- (void)writeDataInBackground:(NSData *)data;
//
// Will send serialPortWriteProgress: to delegate if task lasts more than
// approximately three seconds.
// the dataDictionary object will contain these entries:
// 1. "serialPort": the AMSerialPort object that sent the message
// 2. "value": (NSNumber *)value - bytes sent
// 3. "total": (NSNumber *)total - bytes total

- (void)stopWriteInBackground;

- (int)numberOfWriteInBackgroundThreads;

@end

NS_ASSUME_NONNULL_END
