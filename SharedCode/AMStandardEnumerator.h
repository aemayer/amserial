//
//  AMStandardEnumerator.h
//
//  Created by Andreas on Mon Aug 04 2003.
//  Copyright (c) 2003-2016 Andreas Mayer. All rights reserved.
//
//  2007-10-26 Sean McBride
//  - made code 64 bit and garbage collection clean
//	2016-03-17 Sean McBride
//	- added nullability support

#import "AMSDKCompatibility.h"

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NSUInteger (*CountMethod)(id, SEL);
typedef __nullable id (*NextObjectMethod)(id, SEL, NSUInteger);

@interface AMStandardEnumerator : NSEnumerator
{
@private
	id _collection;
	SEL _countSelector;
	SEL _nextObjectSelector;
	CountMethod _count;
	NextObjectMethod _nextObject;
	NSUInteger _position;
}

// Designated initializer
- (instancetype)initWithCollection:(id)theCollection
					 countSelector:(SEL)theCountSelector
			 objectAtIndexSelector:(SEL)theObjectSelector NS_DESIGNATED_INITIALIZER;

@end

NS_ASSUME_NONNULL_END
