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
import SwiftfinMediaCatalog
import SwiftfinTime

extension BaseItemDto {

    func posterAccessibility(configuration: PosterConfiguration) -> PosterAccessibility {
        let playbackItem = currentProgram ?? self
        var details = [posterAccessibilitySubtitle(using: configuration.subtitleField)]

        if let runtime = playbackItem.runtime {
            details.append(L10n.posterAccessibilityRuntime(PosterAccessibility.duration(runtime)))
        }

        details.append(contentsOf: playbackItem.posterAccessibilityPlaybackState)

        if isRecording {
            details.append(L10n.recording)
        }

        if userData?.isFavorite == true {
            details.append(L10n.favorited)
        }

        return PosterAccessibility(
            label: PosterAccessibility
                .joined(posterAccessibilityTitleComponents + (currentProgram?.posterAccessibilityTitleComponents ?? [])),
            value: PosterAccessibility.joined(details)
        )
    }

    private var posterAccessibilityTitleComponents: [String?] {
        var components: [String?] = []

        if type == .episode || type == .season {
            components.append(seriesName)

            let seasonNumber = type == .season ? indexNumber : parentIndexNumber
            if let seasonNumber {
                components.append(L10n.posterAccessibilitySeason(seasonNumber.formatted()))
            }

            if type == .episode, let indexNumber {
                let number = if let indexNumberEnd, indexNumberEnd > indexNumber {
                    L10n.posterAccessibilityEpisodeRange(indexNumber.formatted(), indexNumberEnd.formatted())
                } else {
                    L10n.episodeNumber(indexNumber.formatted())
                }
                components.append(number)
            }
        }

        components.append(displayTitle)

        if type == .person {
            components.append(subtitle)
        }

        if isPosterAccessibilityProgram {
            components.append(channelName)
            if let startDate {
                components.append(L10n.posterAccessibilityStartTime(startDate.formatted(date: .abbreviated, time: .shortened)))
            }
            if let endDate {
                components.append(L10n.posterAccessibilityEndTime(endDate.formatted(date: .abbreviated, time: .shortened)))
            }
        }

        return components
    }

    private func posterAccessibilitySubtitle(using field: PosterSubtitleField) -> String? {
        guard type != .person, let subtitle = posterSubtitle(using: field) else { return nil }

        if extraType != nil {
            return subtitle
        }

        switch field {
        case .none, .runtime:
            // Runtime is always spoken, even with visual labels hidden.
            return nil
        case .communityRating:
            guard let communityRating else { return nil }
            return L10n.posterAccessibilityCommunityRating(communityRating.formatted(.number.precision(.fractionLength(0 ... 1))))
        case .criticRating:
            guard let criticRating else { return nil }
            let rating = (criticRating / 100).formatted(.percent.precision(.fractionLength(0)))
            return L10n.posterAccessibilityDetail(field.displayTitle, rating)
        default:
            return L10n.posterAccessibilityDetail(field.displayTitle, subtitle)
        }
    }

    private var isPosterAccessibilityProgram: Bool {
        type == .program || type == .liveTvProgram || type == .tvProgram
    }

    private var posterAccessibilityPlaybackState: [String?] {
        let facts = CatalogItemState(self, at: .now).playbackState(canBePlayed: canBePlayed)
        var labels: [String?] = []
        switch facts.phase {
        case .live: labels.append(L10n.live)
        case .unaired: labels.append(L10n.unaired)
        case .ended: labels.append(L10n.ended)
        case .missing: labels.append(L10n.missing)
        case .rewatching: labels.append(L10n.rewatching)
        case .inProgress: labels.append(L10n.inProgress)
        case .played: labels.append(L10n.played)
        case .unplayed: labels.append(L10n.unplayed)
        case nil: break
        }
        if let remaining = facts.remainingDuration {
            labels.append(L10n.posterAccessibilityRemaining(PosterAccessibility.duration(remaining)))
        }
        if let count = facts.unplayedCount {
            labels.append(L10n.posterAccessibilityUnplayedCount(count.formatted()))
        }
        return labels
    }
}
