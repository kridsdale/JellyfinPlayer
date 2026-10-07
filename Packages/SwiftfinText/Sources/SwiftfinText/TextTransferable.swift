//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import CoreTransferable
import Foundation
import UniformTypeIdentifiers

public protocol TextTransferable: Transferable {

    var transferTitle: String { get }
    var transferBody: String { get }
}

public extension TextTransferable {
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .plainText) { (item: Self) in
            let url = try TextExportFile.write(title: item.transferTitle, body: item.transferBody)

            return SentTransferredFile(url)
        }
    }
}

enum TextExportFile {
    static func write(title: String, body: String, directory: URL = .temporaryDirectory) throws -> URL {
        let url = directory.appending(path: title.appending(".txt"))
        try body.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
