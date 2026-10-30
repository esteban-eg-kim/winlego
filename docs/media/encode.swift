// Turns numbered PNG frames into an H.264 MP4 and an animated GIF, using only
// AVFoundation and ImageIO (no ffmpeg needed).
//   swift docs/media/encode.swift <framesDir> <fps> <out.mp4> <out.gif> [gifWidth] [gifFps]
import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
guard args.count >= 5 else {
    FileHandle.standardError.write("usage: encode.swift <framesDir> <fps> <out.mp4> <out.gif> [gifWidth] [gifFps]\n".data(using: .utf8)!)
    exit(1)
}
let framesDir = URL(fileURLWithPath: args[1])
let fps = Int32(args[2])!
let mp4URL = URL(fileURLWithPath: args[3])
let gifURL = URL(fileURLWithPath: args[4])
let gifWidth = args.count > 5 ? Int(args[5])! : 800
let gifFps = args.count > 6 ? Int(args[6])! : 12

let files = try FileManager.default.contentsOfDirectory(at: framesDir, includingPropertiesForKeys: nil)
    .filter { $0.pathExtension == "png" }
    .sorted { $0.lastPathComponent < $1.lastPathComponent }
guard !files.isEmpty else { fatalError("no frames in \(framesDir.path)") }

func load(_ url: URL) -> CGImage {
    let src = CGImageSourceCreateWithURL(url as CFURL, nil)!
    return CGImageSourceCreateImageAtIndex(src, 0, nil)!
}

// MARK: MP4

let first = load(files[0])
let width = first.width, height = first.height
try? FileManager.default.removeItem(at: mp4URL)
let writer = try AVAssetWriter(outputURL: mp4URL, fileType: .mp4)
let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
    AVVideoCodecKey: AVVideoCodecType.h264,
    AVVideoWidthKey: width,
    AVVideoHeightKey: height,
    AVVideoCompressionPropertiesKey: [
        AVVideoAverageBitRateKey: 3_500_000,
        AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
    ],
])
input.expectsMediaDataInRealTime = false
let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
    kCVPixelBufferWidthKey as String: width,
    kCVPixelBufferHeightKey as String: height,
])
writer.add(input)
writer.startWriting()
writer.startSession(atSourceTime: .zero)

for (i, url) in files.enumerated() {
    while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.005) }
    var buffer: CVPixelBuffer?
    CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &buffer)
    let pb = buffer!
    CVPixelBufferLockBaseAddress(pb, [])
    let ctx = CGContext(data: CVPixelBufferGetBaseAddress(pb), width: width, height: height, bitsPerComponent: 8,
                        bytesPerRow: CVPixelBufferGetBytesPerRow(pb), space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)!
    ctx.draw(load(url), in: CGRect(x: 0, y: 0, width: width, height: height))
    CVPixelBufferUnlockBaseAddress(pb, [])
    adaptor.append(pb, withPresentationTime: CMTime(value: CMTimeValue(i), timescale: fps))
}
input.markAsFinished()
let done = DispatchSemaphore(value: 0)
writer.finishWriting { done.signal() }
done.wait()
guard writer.status == .completed else { fatalError("mp4: \(String(describing: writer.error))") }
print("wrote \(mp4URL.path)")

// MARK: GIF

let step = max(1, Int(fps) / gifFps)
let gifFrames = stride(from: 0, to: files.count, by: step).map { files[$0] }
let gifHeight = gifWidth * height / width
try? FileManager.default.removeItem(at: gifURL)
let dest = CGImageDestinationCreateWithURL(gifURL as CFURL, UTType.gif.identifier as CFString, gifFrames.count, nil)!
CGImageDestinationSetProperties(dest, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
let frameProps = [kCGImagePropertyGIFDictionary: [
    kCGImagePropertyGIFDelayTime: Double(step) / Double(fps),
    kCGImagePropertyGIFUnclampedDelayTime: Double(step) / Double(fps),
]] as CFDictionary
for url in gifFrames {
    let ctx = CGContext(data: nil, width: gifWidth, height: gifHeight, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.draw(load(url), in: CGRect(x: 0, y: 0, width: gifWidth, height: gifHeight))
    CGImageDestinationAddImage(dest, ctx.makeImage()!, frameProps)
}
guard CGImageDestinationFinalize(dest) else { fatalError("gif failed") }
print("wrote \(gifURL.path) (\(gifFrames.count) frames, \(gifWidth)×\(gifHeight))")
