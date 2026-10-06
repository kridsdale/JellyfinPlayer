# SwiftfinAudioSession

Owns serialized process audio-session leases and the Apple audio activation/deactivation adapter. All owner and operation state belongs to the main actor. The public API is acquire, release with an awaited native drain, and interruption notification. The platform singleton keeps existing call sites and process-wide ownership.

Activation/deactivation closures are Sendable asynchronous operations. Tests inject controlled operations and gates without changing the Mac's real audio session. Six native contracts cover concurrent owners, duplicate release, delayed old-player drain with a replacement, cancellation before activation, activation failure, undrained output and interruption/reactivation. Real platform setup remains validated through iOS/tvOS builds and simulator playback.

A release cannot deactivate while a newer lease exists. Failed native drain/deactivation retains the known active state. Apple category setup and the legacy synchronous activation fallback run away from the UI actor; the modern SDK asynchronous entry point is used when available. Only fixed numeric opt-in performance events are recorded. There is no server, credential, catalog or media-file responsibility here.
