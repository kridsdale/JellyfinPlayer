# SwiftfinFilters

Owns saved filter value/schema identity, selection/reset/precedence semantics,
catalog query snapshots, and account-bound modern/legacy filter discovery.
SwiftfinNetworking and SwiftfinMediaCatalog are its one-way local dependencies.
No app factories, defaults, localization or UI framework is imported.

The app retains Displayable/ItemFilter/Storable conformances, localized labels,
UIKit letter collation and filter selector bindings. The saved Codable keys,
language displayTitle/value pairs, category raw values and full letter arrays
remain unchanged. Catalog requests still consume the first letter only.
Discovery stages share a single authenticated executor and immutable user ID;
stale success, stale errors and canceled operations cannot reach the UI adapter.
