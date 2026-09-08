import AppKit
import Foundation
import Testing
@testable import MtoGMac

@Test @MainActor func imageFileKeepsOriginalBytesAndMetadata() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let bitmap = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2,
        bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 6, bitsPerPixel: 24))
    let pixels = try #require(bitmap.bitmapData)
    for offset in 0..<12 { pixels[offset] = offset % 3 == 0 ? 255 : 0 }
    let original = try #require(bitmap.representation(using: .jpeg, properties: [:]))
    let file = directory.appendingPathComponent("photo.jpg")
    try original.write(to: file)
    let controller = ClipboardSyncController(cacheDirectoryOverride: directory.appendingPathComponent("cache"))
    let payload = try #require(controller.filePayload(for: file))
    #expect(payload.mimeType == "image/jpeg")
    #expect(payload.fileName == "photo.jpg")
    #expect(payload.binaryData == original)
    #expect(payload.sizeInBytes == original.count)
    let decoded = try #require(ClipboardSyncPayload.fromWirePayload(payload.wirePayload))
    #expect(decoded.binaryData == original)
    var damaged = payload.wirePayload
    damaged["sha256"] = String(repeating: "0", count: 64)
    #expect(ClipboardSyncPayload.fromWirePayload(damaged) == nil)
}

@Test @MainActor func oversizedFileIsRejectedBeforeTransmission() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let file = directory.appendingPathComponent("oversized.bin")
    try Data(count: ClipboardSyncPayload.maxTransferBytes + 1).write(to: file)
    let controller = ClipboardSyncController(cacheDirectoryOverride: directory.appendingPathComponent("cache"))
    #expect(controller.filePayload(for: file) == nil)
}
