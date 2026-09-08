import Foundation
import MtoGCore
import MtoGMedia

let width = 2560, height = 1600, count = 12
for codec in [VideoCodec.h264, .hevc] {
    var report: [String: Any] = ["scope": "synthetic-local-batch-no-usb", "codec": codec.rawValue,
        "width": width, "height": height, "input_frames": count, "target_fps": 60,
        "os": ProcessInfo.processInfo.operatingSystemVersionString,
        "device_latency": "NOT_MEASURED", "per_frame_latency": "NOT_MEASURED"]
    do {
        switch VideoToolboxCodecSupport.hardwareStatus(for: codec, width: width, height: height) {
        case .unavailable(let reason):
            report["status"] = "CAPABILITY_UNAVAILABLE"; report["reason"] = reason
        case .available:
            let source = SyntheticFrameSource(width: width, height: height)
            let frames = (0..<count).map { _ in source.next(pattern: .movingSquare) }
            let start = ProcessInfo.processInfo.systemUptime
            let encoded = try VideoToolboxEncoder(codec: codec, width: width, height: height, framesPerSecond: 60).encode(frames)
            let encodedAt = ProcessInfo.processInfo.systemUptime
            let session = UUID()
            var packets = [VideoPacket(kind: .config, codec: codec, flags: 0, sessionID: session,
                sequence: 1, presentationTimeUs: 0, width: width, height: height, payload: encoded.config)]
            packets += encoded.accessUnits.enumerated().map { index, unit in
                VideoPacket(kind: .accessUnit, codec: codec, flags: unit.isKeyframe ? VideoPacket.keyframeFlag : 0,
                    sessionID: session, sequence: UInt64(index + 2), presentationTimeUs: unit.presentationTimeUs,
                    width: width, height: height, payload: unit.annexBData)
            }
            let decoded = try VideoToolboxDecoder(codec: codec).decode(packets)
            let end = ProcessInfo.processInfo.systemUptime
            report["status"] = decoded.decodedFrames == count ? "PASS" : "FAIL"
            report["encoded_frames"] = encoded.accessUnits.count
            report["decoded_frames"] = decoded.decodedFrames
            report["drop_count"] = count - decoded.decodedFrames
            report["encode_batch_seconds"] = encodedAt - start
            report["decode_batch_seconds"] = end - encodedAt
            report["roundtrip_batch_seconds"] = end - start
            report["batch_throughput_fps"] = Double(decoded.decodedFrames) / (end - start)
        }
    } catch { report["status"] = "FAIL"; report["reason"] = String(describing: error) }
    let data = try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys])
    print(String(decoding: data, as: UTF8.self))
}
