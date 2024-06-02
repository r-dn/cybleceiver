//
//  Playback.swift
//  CoreBluetoothLESample
//
//  Created by Rogier De Nys on 29/05/2024.
//  Copyright © 2024 Apple. All rights reserved.
//

import Foundation
import os

func writeWAVFile(samples: ArraySlice<Int16>, sampleRate: Int, fileURL: URL) {
	let numChannels: Int = 1
	let bitsPerSample: Int = 16
	let byteRate = sampleRate * numChannels * bitsPerSample / 8
	let blockAlign = numChannels * bitsPerSample / 8
	let subchunk2Size = samples.count * numChannels * bitsPerSample / 8
	let chunkSize = 36 + subchunk2Size
	
	var header = Data()
	
	// RIFF header
	header.append("RIFF".data(using: .ascii)!)
	header.append(UInt32(chunkSize).littleEndian.data)
	header.append("WAVE".data(using: .ascii)!)
	
	// fmt subchunk
	header.append("fmt ".data(using: .ascii)!)
	header.append(UInt32(16).littleEndian.data) // Subchunk1Size for PCM
	header.append(UInt16(1).littleEndian.data)  // AudioFormat (1 for PCM)
	header.append(UInt16(numChannels).littleEndian.data)
	header.append(UInt32(sampleRate).littleEndian.data)
	header.append(UInt32(byteRate).littleEndian.data)
	header.append(UInt16(blockAlign).littleEndian.data)
	header.append(UInt16(bitsPerSample).littleEndian.data)
	
	// data subchunk
	header.append("data".data(using: .ascii)!)
	header.append(UInt32(subchunk2Size).littleEndian.data)
	
	// Convert audio data to byte array
	let audioData = samples.flatMap { $0.littleEndian.data }
	
	// Combine header and audio data
	var wavData = header
	wavData.append(contentsOf: audioData)
	
	// Write combined data to file
	do {
		try wavData.write(to: fileURL, options: .atomicWrite)
	} catch {
		os_log("Failed to write WAV file: \(error)")
	}
}

extension FixedWidthInteger {
	var data: Data {
		withUnsafeBytes(of: self) { Data($0) }
	}
}

