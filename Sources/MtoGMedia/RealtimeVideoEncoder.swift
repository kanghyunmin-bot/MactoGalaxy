import CoreMedia
import CoreVideo
import Foundation
import MtoGCore
import VideoToolbox

public struct RealtimeEncodedFrame: Sendable {
    public let config: Data?
    public let accessUnit: EncodedAccessUnit

    public init(config: Data?, accessUnit: EncodedAccessUnit) {
        self.config = config
        self.accessUnit = accessUnit
    }
}

public final class RealtimeVideoEncoder: @unchecked Sendable {
    private let session: VTCompressionSession
    private let collector: RealtimeEncoderCollector

    public init(
        codec: VideoCodec,
        width: Int,
        height: Int,
        framesPerSecond: Int,
        output: @escaping @Sendable (Result<RealtimeEncodedFrame, Error>) -> Void
    ) throws {
        collector = RealtimeEncoderCollector(codec: codec, output: output)
        var created: VTCompressionSession?
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
            outputCallback: realtimeEncoderCallback,
            refcon: Unmanaged.passUnretained(collector).toOpaque(),
            compressionSessionOut: &created
        )
        guard status == noErr, let created else { throw VideoToolboxError.hardwareUnavailable(codec, status) }
        session = created
        do {
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
                let propertyStatus = VTSessionSetProperty(session, key: key, value: value)
                guard propertyStatus == noErr else { throw VideoToolboxError.propertyFailed(propertyStatus) }
            }
            let profile = codec == .h264 ? kVTProfileLevel_H264_High_AutoLevel : kVTProfileLevel_HEVC_Main_AutoLevel
            let profileStatus = VTSessionSetProperty(session, key: kVTCompressionPropertyKey_ProfileLevel, value: profile)
            guard profileStatus == noErr else { throw VideoToolboxError.propertyFailed(profileStatus) }
            let prepareStatus = VTCompressionSessionPrepareToEncodeFrames(session)
            guard prepareStatus == noErr else { throw VideoToolboxError.encodeFailed(prepareStatus) }
        } catch {
            VTCompressionSessionInvalidate(session)
            throw error
        }
    }

    public func encode(
        _ pixelBuffer: CVPixelBuffer,
        presentationTimeUs: UInt64,
        framesPerSecond: Int,
        forceKeyframe: Bool = false
    ) throws {
        var flags = VTEncodeInfoFlags()
        let status = VTCompressionSessionEncodeFrame(
            session,
            imageBuffer: pixelBuffer,
            presentationTimeStamp: CMTime(value: Int64(presentationTimeUs), timescale: 1_000_000),
            duration: CMTime(value: 1, timescale: CMTimeScale(framesPerSecond)),
            frameProperties: forceKeyframe
                ? [kVTEncodeFrameOptionKey_ForceKeyFrame as String: true] as CFDictionary
                : nil,
            sourceFrameRefcon: nil,
            infoFlagsOut: &flags
        )
        guard status == noErr else { throw VideoToolboxError.encodeFailed(status) }
        if flags.contains(.frameDropped) { return }
    }

    public func complete() throws {
        let status = VTCompressionSessionCompleteFrames(session, untilPresentationTimeStamp: .invalid)
        guard status == noErr else { throw VideoToolboxError.encodeFailed(status) }
    }

    public func invalidate() {
        VTCompressionSessionInvalidate(session)
    }
}

private final class RealtimeEncoderCollector: @unchecked Sendable {
    let codec: VideoCodec
    let output: @Sendable (Result<RealtimeEncodedFrame, Error>) -> Void
    private let lock = NSLock()
    private var sentConfig = false

    init(codec: VideoCodec, output: @escaping @Sendable (Result<RealtimeEncodedFrame, Error>) -> Void) {
        self.codec = codec
        self.output = output
    }

    func consume(status: OSStatus, sampleBuffer: CMSampleBuffer?) {
        lock.lock(); defer { lock.unlock() }
        guard status == noErr else {
            output(.failure(VideoToolboxError.encodeFailed(status)))
            return
        }
        guard let sampleBuffer else { return }
        guard CMSampleBufferDataIsReady(sampleBuffer) else {
            output(.failure(VideoToolboxError.encodeFailed(kVTInvalidSessionErr)))
            return
        }
        do {
            guard let format = CMSampleBufferGetFormatDescription(sampleBuffer),
                  let block = CMSampleBufferGetDataBuffer(sampleBuffer) else {
                throw VideoToolboxError.missingDataBuffer
            }
            let config = sentConfig ? nil : try videoParameterSets(format: format, codec: codec)
            sentConfig = true
            let length = CMBlockBufferGetDataLength(block)
            var data = Data(count: length)
            let copyStatus = data.withUnsafeMutableBytes { bytes in
                CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: bytes.baseAddress!)
            }
            guard copyStatus == noErr else { throw VideoToolboxError.encodeFailed(copyStatus) }
            let attachments = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer, createIfNecessary: false) as? [[CFString: Any]]
            let notSync = attachments?.first?[kCMSampleAttachmentKey_NotSync] as? Bool ?? false
            let pts = CMTimeConvertScale(
                CMSampleBufferGetPresentationTimeStamp(sampleBuffer),
                timescale: 1_000_000,
                method: .default
            ).value
            output(.success(RealtimeEncodedFrame(
                config: config,
                accessUnit: EncodedAccessUnit(
                    annexBData: try NALUnitConverter.annexB(fromLengthPrefixed: data),
                    presentationTimeUs: UInt64(max(pts, 0)),
                    isKeyframe: !notSync
                )
            )))
        } catch {
            output(.failure(error))
        }
    }
}

private let realtimeEncoderCallback: VTCompressionOutputCallback = { refcon, _, status, _, sampleBuffer in
    guard let refcon else { return }
    Unmanaged<RealtimeEncoderCollector>.fromOpaque(refcon).takeUnretainedValue().consume(
        status: status,
        sampleBuffer: sampleBuffer
    )
}
