//
//  AMStandardEnumerator.m
//
//  Created by Andreas on Mon Aug 04 2003.
//  Copyright (c) 2003-2015 Andreas Mayer. All rights reserved.
//
//  2007-10-26 Sean McBride
//  - made code 64 bit and garbage collection clean
//	2011-10-18 Andreas Mayer
//	- added ARC compatibility
//	2011-10-19 Sean McBride
//	- code review of ARC changes

#import "AMSDKCompatibility.h"

#import "AMStandardEnumerator.h"


@implementation AMStandardEnumerator

// Cover the superclass' designated initializer
- (instancetype)init NS_UNAVAILABLE
{
	assert(0);
	return nil;
}

// Designated initializer
- (instancetype)initWithCollection:(id)theCollection countSelector:(SEL)theCountSelector objectAtIndexSelector:(SEL)theObjectSelector
{
	self = [super init];
	if (self) {
		_collection = theCollection;
#if !__has_feature(objc_arc)
		[_collection retain];
#endif
		_countSelector = theCountSelector;
		_count = (CountMethod)[_collection methodForSelector:_countSelector];
		_nextObjectSelector = theObjectSelector;
		_nextObject = (NextObjectMethod)[_collection methodForSelector:_nextObjectSelector];
		_position = 0;
	}
	return self;
}

#ifndef __OBJC_GC__
#if !__has_feature(objc_arc)

- (void)dealloc
{
	[_collection release]; _collection = nil;
	[super dealloc];
}

#endif
#endif

- (id)nextObject
{
	if (_position >= _count(_collection, _countSelector))
		return nil;

	return (_nextObject(_collection, _nextObjectSelector, _position++));
}

- (NSArray *)allObjects
{
	NSMutableArray *result = [NSMutableArray array];
	id object;
	while ((object = [self nextObject]) != nil)
		[result addObject:object];
	return result;
}

@end
