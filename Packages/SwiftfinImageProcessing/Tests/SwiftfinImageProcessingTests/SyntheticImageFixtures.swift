//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import CoreGraphics
import Foundation

struct SyntheticImage: Codable, Sendable {
    let name: String
    let width: Int
    let height: Int
    let bytes: Data

    func image(alpha: CGImageAlphaInfo = .premultipliedLast) -> CGImage? {
        guard let provider = CGDataProvider(data: bytes as CFData) else { return nil }
        return CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: alpha.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )
    }
}

func syntheticImages() -> [SyntheticImage] {
    var cases: [SyntheticImage] = []
    func solid(_ name: String, _ width: Int, _ height: Int, _ rgba: [UInt8]) {
        cases.append(.init(
            name: name,
            width: width,
            height: height,
            bytes: Data(Array(repeating: rgba, count: width * height).flatMap(\.self))
        ))
    }
    solid("opaque red", 8, 8, [255, 0, 0, 255])
    solid("opaque black narrow portrait", 1, 64, [0, 0, 0, 255])
    solid("opaque white wide landscape", 97, 1, [255, 255, 255, 255])
    solid("single green pixel", 1, 1, [0, 255, 0, 255])
    solid("transparent blue is ignored", 16, 16, [0, 0, 0, 0])
    solid("alpha 127 is excluded", 7, 11, [64, 20, 10, 127])
    solid("alpha 128 retains premultiplied values", 11, 7, [64, 20, 10, 128])
    let colors: [[UInt8]] = [
        [12, 28, 43, 255],
        [45, 180, 230, 255],
        [96, 48, 160, 255],
        [170, 90, 35, 255],
        [235, 60, 118, 255],
        [68, 145, 80, 255],
        [200, 220, 190, 255],
        [110, 100, 98, 255]
    ]
    let widths = [1, 2, 3, 5, 8, 11, 7, 11]
    let row = zip(colors, widths).flatMap { color, width in Array(repeating: color, count: width).flatMap(\.self) }
    cases.append(.init(
        name: "weighted eight-color median cut",
        width: 48,
        height: 48,
        bytes: Data(Array(repeating: row, count: 48).flatMap(\.self))
    ))
    let portrait = (0 ..< 48).flatMap { y in Array(repeating: colors[(y / 6) % colors.count], count: 12).flatMap(\.self) }
    cases.append(.init(name: "portrait palette sampling", width: 12, height: 48, bytes: Data(portrait)))
    return cases
}
