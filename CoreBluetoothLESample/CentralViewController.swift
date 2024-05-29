/*
 See the LICENSE.txt file for this sample’s licensing information.
 
 Abstract:
 A class to discover, connect, receive notifications and write data to peripherals by using a transfer service and characteristic.
 */

import UIKit
import CoreBluetooth
import os
import AVFAudio


class CentralViewController: UIViewController {
	
	enum State {
		case disconnected, connected, streaming
	}
	
	@IBOutlet var textView: UITextView!
	@IBOutlet var button: UIButton!
	@IBOutlet var avgLabel: UILabel!
	
	var centralManager: CBCentralManager!
	var audioEngine: AVAudioEngine?
	var playerNode: AVAudioPlayerNode?
	let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 1)!
	
	var discoveredPeripheral: CBPeripheral?
	var transferCharacteristic: CBCharacteristic?
	
	var decoder: Decoder?
	var frameBuffer: [DecodedFrame] = []
	var pcmAudioBuffers: [AVAudioPCMBuffer] = []
	
	var currMsgID: UInt8 = 0
	var currTime: Date = .now
	var startTime: Date = .now
	var totalPacketsReceived = 0
	var rxTimes = [Double](repeating: 0, count: 256)
	
	var state: State = .disconnected {
		didSet {
			switch state {
			case .disconnected:
				DispatchQueue.main.async() {
					self.button.setTitle("Reconnecting...", for: .disabled)
					self.button.isEnabled = false
				}
				display("Disconnected from audio_cyble")
				display("Reconnecting...")
				
				audioEngine?.stop()
				playerNode?.reset()
				frameBuffer.removeAll()
				
			case .connected:
				DispatchQueue.main.async() {
					self.button.isEnabled = true
					self.button.setTitle("Start streaming", for: .normal)
				}
				
				audioEngine?.stop()
				playerNode?.reset()
				frameBuffer.removeAll()
				
			case .streaming:
				currMsgID = 0
				currTime = .now
				startTime = .now
				totalPacketsReceived = 0
				DispatchQueue.main.async() {
					self.button.setTitle("Stop streaming", for: .normal)
				}
				display("Streaming...")
				
				do {
					try audioEngine!.start()
					playerNode!.play(at: AVAudioTime(hostTime: AVAudioTime.hostTime(forSeconds: 0.1)))
				} catch {
					display(error.localizedDescription)
				}
					
			}
		}
	}
	
	
	// MARK: - view lifecycle
	
	override func viewDidLoad() {
		centralManager = CBCentralManager(delegate: self, queue: nil, options: [CBCentralManagerOptionShowPowerAlertKey: true])
		
		decoder = Decoder()
		
		avgLabel.font = UIFont.monospacedDigitSystemFont(ofSize: avgLabel.font.pointSize, weight: .regular)
		textView.textContainerInset = .zero
		textView.textContainer.lineFragmentPadding = 0
		
		audioEngine = AVAudioEngine()
		playerNode = AVAudioPlayerNode()
		audioEngine?.attach(playerNode!)
		let format = audioEngine!.mainMixerNode.outputFormat(forBus: 0)
		audioEngine!.connect(playerNode!, to: audioEngine!.mainMixerNode, format: format)
		audioEngine!.prepare()
//		playerNode!.prepare(withFrameCount: 480)
		
		display("Connecting...")
		
		super.viewDidLoad()
	}
	
	override func viewWillDisappear(_ animated: Bool) {
		// Don't keep it going while we're not showing.
		centralManager.stopScan()
		os_log("Scanning stopped")
		
		super.viewWillDisappear(animated)
	}
	
	// MARK: - Helper Methods
	
	/*
	 * We will first check if we are already connected to our counterpart
	 * Otherwise, scan for peripherals - specifically for our service's 128bit CBUUID
	 */
	private func retrievePeripheral() {
		
		let connectedPeripherals: [CBPeripheral] = (centralManager.retrieveConnectedPeripherals(withServices: [TransferService.serviceUUID]))
		
		os_log("Found connected Peripherals with transfer service: %@", connectedPeripherals)
		
		if let connectedPeripheral = connectedPeripherals.last {
			os_log("Connecting to peripheral %@", connectedPeripheral)
			self.discoveredPeripheral = connectedPeripheral
			centralManager.connect(connectedPeripheral, options: nil)
		} else {
			// We were not connected to our counterpart, so start scanning
			centralManager.scanForPeripherals(withServices: [TransferService.serviceUUID],
											  options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
		}
	}
	
	/*
	 *  Call this when things either go wrong, or you're done with the connection.
	 *  This cancels any subscriptions if there are any, or straight disconnects if not.
	 *  (didUpdateNotificationStateForCharacteristic will cancel the connection if a subscription is involved)
	 */
	private func cleanup() {
		// Don't do anything if we're not connected
		guard let discoveredPeripheral = discoveredPeripheral,
			  case .connected = discoveredPeripheral.state else { return }
		
		for service in (discoveredPeripheral.services ?? [] as [CBService]) {
			for characteristic in (service.characteristics ?? [] as [CBCharacteristic]) {
				if characteristic.uuid == TransferService.characteristicUUID && characteristic.isNotifying {
					// It is notifying, so unsubscribe
					self.discoveredPeripheral?.setNotifyValue(false, for: characteristic)
				}
			}
		}
		
		// If we've gotten this far, we're connected, but we're not subscribed, so we just disconnect
		centralManager.cancelPeripheralConnection(discoveredPeripheral)
	}
	
}

extension CentralViewController: CBCentralManagerDelegate {
	// implementations of the CBCentralManagerDelegate methods
	
	/*
	 *  centralManagerDidUpdateState is a required protocol method.
	 *  Usually, you'd check for other states to make sure the current device supports LE, is powered on, etc.
	 *  In this instance, we're just using it to wait for CBCentralManagerStatePoweredOn, which indicates
	 *  the Central is ready to be used.
	 */
	internal func centralManagerDidUpdateState(_ central: CBCentralManager) {
		
		switch central.state {
		case .poweredOn:
			// ... so start working with the peripheral
			os_log("CBManager is powered on")
			retrievePeripheral()
		case .poweredOff:
			os_log("CBManager is not powered on")
			// In a real app, you'd deal with all the states accordingly
			return
		case .resetting:
			os_log("CBManager is resetting")
			// In a real app, you'd deal with all the states accordingly
			return
		case .unauthorized:
			// In a real app, you'd deal with all the states accordingly
			if #available(iOS 13.0, *) {
				switch CBCentralManager.authorization {
				case .denied:
					os_log("You are not authorized to use Bluetooth")
				case .restricted:
					os_log("Bluetooth is restricted")
				default:
					os_log("Unexpected authorization")
				}
			} else {
				// Fallback on earlier versions
			}
			return
		case .unknown:
			os_log("CBManager state is unknown")
			// In a real app, you'd deal with all the states accordingly
			return
		case .unsupported:
			os_log("Bluetooth is not supported on this device")
			// In a real app, you'd deal with all the states accordingly
			return
		@unknown default:
			os_log("A previously unknown central manager state occurred")
			// In a real app, you'd deal with yet unknown cases that might occur in the future
			return
		}
	}
	
	/*
	 *  This callback comes whenever a peripheral that is advertising the transfer serviceUUID is discovered.
	 *  We check the RSSI, to make sure it's close enough that we're interested in it, and if it is,
	 *  we start the connection process
	 */
	func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
						advertisementData: [String: Any], rssi RSSI: NSNumber) {
		
		os_log("Discovered %s at %d dBm", String(describing: peripheral.name), RSSI.intValue)
		
		// Device is in range - have we already seen it?
		if discoveredPeripheral != peripheral {
			
			// Save a local copy of the peripheral, so CoreBluetooth doesn't get rid of it.
			discoveredPeripheral = peripheral
			
			// And finally, connect to the peripheral.
			os_log("Connecting to perhiperal %@", peripheral)
			centralManager.connect(peripheral, options: nil)
		}
	}
	
	func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
		os_log("Failed to connect to %@. %s", peripheral, String(describing: error))
		cleanup()
	}
	
	/*
	 *  We've connected to the peripheral, now we need to discover the services and characteristics to find the 'transfer' characteristic.
	 */
	func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
		os_log("Peripheral Connected")
		// Stop scanning
		centralManager.stopScan()
		os_log("Scanning stopped")
		
		// Make sure we get the discovery callbacks
		peripheral.delegate = self
		
		display("Connected to audio_cyble")
		
		// Search only for services that match our UUID
		peripheral.discoverServices([TransferService.serviceUUID])
	}
	
	/*
	 *  Once the disconnection happens, we need to clean up our local copy of the peripheral
	 */
	func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
		os_log("Perhiperal Disconnected")
		discoveredPeripheral = nil
		state = .disconnected
		retrievePeripheral()
	}
	
}

extension CentralViewController: CBPeripheralDelegate {
	// implementations of the CBPeripheralDelegate methods
	
	/*
	 *  The peripheral letting us know when services have been invalidated.
	 */
	func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService]) {
		
		for service in invalidatedServices where service.uuid == TransferService.serviceUUID {
			os_log("Transfer service is invalidated - rediscover services")
			peripheral.discoverServices([TransferService.serviceUUID])
		}
	}
	
	/*
	 *  The Transfer Service was discovered
	 */
	func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
		if let error = error {
			os_log("Error discovering services: %s", error.localizedDescription)
			cleanup()
			return
		}
		
		// Discover the characteristic we want...
		
		// Loop through the newly filled peripheral.services array, just in case there's more than one.
		guard let peripheralServices = peripheral.services else { return }
		os_log("discovered characteristics")
		for service in peripheralServices {
			peripheral.discoverCharacteristics([TransferService.characteristicUUID], for: service)
		}
	}
	
	/*
	 *  The Transfer characteristic was discovered.
	 *  Once this has been found, we want to subscribe to it, which lets the peripheral know we want the data it contains
	 */
	func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
		// Deal with errors (if any).
		if let error = error {
			os_log("Error discovering characteristics: %s", error.localizedDescription)
			cleanup()
			return
		}
		
		// Again, we loop through the array, just in case and check if it's the right one
		guard let serviceCharacteristics = service.characteristics else { return }
		for characteristic in serviceCharacteristics where characteristic.uuid == TransferService.characteristicUUID {
			os_log("discovered correct characteristic")
			// If it is, subscribe to it
			transferCharacteristic = characteristic
			state = .connected
		}
	}
	
	/*
	 *   This callback lets us know more data has arrived via notification on the characteristic
	 */
	func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
		// Deal with errors (if any)
		if let error = error {
			os_log("Error discovering characteristics: %s", error.localizedDescription)
			cleanup()
			return
		}
		
		guard let characteristicData = characteristic.value else { return }
		
//		os_log("Received %d bytes", characteristicData.count)
		
		
		// End-of-message case: show the data.
		// Dispatch the text view update to the main queue for updating the UI, because
		// we don't know which thread this method will be called back on.
		
		// Otherwise, just append the data to what we have previously received.
		let dataArray = [UInt8](characteristicData)
		let receivedMsgID = dataArray.last!
		
		guard receivedMsgID == currMsgID else {
			display("A packet got dropped")
			return
		}
		let newCurrTime = Date.now
		rxTimes[Int(currMsgID)] = newCurrTime.timeIntervalSince(currTime)
		
		currTime = newCurrTime
		currMsgID = currMsgID &+ 1
		totalPacketsReceived += 1
		
		let encodedFrame = EncodedFrame(data: dataArray.dropLast())
		
		do {
			var decodedFrame = try encodedFrame.decode(decoder: self.decoder!)
			frameBuffer.append(decodedFrame)
			
			decodedFrame.samples.withUnsafeMutableBufferPointer { umrbp in
				let audioBuffer = AudioBuffer(mNumberChannels: 1, mDataByteSize: UInt32(umrbp.count * MemoryLayout<Float>.size), mData: umrbp.baseAddress)
				var bufferList = AudioBufferList(mNumberBuffers: 1, mBuffers: audioBuffer)
				let outputAudioBuffer = AVAudioPCMBuffer(pcmFormat: format, bufferListNoCopy: &bufferList)!
				pcmAudioBuffers.append(outputAudioBuffer)
				playerNode!.scheduleBuffer(outputAudioBuffer)
			}
			
		} catch {
			os_log("error decoding")
		}
		
		if currMsgID % 64 == 0 {
			let avgTimePerPacket = rxTimes.reduce(0, +)/256
			
			DispatchQueue.main.async() {
				self.avgLabel.text = "\(String(format: "%.2f", avgTimePerPacket * 1000)) ms per packet"
				self.avgLabel.textColor = avgTimePerPacket < 0.01 ? .label : .red
			}
		}
		
	}
	
	/*
	 *  The peripheral letting us know whether our subscribe/unsubscribe happened or not
	 */
	func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
		// Deal with errors (if any)
		if let error = error {
			os_log("Error changing notification state: %s", error.localizedDescription)
			return
		}
		
		// Exit if it's not the transfer characteristic
		guard characteristic.uuid == TransferService.characteristicUUID else { return }
		
		if characteristic.isNotifying {
			// Notification has started
			os_log("Notification began on %@", characteristic)
		} else {
			// Notification has stopped, so disconnect from the peripheral
			os_log("Notification stopped on %@. Disconnecting", characteristic)
			cleanup()
		}
		
	}
}

extension CentralViewController {
	@IBAction func buttonPressed(sender: UIButton) {
		os_log("button pressed")
		switch state {
		case .disconnected:
			break
		case .connected:
			// start streaming
			discoveredPeripheral!.setNotifyValue(true, for: transferCharacteristic!)
			state = .streaming
		case .streaming:
			// TODO: stop streaming
			break
		}
	}
	
	
	func display(_ text: String) {
		DispatchQueue.main.async() {
			self.textView.text.append("\(text)\n")
		}
	}
}
