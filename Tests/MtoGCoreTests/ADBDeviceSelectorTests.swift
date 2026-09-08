import Testing
@testable import MtoGCore

struct ADBDeviceSelectorTests {
    @Test
    func parsesAndSelectsOnlyAuthorizedDevices() throws {
        let output = """
        List of devices attached
        R58M123 device product:gts model:Galaxy_Tab transport_id:1 usb:1-1
        emulator-5554 offline transport_id:2
        R58M999 unauthorized usb:1-2
        """
        let devices = ADBDeviceParser.parse(output)
        #expect(devices.count == 3)
        #expect(try ADBDeviceSelector.select(devices: devices, preferredSerial: nil).serial == "R58M123")
    }

    @Test
    func multipleDevicesRequireExplicitSelection() throws {
        let devices = [
            ADBDevice(serial: "B", state: .authorized, details: "usb:2"),
            ADBDevice(serial: "A", state: .authorized, details: "usb:1")
        ]
        #expect(throws: ADBDeviceSelectionError.multipleAuthorized(["A", "B"])) {
            _ = try ADBDeviceSelector.select(devices: devices, preferredSerial: nil)
        }
        #expect(try ADBDeviceSelector.select(devices: devices, preferredSerial: "B").serial == "B")
        #expect(throws: ADBDeviceSelectionError.preferredUnavailable("missing")) {
            _ = try ADBDeviceSelector.select(devices: devices, preferredSerial: "missing")
        }
    }

    @Test
    func noAuthorizedDeviceFails() {
        #expect(throws: ADBDeviceSelectionError.noAuthorizedDevice) {
            _ = try ADBDeviceSelector.select(
                devices: [ADBDevice(serial: "x", state: .unauthorized, details: "")],
                preferredSerial: nil
            )
        }
    }
}
