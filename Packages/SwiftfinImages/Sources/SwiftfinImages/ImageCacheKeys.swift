//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import CryptoKit
import Foundation

public enum ImageCacheKeys {
    public static func poster(for url: URL) -> String? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        var maxWidthValue: String?
        if let maxWidth = components.queryItems?.first(where: { $0.name == "maxWidth" }) {
            maxWidthValue = maxWidth.value
            components.queryItems = components.queryItems?.filter { $0.name != "maxWidth" }
        }
        guard let newURL = components.url else { return nil }
        let key = sha1(newURL.path + (newURL.query ?? ""))
        return maxWidthValue.map { key + "-" + $0 } ?? key
    }

    public static func local(for url: URL, identities: ServerImageCacheIdentityIndex) -> String? {
        guard url.path.contains("Splashscreen") else { return poster(for: url) }
        guard let prefixURL = URL(string: trimmingLegacySuffix(url.absoluteString, "/Branding/Splashscreen?")),
              let serverID = identities.serverID(for: prefixURL) else { return nil }
        return sha1(serverID + "-splashscreen")
    }

    private static func sha1(_ value: String) -> String {
        Insecure.SHA1.hash(data: Data(value.utf8)).reduce(into: "") { $0 += String(format: "%02x", $1) }
    }

    // Preserve the installed filename generator's trailing-character behavior.
    private static func trimmingLegacySuffix(_ value: String, _ suffix: String) -> String {
        guard suffix.count <= value.count else { return value }
        var value = value
        var suffix = suffix
        while value.last == suffix.last {
            guard !value.isEmpty else { break }
            value.removeLast()
            suffix.removeLast()
        }
        return value
    }
}
