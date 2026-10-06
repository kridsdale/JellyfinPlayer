//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
@testable import SwiftfinLocalization
import Testing

@Test
func `owns all existing language resources`() {
    let languages = Set(LocalizationResources.bundle.localizations)
    #expect(languages.count == 54)
    #expect(languages.isSuperset(of: ["en", "fr", "ja", "zh-Hans", "pt-BR"]))
}

@Test
func `foreign translations resolve inside the package`() throws {
    let directory = try #require(LocalizationResources.bundle.url(forResource: "fr", withExtension: "lproj"))
    let french = try #require(Bundle(url: directory))
    let value = french.localizedString(forKey: "next", value: "MISSING", table: "Localizable")
    #expect(value != "MISSING")
    #expect(value != "Next")
}

@Test
func `typed format API keeps repeated positional arguments`() {
    #expect(L10n.seasonAndEpisode("2", "7") == "S2:E7")
    #expect(L10n.episodeNumber("7").contains("7"))
}

@Test
func `proper nouns remain locale independent`() {
    #expect(L10n.h264 == "H.264")
    #expect(L10n.dolbyVision == "Dolby Vision")
    #expect(L10n.hdr10Plus == "HDR10+")
}
