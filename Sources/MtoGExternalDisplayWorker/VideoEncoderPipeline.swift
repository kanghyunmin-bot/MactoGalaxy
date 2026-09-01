import CoreVideo
import Foundation
import MtoGCore
import MtoGMedia

final class VideoEncoderPipeline {
    private let encoder: RealtimeVideoEncoder
    private let framesPerSecond: Int

    init(
        codec: VideoCodec,
        width: Int,
        height: Int,
        framesPerSecond: Int,
        output: @escaping @Sendable (Result<RealtimeEncodedFrame, Error>) -> Void
    ) throws {
        self.framesPerSecond = framesPerSecond
        self.encoder = try RealtimeVideoEncoder(
            codec: codec,
            width: width,
            height: height,
            framesPerSecond: framesPerSecond,
            output: output
        )
    }

    func encode(_ frame: CapturedVideoFrame) throws {
        try encoder.encode(
            frame.pixelBuffer,
            presentationTimeUs: frame.presentationTimeUs,
            framesPerSecond: framesPerSecond
        )
    }

    func complete() throws {
        try encoder.complete()
    }

    func invalidate() {
        encoder.invalidate()
    }
}
