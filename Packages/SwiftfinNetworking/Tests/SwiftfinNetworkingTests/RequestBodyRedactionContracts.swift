//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
import JellyfinAPI
import SwiftfinNetworking
import Testing

struct RequestBodyRedactionContracts {
    private func redact(_ endpoint: String, _ body: String) throws -> Data {
        try #require(JellyfinRequestBodyRedactor.body(
            at: URL(string: "https://unit.example.test/base/" + endpoint)!,
            body: Data(body.utf8),
            replacement: "synthetic-redaction"
        ))
    }

    private func object(_ data: Data) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    @Test
    func `authentication redacts the same SDK password field and retains user name`() throws {
        let data = try redact("Users/AuthenticateByName", #"{"Username":"synthetic-name","Pw":"synthetic-password"}"#)
        let result = try JSONDecoder().decode(AuthenticateUserByName.self, from: data)
        #expect(result.username == "synthetic-name" && result.pw == "synthetic-redaction")
        #expect(!String(decoding: data, as: UTF8.self).contains("synthetic-password"))
    }

    @Test
    func `password update redacts all three fields and clears reset flag`() throws {
        let data = try redact("Users/u/Password", #"{"CurrentPassword":"one","CurrentPw":"two","NewPw":"three","IsResetPassword":true}"#)
        let result = try JSONDecoder().decode(UpdateUserPassword.self, from: data)
        #expect(result.currentPassword == "synthetic-redaction" && result.currentPw == "synthetic-redaction" && result
            .newPw == "synthetic-redaction")
        #expect(result.isResetPassword == nil)
        #expect(try !object(data).keys.contains("IsResetPassword"))
    }

    @Test
    func `missing password fields are added by the same typed SDK encoding`() throws {
        let auth = try JSONDecoder().decode(AuthenticateUserByName.self, from: redact("AuthenticateByName", "{}"))
        #expect(auth.pw == "synthetic-redaction")
        let password = try JSONDecoder().decode(UpdateUserPassword.self, from: redact("Password", "{}"))
        #expect(password.currentPassword == "synthetic-redaction" && password.currentPw == "synthetic-redaction" && password
            .newPw == "synthetic-redaction")
    }

    @Test
    func `unknown paths and malformed typed bodies retain exact original bytes`() {
        for (path, text) in [
            ("Password", "bad json"),
            ("AuthenticateByName", "[]"),
            ("Items/PasswordBackup", "{ \"Pw\": \"synthetic\" }"),
            ("password", "{ \"Pw\": \"synthetic\" }")
        ] {
            let data = Data(text.utf8)
            #expect(JellyfinRequestBodyRedactor.body(
                at: URL(string: "https://unit.example.test/" + path)!,
                body: data,
                replacement: "redacted"
            ) == data)
        }
    }

    @Test
    func `path matching is based on final component and ignores queries`() throws {
        let data = Data(#"{"Pw":"synthetic"}"#.utf8)
        let authURL = try #require(URL(string: "https://unit.example.test/base/AuthenticateByName?x=Password"))
        let itemURL = try #require(URL(string: "https://unit.example.test/base/Items?x=AuthenticateByName"))
        let result = try #require(JellyfinRequestBodyRedactor.body(at: authURL, body: data, replacement: "redacted"))
        #expect(try object(result)["Pw"] as? String == "redacted")
        #expect(JellyfinRequestBodyRedactor.body(at: itemURL, body: data, replacement: "redacted") == data)
    }

    @Test
    func `SDK recoding retains its original omission of unknown fields`() throws {
        let result = try object(redact("AuthenticateByName", #"{"Username":"name","Pw":"value","Extra":"unknown"}"#))
        #expect(result["Username"] as? String == "name" && result["Pw"] as? String == "synthetic-redaction")
        #expect(result["Extra"] == nil)
    }
}
