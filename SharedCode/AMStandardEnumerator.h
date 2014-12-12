//
//  AMStandardEnumerator.h
//
//  Created by Andreas on Mon Aug 04 2003.
//  Copyright (c) 2003-2014 Andreas Mayer. All rights reserved.
//
//  2007-10-26 Sean McBride
//  - made code 64 bit and garbage collection clean

#import "AMSDKCompatibility.h"

#import <Foundation/Foundation.h>

typedef NSUInteger (*CountMethod)(id, SEL);
typedef id (*NextObjectMethod)(id, SEL, NSUInteger);

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
- (instancetype)initWithCollection:(id)theCollection countSelector:(SEL)theCountSelector objectAtIndexSelector:(SEL)theObjectSelector NS_DESIGNATED_INITIALIZER;


@end
