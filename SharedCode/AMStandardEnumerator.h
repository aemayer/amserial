//
//  AMStandardEnumerator.h
//
//  Created by Andreas Mayer on 2003-08-04.
//  Copyright (c) 2003-2016 Andreas Mayer. All rights reserved.
//
//  2007-10-26 Sean McBride
//  - made code 64 bit and garbage collection clean
//	2016-03-17 Sean McBride
//	- added nullability support

#import "AMSDKCompatibility.h"

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface AMStandardEnumerator : NSEnumerator

// Designated initializer
- (instancetype)initWithCollection:(id)theCollection
					 countSelector:(SEL)theCountSelector
			 objectAtIndexSelector:(SEL)theObjectSelector NS_DESIGNATED_INITIALIZER;

@end

NS_ASSUME_NONNULL_END
