#!/bin/sh
# Independent library contracts, then development-only composition checks.
set -eu
REPO_ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
for KIDS_PACKAGE in SwiftfinValues SwiftfinTime SwiftfinFormatting SwiftfinAccountAccess SwiftfinUserMediaState SwiftfinPlaybackReporting SwiftfinPlaybackPreparation SwiftfinRecordingTimers SwiftfinFilters SwiftfinItemMetadata SwiftfinServerOperations SwiftfinUserAdministration SwiftfinMediaCatalog SwiftfinPaging SwiftfinScrolling SwiftfinMediaTracks SwiftfinPlaybackPreviews SwiftfinNativePlayback SwiftfinCollections SwiftfinPlaybackProfiles SwiftfinImages SwiftfinSessions SwiftfinNetworking SwiftfinAsyncStreams SwiftfinConnections SwiftfinAccountStore SwiftfinCredentials SwiftfinConnectivity SwiftfinAccountModels SwiftfinStorage SwiftfinStoredValues SwiftfinStoredValuesUI SwiftfinLocalization SwiftfinUIState SwiftfinAudioSession SwiftfinNowPlaying SwiftfinVLC KidsDomain KidsAccounts KidsDiagnostics KidsCatalog KidsArtwork KidsPlayback KidsPlaybackSession KidsPersistence; do
    swift test --package-path "$REPO_ROOT/Packages/$KIDS_PACKAGE"
done
python3 "$REPO_ROOT/Scripts/Translations/test_codegen.py"
swift test --package-path "$REPO_ROOT/KidsCore"
sh "$REPO_ROOT/Scripts/Kids/test_runtime.sh"
