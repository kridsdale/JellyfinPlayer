# SwiftfinItemMetadata

Owns item metadata editing, remote identity/image/subtitle lookup, metadata reference pickers, component mutation policies and account-bound tag search. The app retains UI/file-picker inputs, localized errors, notifications and presentation state. A captured authenticated executor owns all requests; no factories, defaults, SwiftUI or credentials store are imported.

Existing write-capable endpoints are preserved for their explicit administrative UI actions. All package tests use synthetic senders; tests must never run media edits, subtitle operations, refresh or deletion against the server or RAID.

Dependencies: SwiftfinNetworking, exact Jellyfin SDK 3.2.0/Get 2.2.1. No database or CloudKit schema changes.
