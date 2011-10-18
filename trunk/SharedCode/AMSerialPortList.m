//
//  AMSerialPortList.m
//
//  Created by Andreas on 2002-04-24.
//  Copyright (c) 2001-2011 Andreas Mayer. All rights reserved.
//
//  2002-09-09 Andreas Mayer
//  - reuse AMSerialPort objects when calling init on an existing AMSerialPortList
//  2002-09-30 Andreas Mayer
//  - added +sharedPortList
//  2004-07-05 Andreas Mayer
//  - added some log statements
//  2007-05-22 Nick Zitzmann
//  - added notifications for when serial ports are added/removed
//  2007-07-18 Sean McBride
//  - minor improvements to the added/removed notification support
//  - changed singleton creation technique, now matches Apple's sample code
//  - removed oldPortList as it is no longer needed
//  2007-10-26 Sean McBride
//  - made code 64 bit and garbage collection clean
//  2008-10-21 Sean McBride
//  - fixed some memory management issues
//  2010-01-04 Sean McBride
//  - fixed some memory management issues
//  2011-08-18 Andreas Mayer
//  - minor edits to placate the clang static analyzer
//  2011-10-14 Sean McBride
//  - removed one NSRunLoop method in favour of CFRunLoop
//	2011-10-18 Andreas Mayer
//	- added ARC compatibility

#import "AMSDKCompatibility.h"

#import "AMSerialPortList.h"
#import "AMSerialPort.h"
#import "AMStandardEnumerator.h"

#include <termios.h>

#include <CoreFoundation/CoreFoundation.h>

#include <IOKit/IOKitLib.h>
#include <IOKit/serial/IOSerialKeys.h>
#include <IOKit/IOBSD.h>

NSString *const AMSerialPortListDidAddPortsNotification = @"AMSerialPortListDidAddPortsNotification";
NSString *const AMSerialPortListDidRemovePortsNotification = @"AMSerialPortListDidRemovePortsNotification";
NSString *const AMSerialPortListAddedPorts = @"AMSerialPortListAddedPorts";
NSString *const AMSerialPortListRemovedPorts = @"AMSerialPortListRemovedPorts";


@implementation AMSerialPortList

#if __has_feature(objc_arc)

+ (AMSerialPortList *)sharedPortList {
	static dispatch_once_t pred = 0;
	__strong static AMSerialPortList *_sharedPortList = nil;
	dispatch_once(&pred, ^{
		_sharedPortList = [[AMSerialPortList alloc] init];
	});
	return _sharedPortList;
}

#else

static AMSerialPortList *AMSerialPortListSingleton = nil;

+ (AMSerialPortList *)sharedPortList
{
    @synchronized(self) {
        if (AMSerialPortListSingleton == nil) {
#ifndef __OBJC_GC__
			// -autorelease is overridden to do nothing
			// This placates the static analyzer.
			[[[self alloc] init] autorelease]; // assignment not done here
#else
			// Singleton creation is easy in the GC case, just create it if it hasn't been created yet,
			// it won't get collected since globals are strongly referenced.
			AMSerialPortListSingleton = [[self alloc] init];

			// -release is overridden to do nothing
			// This placates the static analyzer.
			[AMSerialPortListSingleton release];
#endif
       }
    }
    return AMSerialPortListSingleton;
}

#ifndef __OBJC_GC__

+ (id)allocWithZone:(NSZone *)zone
{
	id result = nil;
    @synchronized(self) {
        if (AMSerialPortListSingleton == nil) {
            AMSerialPortListSingleton = [super allocWithZone:zone];
			result = AMSerialPortListSingleton;  // assignment and return on first allocation
			//on subsequent allocation attempts return nil
        }
    }
	return result;
}
 
- (id)copyWithZone:(NSZone *)zone
{
	(void)zone;
    return self;
}
 
- (id)retain
{
    return self;
}
 
- (NSUInteger)retainCount
{
    return NSUIntegerMax;  //denotes an object that cannot be released
}
 
- (oneway void)release
{
    //do nothing
}
 
- (id)autorelease
{
    return self;
}

- (void)dealloc
{
	[portList release]; portList = nil;
	[super dealloc];
}

#endif	// #ifndef __OBJC_GC__
#endif	// #if __has_feature(objc_arc)

+ (NSEnumerator *)portEnumerator
{
#if __has_feature(objc_arc)
	return [[AMStandardEnumerator alloc] initWithCollection:[AMSerialPortList sharedPortList] countSelector:@selector(count) objectAtIndexSelector:@selector(objectAtIndex:)];
#else
	return [[[AMStandardEnumerator alloc] initWithCollection:[AMSerialPortList sharedPortList]
		countSelector:@selector(count) objectAtIndexSelector:@selector(objectAtIndex:)] autorelease];
#endif
}

+ (NSEnumerator *)portEnumeratorForSerialPortsOfType:(NSString *)serialTypeKey
{
#if __has_feature(objc_arc)
	return [[AMStandardEnumerator alloc] initWithCollection:[[AMSerialPortList sharedPortList] serialPortsOfType:serialTypeKey] countSelector:@selector(count) objectAtIndexSelector:@selector(objectAtIndex:)];
#else
	return [[[AMStandardEnumerator alloc] initWithCollection:[[AMSerialPortList sharedPortList]
		serialPortsOfType:serialTypeKey] countSelector:@selector(count) objectAtIndexSelector:@selector(objectAtIndex:)] autorelease];
#endif
}

- (AMSerialPort *)portByPath:(NSString *)bsdPath
{
	AMSerialPort *result = nil;
	AMSerialPort *port;
	NSEnumerator *enumerator;
	
	enumerator = [portList objectEnumerator];
	while ((port = [enumerator nextObject]) != nil) {
		if ([[port bsdPath] isEqualToString:bsdPath]) {
			result = port;
			break;
		}
	}
	return result;
}

- (AMSerialPort *)getNextSerialPort:(io_iterator_t)serialPortIterator
{
	AMSerialPort	*serialPort = nil;

	io_object_t serialService = IOIteratorNext(serialPortIterator);
	if (serialService != 0) {
		CFStringRef modemName = (CFStringRef)IORegistryEntryCreateCFProperty(serialService, CFSTR(kIOTTYDeviceKey), kCFAllocatorDefault, 0);
		CFStringRef bsdPath = (CFStringRef)IORegistryEntryCreateCFProperty(serialService, CFSTR(kIOCalloutDeviceKey), kCFAllocatorDefault, 0);
		CFStringRef serviceType = (CFStringRef)IORegistryEntryCreateCFProperty(serialService, CFSTR(kIOSerialBSDTypeKey), kCFAllocatorDefault, 0);
		if (modemName && bsdPath) {
			// If the port already exists in the list of ports, we want that one.  We only create a new one as a last resort.
#if __has_feature(objc_arc)
			serialPort = [self portByPath:(__bridge NSString*)bsdPath];
			if (serialPort == nil) {
				serialPort = [[AMSerialPort alloc] init:(__bridge NSString*)bsdPath withName:(__bridge NSString*)modemName type:(__bridge NSString*)serviceType];
			}
#else
			serialPort = [self portByPath:(NSString*)bsdPath];
			if (serialPort == nil) {
				serialPort = [[[AMSerialPort alloc] init:(NSString*)bsdPath withName:(NSString*)modemName type:(NSString*)serviceType] autorelease];
			}
#endif
		}
		if (modemName) {
			CFRelease(modemName);
		}
		if (bsdPath) {
			CFRelease(bsdPath);
		}
		if (serviceType) {
			CFRelease(serviceType);
		}
		
		// We have sucked this service dry of information so release it now.
		(void)IOObjectRelease(serialService);
	}
	
	return serialPort;
}

- (void)portsWereAdded:(io_iterator_t)iterator
{
	AMSerialPort *serialPort;
	NSMutableArray *addedPorts = [NSMutableArray array];
	
	while ((serialPort = [self getNextSerialPort:iterator]) != nil) {
		[addedPorts addObject:serialPort];
		[portList addObject:serialPort];
	}
	
	NSNotificationCenter* notifCenter = [NSNotificationCenter defaultCenter];
	NSDictionary* userInfo = [NSDictionary dictionaryWithObject:addedPorts forKey:AMSerialPortListAddedPorts];
	[notifCenter postNotificationName:AMSerialPortListDidAddPortsNotification object:self userInfo:userInfo];
}

- (void)portsWereRemoved:(io_iterator_t)iterator
{
	AMSerialPort *serialPort;
	NSMutableArray *removedPorts = [NSMutableArray array];
	
	while ((serialPort = [self getNextSerialPort:iterator]) != nil) {
		// Since the port was removed, one should obviously not attempt to use it anymore -- so 'close' it.
		// -close does nothing if the port was never opened.
		[serialPort close];
		
		[removedPorts addObject:serialPort];
		[portList removeObject:serialPort];
	}

	NSNotificationCenter* notifCenter = [NSNotificationCenter defaultCenter];
	NSDictionary* userInfo = [NSDictionary dictionaryWithObject:removedPorts forKey:AMSerialPortListRemovedPorts];
	[notifCenter postNotificationName:AMSerialPortListDidRemovePortsNotification object:self userInfo:userInfo];
}

static void AMSerialPortWasAddedNotification(void *refcon, io_iterator_t iterator)
{
	(void)refcon;
	[[AMSerialPortList sharedPortList] portsWereAdded:iterator];
}

static void AMSerialPortWasRemovedNotification(void *refcon, io_iterator_t iterator)
{
	(void)refcon;
	[[AMSerialPortList sharedPortList] portsWereRemoved:iterator];
}

- (void)registerForSerialPortChangeNotifications
{
	IONotificationPortRef notificationPort = IONotificationPortCreate(kIOMasterPortDefault);
	if (notificationPort) {
		CFRunLoopSourceRef notificationSource = IONotificationPortGetRunLoopSource(notificationPort);
		if (notificationSource) {
			// Serial devices are instances of class IOSerialBSDClient
			CFMutableDictionaryRef classesToMatch1 = IOServiceMatching(kIOSerialBSDServiceValue);
			if (classesToMatch1) {
				CFDictionarySetValue(classesToMatch1, CFSTR(kIOSerialBSDTypeKey), CFSTR(kIOSerialBSDAllTypes));
				
				// Copy classesToMatch1 now, while it has a non-zero ref count.
				CFMutableDictionaryRef classesToMatch2 = CFDictionaryCreateMutableCopy(kCFAllocatorDefault, 0, classesToMatch1);
				// Add to the runloop
				CFRunLoopAddSource(CFRunLoopGetCurrent(), notificationSource, kCFRunLoopCommonModes);
				
				// Set up notification for ports being added.
				io_iterator_t unused;
				kern_return_t kernResult = IOServiceAddMatchingNotification(notificationPort, kIOPublishNotification, classesToMatch1, AMSerialPortWasAddedNotification, NULL, &unused); // consumes a reference to classesToMatch1
				if (kernResult != KERN_SUCCESS) {
#ifdef AMSerialDebug
					NSLog(@"Error %d when setting up add notifications!", kernResult);
#endif
				} else {
					while (IOIteratorNext(unused)) {}	// arm the notification
				}
				
				if (classesToMatch2) {
					// Set up notification for ports being removed.
					kernResult = IOServiceAddMatchingNotification(notificationPort, kIOTerminatedNotification, classesToMatch2, AMSerialPortWasRemovedNotification, NULL, &unused); // consumes a reference to classesToMatch2
					if (kernResult != KERN_SUCCESS) {
#ifdef AMSerialDebug
						NSLog(@"Error %d when setting up add notifications!", kernResult);
#endif
					} else {
						while (IOIteratorNext(unused)) {}	// arm the notification
					}
				}
			} else {
#ifdef AMSerialDebug
				NSLog(@"IOServiceMatching returned a NULL dictionary.");
#endif
			}
		}
		// Note that IONotificationPortDestroy(notificationPort) is deliberately not called here because if it were our port change notifications would never fire.  This minor leak is pretty irrelevant since this object is a singleton that lives for the life of the application anyway.
	}
}

- (void)addAllSerialPortsToArray:(NSMutableArray *)array
{
	kern_return_t kernResult;
	CFMutableDictionaryRef classesToMatch;
	io_iterator_t serialPortIterator;
	AMSerialPort* serialPort;
	
	// Serial devices are instances of class IOSerialBSDClient
	classesToMatch = IOServiceMatching(kIOSerialBSDServiceValue);
	if (classesToMatch != NULL) {
		CFDictionarySetValue(classesToMatch, CFSTR(kIOSerialBSDTypeKey), CFSTR(kIOSerialBSDAllTypes));

		// This function decrements the refcount of the dictionary passed it
		kernResult = IOServiceGetMatchingServices(kIOMasterPortDefault, classesToMatch, &serialPortIterator);
		if (kernResult == KERN_SUCCESS) {
			while ((serialPort = [self getNextSerialPort:serialPortIterator]) != nil) {
				[array addObject:serialPort];
			}
			(void)IOObjectRelease(serialPortIterator);
		} else {
#ifdef AMSerialDebug
			NSLog(@"IOServiceGetMatchingServices returned %d", kernResult);
#endif
		}
	} else {
#ifdef AMSerialDebug
		NSLog(@"IOServiceMatching returned a NULL dictionary.");
#endif
	}
}

- (id)init
{
	if ((self = [super init])) {
#if __has_feature(objc_arc)
		portList = [NSMutableArray array];
#else
		portList = [[NSMutableArray array] retain];
#endif
	
		[self addAllSerialPortsToArray:portList];
		[self registerForSerialPortChangeNotifications];
	}
	
	return self;
}

- (NSUInteger)count
{
	return [portList count];
}

- (AMSerialPort *)objectAtIndex:(NSUInteger)idx
{
	return [portList objectAtIndex:idx];
}

- (AMSerialPort *)objectWithName:(NSString *)name
{
	AMSerialPort *result = nil;
	NSEnumerator *enumerator = [portList objectEnumerator];
	AMSerialPort *port;
	while ((port = [enumerator nextObject]) != nil) {
		if ([[port name] isEqualToString:name]) {
			result = port;
			break;
		}
	}
	return result;
}

- (NSArray *)serialPorts
{
#if __has_feature(objc_arc)
	return [portList copy];
#else
	return [[portList copy] autorelease];
#endif
}

- (NSArray *)serialPortsOfType:(NSString *)serialTypeKey
{
	NSMutableArray *result = [NSMutableArray array];
	NSEnumerator *enumerator = [portList objectEnumerator];
	AMSerialPort *port;
	while ((port = [enumerator nextObject]) != nil) {
		if ([[port type] isEqualToString:serialTypeKey]) {
			[result addObject:port];
		}
	}
	return result;
}


@end
