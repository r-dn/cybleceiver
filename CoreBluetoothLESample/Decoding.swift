//
//  AudioData.swift
//  CoreBluetoothLESample
//
//  Created by Rogier De Nys on 27/05/2024.
//  Copyright © 2024 Apple. All rights reserved.
//

import Foundation
import Clc3

class Decoder {
	var decoder: lc3_decoder_t
	var dec_mem: UnsafeMutableRawPointer
	
	static let BITRATE			= 128000
	static let FRAME_US			= 10000
	static let SRATE_HZ			= 48000
	static let NCHANNELS		= 1
	static let PCM_SBITS		= 16
	static let FRAME_SAMPLES	= SRATE_HZ*FRAME_US/1000000
	static let BLOCK_SIZE		= BITRATE/8*FRAME_US/1000000
	static let PCM_SBYTES		= PCM_SBITS/8
	
	init() {
		dec_mem = malloc(MemoryLayout.size(ofValue: lc3_decoder_mem_48k_t()))
		decoder = lc3_setup_decoder(Int32(Self.FRAME_US), Int32(Self.SRATE_HZ), Int32(Self.SRATE_HZ), dec_mem)
	}
	
	deinit {
		free(decoder)
		free(dec_mem)
	}
}

struct EncodedFrame {
	let data: [UInt8]
	
	func decode(decoder: Decoder) throws -> DecodedFrame {
		guard data.count == Decoder.BLOCK_SIZE else {
			throw DecodingError.dataWrongSize
		}
		
		let outPtr = UnsafeMutableRawPointer.allocate(
			byteCount: Decoder.FRAME_SAMPLES*MemoryLayout<UInt16>.stride,
			alignment: MemoryLayout<Int32>.alignment
		)
		defer { outPtr.deallocate() }
		
		
		let result = data.withUnsafeBytes { rawBufferPointer in
			let dataPtr = rawBufferPointer.baseAddress?.assumingMemoryBound(to: UInt8.self)
			return lc3_decode(decoder.decoder, dataPtr, Int32(Decoder.BLOCK_SIZE), LC3_PCM_FORMAT_S16, outPtr, 1)
		}
		
		guard result == 0 else {
			throw DecodingError.codecError
		}
		
		
		let outTyped = outPtr.bindMemory(to: Int16.self, capacity: Decoder.FRAME_SAMPLES)
		let outBuffer = UnsafeBufferPointer(start: outTyped, count: Decoder.FRAME_SAMPLES)
		let outArray = Array(outBuffer)
		
		return DecodedFrame(samples: outArray)
	}
}

enum DecodingError: Error {
	case dataWrongSize, codecError
}

struct DecodedFrame {
	var samples: [Int16]
}
