//
//  AMSerialErrors.h
//
//  Created by Andreas Mayer on 2006-07-27.
//  SPDX-FileCopyrightText: Copyright (c) 2006-2016 Andreas Mayer. All rights reserved.
//  SPDX-License-Identifier: BSD-3-Clause
//

typedef NS_ENUM(NSInteger, AMSerialError) {
	kAMSerialErrorNone = 0,
	kAMSerialErrorFatal = 99,
	
	// reading only
	kAMSerialErrorTimeout = 100,
	kAMSerialErrorInternalBufferFull = 101,
	
	// writing only
	kAMSerialErrorNoDataToWrite = 200,
	kAMSerialErrorOnlySomeDataWritten = 201,
};

typedef NS_ENUM(int, AMSerialEndCode) {
	// reading only
	kAMSerialEndCodeEndOfStream = 0,
	kAMSerialEndCodeStopCharReached = 1,
	kAMSerialEndCodeStopLengthReached = 2,
	kAMSerialEndCodeStopLengthExceeded = 3,
	
	// old names, deprecated
	kAMSerialEndOfStream DEPRECATED_ATTRIBUTE = kAMSerialEndCodeEndOfStream,
	kAMSerialStopCharReached DEPRECATED_ATTRIBUTE = kAMSerialEndCodeStopCharReached,
	kAMSerialStopLengthReached DEPRECATED_ATTRIBUTE = kAMSerialEndCodeStopLengthReached,
	kAMSerialStopLengthExceeded DEPRECATED_ATTRIBUTE = kAMSerialEndCodeStopLengthExceeded,
};
