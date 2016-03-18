//
//  AMStandardEnumerator.h
//
//  Created by Andreas Mayer on 2003-08-04.
//  Copyright (c) 2003-2016 Andreas Mayer. All rights reserved.
//

#import "AMSDKCompatibility.h"

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface AMStandardEnumerator : NSEnumerator

// Designated initializer
- (instancetype)initWithCollection:(id)theCollection
					 countSelector:(SEL)theCountSelector
			 objectAtIndexSelector:(SEL)theObjectSelector NS_DESIGNATED_INITIALIZER DEPRECATED_ATTRIBUTE;

@end

NS_ASSUME_NONNULL_END
