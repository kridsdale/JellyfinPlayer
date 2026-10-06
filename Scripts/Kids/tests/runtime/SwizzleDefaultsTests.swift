//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation

enum RuntimeTestFailure: Error {
    case expectation(String)
}

@main
struct SwizzleDefaultsTests {
    static func expect(_ condition: Bool, _ message: String) throws {
        guard condition else { throw RuntimeTestFailure.expectation(message) }
    }

    static func main() async throws {
        let suiteName = "KidsJellyFin.RuntimeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let keys = ["bool", "string", "integer", "double"].map { "\(suiteName).\($0)" }
        defaults.set(false, forKey: keys[0])
        defaults.set("original", forKey: keys[1])
        defaults.set(7, forKey: keys[2])
        defaults.set(1.25, forKey: keys[3])
        defer { keys.forEach(SwizzleDefaults.remove) }

        SwizzleDefaults.set(true, for: keys[0])
        SwizzleDefaults.set("override", for: keys[1])
        SwizzleDefaults.set(42, for: keys[2])
        SwizzleDefaults.set(3.5, for: keys[3])
        try expect(defaults.bool(forKey: keys[0]), "Boolean override")
        try expect(defaults.string(forKey: keys[1]) == "override", "String override")
        try expect(defaults.integer(forKey: keys[2]) == 42, "Integer override")
        try expect(defaults.double(forKey: keys[3]) == 3.5, "Double override")
        try expect((defaults.object(forKey: keys[2]) as? NSNumber)?.intValue == 42, "Object getter must agree")
        try expect(defaults.string(forKey: keys[2]) == "42", "Numeric string coercion")
        SwizzleDefaults.set("19", for: keys[1])
        try expect(defaults.integer(forKey: keys[1]) == 19, "String integer coercion")
        keys.forEach(SwizzleDefaults.remove)
        try expect(!defaults.bool(forKey: keys[0]), "Remove must restore stored Boolean")
        try expect(defaults.string(forKey: keys[1]) == "original", "Remove must preserve stored string")
        try expect(defaults.integer(forKey: keys[2]) == 7, "Remove must preserve stored integer")
        try expect(defaults.double(forKey: keys[3]) == 1.25, "Remove must preserve stored double")

        let failures = await withTaskGroup(of: Bool.self, returning: Int.self) { group in
            for worker in 0 ..< 64 {
                group.addTask {
                    let key = "\(suiteName).worker.\(worker)"
                    let reader = UserDefaults(suiteName: suiteName)!
                    defer { SwizzleDefaults.remove(key) }
                    for value in 0 ..< 100 {
                        SwizzleDefaults.set(value, for: key)
                        guard reader.integer(forKey: key) == value,
                              (reader.object(forKey: key) as? NSNumber)?.intValue == value else { return false }
                    }
                    SwizzleDefaults.remove(key)
                    return reader.object(forKey: key) == nil
                }
            }
            var failures = 0
            for await succeeded in group {
                if !succeeded {
                    failures += 1
                }
            }
            return failures
        }
        try expect(failures == 0, "Concurrent independent overrides must not lose or cross values")
        print("PASS: overrides, conversions, removal, stored-value preservation, 64 concurrent writers (6,400 updates)")
    }
}
