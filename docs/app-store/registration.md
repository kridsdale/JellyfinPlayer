# KidsJellyFin App Store registration

- App Store Connect app ID: `6819134482`
- App name: `KidsJellyFin`
- Registered bundle ID: `com.kridsdale.JellyfinPlayer`
- tvOS draft version: `1.0`; project marketing version matches it
- GitHub: https://github.com/kridsdale/KidsJellyFin
- Xcode project: `KidsJellyFin.xcodeproj`
- Product/scheme: `KidsJellyFin tvOS`; validation scheme: `KidsValidation`

The stable bundle, CloudKit and Swift module identities are retained across the branding rename. The local checkout location remains unchanged so existing tooling and state references remain valid. iOS retains the upstream interface; macOS and visionOS binaries are not supplied by this project. Only the existing tvOS draft receives platform-specific metadata.

English-US listing sources live in `AppStore/en-US/metadata.json`, with description and Apple TV privacy text as separate reviewable files. Public support and privacy pages live beside this document. GitHub issues provide the maintainer contact channel. The published privacy and marketing URLs use immutable source revisions. Update them deliberately when publishing revised policy or product information.

## Repeatable metadata updates

`Scripts/AppStore/metadata.py` uses Apple's REST API and ES256 authentication. Run it with a Python environment that includes `cryptography`. Supply a `.p8` key outside the repository, its Key ID, and the Issuer ID for a team key; omit Issuer ID for an individual key. Never put the private key or a bearer JWT in command arguments or source control.

```sh
python3 Scripts/AppStore/metadata.py --key-file /private/path/AuthKey_KEYID.p8 \
  --key-id KEYID --issuer-id ISSUER_UUID --expected-sku REGISTERED_SKU
# Add --apply to save the planned fields and verify them by reading Apple's API.
```

The script checks the exact app ID, bundle ID, SKU, editable draft, tvOS platform and version before any write. It saves old field values and a proposed diff under ignored `build/validation/app-store`, journals successful updates, and requires a second plan to be empty. Repeating an already applied update performs no writes. Keys and JWTs are never printed or saved. No build upload, App Review submission, release request, pricing, age-rating questionnaire, Kids Category declaration, or privacy nutrition-label answers are performed by this metadata tool.

Before submission, complete truthful age/content and privacy questionnaires, review contact and reviewer access, and upload screenshots and a signed tested build. These need separate verification and are not established by saving the listing text. The existing Apple age rating is preserved rather than inferred from the app name.

## Final draft readback (2026-10-05)

The authenticated read-only metadata plan verified app `6819134482`, bundle `com.kridsdale.JellyfinPlayer`, SKU `com.kridsdale.jellyfinplayer` and tvOS version `1.0`. It returned **zero planned metadata operations**: the draft matches the checked-in listing fields. This verification performed no writes, upload, submission or release, and does not establish completion of Apple's privacy/content questionnaires or review requirements.
