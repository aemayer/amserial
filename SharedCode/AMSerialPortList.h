//
//  AMSerialPortList.h
//
//  Created by Andreas Mayer on 2002-04-24.
//  Copyright (c) 2001-2016 Andreas Mayer. All rights reserved.
//

#import "AMSDKCompatibility.h"

#import <Foundation/Foundation.h>

// For constants clients will want to pass to methods that want a 'serialTypeKey'
#import <IOKit/serial/IOSerialKeys.h>
// note: the constants are C strings, so use '@' to convert, for example:
// NSArray *ports = [[AMSerialPort sharedPortList] serialPortsOfType:@kIOSerialBSDModemType];

NS_ASSUME_NONNULL_BEGIN

@class AMSerialPort;

extern NSString * const AMSerialPortListDidAddPortsNotification;
extern NSString * const AMSerialPortListDidRemovePortsNotification;
extern NSString * const AMSerialPortListAddedPorts;
extern NSString * const AMSerialPortListRemovedPorts;

@interface AMSerialPortList : NSObject

+ (instancetype)sharedPortList;

+ (NSEnumerator *)portEnumerator;
+ (NSEnumerator *)portEnumeratorForSerialPortsOfType:(NSString *)serialTypeKey;

- (NSUInteger)count;
- (AMSerialPort *)objectAtIndex:(NSUInteger)idx;
- (nullable AMSerialPort *)objectWithName:(NSString *)name;

- (NSArray *)serialPorts;
- (NSArray *)serialPortsOfType:(NSString *)serialTypeKey;

@end

NS_ASSUME_NONNULL_END
