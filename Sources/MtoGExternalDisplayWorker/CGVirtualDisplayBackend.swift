import AppKit
import CoreGraphics
import Foundation
import ObjectiveC.runtime

final class CGVirtualDisplayBackend {
    private var display: NSObject?

    func create() throws -> CGDirectDisplayID {
        guard let descriptorClass = NSClassFromString("CGVirtualDisplayDescriptor") as? NSObject.Type,
              let displayClass = NSClassFromString("CGVirtualDisplay"),
              let settingsClass = NSClassFromString("CGVirtualDisplaySettings") as? NSObject.Type,
              let modeClass = NSClassFromString("CGVirtualDisplayMode") as? NSObject.Type else {
            throw WorkerError.virtualDisplayUnavailable
        }
        let descriptor = descriptorClass.init()
        descriptor.setValue(505, forKey: "vendorID")
        descriptor.setValue(46002, forKey: "productID")
        descriptor.setValue(930011, forKey: "serialNum")
        descriptor.setValue(930011, forKey: "serialNumber")
        descriptor.setValue("MtoG Galaxy Tab", forKey: "name")
        descriptor.setValue(1920, forKey: "maxPixelsWide")
        descriptor.setValue(1200, forKey: "maxPixelsHigh")
        descriptor.setValue(NSValue(size: CGSize(width: 325, height: 203)), forKey: "sizeInMillimeters")
        descriptor.setValue(NSValue(point: CGPoint(x: 0.3125, y: 0.3291)), forKey: "whitePoint")
        descriptor.setValue(NSValue(point: CGPoint(x: 0.1494, y: 0.0557)), forKey: "bluePrimary")
        descriptor.setValue(NSValue(point: CGPoint(x: 0.2559, y: 0.6983)), forKey: "greenPrimary")
        descriptor.setValue(NSValue(point: CGPoint(x: 0.6797, y: 0.3203)), forKey: "redPrimary")
        descriptor.setValue(DispatchQueue.global(qos: .userInitiated), forKey: "queue")

        let display = try instantiate(displayClass: displayClass, descriptor: descriptor)
        self.display = display
        let settings = settingsClass.init()
        let mode = modeClass.init()
        mode.setValue(1920, forKey: "width")
        mode.setValue(1200, forKey: "height")
        mode.setValue(60.0, forKey: "refreshRate")
        settings.setValue([mode], forKey: "modes")
        settings.setValue(0, forKey: "rotation")
        settings.setValue(0, forKey: "hiDPI")
        if !applySettings(display: display, settings: settings) {
            workerStatus("macOS kept fallback external display settings")
        }
        guard let number = display.value(forKey: "displayID") as? NSNumber,
              number.uint32Value != 0 else { throw WorkerError.displayIdUnavailable }
        return CGDirectDisplayID(number.uint32Value)
    }

    func stop() {
        display = nil
    }

    private func instantiate(displayClass: AnyClass, descriptor: NSObject) throws -> NSObject {
        let classObject: AnyObject = displayClass
        guard let allocated = classObject.perform(NSSelectorFromString("alloc"))?.takeUnretainedValue(),
              let method = class_getInstanceMethod(displayClass, NSSelectorFromString("initWithDescriptor:")) else {
            throw WorkerError.virtualDisplayCreateFailed
        }
        typealias Initializer = @convention(c) (AnyObject, Selector, AnyObject) -> AnyObject?
        let function = unsafeBitCast(method_getImplementation(method), to: Initializer.self)
        guard let value = function(allocated, NSSelectorFromString("initWithDescriptor:"), descriptor) as? NSObject else {
            throw WorkerError.virtualDisplayCreateFailed
        }
        return value
    }

    private func applySettings(display: NSObject, settings: NSObject) -> Bool {
        guard let method = class_getInstanceMethod(type(of: display), NSSelectorFromString("applySettings:")) else {
            return false
        }
        typealias Apply = @convention(c) (AnyObject, Selector, AnyObject) -> Bool
        let function = unsafeBitCast(method_getImplementation(method), to: Apply.self)
        return function(display, NSSelectorFromString("applySettings:"), settings)
    }
}
