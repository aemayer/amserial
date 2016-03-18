//
//  AMSerialErrors.h
//
//  Created by Andreas Mayer on 2006-07-27.
//  Copyright (c) 2006-2016 Andreas Mayer. All rights reserved.
//


enum {
	kAMSerialErrorNone = 0,
	kAMSerialErrorFatal = 99,
	
	// reading only
	kAMSerialErrorTimeout = 100,
	kAMSerialErrorInternalBufferFull = 101,
	
	// writing only
	kAMSerialErrorNoDataToWrite = 200,
	kAMSerialErrorOnlySomeDataWritten = 201,
};

enum {
	// reading only
	kAMSerialEndOfStream = 0,
	kAMSerialStopCharReached = 1,
	kAMSerialStopLengthReached = 2,
	kAMSerialStopLengthExceeded = 3,
};
