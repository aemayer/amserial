//
//  AMStandardEnumerator.m
//
//  Created by Andreas Mayer on 2003-08-04.
//  Copyright (c) 2003-2016 Andreas Mayer. All rights reserved.
//
//  2007-10-26 Sean McBride
//  - made code 64 bit and garbage collection clean
//  2011-10-18 Andreas Mayer
//  - added ARC compatibility
//  2011-10-19 Sean McBride
//  - code review of ARC changes
//  2016-03-17 Sean McBride
//  - added nullability support
//  2016-03-18 Sean McBride
//  - this class is now deprecated, use fast enumeration on AMSerialPortList itself instead

#import "AMSDKCompatibility.h"

#import "AMStandardEnumerator.h"

typedef NSUInteger (*AMCountMethod)(id, SEL);
typedef __nullable id (*AMNextObjectMethod)(id, SEL, NSUInteger);

// Private Interface
@interface AMStandardEnumerator()
{
@private
	id _collection;
	SEL _countSelector;
	SEL _nextObjectSelector;
	AMCountMethod _count;
	AMNextObjectMethod _nextObject;
	NSUInteger _position;
}
@end

@implementation AMStandardEnumerator

// Cover the superclass' designated initializer
- (instancetype)init NS_UNAVAILABLE
{
	assert(0);
	return nil;
}

// Designated initializer
- (instancetype)initWithCollection:(id)theCollection
					 countSelector:(SEL)theCountSelector
			 objectAtIndexSelector:(SEL)theObjectSelector
{
	assert(theCollection);
	assert(theCountSelector);
	assert(theObjectSelector);
	
	self = [super init];
	if (self) {
		_collection = theCollection;
#if !__has_feature(objc_arc)
		[_collection retain];
#endif
		_countSelector = theCountSelector;
		_count = (AMCountMethod)[_collection methodForSelector:_countSelector];
		_nextObjectSelector = theObjectSelector;
		_nextObject = (AMNextObjectMethod)[_collection methodForSelector:_nextObjectSelector];
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

- (nullable id)nextObject
{
	if (_position >= _count(_collection, _countSelector)) {
		return nil;
	}

	return (_nextObject(_collection, _nextObjectSelector, _position++));
}

- (NSArray *)allObjects
{
	NSMutableArray *result = [NSMutableArray array];
	id object;
	while ((object = [self nextObject]) != nil) {
		[result addObject:object];
	}
	
	assert(result);
	return result;
}

@end
