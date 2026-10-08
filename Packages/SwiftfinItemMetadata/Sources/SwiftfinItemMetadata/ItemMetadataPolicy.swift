//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import JellyfinAPI

public enum ItemMetadataPolicy {
    /// Preserve the supported item types from the installed identification UI.
    public static func supportsIdentification(of kind: BaseItemKind) -> Bool {
        [.boxSet, .movie, .person, .series].contains(kind)
    }

    private static func apply<Value>(_ change: MetadataComponentChange<Value>, to values: [Value]?) -> [Value]? {
        switch change { case let .append(new): (values ?? []) + new
        case let .remove(old): values?.filter { !old.contains($0) }
        case let .replace(new): new }
    }

    public static func genres(_ change: MetadataComponentChange<String>, in item: BaseItemDto) -> BaseItemDto {
        var item = item
        item.genres = apply(change, to: item.genres)
        return item
    }

    public static func tags(_ change: MetadataComponentChange<String>, in item: BaseItemDto) -> BaseItemDto {
        var item = item
        item.tags = apply(change, to: item.tags)
        return item
    }

    public static func studios(_ change: MetadataComponentChange<NameIDPair>, in item: BaseItemDto) -> BaseItemDto {
        var item = item
        item.studios = apply(change, to: item.studios)
        return item
    }

    public static func people(_ change: MetadataComponentChange<BaseItemPerson>, in item: BaseItemDto) -> BaseItemDto {
        var item = item
        item.people = apply(change, to: item.people)
        return item
    }

    public static func person(id: String?, name: String, kind: PersonKind, role: String) -> BaseItemPerson {
        BaseItemPerson(id: id, name: name, role: role.isEmpty ? (kind == .unknown ? nil : kind.rawValue) : role, type: kind)
    }

    public static func nameMatches(
        _ name: String,
        names: [String]
    ) -> Bool {
        names.contains { $0.caseInsensitiveCompare(name) == .orderedSame }
    }

    public static func updatePayload(_ item: BaseItemDto) -> BaseItemDto {
        var item = item
        item.trickplay = nil
        return item
    }

    public static func subtitles(_ item: BaseItemDto) -> MetadataSubtitleGroups {
        let streams = (item.mediaSources ?? []).flatMap { ($0.mediaStreams ?? []).filter { $0.type == .subtitle } }
        return .init(internalStreams: streams.filter { $0.isExternal == false }, externalStreams: streams.filter { $0.isExternal == true })
    }
}
