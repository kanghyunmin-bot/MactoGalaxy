import Foundation
import MtoGCore

let arguments = CommandLine.arguments
func value(after option: String) -> String? {
    guard let index = arguments.firstIndex(of: option), arguments.indices.contains(index + 1) else { return nil }
    return arguments[index + 1]
}

guard let serial = value(after: "--serial"),
      let sessionValue = value(after: "--session"),
      let sessionID = UUID(uuidString: sessionValue) else {
    fputs("error:selected Android serial and control session are required\n", stderr)
    Foundation.exit(2)
}

let requestedWidth = Int(value(after: "--width") ?? "1920") ?? 0
let requestedHeight = Int(value(after: "--height") ?? "1200") ?? 0
let codecArgument = value(after: "--codec") ?? "auto"
guard ["auto", "h264", "hevc"].contains(codecArgument),
      (640...2560).contains(requestedWidth), (480...1600).contains(requestedHeight),
      requestedWidth % 2 == 0, requestedHeight % 2 == 0 else {
    fputs("error:invalid display size or codec\n", stderr)
    Foundation.exit(2)
}
let worker = ExternalDisplayWorker(selectedSerial: serial, controlSessionID: sessionID,
    width: requestedWidth, height: requestedHeight, preferredCodec: VideoCodec(rawValue: codecArgument))
Foundation.exit(worker.run())
