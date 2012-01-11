//
//  AMStandardEnumerator.m
//
//  Created by Andreas on Mon Aug 04 2003.
//  Copyright (c) 2003-2012 Andreas Mayer. All rights reserved.
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

// Designated initializer
- (instancetype)initWithCollection:(id)theCollection countSelector:(SEL)theCountSelector objectAtIndexSelector:(SEL)theObjectSelector
{
	self = [super init];
	if (self) {
		collection = theCollection;
#if !__has_feature(objc_arc)
		[collection retain];
#endif
		countSelector = theCountSelector;
		count = (CountMethod)[collection methodForSelector:countSelector];
		nextObjectSelector = theObjectSelector;
		nextObject = (NextObjectMethod)[collection methodForSelector:nextObjectSelector];
		position = 0;
	}
	return self;
}

#ifndef __OBJC_GC__
#if !__has_feature(objc_arc)

- (void)dealloc
{
	[collection release]; collection = nil;
	[super dealloc];
}

#endif
#endif

- (id)nextObject
{
	if (position >= count(collection, countSelector))
		return nil;

	return (nextObject(collection, nextObjectSelector, position++));
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
