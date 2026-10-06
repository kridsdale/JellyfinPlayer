//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

// SPDX-License-Identifier: MPL-2.0
import Foundation
import OSLog

/// Explicit opt-in diagnostics. The event schema accepts only fixed enums and numeric
/// measurements: no URL, header, token, item title, file path or response payload.
public enum KidsPerformanceOperation: String, Codable, Sendable {
    case launch
    case catalog
    case policy
    case episodes
    case authorize
    case ancestry
    case http
    case decode
    case artwork
    case title
    case playback
    case metadata
    case bitrate
    case playbackInfo
    case playbackReport
    case audioActivation
    case audioDeactivation
    case playerDrain
    case provider
    case storeOpen
    case storeLoad
    case storeSave
    case episodeCache
    case artworkCache
    case prefetch
}

public enum KidsPerformanceVariant: String, Codable, Sendable {
    case shows
    case movies
    case grid
    case title
    case countdown
    case ordered
    case shuffle
    case movie
    case once
    case unknown
}

public enum KidsPerformanceEndpoint: String, Codable, Sendable {
    case serverInfo
    case userPolicy
    case libraries
    case items
    case ancestors
    case artwork
    case itemDetails
    case episodeList
    case playbackInfo
    case bitrate
    case playbackStart
    case playbackProgress
    case playbackStop
    case other
}

public enum KidsPerformancePhase: String, Codable, Sendable {
    case begin
    case end
    case network
    case response
    case catalogReady
    case firstShowsReady
    case firstMoviesReady
    case showsReady
    case moviesReady
    case browsePresented
    case titleSelected
    case actionsReady
    case imageConstructed
    case imagePublished
    case artworkPresented
    case itemSelected
    case authorized
    case controllerReady
    case managerStart
    case providerReady
    case vlcOpen
    case vlcOpenReturned
    case vlcOpening
    case vlcBuffering
    case vlcPlaying
    case resumeSeek
    case firstInput
    case firstDecode
    case firstVideoOutput
    case firstClock
    case playbackBegan
    case playerSurfacePresented
    case playerError
    case observationTimeout
}

public enum KidsPerformanceOutcome: String, Codable, Sendable {
    case success
    case failure
    case cancelled
}

public struct KidsPerformanceEvent: Codable, Sendable {
    public let runID: String
    public let traceID: String
    public let parentID: String?
    public let operation: KidsPerformanceOperation
    public let variant: KidsPerformanceVariant
    public let endpoint: KidsPerformanceEndpoint?
    public let phase: KidsPerformancePhase
    public let elapsedMS: Double
    public let uptimeMS: Double
    public let unixMS: Double
    public let outcome: KidsPerformanceOutcome?
    public let values: [String: Double]
}

/// Writes off the main actor. The finite file cap prevents an accidentally prolonged
/// profiling launch consuming unbounded storage. Files are retained for review, never uploaded.
public final class KidsPerformanceRecorder: @unchecked Sendable {
    public let runID = UUID().uuidString
    public let enabled: Bool
    public let fileURL: URL?
    private let queue = DispatchQueue(label: "com.kridsdale.JellyfinPlayer.performance", qos: .utility)
    private let logger = Logger(subsystem: "com.kridsdale.JellyfinPlayer", category: "Performance")
    private let sink: (@Sendable (KidsPerformanceEvent) -> Void)?
    private let maxBytes: Int
    private var written = 0
    private var handle: FileHandle?

    public init(
        enabled: Bool,
        directory: URL? = nil,
        maxBytes: Int = 8 * 1024 * 1024,
        sink: (@Sendable (KidsPerformanceEvent) -> Void)? = nil
    ) {
        self.enabled = enabled
        self.maxBytes = max(0, maxBytes)
        self.sink = sink
        if enabled, let directory {
            fileURL = directory.appendingPathComponent(runID + ".jsonl")
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if let fileURL, FileManager.default.createFile(atPath: fileURL.path, contents: nil) {
                handle = try? FileHandle(forWritingTo: fileURL)
            }
        } else {
            fileURL = nil
        }
    }

    public func begin(
        _ operation: KidsPerformanceOperation,
        variant: KidsPerformanceVariant = .unknown,
        endpoint: KidsPerformanceEndpoint? = nil,
        parent: KidsPerformanceSpan? = nil,
        values: [String: Double] = [:]
    ) -> KidsPerformanceSpan? {
        guard enabled else { return nil }
        let span = KidsPerformanceSpan(recorder: self, operation: operation, variant: variant, endpoint: endpoint, parentID: parent?.id)
        span.mark(.begin, values: values)
        return span
    }

    fileprivate func record(_ event: KidsPerformanceEvent) {
        guard enabled else { return }
        queue.async { [self] in
            guard let data = try? JSONEncoder().encode(event), written + data.count + 1 <= maxBytes else { return }
            written += data.count + 1
            sink?(event)
            if let handle {
                try? handle.write(contentsOf: data + Data([10]))
            }
            // Unified log is searchable from simctl/xctrace without a vendor agent.
            if sink == nil, let line = String(data: data, encoding: .utf8) {
                logger.info("\(line, privacy: .public)")
            }
        }
    }

    /// For tests/export boundaries only; never blocks a playback/image hot path.
    public func flush() {
        queue.sync {}
    }
}

public final class KidsPerformanceSpan: @unchecked Sendable {
    public let id = UUID().uuidString
    private let recorder: KidsPerformanceRecorder
    private let operation: KidsPerformanceOperation
    private let variant: KidsPerformanceVariant
    private let endpoint: KidsPerformanceEndpoint?
    private let parentID: String?
    private static let metrics: Set<String> = [
        "task_ms",
        "reused",
        "fetch_type",
        "received_bytes",
        "redirects",
        "dns_ms",
        "connect_ms",
        "tls_ms",
        "request_ms",
        "ttfb_ms",
        "transfer_ms",
        "fetch_ms",
        "pre_request_ms",
        "status",
        "bytes",
        "shows",
        "movies",
        "width",
        "height",
        "retry",
        "resume_seconds",
        "episodes",
        "transcoding",
        "automatic",
        "bits_per_second",
        "read_bytes",
        "decoded_video",
        "displayed_pictures",
        "lost_pictures",
        "resume_pending",
        "seconds",
        "failure_code",
        "video_codec",
        "bit_depth",
        "video_fps",
        "video_bitrate",
        "probe_revision",
        "cache_hit",
        "shared_wait",
        "prefetch_count",
        "prefetch_failures",
        "cache_bytes",
        "placeholder"
    ]
    private let start = DispatchTime.now().uptimeNanoseconds
    private let lock = NSLock()
    private var finished = false
    private var seen = Set<KidsPerformancePhase>()

    fileprivate init(
        recorder: KidsPerformanceRecorder,
        operation: KidsPerformanceOperation,
        variant: KidsPerformanceVariant,
        endpoint: KidsPerformanceEndpoint?,
        parentID: String?
    ) {
        self.recorder = recorder
        self.operation = operation
        self.variant = variant
        self.endpoint = endpoint
        self.parentID = parentID
    }

    public func mark(_ phase: KidsPerformancePhase, outcome: KidsPerformanceOutcome? = nil, values: [String: Double] = [:]) {
        let now = DispatchTime.now().uptimeNanoseconds
        recorder.record(KidsPerformanceEvent(
            runID: recorder.runID,
            traceID: id,
            parentID: parentID,
            operation: operation,
            variant: variant,
            endpoint: endpoint,
            phase: phase,
            elapsedMS: Double(now >= start ? now - start : 0) / 1_000_000,
            uptimeMS: Double(now) / 1_000_000,
            unixMS: Date().timeIntervalSince1970 * 1000,
            outcome: outcome,
            values: values.filter { Self.metrics.contains($0.key) && $0.value.isFinite }
        ))
    }

    public func once(_ phase: KidsPerformancePhase, values: [String: Double] = [:]) {
        lock.lock()
        let inserted = seen.insert(phase).inserted
        lock.unlock()
        if inserted {
            mark(phase, values: values)
        }
    }

    /// Fixed numeric failure codes preserve useful diagnostics without serializing an
    /// arbitrary error description, which could contain a request URL or credential.
    public func finish(error: Error) {
        let code: Double = switch error {
        case KidsAPIError.authentication: 1
        case KidsAPIError.policy: 2
        case KidsAPIError.libraryChanged: 3
        case KidsAPIError.invalidResponse: 4
        case KidsAPIError.connection: 5
        case KidsAPIError.unavailable: 6
        case KidsContractError.denied: 7
        case KidsContractError.unavailable: 8
        case KidsContractError.ambiguousEpisodes: 9
        case KidsContractError.missingCursor: 10
        case KidsContractError.invalidStateVersion: 11
        case is CancellationError: 12
        default: 0
        }
        finish(error is CancellationError ? .cancelled : .failure, values: ["failure_code": code])
    }

    public func finish(_ outcome: KidsPerformanceOutcome = .success, values: [String: Double] = [:]) {
        lock.lock()
        let shouldFinish = !finished
        finished = true
        lock.unlock()
        if shouldFinish {
            mark(.end, outcome: outcome, values: values)
        }
    }
}

public enum KidsPerformanceCodec: Int, Sendable {
    case unknown = 0
    case h264
    case hevc
    case mpeg4
    case mpeg2
    case vp9
    case av1
    case vp8
    case vc1
    case other
    public init(_ name: String?) {
        switch name?.lowercased() {
        case nil: self = .unknown
        case "h264", "avc": self = .h264
        case "hevc", "h265": self = .hevc
        case "mpeg4", "msmpeg4v3": self = .mpeg4
        case "mpeg2video": self = .mpeg2
        case "vp9": self = .vp9
        case "av1": self = .av1
        case "vp8": self = .vp8
        case "vc1": self = .vc1
        default: self = .other
        }
    }
}

public enum KidsPerformance {
    @TaskLocal
    public static var current: KidsPerformanceSpan?
    public static let recorder: KidsPerformanceRecorder = {
        let enabled = ProcessInfo.processInfo.arguments.contains("--kids-profile") || ProcessInfo.processInfo
            .environment["KIDS_PROFILE"] == "1"
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("KidsPlayer/Performance", isDirectory: true)
        return KidsPerformanceRecorder(enabled: enabled, directory: directory)
    }()

    public static let launch = recorder.begin(.launch, values: ["probe_revision": 12])
    public static func begin(
        _ operation: KidsPerformanceOperation,
        variant: KidsPerformanceVariant = .unknown,
        endpoint: KidsPerformanceEndpoint? = nil,
        values: [String: Double] = [:]
    ) -> KidsPerformanceSpan? {
        recorder.begin(operation, variant: variant, endpoint: endpoint, parent: current, values: values)
    }
}

/// A per-task delegate observes the existing request/session; it does not add requests,
/// caches, prefetching, retries, logging of request data or a new connection pool.
public final class KidsPerformanceTaskDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let span: KidsPerformanceSpan
    public init(span: KidsPerformanceSpan) {
        self.span = span
    }

    public func urlSession(_ session: URLSession, task: URLSessionTask, didFinishCollecting metrics: URLSessionTaskMetrics) {
        for transaction in metrics.transactionMetrics {
            var values: [String: Double] = [
                "task_ms": metrics.taskInterval.duration * 1000,
                "reused": transaction.isReusedConnection ? 1 : 0,
                "fetch_type": Double(transaction.resourceFetchType.rawValue),
                "received_bytes": Double(transaction.countOfResponseBodyBytesReceived),
                "redirects": Double(metrics.redirectCount)
            ]
            func interval(_ name: String, _ from: Date?, _ to: Date?) {
                if let from, let to {
                    values[name] = max(0, to.timeIntervalSince(from) * 1000)
                }
            }
            interval("dns_ms", transaction.domainLookupStartDate, transaction.domainLookupEndDate)
            interval("connect_ms", transaction.connectStartDate, transaction.connectEndDate)
            interval("tls_ms", transaction.secureConnectionStartDate, transaction.secureConnectionEndDate)
            interval("request_ms", transaction.requestStartDate, transaction.requestEndDate)
            interval("ttfb_ms", transaction.requestEndDate ?? transaction.requestStartDate, transaction.responseStartDate)
            interval("transfer_ms", transaction.responseStartDate, transaction.responseEndDate)
            interval("fetch_ms", transaction.fetchStartDate, transaction.responseEndDate)
            interval("pre_request_ms", transaction.fetchStartDate, transaction.requestStartDate)
            span.mark(.network, values: values)
        }
    }
}
