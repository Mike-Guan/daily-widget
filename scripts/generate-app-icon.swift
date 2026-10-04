import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

guard CommandLine.arguments.count == 3 else {
    fputs("Usage: swift generate-app-icon.swift <source.png> <destination.png>\n", stderr)
    exit(2)
}

let sourceURL = URL(fileURLWithPath: CommandLine.arguments[1])
let destinationURL = URL(fileURLWithPath: CommandLine.arguments[2])
guard
    let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
    let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
else {
    fputs("Unable to read source icon.\n", stderr)
    exit(3)
}

let width = image.width
let height = image.height
let bytesPerRow = width * 4
let colorSpace = CGColorSpaceCreateDeviceRGB()
let sourceBitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
var sourcePixels = [UInt8](repeating: 0, count: height * bytesPerRow)

guard let sourceContext = CGContext(
    data: &sourcePixels,
    width: width,
    height: height,
    bitsPerComponent: 8,
    bytesPerRow: bytesPerRow,
    space: colorSpace,
    bitmapInfo: sourceBitmapInfo
) else {
    fputs("Unable to create source bitmap.\n", stderr)
    exit(4)
}
sourceContext.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

var output = [UInt8](repeating: 255, count: height * bytesPerRow)
let centerX = Double(width) / 2
let centerY = Double(height) / 2
let radius = Double(min(width, height)) * 0.362
let rimWidth = Double(min(width, height)) * 0.010
let fill = (r: 220.0, g: 227.0, b: 255.0)
let rim = (r: 200.0, g: 211.0, b: 255.0)

func mix(_ from: Double, _ to: Double, _ amount: Double) -> UInt8 {
    UInt8(max(0, min(255, (from + (to - from) * amount).rounded())))
}

for y in 0..<height {
    for x in 0..<width {
        let offset = y * bytesPerRow + x * 4
        let distance = hypot(Double(x) + 0.5 - centerX, Double(y) + 0.5 - centerY)
        let outerCoverage = max(0, min(1, radius + 0.5 - distance))
        let innerCoverage = max(0, min(1, radius - rimWidth + 0.5 - distance))

        var red = mix(255, rim.r, outerCoverage)
        var green = mix(255, rim.g, outerCoverage)
        var blue = mix(255, rim.b, outerCoverage)
        red = mix(Double(red), fill.r, innerCoverage)
        green = mix(Double(green), fill.g, innerCoverage)
        blue = mix(Double(blue), fill.b, innerCoverage)

        let originalRed = sourcePixels[offset]
        let originalGreen = sourcePixels[offset + 1]
        let originalBlue = sourcePixels[offset + 2]
        let insideCheckRegion = x >= width * 23 / 100 && x <= width * 78 / 100
            && y >= height * 28 / 100 && y <= height * 72 / 100
        let belongsToCheck = insideCheckRegion
            && originalBlue > 225
            && Int(originalBlue) - Int(originalRed) > 25
            && Int(originalBlue) - Int(originalGreen) > 15
            && originalRed < 225

        if belongsToCheck {
            output[offset] = originalRed
            output[offset + 1] = originalGreen
            output[offset + 2] = originalBlue
            output[offset + 3] = sourcePixels[offset + 3]
        } else {
            output[offset] = red
            output[offset + 1] = green
            output[offset + 2] = blue
            output[offset + 3] = 255
        }
    }
}

guard let outputContext = CGContext(
    data: &output,
    width: width,
    height: height,
    bitsPerComponent: 8,
    bytesPerRow: bytesPerRow,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
), let outputImage = outputContext.makeImage() else {
    fputs("Unable to create output bitmap.\n", stderr)
    exit(5)
}

guard let destination = CGImageDestinationCreateWithURL(
    destinationURL as CFURL,
    UTType.png.identifier as CFString,
    1,
    nil
) else {
    fputs("Unable to create PNG destination.\n", stderr)
    exit(6)
}

CGImageDestinationAddImage(destination, outputImage, nil)
guard CGImageDestinationFinalize(destination) else {
    fputs("Unable to write PNG.\n", stderr)
    exit(7)
}
