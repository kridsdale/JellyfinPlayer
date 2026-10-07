# SwiftfinMediaCatalog

Owns inherited media-library read queries, immutable filter/parent snapshots, request construction, endpoint pagination capabilities, consumed-row normalization, user-view exclusions, scheduled-recording eligibility and metadata-only artwork sampling. All I/O uses one injected exact transport/user pair; every request is read-only and no file/playback/credential mutators are exposed. No factories, settings, UI or progress persistence.

The app maps presentation inputs and captures settings/time before calling this owner. Paging generations and current-account validity remain owned by SwiftfinPaging and composition. This module does not bypass KidsCatalog authorization and does not grant library access.

CatalogItemState captures one explicit clock for availability and progress facts. Its visual progress-label interval retains whole-second resume ticks and elapsed-airing fallback; CatalogPlaybackState exposes separate raw phase, spoken remaining duration and count values. Localized labels and rendering remain in app adapters. Opposite-sign tick subtraction overflow yields an absent visual label. These pure projections do not read or mutate accounts or server state.
