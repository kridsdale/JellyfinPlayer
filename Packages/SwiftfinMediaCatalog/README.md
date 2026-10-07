# SwiftfinMediaCatalog

Owns inherited media-library read queries, immutable filter/parent snapshots, request construction, endpoint pagination capabilities, consumed-row normalization, user-view exclusions, scheduled-recording eligibility and metadata-only artwork sampling. All I/O uses one injected exact transport/user pair; every request is read-only and no file/playback/credential mutators are exposed. No factories, settings, UI or progress persistence.

The app maps presentation inputs and captures settings/time before calling this owner. Paging generations and current-account validity remain owned by SwiftfinPaging and composition. This module does not bypass KidsCatalog authorization and does not grant library access.
