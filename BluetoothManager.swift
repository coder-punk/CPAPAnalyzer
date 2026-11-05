import Foundation
import CoreBluetooth

final class BluetoothManager: NSObject, ObservableObject, CBCentralManagerDelegate {
    @Published var devices: [String] = []
    @Published var stateText = "Bluetooth wordt voorbereid"
    private var central: CBCentralManager!
    override init() { super.init(); central = CBCentralManager(delegate: self, queue: .main) }
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        stateText = central.state == .poweredOn ? "Bluetooth ingeschakeld" : "Bluetooth niet beschikbaar of uitgeschakeld"
    }
    func scan() {
        guard central.state == .poweredOn else { return }
        devices = []
        central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        stateText = "Zoeken naar BLE-apparaten (geen therapiedata-uitlezing)"
    }
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        let name = peripheral.name ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? "Onbekend apparaat"
        if !devices.contains(name) { devices.append(name) }
    }
    func stop() { central.stopScan(); stateText = "Zoeken gestopt" }
}
