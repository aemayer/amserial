//
//  AMSDKCompatibility.h
//
//  Created by Nick Zitzmann on 2007-10-22.
//  SPDX-FileCopyrightText: Copyright (c) 2007-2016 Andreas Mayer. All rights reserved.
//  SPDX-License-Identifier: BSD-3-Clause
//

// AMSerialPort uses some features from newer SDKs.
// This allows older SDKs to be used by adding compatibility wrappers.

#import <Foundation/Foundation.h>

// We don't support deployment older than 10.6.
#if MAC_OS_X_VERSION_MIN_REQUIRED < 1060
	#error Minimum deployment supported is 10.6.
#endif

// We don't support SDKs older than 10.7.
#if MAC_OS_X_VERSION_MAX_ALLOWED < 1070
	#error You must use the 10.7 SDK or newer.
#endif

// instancetype is new in clang. id is a good replacement elsewhere.
#if !__has_feature(objc_instancetype) && !defined(instancetype)
	#define instancetype id
#endif

// The 10.10 SDK added NS_DESIGNATED_INITIALIZER, to tag a designated initializer for additional compiler checking.
#ifndef NS_DESIGNATED_INITIALIZER
	#define NS_DESIGNATED_INITIALIZER
#endif

// The 10.8 SDK added NS_ENUM, reproduce it if not defined.
#ifndef NS_ENUM
    #define NS_ENUM(_type, _name) enum _name : _type _name; enum _name : _type
#endif

// Newer compilers and the 10.11 SDK added nullability support, which we just stub to nothing for older cases.
#if __has_feature(nullability)
	#define _amnonnull __nonnull
#else
	#define _amnonnull
	
	#define __nullable
	#define nullable
#endif

#ifndef NS_ASSUME_NONNULL_BEGIN
	#define NS_ASSUME_NONNULL_BEGIN
#endif

#ifndef NS_ASSUME_NONNULL_END
	#define NS_ASSUME_NONNULL_END
#endif
