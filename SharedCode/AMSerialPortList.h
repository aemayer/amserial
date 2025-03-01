//
//  AMSerialPortList.h
//
//  Created by Andreas Mayer on 2002-04-24.
//  SPDX-FileCopyrightText: Copyright (c) 2001-2016 Andreas Mayer. All rights reserved.
//  SPDX-License-Identifier: BSD-3-Clause
//

#import "AMSDKCompatibility.h"

#import <Foundation/Foundation.h>

// For constants clients will want to pass to methods that want a 'serialTypeKey'
#import <IOKit/serial/IOSerialKeys.h>

NS_ASSUME_NONNULL_BEGIN

@class AMSerialPort;

// Names of posted notifications.
extern NSString * const AMSerialPortListDidAddPortsNotification;
extern NSString * const AMSerialPortListDidRemovePortsNotification;

// Keys in notification userInfo dictionaries.
extern NSString * const AMSerialPortListAddedPorts;
extern NSString * const AMSerialPortListRemovedPorts;

@interface AMSerialPortList : NSObject <NSFastEnumeration>
{
@private
	NSMutableArray *_portList;
}

// Returns a singleton instance, creating it first if necessary.
// The first creation also starts observation of ports being added and removed and will post notifications right away for any already existing ports.
+ (instancetype)sharedPortList;

+ (NSEnumerator *)portEnumerator DEPRECATED_ATTRIBUTE;
+ (NSEnumerator *)portEnumeratorForSerialPortsOfType:(NSString *)serialTypeKey DEPRECATED_ATTRIBUTE;

- (NSUInteger)count DEPRECATED_ATTRIBUTE;
- (AMSerialPort *)objectAtIndex:(NSUInteger)idx DEPRECATED_ATTRIBUTE;

// Returns the port, if any, with the matching name.
- (nullable AMSerialPort *)objectWithName:(NSString *)name;

// Returns an array of all currently known ports (of all types). May be an empty array.
- (NSArray *)serialPorts;

// Returns an array of all currently known ports that match the given type. May be an empty array.
// Types are from IOSerialKeys.h, ex: @kIOSerialBSDAllTypes, @kIOSerialBSDModemType, @kIOSerialBSDRS232Type.
- (NSArray *)serialPortsOfType:(NSString *)serialTypeKey;

@end

NS_ASSUME_NONNULL_END
