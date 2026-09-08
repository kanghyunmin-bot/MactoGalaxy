import CoreMedia
import CoreVideo
import Foundation
import MtoGCore
import VideoToolbox

public struct VideoRoundTripResult: Equatable, Sendable {
    public let decodedFrames: Int
    public let width: Int
    public let height: Int
    public let timestamps: [UInt64]
    public let sawConfig: Bool
    public let sawKeyframe: Bool
}

public final class VideoToolboxDecoder {
    private let codec: VideoCodec

    public init(codec: VideoCodec) {
        self.codec = codec
    }

    public func decode(_ packets: [VideoPacket]) throws -> VideoRoundTripResult {
        guard let configPacket = packets.first(where: { $0.kind == .config }) else {
            throw VideoToolboxError.missingParameterSets
        }
        let format = try makeFormatDescription(configPacket.payload)
        let collector = DecoderCollector()
        var session: VTDecompressionSession?
        let attributes = [
            kCVPixelBufferPixelFormatTypeKey as String: NSNumber(value: kCVPixelFormatType_32BGRA)
        ] as CFDictionary
        var callback = VTDecompressionOutputCallbackRecord(
            decompressionOutputCallback: decoderOutputCallback,
            decompressionOutputRefCon: Unmanaged.passUnretained(collector).toOpaque()
        )
        let status = VTDecompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            formatDescription: format,
            decoderSpecification: nil,
            imageBufferAttributes: attributes,
            outputCallback: &callback,
            decompressionSessionOut: &session
        )
        guard status == noErr, let session else { throw VideoToolboxError.decodeFailed(status) }
        defer { VTDecompressionSessionInvalidate(session) }

        var sawKeyframe = false
        for packet in packets where packet.kind == .accessUnit {
            sawKeyframe = sawKeyframe || packet.isKeyframe
            let sample = try makeSampleBuffer(packet: packet, format: format)
            var infoFlags = VTDecodeInfoFlags()
            let decodeStatus = VTDecompressionSessionDecodeFrame(
                session,
                sampleBuffer: sample,
                flags: [],
                frameRefcon: nil,
                infoFlagsOut: &infoFlags
            )
            guard decodeStatus == noErr else { throw VideoToolboxError.decodeFailed(decodeStatus) }
        }
        let waitStatus = VTDecompressionSessionWaitForAsynchronousFrames(session)
        guard waitStatus == noErr else { throw VideoToolboxError.decodeFailed(waitStatus) }
        if let error = collector.error { throw error }
        return VideoRoundTripResult(
            decodedFrames: collector.timestamps.count,
            width: collector.width,
            height: collector.height,
            timestamps: collector.timestamps,
            sawConfig: true,
            sawKeyframe: sawKeyframe
        )
    }

    private func makeFormatDescription(_ config: Data) throws -> CMVideoFormatDescription {
        let units = try NALUnitConverter.nalUnits(fromAnnexB: config)
        let selected: [Data]
        if codec == .h264 {
            let sps = units.first { !$0.isEmpty && ($0[0] & 0x1F) == 7 }
            let pps = units.first { !$0.isEmpty && ($0[0] & 0x1F) == 8 }
            selected = try [sps, pps].map { try $0 ?? { throw VideoToolboxError.missingParameterSets }() }
        } else {
            let vps = units.first { !$0.isEmpty && (($0[0] >> 1) & 0x3F) == 32 }
            let sps = units.first { !$0.isEmpty && (($0[0] >> 1) & 0x3F) == 33 }
            let pps = units.first { !$0.isEmpty && (($0[0] >> 1) & 0x3F) == 34 }
            selected = try [vps, sps, pps].map { try $0 ?? { throw VideoToolboxError.missingParameterSets }() }
        }

        let allocations = selected.map { data -> UnsafeMutablePointer<UInt8> in
            let pointer = UnsafeMutablePointer<UInt8>.allocate(capacity: data.count)
            data.copyBytes(to: pointer, count: data.count)
            return pointer
        }
        defer { allocations.forEach { $0.deallocate() } }
        var pointers = allocations.map { UnsafePointer($0) as UnsafePointer<UInt8> }
        var sizes = selected.map(\.count)
        var format: CMFormatDescription?
        let status: OSStatus
        if codec == .h264 {
            status = CMVideoFormatDescriptionCreateFromH264ParameterSets(
                allocator: kCFAllocatorDefault,
                parameterSetCount: pointers.count,
                parameterSetPointers: &pointers,
                parameterSetSizes: &sizes,
                nalUnitHeaderLength: 4,
                formatDescriptionOut: &format
            )
        } else {
            status = CMVideoFormatDescriptionCreateFromHEVCParameterSets(
                allocator: kCFAllocatorDefault,
                parameterSetCount: pointers.count,
                parameterSetPointers: &pointers,
                parameterSetSizes: &sizes,
                nalUnitHeaderLength: 4,
                extensions: nil,
                formatDescriptionOut: &format
            )
        }
        guard status == noErr, let format else { throw VideoToolboxError.decodeFailed(status) }
        return format
    }

    private func makeSampleBuffer(packet: VideoPacket, format: CMFormatDescription) throws -> CMSampleBuffer {
        let data = try NALUnitConverter.lengthPrefixed(fromAnnexB: packet.payload)
        var block: CMBlockBuffer?
        var status = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: data.count,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: data.count,
            flags: 0,
            blockBufferOut: &block
        )
        guard status == kCMBlockBufferNoErr, let block else { throw VideoToolboxError.decodeFailed(status) }
        status = data.withUnsafeBytes { bytes in
            CMBlockBufferReplaceDataBytes(with: bytes.baseAddress!, blockBuffer: block, offsetIntoDestination: 0, dataLength: data.count)
        }
        guard status == kCMBlockBufferNoErr else { throw VideoToolboxError.decodeFailed(status) }
        var timing = CMSampleTimingInfo(
            duration: .invalid,
            presentationTimeStamp: CMTime(value: Int64(packet.presentationTimeUs), timescale: 1_000_000),
            decodeTimeStamp: .invalid
        )
        var sampleSize = data.count
        var sample: CMSampleBuffer?
        status = CMSampleBufferCreateReady(
            allocator: kCFAllocatorDefault,
            dataBuffer: block,
            formatDescription: format,
            sampleCount: 1,
            sampleTimingEntryCount: 1,
            sampleTimingArray: &timing,
            sampleSizeEntryCount: 1,
            sampleSizeArray: &sampleSize,
            sampleBufferOut: &sample
        )
        guard status == noErr, let sample else { throw VideoToolboxError.decodeFailed(status) }
        return sample
    }
}

private final class DecoderCollector: @unchecked Sendable {
    let lock = NSLock()
    var width = 0
    var height = 0
    var timestamps: [UInt64] = []
    var error: Error?

    func consume(status: OSStatus, imageBuffer: CVImageBuffer?, presentationTime: CMTime) {
        lock.lock(); defer { lock.unlock() }
        guard status == noErr, let imageBuffer else {
            error = VideoToolboxError.decodeFailed(status)
            return
        }
        width = CVPixelBufferGetWidth(imageBuffer)
        height = CVPixelBufferGetHeight(imageBuffer)
        let converted = CMTimeConvertScale(presentationTime, timescale: 1_000_000, method: .default).value
        timestamps.append(UInt64(max(converted, 0)))
    }
}

private let decoderOutputCallback: VTDecompressionOutputCallback = {
    refcon, _, status, _, imageBuffer, presentationTime, _ in
    guard let refcon else { return }
    Unmanaged<DecoderCollector>.fromOpaque(refcon).takeUnretainedValue().consume(
        status: status,
        imageBuffer: imageBuffer,
        presentationTime: presentationTime
    )
}
