# KidsExperience

Owns the tvOS child and parent screens, artwork presentation, remote focus, navigation and playback controls. The public entry point is `KidsRootView(model:playbackPresentation:)`. Navigation and rendering consume KidsApplication state and KidsPlaybackSession commands; screens cannot replace the verified catalog, progress store or active session.

`KidsPlaybackPresentation` is the only native rendering interface. The composition host supplies a video surface and parent track controls as main-actor SwiftUI values. Every native track mutation must call the supplied authorization closure immediately before changing a selection. Native SDK types, stream credentials, global session containers and player construction stay outside this package.

Synthetic DEBUG previews use an internal empty renderer and application fixtures. Production construction always requires a host renderer. The existing `KidsNavigationTests` and opt-in real-server tests validate the actual package views through the simulator, including remote focus, recovery, durable Retry and genuine EOF/session-cap behavior. They live in the app integration harness because they exercise the composed environment rather than an isolated view mock.

Add screens within the same child navigation policy. Add new external rendering through the presentation port; do not import the app module or a Jellyfin/native-player SDK to gain implicit access to global state.
