# SwiftfinUserAdministration

Swift 6 actor-owned administration API. Composition injects one authenticated request executor; the owner never resolves a global account, stores credentials or imports UI. Existing administrative actions are invoked only by their explicit UI actions. All tests use synthetic request senders; no server maintenance or media operation runs during validation.

Dependencies: SwiftfinNetworking, SwiftfinCollections, exact Jellyfin SDK 3.2.0/Get 2.2.1. User administration and server operations are separate peers with no edge between them.

AutoPlayConfigurationUpdates is created for the client's captured authenticated user. A fresh submitted configuration is copied and only the next-episode flag changes; an injected caller checkpoint surrounds admission and request/receipt publication. Accepted requests drain serially and pending replacements coalesce. Cancellation keeps the predecessor handle, including through transport replacement. Current failures may reach a UI callback; retired/cancelled work stays quiet. Optimistic presentation and accepted remote changes are not rolled back.

Application UserSession retains/reuses the writer per exact transport and cancels it on stop. A transient menu owns presentation rather than command lifetime. This ordering applies to this writer family; independent administrative configuration operations remain a separate integration/audit requirement.
