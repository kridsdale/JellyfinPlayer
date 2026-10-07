# SwiftfinPlaybackPreviews

Owns chapter and sprite-sheet timelines, a bounded actor-owned image LRU/single-flight loader, and UIKit preview decoding/cropping. Foundation core; UIKit/Combine adapter. No Jellyfin SDK, settings, accounts, global factories, network sessions, native video or persistence imports. Only injected image loads run; no video prefetch occurs.

Composition captures an exact authenticated transport and supplies an identity-validity predicate and chapter/sheet data loaders. Invalidation clears images and cancels flights. Loads from invalidated identity, canceled/evicted tasks and stale generations cannot publish. Failed loads are not cached permanently. Default capacity is 16 images with four tracked flights; required requests can displace obsolete work and bounded adjacent image warmup cannot displace required work.

Chapter selection includes the final chapter. Invalid/zero/overflowing dimensions and intervals fail construction. Sprite addresses use half-open intervals, clamp to the final valid frame and bound adjacent sheets to the runtime. Cropping validates indexes and uses pixel dimensions with retained image scale/orientation. Tests separate Foundation timeline/cache contracts from UIKit image contracts; neither implies real decoder performance.

`PreviewImageSelection` owns scrub request cancellation and latest-request publication. Returning to an already displayed tile cancels a pending different tile. Stopping clears publication, and pending work does not retain the selection owner. The app view only renders the published image and forwards scrub/disappear events. Adjacent UIKit contracts run in the real tvOS validation host; pure timeline/cache contracts also run through SwiftPM on macOS.
