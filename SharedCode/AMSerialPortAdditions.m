//
//  AMSerialPortAdditions.m
//
//  Created by Andreas Mayer on 2002-05-02.
//  SPDX-FileCopyrightText: Copyright (c) 2001-2020 Andreas Mayer. All rights reserved.
//  SPDX-License-Identifier: BSD-3-Clause
//
//  2002-07-02 Andreas Mayer
//  - initialize buffer in readString
//  2002-10-04 Andreas Mayer
//  - readDataInBackgroundWithTarget:selector: and writeDataInBackground: added
//  2002-10-10 Andreas Mayer
//  - stopWriteInBackground added
//  - send notifications about sent data through distributed notification center
//  2002-10-17 Andreas Mayer
//  - numberOfWriteInBackgroundThreads added
//  - if total write time will exceed 3 seconds, send
//    CommXWriteInBackgroundProgressNotification without delay
//  2002-10-25 Andreas Mayer
//  - readDataInBackground and stopReadInBackground added
//  2004-02-10 Andreas Mayer
//    - replaced notifications for background reading/writing with direct messages to delegate
//      see informal protocol
//  2004-08-18 Andreas Mayer
//  - readStringOfLength: added (suggested by Michael Beck)
//  2005-04-11 Andreas Mayer
//  -  attempt at a fix for readDataInBackgroundThread - fileDescriptor could already be closed
//     (thanks to David Bainbridge for the bug report) does not work as of yet
//  2006-08-16 Andreas Mayer / Sean McBride
//  - changed interface for blocking read/write access significantly
//  - fixed -checkRead and renamed it to -bytesAvailable
//  - see AMSerialPort_Deprecated for old interfaces
//  2007-10-26 Sean McBride
//  - made code 64 bit and garbage collection clean
//  2009-05-08 Sean McBride
//  - added writeBytes:length:error: method
//  - associated a name with created threads (for debugging, 10.6 only)
//  2010-01-04 Sean McBride
//  - fixed some memory management issues
//  - the timeout feature (for reading) was broken, now fixed
//  - don't rely on system clock for measuring elapsed time (because the user can change the clock)
//  2011-10-18 Andreas Mayer
//  - added ARC compatibility
//  2011-10-19 Sean McBride
//  - code review of ARC changes
//  2012-03-12 Sean McBride
//  - replaced deprecated UpTime function with mach_absolute_time
//  2016-03-17 Sean McBride
//  - added nullability support

#import "AMSDKCompatibility.h"

#import <sys/ioctl.h>
#import <sys/filio.h>
#import <pthread.h>
#import <mach/mach_time.h>

#import "AMSerialPortAdditions.h"
#import "AMSerialErrors.h"

// Workaround for <rdar://14095332>.  The 10.11 SDK and older have a minor undefined behaviour where "1 << 31" may be performed.  (It's actually undefined to left-shift a 1 into the sign bit.)  So I just copy-pasted the corrected macro from the 10.12 SDK.
#if (MAC_OS_X_VERSION_MAX_ALLOWED < 101200)
	#define	AM_FD_SET(n, p)	do { int __fd = (n); ((p)->fds_bits[(unsigned long)__fd/__DARWIN_NFDBITS] |= ((__int32_t)(((unsigned long)1)<<((unsigned long)__fd % __DARWIN_NFDBITS)))); } while(0)
#else
	#define	AM_FD_SET(n, p) FD_SET(n, p)
#endif

@interface AMSerialPort (AMSerialPortAdditionsPrivate)
- (void)readDataInBackgroundThread:(id)unused;
- (void)writeDataInBackgroundThread:(NSData *)data;
- (nullable id)am_readTarget;
- (void)am_setReadTarget:(nullable id)newReadTarget;
- (nullable NSData *)readAndStopAfterBytes:(BOOL)stopAfterBytes bytes:(NSUInteger)bytes stopAtChar:(BOOL)stopAtChar stopChar:(char)stopChar error:(NSError **)error;
- (void)reportProgress:(NSUInteger)progress dataLen:(NSUInteger)dataLen;
@end


@implementation AMSerialPort (AMSerialPortAdditions)


// ============================================================
#pragma mark -
#pragma mark blocking IO
// ============================================================

- (void)doRead:(NSTimer *)timer
{
	assert(timer); (void)timer;
	
#ifdef AMSerialDebug
	NSLog(@"doRead");
#endif
	int res;
	struct timeval timeout;
	if (_fileDescriptor >= 0) {
		FD_ZERO(_readfds);
		AM_FD_SET(_fileDescriptor, _readfds);
		[self readTimeoutAsTimeval:&timeout];
		res = select(_fileDescriptor+1, _readfds, nil, nil, &timeout);
		if (res >= 1) {
			NSString *readStr = [self readStringUsingEncoding:NSUTF8StringEncoding error:nil];
			// ARC will complain because the selector is unknown at this point; this is correct.
			// We might replace -waitForInput:selector: with a block based method in the future
			// and thus avoid this problem. Until then, we disable the warning.
#if defined(__clang__) && defined(__has_warning)
	#if __has_warning("-Warc-performSelector-leaks")
		#pragma clang diagnostic push
		#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
	#endif
#endif
			[[self am_readTarget] performSelector:_am_readSelector withObject:readStr];
#if defined(__clang__) && defined(__has_warning)
	#if __has_warning("-Warc-performSelector-leaks")
		#pragma clang diagnostic pop
	#endif
#endif
			[self am_setReadTarget:nil];
		} else {
			[NSTimer scheduledTimerWithTimeInterval:0.1
											 target:self
										   selector:@selector(doRead:)
										   userInfo:self
											repeats:NO];
		}
	} else {
		// file already closed
		[self am_setReadTarget:nil];
	}
}

// all blocking reads returns after [self readTimout] seconds elapse, at the latest
- (nullable NSData *)readAndReturnError:(NSError **)error
{
	NSData *result = [self readAndStopAfterBytes:NO bytes:0 stopAtChar:NO stopChar:0 error:error];
	return result;
}

// returns after 'bytes' bytes are read
- (nullable NSData *)readBytes:(NSUInteger)bytes
						 error:(NSError **)error
{
	NSData *result = [self readAndStopAfterBytes:YES bytes:bytes stopAtChar:NO stopChar:0 error:error];
	return result;
}

// returns when 'stopChar' is encountered
- (nullable NSData *)readUpToChar:(char)stopChar
							error:(NSError **)error
{
	NSData *result = [self readAndStopAfterBytes:NO bytes:0 stopAtChar:YES stopChar:stopChar error:error];
	return result;
}

// returns after 'bytes' bytes are read or if 'stopChar' is encountered, whatever comes first
- (nullable NSData *)readBytes:(NSUInteger)bytes
					  upToChar:(char)stopChar
						 error:(NSError **)error
{
	NSData *result = [self readAndStopAfterBytes:YES bytes:bytes stopAtChar:YES stopChar:stopChar error:error];
	return result;
}

// data read will be converted into an NSString, using the given encoding
// NOTE: encodings that take up more than one byte per character may fail if only a part of the final string was received
- (nullable NSString *)readStringUsingEncoding:(NSStringEncoding)encoding
										 error:(NSError **)error
{
	NSString *result = nil;
	NSData *data = [self readAndStopAfterBytes:NO bytes:0 stopAtChar:NO stopChar:0 error:error];
	if (data) {
		result = [[NSString alloc] initWithData:data encoding:encoding];
#if !__has_feature(objc_arc)
		[result autorelease];
#endif
	}
	return result;
}

- (nullable NSString *)readBytes:(NSUInteger)bytes
				   usingEncoding:(NSStringEncoding)encoding
						   error:(NSError **)error
{
	NSString *result = nil;
	NSData *data = [self readAndStopAfterBytes:YES bytes:bytes stopAtChar:NO stopChar:0 error:error];
	if (data) {
		result = [[NSString alloc] initWithData:data encoding:encoding];
#if !__has_feature(objc_arc)
		[result autorelease];
#endif
	}
	return result;
}

// NOTE: 'stopChar' has to be a byte value, using the given encoding; you can not wait for an arbitrary character from a multi-byte encoding
- (nullable NSString *)readUpToChar:(char)stopChar
					  usingEncoding:(NSStringEncoding)encoding
							  error:(NSError **)error
{
	NSString *result = nil;
	NSData *data = [self readAndStopAfterBytes:NO bytes:0 stopAtChar:YES stopChar:stopChar error:error];
	if (data) {
		result = [[NSString alloc] initWithData:data encoding:encoding];
#if !__has_feature(objc_arc)
		[result autorelease];
#endif
	}
	return result;
}

- (nullable NSString *)readBytes:(NSUInteger)bytes
						upToChar:(char)stopChar
				   usingEncoding:(NSStringEncoding)encoding
						   error:(NSError **)error
{
	NSString *result = nil;
	NSData *data = [self readAndStopAfterBytes:YES bytes:bytes stopAtChar:YES stopChar:stopChar error:error];
	if (data) {
		result = [[NSString alloc] initWithData:data encoding:encoding];
#if !__has_feature(objc_arc)
		[result autorelease];
#endif
	}
	return result;
}


// write to the serial port; NO if an error occurred
//
// Perhaps surprisingly, note that if 'error' is non-nil, an NSError is always created,
// even if the method was successful. Only consult the error if the method returns NO.
- (BOOL)writeData:(nullable NSData *)data
			error:(NSError **)error
{
#ifdef AMSerialDebug
	NSString *dataAsString = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
	NSLog(@"•wrote: %@ • %@", data, dataAsString);
#endif

	BOOL result = NO;

	const char *dataBytes = (const char*)[data bytes];
	NSUInteger dataLen = [data length];
	ssize_t bytesWritten = 0;
	AMSerialError errorCode = kAMSerialErrorNone;
	if (dataBytes && (dataLen > 0)) {
		bytesWritten = write(_fileDescriptor, dataBytes, dataLen);
		if (bytesWritten < 0) {
			errorCode = kAMSerialErrorFatal;
		} else if ((NSUInteger)bytesWritten == dataLen) {
			result = YES;
		} else {
			errorCode = kAMSerialErrorOnlySomeDataWritten;
		}
	} else {
		errorCode = kAMSerialErrorNoDataToWrite;
	}
	if (error) {
		NSDictionary *userInfo = nil;
		if (bytesWritten > 0) {
			NSNumber* bytesWrittenNum = [NSNumber numberWithLongLong:bytesWritten];
			userInfo = [NSDictionary dictionaryWithObject:bytesWrittenNum forKey:@"bytesWritten"];
		}
		*error = [NSError errorWithDomain:AMSerialErrorDomain code:errorCode userInfo:userInfo];
	}
	
#ifdef __OBJC_GC__
	// To prevent premature collection.  (Under GC, the given NSData may have no strong references for all we know, and our inner pointer does not keep the NSData alive.  So without this, the data could be collected before we are done with it!)
	[data self];
#endif
	
	return result;
}

- (BOOL)writeString:(nullable NSString *)string
	  usingEncoding:(NSStringEncoding)encoding
			  error:(NSError **)error
{
	NSData *data = [string dataUsingEncoding:encoding];
	return [self writeData:data error:error];
}

- (BOOL)writeBytes:(nullable const void *)bytes
			length:(NSUInteger)length
			 error:(NSError **)error
{
	NSData *data = [NSData dataWithBytes:bytes length:length];
	return [self writeData:data error:error];
}

- (int)bytesAvailable
{
#ifdef AMSerialDebug
	NSLog(@"bytesAvailable");
#endif

	// yes, that cast is correct.  ioctl() is declared to take a char* but should be void* as really it
	// depends on the 2nd parameter.  Ahhh, I love crappy old UNIX APIs :)
	int result = 0;
	int err = ioctl(_fileDescriptor, FIONREAD, (char *)&result);
	if (err != 0) {
		result = -1;
	}
	return result;
}


- (void)waitForInput:(id)target selector:(SEL)selector
{
#ifdef AMSerialDebug
	NSLog(@"waitForInput");
#endif
	[self am_setReadTarget:target];
	_am_readSelector = selector;
	[NSTimer scheduledTimerWithTimeInterval:0.1
									 target:self
								   selector:@selector(doRead:)
								   userInfo:self
									repeats:NO];
}

// ============================================================
#pragma mark -
#pragma mark threaded IO
// ============================================================

- (void)readDataInBackground
{
#ifdef AMSerialDebug
	NSLog(@"readDataInBackground");
#endif
	NSObject<AMSerialDelegate>* strongDelegate = [self delegate];
	if ([strongDelegate respondsToSelector:@selector(serialPortReadData:)]) {
		_countReadInBackgroundThreads++;
		[NSThread detachNewThreadSelector:@selector(readDataInBackgroundThread:)
								 toTarget:self
							   withObject:nil];
	}
}

- (void)stopReadInBackground
{
#ifdef AMSerialDebug
	NSLog(@"stopReadInBackground");
#endif
	_stopReadInBackground = YES;
}

- (void)writeDataInBackground:(NSData *)data
{
	assert(data);
	
#ifdef AMSerialDebug
	NSLog(@"writeDataInBackground");
#endif
	NSObject<AMSerialDelegate>* strongDelegate = [self delegate];
	if ([strongDelegate respondsToSelector:@selector(serialPortWriteProgress:)]) {
		_countWriteInBackgroundThreads++;
		[NSThread detachNewThreadSelector:@selector(writeDataInBackgroundThread:)
								 toTarget:self
							   withObject:data];
	}
}

- (void)stopWriteInBackground
{
#ifdef AMSerialDebug
	NSLog(@"stopWriteInBackground");
#endif
	_stopWriteInBackground = YES;
}

- (int)numberOfWriteInBackgroundThreads
{
	return _countWriteInBackgroundThreads;
}


@end

#pragma mark -

static int64_t AMMicrosecondsSinceBoot (void)
{
	static mach_timebase_info_data_t machTimeBaseInfo;
	
	// If this is the first time we've run, get the timebase.
	if (machTimeBaseInfo.denom == 0)
	{
		mach_timebase_info(&machTimeBaseInfo);
	}
	
	// Convert to microseconds.
	uint64_t uptime = mach_absolute_time();
	uint64_t uptimeMicro = uptime * machTimeBaseInfo.numer / machTimeBaseInfo.denom / NSEC_PER_USEC;
	assert(uptimeMicro < INT64_MAX);
	
	return (int64_t)uptimeMicro;
}

@implementation AMSerialPort (AMSerialPortAdditionsPrivate)

// ============================================================
#pragma mark -
#pragma mark threaded methods
// ============================================================

- (void)readDataInBackgroundThread:(nullable id)unused
{
	(void)unused;
	
	(void)pthread_setname_np ("de.harmless.AMSerialPort.readDataInBackgroundThread");
	
	NSData *data = nil;
	void *localBuffer;
	ssize_t bytesRead = 0;
	fd_set *localReadFDs = NULL;

	[_readLock lock];	// read in sequence
	//NSLog(@"readDataInBackgroundThread - [readLock lock]");

	localBuffer = malloc(AMSER_MAXBUFSIZE);
	_stopReadInBackground = NO;
#if __has_feature(objc_arc)
	@autoreleasepool
#else
	NSAutoreleasePool *localAutoreleasePool = [[NSAutoreleasePool alloc] init];
#endif
	{
	[_closeLock lock];
	if ((_fileDescriptor >= 0) && (!_stopReadInBackground)) {
		//NSLog(@"readDataInBackgroundThread - [closeLock lock]");
		localReadFDs = (fd_set*)malloc(sizeof(fd_set));
		FD_ZERO(localReadFDs);
		AM_FD_SET(_fileDescriptor, localReadFDs);
		[_closeLock unlock];
		//NSLog(@"readDataInBackgroundThread - [closeLock unlock]");
		int res = select(_fileDescriptor+1, localReadFDs, nil, nil, nil); // timeout);
		if ((res >= 1) && (_fileDescriptor >= 0)) {
			bytesRead = read(_fileDescriptor, localBuffer, AMSER_MAXBUFSIZE);
		}
		if (bytesRead >= 0) {
			data = [NSData dataWithBytes:localBuffer length:(NSUInteger)bytesRead];
		}
		NSDictionary* tmp = [NSDictionary dictionaryWithObjectsAndKeys:
							 self, @"serialPort",
							 data, @"data", // data may be nil
							 nil];
		NSObject<AMSerialDelegate>* strongDelegate = [self delegate];
		[strongDelegate performSelectorOnMainThread:@selector(serialPortReadData:)
										 withObject:tmp
									  waitUntilDone:NO];
	} else {
		[_closeLock unlock];
	}
	}
#if !__has_feature(objc_arc)
	[localAutoreleasePool drain];
#endif
	free(localReadFDs);
	free(localBuffer);

	_countReadInBackgroundThreads--;

	[_readLock unlock];
	//NSLog(@"readDataInBackgroundThread - [readLock unlock]");
}

- (void)writeDataInBackgroundThread:(NSData *)data
{
	assert(data);
	
	(void)pthread_setname_np ("de.harmless.AMSerialPort.writeDataInBackgroundThread");
	
#ifdef AMSerialDebug
	NSLog(@"writeDataInBackgroundThread");
#endif
	void *localBuffer;
	NSUInteger pos;
	NSUInteger bufferLen;
	NSUInteger dataLen;
	ssize_t written;
	NSDate *nextNotificationDate;
	BOOL notificationSent = NO;
	speed_t speed;
	unsigned long estimatedTime;
	BOOL error = NO;
	
#if __has_feature(objc_arc)
	@autoreleasepool
#else
	NSAutoreleasePool *localAutoreleasePool = [[NSAutoreleasePool alloc] init];

	[data retain];
#endif
	{
	localBuffer = malloc(AMSER_MAXBUFSIZE);
	_stopWriteInBackground = NO;
	[_writeLock lock];	// write in sequence
	pos = 0;
	dataLen = [data length];
	speed = [self speed];
	estimatedTime = (dataLen*8)/speed;
	if (estimatedTime > 3) { // will take more than 3 seconds
		notificationSent = YES;
		[self reportProgress:pos dataLen:dataLen];
		nextNotificationDate = [NSDate dateWithTimeIntervalSinceNow:1.0];
	} else {
		nextNotificationDate = [NSDate dateWithTimeIntervalSinceNow:2.0];
	}
	while (!_stopWriteInBackground && (pos < dataLen) && !error) {
		bufferLen = MIN(AMSER_MAXBUFSIZE, dataLen-pos);

		[data getBytes:localBuffer range:NSMakeRange(pos, bufferLen)];
		written = write(_fileDescriptor, localBuffer, bufferLen);
		error = (written <= 0); // error condition
		if (error)
			break;
		pos += (NSUInteger)written;

		NSDate* now = [NSDate date];
		if ([now compare:nextNotificationDate] == NSOrderedDescending) {
			if (notificationSent || (pos < dataLen)) { // not for last block only
				notificationSent = YES;
				[self reportProgress:pos dataLen:dataLen];
				nextNotificationDate = [NSDate dateWithTimeIntervalSinceNow:1.0];
			}
		}
	}
	if (notificationSent) {
		[self reportProgress:pos dataLen:dataLen];
	}
	_stopWriteInBackground = NO;
	[_writeLock unlock];
	_countWriteInBackgroundThreads--;
	
	free(localBuffer);
	}
#if !__has_feature(objc_arc)
	[data release];
	[localAutoreleasePool drain];
#endif
}

- (nullable id)am_readTarget
{
	return _am_readTarget; 
}

- (void)am_setReadTarget:(nullable id)newReadTarget
{
	if (_am_readTarget != newReadTarget) {
#if !__has_feature(objc_arc)
		[newReadTarget retain];
		[_am_readTarget release];
#endif
		_am_readTarget = newReadTarget;
	}
}

// Low-level blocking read method.
// This method reads from the serial port and blocks as necessary, it returns when:
//  - [self readTimeout] seconds has elapsed
//  - if stopAfterBytes is YES, when 'bytesToRead' bytes have been read
//  - if stopAtChar is YES, when 'stopChar' is found at the end of the read buffer
//  - a fatal error occurs
//
// Upon return: as long as some data was actually read, and no serious error occurred, an autoreleased NSData
// object with that data is created and returned, otherwise nil is.
//
// Perhaps surprisingly, note that if 'error' is non-nil, an NSError is always created,
// even if the method was successful. Only consult the error if the method returns NO.
- (nullable NSData *)readAndStopAfterBytes:(BOOL)stopAfterBytes
									 bytes:(NSUInteger)bytesToRead
								stopAtChar:(BOOL)stopAtChar
								  stopChar:(char)stopChar
									 error:(NSError **)error
{
	NSData *result = nil;
	
	struct timeval timeout;
	NSUInteger bytesRead = 0;
	AMSerialError errorCode = kAMSerialErrorNone;
	AMSerialEndCode endCode = kAMSerialEndCodeEndOfStream;
	NSError *underlyingError = nil;
	
	// How long, in total, in microseconds, do we block before timing out?
	int64_t totalTimeout = llround([self readTimeout] * 1000000.0);
	assert(totalTimeout >= 0);
	
	// This value will be decreased each time through the loop
	int64_t remainingTimeout = totalTimeout;
	
	// Note the time that we start
	int64_t startTime = AMMicrosecondsSinceBoot();
	
	while (YES) {
		if (remainingTimeout <= 0) {
			errorCode = kAMSerialErrorTimeout;
			break;
		} else {
			// Convert to 'struct timeval'
			timeout.tv_sec = (__darwin_time_t)(remainingTimeout / 1000000);
			timeout.tv_usec = (__darwin_suseconds_t)(remainingTimeout - (timeout.tv_sec * 1000000));
#ifdef AMSerialDebug
			NSLog(@"timeout remaining: %qd µs = %ld s and %d µs", remainingTimeout, timeout.tv_sec, timeout.tv_usec);
#endif
			
			// If the remaining time is so small that it has rounded to zero, bump it up to 1 microsecond.
			// Why?  Because passing a zeroed timeval to select() indicates that we want to poll, but we don't.
			if ((timeout.tv_sec == 0) && (timeout.tv_usec == 0)) {
				timeout.tv_usec = 1;
			}
			FD_ZERO(_readfds);
			AM_FD_SET(_fileDescriptor, _readfds);
			int selectResult = select(_fileDescriptor+1, _readfds, NULL, NULL, &timeout);
			if (selectResult == -1) {
				underlyingError = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];
				errorCode = kAMSerialErrorFatal;
				break;
			} else if (selectResult == 0) {
				errorCode = kAMSerialErrorTimeout;
				break;
			} else if (selectResult == 1) {
				assert(FD_ISSET(_fileDescriptor, _readfds));
				
				size_t	sizeToRead;
				if (stopAfterBytes) {
					sizeToRead = (MIN(bytesToRead, AMSER_MAXBUFSIZE))-bytesRead;
				} else {
					sizeToRead = AMSER_MAXBUFSIZE-bytesRead;
				}
				assert(sizeToRead > 0);
				
				ssize_t	readResult = read(_fileDescriptor, _buffer+bytesRead, sizeToRead);
				if (readResult > 0) {
					bytesRead += (NSUInteger)readResult;
					assert((bytesRead > 0) && (bytesRead <= AMSER_MAXBUFSIZE));
					if (stopAfterBytes) {
						if (bytesRead == bytesToRead) {
							endCode = kAMSerialEndCodeStopLengthReached;
							break;
						} else if (bytesRead > bytesToRead) {
							endCode = kAMSerialEndCodeStopLengthExceeded;
							break;
						}
					}
					if (stopAtChar && (_buffer[bytesRead-1] == stopChar)) {
						endCode = kAMSerialEndCodeStopCharReached;
						break;
					}
					if (bytesRead >= AMSER_MAXBUFSIZE) {
						errorCode = kAMSerialErrorInternalBufferFull;
						break;
					}
				} else if (readResult == 0) {
					// Even though select() has indicated the descriptor is ready for reading, that doesn't actually mean there's any data there, and indeed upon reading end-of-file, zero is returned. We'll just try again next loop.
				} else {
					assert(readResult == -1);
					
					// Make underlying error
					underlyingError = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno userInfo:nil];
					errorCode = kAMSerialErrorFatal;
					break;
				}
			}
			else {
				// We only tried to examine one descriptor, so any other return value from select should be impossible.
				assert(0);
			}
			
			// Reduce the timeout value by the amount of time actually spent so far
			int64_t elapsed = AMMicrosecondsSinceBoot() - startTime;
			assert(elapsed >= 0);
			remainingTimeout -= elapsed;
		}
	}
	
#ifdef AMSerialDebug
	NSLog(@"timeout remaining at end: %qd us (negative means timeout occurred!)", remainingTimeout);
#endif
	
	if (error) {
		NSMutableDictionary *userInfo = [NSMutableDictionary dictionary];
		[userInfo setObject:[NSNumber numberWithUnsignedLongLong:bytesRead] forKey:@"bytesRead"];
		if (underlyingError) {
			[userInfo setObject:underlyingError forKey:NSUnderlyingErrorKey];
		}
		if (errorCode == kAMSerialErrorNone) {
			[userInfo setObject:[NSNumber numberWithInt:endCode] forKey:@"endCode"];
		}
		*error = [NSError errorWithDomain:AMSerialErrorDomain code:errorCode userInfo:userInfo];
	}
	if ((bytesRead > 0) && (errorCode != kAMSerialErrorFatal)) {
		result = [NSData dataWithBytes:_buffer length:bytesRead];
	}
	
#ifdef AMSerialDebug
	NSString *resultAsString = result ? [[NSString alloc] initWithData:result encoding:NSUTF8StringEncoding] : nil;
	NSLog(@"• read: %@ • %@", result, resultAsString);
#endif

	return result;
}

- (void)reportProgress:(NSUInteger)progress dataLen:(NSUInteger)dataLen
{
#ifdef AMSerialDebug
	NSLog(@"send AMSerialWriteInBackgroundProgressMessage");
#endif
	NSDictionary* tmp = [NSDictionary dictionaryWithObjectsAndKeys:
						 self, @"serialPort",
						 [NSNumber numberWithUnsignedLongLong:progress], @"value",
						 [NSNumber numberWithUnsignedLongLong:dataLen], @"total",
						 nil];
	NSObject<AMSerialDelegate>* strongDelegate = [self delegate];
	[strongDelegate performSelectorOnMainThread:@selector(serialPortWriteProgress:)
									 withObject:tmp
								  waitUntilDone:NO];
}

@end
