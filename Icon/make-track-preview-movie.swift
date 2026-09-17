// make-track-preview-movie.swift - turns one image into a one-second, one-frame H.264 movie: the
// placeholder the Recordings tab's player shows with nothing selected. A movie rather than the image
// itself, because the player shows a crossed-out play button for a file it cannot play.
//
//   /usr/bin/sips -s format png Icon/track-preview-movie.svg --out <frame.png>
//   swift Icon/make-track-preview-movie.swift <frame.png> Speech.app/Contents/Resources/track-preview.mov

import AVFoundation
import AppKit

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("make-track-preview-movie: \(message)\n".utf8))
    exit(1)
}

let arguments = CommandLine.arguments
guard arguments.count == 3 else { fail("usage: make-track-preview-movie.swift <image> <out.mov>") }
let imageURL = URL(fileURLWithPath: arguments[1])
let movieURL = URL(fileURLWithPath: arguments[2])

guard let image = NSImage(contentsOf: imageURL),
      let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
else { fail("cannot read \(imageURL.path)") }
let width = cgImage.width
let height = cgImage.height
guard width % 2 == 0, height % 2 == 0 else { fail("H.264 needs even dimensions, got \(width)x\(height)") }

try? FileManager.default.removeItem(at: movieURL)
let writer: AVAssetWriter
do {
    writer = try AVAssetWriter(outputURL: movieURL, fileType: .mov)
} catch {
    fail("cannot create \(movieURL.path): \(error.localizedDescription)")
}
let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
    AVVideoCodecKey: AVVideoCodecType.h264,
    AVVideoWidthKey: width,
    AVVideoHeightKey: height,
])
input.expectsMediaDataInRealTime = false
let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
    kCVPixelBufferWidthKey as String: width,
    kCVPixelBufferHeightKey as String: height,
])
guard writer.canAdd(input) else { fail("the writer refuses an H.264 input") }
writer.add(input)
guard writer.startWriting() else { fail("cannot start writing: \(writer.error?.localizedDescription ?? "unknown")") }
writer.startSession(atSourceTime: .zero)

var buffer: CVPixelBuffer?
CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32ARGB, nil, &buffer)
guard let pixels = buffer else { fail("cannot allocate a pixel buffer") }
CVPixelBufferLockBaseAddress(pixels, [])
guard let context = CGContext(
    data: CVPixelBufferGetBaseAddress(pixels), width: width, height: height, bitsPerComponent: 8,
    bytesPerRow: CVPixelBufferGetBytesPerRow(pixels), space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)
else { fail("cannot draw into the pixel buffer") }
context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
CVPixelBufferUnlockBaseAddress(pixels, [])

while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.01) }
guard adaptor.append(pixels, withPresentationTime: .zero) else {
    fail("cannot append the frame: \(writer.error?.localizedDescription ?? "unknown")")
}
input.markAsFinished()
// One second long, so the player's clock and scrubber read as a short clip rather than nothing.
writer.endSession(atSourceTime: CMTime(value: 1, timescale: 1))

let done = DispatchSemaphore(value: 0)
writer.finishWriting { done.signal() }
done.wait()
guard writer.status == .completed else { fail("writing failed: \(writer.error?.localizedDescription ?? "unknown")") }
print(movieURL.path)
