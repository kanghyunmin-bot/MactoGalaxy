import CoreMedia
import CoreVideo
import Foundation
import MtoGCore
import VideoToolbox

public enum VideoToolboxError: Error, LocalizedError {
    case hardwareUnavailable(VideoCodec, OSStatus)
    case propertyFailed(OSStatus)
    case encodeFailed(OSStatus)
    case decodeFailed(OSStatus)
    case missingFormatDescription
    case missingParameterSets
    case missingDataBuffer
    case pixelBufferFailed(CVReturn)

    public var errorDescription: String? {
        switch self {
        case .hardwareUnavailable(let codec, let status): return "hardware \(codec.rawValue) unavailable: \(status)"
        case .propertyFailed(let status): return "VideoToolbox property failed: \(status)"
        case .encodeFailed(let status): return "VideoToolbox encode failed: \(status)"
        case .decodeFailed(let status): return "VideoToolbox decode failed: \(status)"
        case .missingFormatDescription: return "encoded format description missing"
        case .missingParameterSets: return "codec parameter sets missing"
        case .missingDataBuffer: return "encoded data buffer missing"
        case .pixelBufferFailed(let status): return "pixel buffer failed: \(status)"
        }
    }
}

public struct EncodedAccessUnit: Equatable, Sendable {
    public let annexBData: Data
    public let presentationTimeUs: UInt64
    public let isKeyframe: Bool

    public init(annexBData: Data, presentationTimeUs: UInt64, isKeyframe: Bool) {
        self.annexBData = annexBData
        self.presentationTimeUs = presentationTimeUs
        self.isKeyframe = isKeyframe
    }
}

public struct EncodedVideoStream: Equatable, Sendable {
    public let config: Data
    public let accessUnits: [EncodedAccessUnit]
}

public enum HardwareCodecStatus: Equatable, Sendable {
    case available
    case unavailable(String)
}

public enum VideoToolboxCodecSupport {
    public static func hardwareStatus(for codec: VideoCodec, width: Int, height: Int) -> HardwareCodecStatus {
        var session: VTCompressionSession?
        let specification = [
            kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder as String: true
        ] as CFDictionary
        let status = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: Int32(width),
            height: Int32(height),
            codecType: codec.cmCodecType,
            encoderSpecification: specification,
            imageBufferAttributes: nil,
            compressedDataAllocator: nil,
            outputCallback: nil,
            refcon: nil,
            compressionSessionOut: &session
        )
        if let session { VTCompressionSessionInvalidate(session) }
        return status == noErr ? .available : .unavailable("OSStatus \(status)")
    }
}

public final class VideoToolboxEncoder {
    private let codec: VideoCodec
    private let width: Int
    private let height: Int
    private let framesPerSecond: Int

    public init(codec: VideoCodec, width: Int, height: Int, framesPerSecond: Int) {
        self.codec = codec
        self.width = width
        self.height = height
        self.framesPerSecond = framesPerSecond
    }

    public func encode(_ frames: [SyntheticFrame]) throws -> EncodedVideoStream {
        let collector = EncoderCollector(codec: codec)
        var session: VTCompressionSession?
        let specification = [
            kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder as String: true
        ] as CFDictionary
        let status = VTCompressionSessionCreate(
            allocator: kCFAllocatorDefault,
            width: Int32(width),
            height: Int32(height),
            codecType: codec.cmCodecType,
            encoderSpecification: specification,
            imageBufferAttributes: nil,
            compressedDataAllocator: nil,
            outputCallback: encoderOutputCallback,
            refcon: Unmanaged.passUnretained(collector).toOpaque(),
            compressionSessionOut: &session
        )
        guard status == noErr, let session else { throw VideoToolboxError.hardwareUnavailable(codec, status) }
        defer { VTCompressionSessionInvalidate(session) }
        try setProperties(session)
        let prepareStatus = VTCompressionSessionPrepareToEncodeFrames(session)
        guard prepareStatus == noErr else { throw VideoToolboxError.encodeFailed(prepareStatus) }

        for frame in frames {
            let pixelBuffer = try makePixelBuffer(frame)
            var infoFlags = VTEncodeInfoFlags()
            let encodeStatus = VTCompressionSessionEncodeFrame(
                session,
                imageBuffer: pixelBuffer,
                presentationTimeStamp: CMTime(value: Int64(frame.presentationTimeUs), timescale: 1_000_000),
                duration: CMTime(value: 1, timescale: CMTimeScale(framesPerSecond)),
                frameProperties: nil,
                sourceFrameRefcon: nil,
                infoFlagsOut: &infoFlags
            )
            guard encodeStatus == noErr else { throw VideoToolboxError.encodeFailed(encodeStatus) }
        }
        let completeStatus = VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .invalid)
        guard completeStatus == noErr else { throw VideoToolboxError.encodeFailed(completeStatus) }
        if let error = collector.error { throw error }
        guard let config = collector.config else { throw VideoToolboxError.missingParameterSets }
        return EncodedVideoStream(config: config, accessUnits: collector.accessUnits)
    }

    private func setProperties(_ session: VTCompressionSession) throws {
        let properties: [(CFString, CFTypeRef)] = [
            (kVTCompressionPropertyKey_RealTime, kCFBooleanTrue),
            (kVTCompressionPropertyKey_AllowFrameReordering, kCFBooleanFalse),
            (kVTCompressionPropertyKey_ExpectedFrameRate, NSNumber(value: framesPerSecond)),
            (kVTCompressionPropertyKey_MaxKeyFrameInterval, NSNumber(value: framesPerSecond)),
            (kVTCompressionPropertyKey_MaxKeyFrameIntervalDuration, NSNumber(value: 1.0)),
            (kVTCompressionPropertyKey_AverageBitRate, NSNumber(value: boundedVideoBitrate(width: width, height: height))),
            (kVTCompressionPropertyKey_DataRateLimits, [
                NSNumber(value: boundedVideoBitrate(width: width, height: height) / 8),
                NSNumber(value: 1)
            ] as CFArray)
        ]
        for (key, value) in properties {
            let status = VTSessionSetProperty(session, key: key, value: value)
            guard status == noErr else { throw VideoToolboxError.propertyFailed(status) }
        }
        let profile: CFString = codec == .h264
            ? kVTProfileLevel_H264_High_AutoLevel
            : kVTProfileLevel_HEVC_Main_AutoLevel
        let status = VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ProfileLevel, value: profile)
        guard status == noErr else { throw VideoToolboxError.propertyFailed(status) }
    }

    private func makePixelBuffer(_ frame: SyntheticFrame) throws -> CVPixelBuffer {
        guard frame.width == width, frame.height == height else { throw VideoToolboxError.pixelBufferFailed(kCVReturnInvalidArgument) }
        var pixelBuffer: CVPixelBuffer?
        let attributes = [
            kCVPixelBufferIOSurfacePropertiesKey as String: [:],
            kCVPixelBufferMetalCompatibilityKey as String: true
        ] as CFDictionary
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attributes,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let pixelBuffer else { throw VideoToolboxError.pixelBufferFailed(status) }
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        guard let destination = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            throw VideoToolboxError.pixelBufferFailed(kCVReturnInvalidArgument)
        }
        let destinationStride = CVPixelBufferGetBytesPerRow(pixelBuffer)
        frame.bgraBytes.withUnsafeBytes { source in
            guard let sourceBase = source.baseAddress else { return }
            for row in 0..<height {
                memcpy(destination.advanced(by: row * destinationStride), sourceBase.advanced(by: row * width * 4), width * 4)
            }
        }
        return pixelBuffer
    }
}

private final class EncoderCollector: @unchecked Sendable {
    let codec: VideoCodec
    let lock = NSLock()
    var config: Data?
    var accessUnits: [EncodedAccessUnit] = []
    var error: Error?

    init(codec: VideoCodec) { self.codec = codec }

    func consume(status: OSStatus, sampleBuffer: CMSampleBuffer?) {
        lock.lock(); defer { lock.unlock() }
        guard status == noErr else {
            error = VideoToolboxError.encodeFailed(status)
            return
        }
        guard let sampleBuffer else { return }
        guard CMSampleBufferDataIsReady(sampleBuffer) else {
            error = VideoToolboxError.encodeFailed(kVTInvalidSessionErr)
            return
        }
        do {
            guard let format = CMSampleBufferGetFormatDescription(sampleBuffer) else {
                throw VideoToolboxError.missingFormatDescription
            }
            if config == nil { config = try videoParameterSets(format: format, codec: codec) }
            guard let block = CMSampleBufferGetDataBuffer(sampleBuffer) else { throw VideoToolboxError.missingDataBuffer }
            let length = CMBlockBufferGetDataLength(block)
            var data = Data(count: length)
            let copyStatus = data.withUnsafeMutableBytes { bytes in
                CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: bytes.baseAddress!)
            }
            guard copyStatus == kCMBlockBufferNoErr else { throw VideoToolboxError.encodeFailed(copyStatus) }
            let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[CFString: Any]]
            let notSync = attachments?.first?[kCMSampleAttachmentKey_NotSync] as? Bool ?? false
            let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
            let microseconds = max(CMTimeConvertScale(pts, timescale: 1_000_000, method: .default).value, 0)
            accessUnits.append(
                EncodedAccessUnit(
                    annexBData: try NALUnitConverter.annexB(fromLengthPrefixed: data),
                    presentationTimeUs: UInt64(microseconds),
                    isKeyframe: !notSync
                )
            )
        } catch {
            self.error = error
        }
    }
}

private let encoderOutputCallback: VTCompressionOutputCallback = { refcon, _, status, _, sampleBuffer in
    guard let refcon else { return }
    Unmanaged<EncoderCollector>.fromOpaque(refcon).takeUnretainedValue().consume(
        status: status,
        sampleBuffer: sampleBuffer
    )
}

func videoParameterSets(format: CMFormatDescription, codec: VideoCodec) throws -> Data {
    var sets: [Data] = []
    var count = 0
    var headerLength: Int32 = 0
    let firstStatus: OSStatus
    var pointer: UnsafePointer<UInt8>?
    var size = 0
    if codec == .h264 {
        firstStatus = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
            format, parameterSetIndex: 0, parameterSetPointerOut: &pointer,
            parameterSetSizeOut: &size, parameterSetCountOut: &count,
            nalUnitHeaderLengthOut: &headerLength
        )
    } else {
        firstStatus = CMVideoFormatDescriptionGetHEVCParameterSetAtIndex(
            format, parameterSetIndex: 0, parameterSetPointerOut: &pointer,
            parameterSetSizeOut: &size, parameterSetCountOut: &count,
            nalUnitHeaderLengthOut: &headerLength
        )
    }
    guard firstStatus == noErr, count > 0 else { throw VideoToolboxError.missingParameterSets }
    for index in 0..<count {
        pointer = nil; size = 0
        let status: OSStatus
        if codec == .h264 {
            status = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(
                format, parameterSetIndex: index, parameterSetPointerOut: &pointer,
                parameterSetSizeOut: &size, parameterSetCountOut: nil,
                nalUnitHeaderLengthOut: nil
            )
        } else {
            status = CMVideoFormatDescriptionGetHEVCParameterSetAtIndex(
                format, parameterSetIndex: index, parameterSetPointerOut: &pointer,
                parameterSetSizeOut: &size, parameterSetCountOut: nil,
                nalUnitHeaderLengthOut: nil
            )
        }
        guard status == noErr, let pointer, size > 0 else { throw VideoToolboxError.missingParameterSets }
        sets.append(Data(bytes: pointer, count: size))
    }
    return NALUnitConverter.annexB(parameterSets: sets)
}

func boundedVideoBitrate(width: Int, height: Int) -> Int {
    min(max(width * height * 4, 2_000_000), 40_000_000)
}

extension VideoCodec {
    var cmCodecType: CMVideoCodecType {
        self == .h264 ? kCMVideoCodecType_H264 : kCMVideoCodecType_HEVC
    }
}
