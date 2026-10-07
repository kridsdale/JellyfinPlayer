//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import JellyfinAPI
import SwiftfinFormatting
import SwiftfinLocalization
import SwiftfinMediaTracks

extension BaseItemDto {

    func posterSubtitle(using field: PosterSubtitleField) -> String? {
        let value: String? = if let extraType {
            extraType.displayTitle
        } else if type == .person {
            subtitle
        } else {
            posterSubtitleValue(for: field)
        }
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        return value
    }

    private func posterSubtitleValue(for field: PosterSubtitleField) -> String? {
        switch field {
        case .none:
            return nil
        case .year:
            if let year = productionYear, year > 0 {
                return year.description
            }
            return premiereDate?.formatted(.dateTime.year())
        case .runtime:
            return runtime?.formatted(.hourMinuteAbbreviated)
        case .officialRating:
            return officialRating
        case .communityRating:
            guard let rating = communityRating, rating.isFinite, (0 ... 10).contains(rating) else { return nil }
            return "★ \(rating.formatted(.number.precision(.fractionLength(0 ... 1))))"
        case .criticRating:
            guard let rating = criticRating, rating.isFinite, (0 ... 100).contains(rating) else { return nil }
            return L10n.posterCriticScore(rating.formatted(.number.precision(.fractionLength(0))))
        case .quality:
            return posterQualityLabel
        case .genre:
            return genres?.first
        case .studio:
            return studios?.first?.name
        }
    }

    private var posterQualityLabel: String? {
        let quality = MediaVideoQuality(self)
        var labels = quality.resolution.map { [$0.rawValue] } ?? []
        switch quality.range {
        case .dolbyVision: labels.append(L10n.dolbyVision)
        case .hdr: labels.append(L10n.hdr)
        case nil: break
        }
        return labels.isEmpty ? nil : labels.joined(separator: " ")
    }
}
