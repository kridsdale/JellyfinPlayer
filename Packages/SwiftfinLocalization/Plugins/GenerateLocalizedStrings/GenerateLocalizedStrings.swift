//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import PackagePlugin

@main
struct GenerateLocalizedStrings: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) async throws -> [Command] {
        let input = target.directoryURL.appending(path: "Resources/en.lproj/Localizable.strings")
        let output = context.pluginWorkDirectoryURL.appending(path: "Strings.swift")
        return try [.buildCommand(
            displayName: "Generate typed Swiftfin localization",
            executable: context.tool(named: "LocalizationCodegen").url,
            arguments: [input.path, output.path],
            inputFiles: [input],
            outputFiles: [output]
        )]
    }
}
