//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import Get
import JellyfinAPI
import SwiftfinMediaTracks
import SwiftfinNetworking

@MainActor
public protocol PlaybackURLResolving {
    var serverURL: URL { get }
    func streamURL(path: String) -> URL?
    func streamURL(for request: Request<Data>) -> URL?
}

extension JellyfinTransport: PlaybackURLResolving {
    public var serverURL: URL {
        configuration.url
    }

    public func streamURL(path: String) -> URL? {
        url(path: path)
    }

    public func streamURL(for request: Request<Data>) -> URL? {
        url(with: request)
    }
}

/// Composition binds values, URL construction and HTTP metrics to one immutable
/// user/transport. Playback-info is requested only for an actual Play action.
@MainActor
public final class PlaybackPreparationClient {
    private let executor: AuthenticatedRequestExecutor
    private let urls: any PlaybackURLResolving
    private let userID: String
    public init(executor: AuthenticatedRequestExecutor, urls: any PlaybackURLResolving, userID: String) {
        self.executor = executor
        self.urls = urls
        self.userID = userID
    }

    public func checkBinding() throws {
        try executor.checkBinding()
    }

    public func item(id: String, delegate: (any URLSessionDataDelegate)? = nil) async throws -> BaseItemDto {
        let item = try await executor.value(for: Paths.getItem(itemID: id, userID: userID), delegate: delegate)
        guard item.id == id else { throw PlaybackPreparationError.itemIdentityChanged }
        return item
    }

    public func prepare(
        item: BaseItemDto,
        initial: MediaSourceInfo,
        profile: DeviceProfile,
        maxBitrate: Int,
        audio: Int?,
        subtitle: Int?,
        delegate: (any URLSessionDataDelegate)? = nil
    ) async throws -> PreparedPlayback {
        try checkBinding()
        guard let itemID = item.id else { throw PlaybackPreparationError.missingItemID }
        let body = PlaybackPreparationPolicy.info(
            item: item,
            initial: initial,
            userID: userID,
            profile: profile,
            maxBitrate: maxBitrate,
            audio: audio,
            subtitle: subtitle
        )
        let response = try await executor.value(for: Paths.getPostedPlaybackInfo(itemID: itemID, body), delegate: delegate)
        let source = try PlaybackPreparationPolicy.resolveSource(in: response.mediaSources, initial: initial)
        guard let sessionID = response.playSessionID else { throw PlaybackPreparationError.missingPlaySession }
        var updated = item
        updated.runTimeTicks = source.runTimeTicks ?? item.runTimeTicks
        let url = try streamURL(item: updated, source: source, sessionID: sessionID)
        try checkBinding()
        return .init(item: updated, source: source, playSessionID: sessionID, url: url)
    }

    /// Resolves approved text sidecars without loading them. The URL port belongs
    /// to the same immutable account/connection used for this item's preparation.
    public func sidecarSubtitles(from streams: [MediaStream]) throws -> [PreparedSidecarSubtitle] {
        try checkBinding()
        let serverURL = urls.serverURL
        var result: [PreparedSidecarSubtitle] = []
        for stream in streams.sidecarSubtitles {
            try checkBinding()
            guard var path = stream.deliveryURL, !path.isEmpty else { continue }
            // Preserve base-path joining, without chopping relative paths or
            // attempting removeFirst on an empty server-provided string.
            if serverURL.absoluteString.hasSuffix("/"), path.hasPrefix("/") {
                path.removeFirst()
            }
            let url = urls.streamURL(path: path)
            try checkBinding()
            if let url {
                result.append(.init(jellyfinIndex: stream.index, url: url))
            }
        }
        try checkBinding()
        return result
    }

    public func bitrateBytes(size: Int, delegate: (any URLSessionDataDelegate)? = nil) async throws -> Data {
        try await executor.value(for: Paths.getBitrateTestBytes(size: size), delegate: delegate)
    }

    public func image(url: URL) async throws -> Data {
        try await executor.value(for: Request<Data>(url: url))
    }

    public func trickplayImage(itemID: String, width: Int, index: Int, sourceID: String) async throws -> Data {
        try await executor.value(for: Paths.getTrickplayTileImage(itemID: itemID, width: width, index: index, mediaSourceID: sourceID))
    }

    public func streamURL(item: BaseItemDto, source: MediaSourceInfo, sessionID: String) throws -> URL {
        try checkBinding()
        guard let id = item.id else { throw PlaybackPreparationError.missingItemID }
        if let path = source.transcodingURL {
            guard let url = urls.streamURL(path: path) else { throw PlaybackPreparationError.invalidURL }
            return url
        }
        if item.mediaType == .video {
            let parameters = Paths.GetVideoStreamParameters(
                isStatic: true,
                tag: source.eTag ?? item.etag,
                playSessionID: sessionID,
                mediaSourceID: source.id ?? id,
                liveStreamID: source.liveStreamID
            )
            guard let url = urls.streamURL(for: Paths.getVideoStream(itemID: id, parameters: parameters))
            else { throw PlaybackPreparationError.invalidURL }
            return url
        }
        guard let path = source.path, let url = URL(string: path) else { throw PlaybackPreparationError.invalidURL }
        return url
    }
}
