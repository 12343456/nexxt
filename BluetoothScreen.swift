import SwiftUI
import CoreBluetooth

final class BluetoothManager: NSObject, ObservableObject, CBCentralManagerDelegate {
    @Published var devices: [CBPeripheral] = []
    @Published var state: CBManagerState = .unknown
    private var central: CBCentralManager!
    override init() { super.init(); central = CBCentralManager(delegate: self, queue: .main) }
    func centralManagerDidUpdateState(_ central: CBCentralManager) { state = central.state }
    func scan() { guard state == .poweredOn else { return }; devices.removeAll(); central.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]) }
    func stop() { central.stopScan() }
    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) { if !devices.contains(where: { $0.identifier == peripheral.identifier }) { devices.append(peripheral) } }
}

struct BluetoothScreen: View {
    @StateObject private var bluetooth = BluetoothManager()
    var body: some View {
        NavigationStack { List { HStack { Circle().fill(bluetooth.state == .poweredOn ? Color.green : Color.red).frame(width: 10, height: 10); Text(bluetooth.state == .poweredOn ? "Bluetooth включён" : "Bluetooth недоступен") }; Button("Сканировать") { bluetooth.scan() }; ForEach(bluetooth.devices, id: \.identifier) { device in VStack(alignment: .leading) { Text(device.name ?? "Неизвестное устройство"); Text(device.identifier.uuidString).font(.caption).foregroundStyle(Color.secondary) } } }.navigationTitle("Bluetooth").onDisappear { bluetooth.stop() } }
    }
}
