//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
guard CommandLine.arguments.count == 3 else {
    print("Generation is owned by the SwiftfinLocalization build-tool plugin.")
    print("For an explicit fixture: swift Scripts/Translations/GenerateStrings.swift input.strings output.swift")
    exit(1)
}

process.arguments = [
    "swift",
    "run",
    "--package-path",
    root.appending(path: "Packages/SwiftfinLocalization").path,
    "LocalizationCodegen"
] + Array(CommandLine.arguments.dropFirst())
try process.run()
process.waitUntilExit()
exit(process.terminationStatus)
