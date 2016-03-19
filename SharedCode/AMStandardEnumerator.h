//
//  AMStandardEnumerator.h
//
//  Created by Andreas Mayer on 2003-08-04.
//  Copyright (c) 2003-2016 Andreas Mayer. All rights reserved.
//

#import "AMSDKCompatibility.h"

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Private
typedef NSUInteger (*AMCountMethod)(id, SEL);
typedef __nullable id (*AMNextObjectMethod)(id, SEL, NSUInteger);

@interface AMStandardEnumerator : NSEnumerator
{
@private
	id _collection;
	SEL _countSelector;
	SEL _nextObjectSelector;
	AMCountMethod _count;
	AMNextObjectMethod _nextObject;
	NSUInteger _position;
}

// Designated initializer
- (instancetype)initWithCollection:(id)theCollection
					 countSelector:(SEL)theCountSelector
			 objectAtIndexSelector:(SEL)theObjectSelector NS_DESIGNATED_INITIALIZER DEPRECATED_ATTRIBUTE;

@end

NS_ASSUME_NONNULL_END
