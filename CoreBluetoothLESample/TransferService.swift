/*
See the LICENSE.txt file for this sample’s licensing information.

Abstract:
Transfer service and characteristics UUIDs
*/

import Foundation
import CoreBluetooth




struct TransferService {
	static let serviceUUID = CBUUID(string: "CF84")
	static let characteristicUUID = CBUUID(string: "A7BC")
}
