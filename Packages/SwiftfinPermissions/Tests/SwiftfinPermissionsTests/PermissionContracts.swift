//
// Swiftfin is subject to the terms of the Mozilla Public
// License, v2.0. If a copy of the MPL was not distributed with this
// file, you can obtain one at https://mozilla.org/MPL/2.0/.
//
// Copyright (c) 2026 Jellyfin & Jellyfin Contributors
//

import Foundation
@testable import SwiftfinPermissions
import Testing

private enum SyntheticFailure: Error, Sendable, Equatable { case unavailable, denied }

@MainActor
private final class AuthenticationDriver: AuthenticationPermissionDriver {
    var availability = AuthenticationAvailability(available: true, error: nil)
    var reasons: [String] = []
    var callbacks: [@Sendable (Result<Void, any Error>) -> Void] = []
    var retireCount = 0
    func begin(reason: String, completion: @escaping @Sendable (Result<Void, any Error>) -> Void) {
        reasons.append(reason)
        callbacks.append(completion)
    }

    func retire() {
        retireCount += 1
    }
}

@MainActor
private final class LocationDriver: LocationPermissionDriver {
    var servicesEnabled = true
    var authorization = LocationAuthorization.notDetermined
    var callbacks: [@Sendable (PermissionStatus?) -> Void] = []
    var retireCount = 0
    func begin(completion: @escaping @Sendable (PermissionStatus?) -> Void) {
        callbacks.append(completion)
    }

    func retire() {
        retireCount += 1
    }
}

@MainActor
struct PermissionContracts {
    private func started(_ condition: () -> Bool) async {
        for _ in 0 ..< 1000 {
            if condition() {
                return
            }
            await Task.yield()
        }
        #expect(condition())
    }

    @Test
    func `authorization projection retains all legacy statuses`() {
        for (input, expected) in [
            (LocationAuthorization.always, PermissionStatus.authorized),
            (.whenInUse, .authorized),
            (.denied, .denied),
            (.restricted, .denied),
            (.notDetermined, .unknown),
            (.unknown, .unknown)
        ] {
            #expect(input.status == expected)
        }
    }

    @Test
    func `disabled services return denied without prompt`() async throws {
        let driver = LocationDriver()
        driver.servicesEnabled = false
        driver.authorization = .always
        #expect(try await PermissionRequests.location(driver) == .denied)
        #expect(driver.callbacks.isEmpty && driver.retireCount == 0)
    }

    @Test
    func `decided authorization returns current status without prompt`() async throws {
        for authorization in [LocationAuthorization.always, .whenInUse, .denied, .restricted, .unknown] {
            let driver = LocationDriver()
            driver.authorization = authorization
            #expect(try await PermissionRequests.location(driver) == authorization.status)
            #expect(driver.callbacks.isEmpty && driver.retireCount == 0)
        }
    }

    @Test
    func `pending location updates do not resolve until A real decision`() async throws {
        let driver = LocationDriver()
        let task = Task { try await PermissionRequests.location(driver) }
        await started { !driver.callbacks.isEmpty }
        driver.callbacks[0](nil)
        #expect(driver.retireCount == 0)
        driver.callbacks[0](.authorized)
        #expect(try await task.value == .authorized && driver.retireCount == 1)
    }

    @Test
    func `quiet location cancellation returns without any native callback`() async {
        let driver = LocationDriver()
        let task = Task { try await PermissionRequests.location(driver) }
        await started { !driver.callbacks.isEmpty }
        task.cancel()
        do { _ = try await task.value
            Issue.record("Cancellation returned a status")
        } catch { #expect(error is CancellationError) }
        #expect(driver.retireCount == 1)
        driver.callbacks[0](.authorized)
        driver.callbacks[0](.denied)
        #expect(driver.retireCount == 1)
    }

    @Test
    func `already cancelled task does not begin location or authentication`() async {
        let location = LocationDriver()
        let authentication = AuthenticationDriver()
        let first = Task { try await PermissionRequests.location(location) }
        first.cancel()
        let second = Task { try await PermissionRequests.authenticate(authentication, reason: "synthetic") }
        second.cancel()
        for task in [first, second] {
            do { _ = try await task.value
                Issue.record("Precancelled request succeeded")
            } catch { #expect(error is CancellationError) }
        }
        #expect(location.callbacks.isEmpty && authentication.callbacks.isEmpty)
    }

    @Test
    func `retired callbacks cannot resolve A replacement request`() async throws {
        let driver = LocationDriver()
        let old = Task { try await PermissionRequests.location(driver) }
        await started { driver.callbacks.count == 1 }
        old.cancel()
        do { _ = try await old.value
            Issue.record("Old request succeeded")
        } catch { #expect(error is CancellationError) }
        let current = Task { try await PermissionRequests.location(driver) }
        await started { driver.callbacks.count == 2 }
        driver.callbacks[0](.denied)
        #expect(driver.retireCount == 1)
        driver.callbacks[1](.authorized)
        #expect(try await current.value == .authorized && driver.retireCount == 2)
    }

    @Test
    func `callbacks may arrive from an independent executor`() async throws {
        let driver = LocationDriver()
        let task = Task { try await PermissionRequests.location(driver) }
        await started { !driver.callbacks.isEmpty }
        let callback = driver.callbacks[0]
        await Task.detached { callback(.denied) }.value
        #expect(try await task.value == .denied && driver.retireCount == 1)
    }

    @Test
    func `authentication preserves reason and nonthrowing success`() async throws {
        let driver = AuthenticationDriver()
        let task = Task { try await PermissionRequests.authenticate(driver, reason: "synthetic reason") }
        await started { !driver.callbacks.isEmpty }
        #expect(driver.reasons == ["synthetic reason"])
        driver.callbacks[0](.success(()))
        #expect(try await task.value == .authorized && driver.retireCount == 1)
    }

    @Test
    func `unavailable authentication preserves SDK error and nil fallback`() async {
        for error in [SyntheticFailure?.some(.unavailable), nil] {
            let driver = AuthenticationDriver()
            driver.availability = .init(available: false, error: error)
            do { _ = try await PermissionRequests.authenticate(driver, reason: "")
                Issue.record("Unavailable authentication succeeded")
            } catch let actual as SyntheticFailure { #expect(actual == error) }
            catch let actual as PermissionRequestError { #expect(error == nil && actual == .deviceAuthenticationUnavailable) }
            catch { Issue.record("Wrong failure kind") }
            #expect(driver.callbacks.isEmpty && driver.retireCount == 0)
        }
    }

    @Test
    func `authentication failure propagates without changing its payload`() async {
        let driver = AuthenticationDriver()
        let task = Task { try await PermissionRequests.authenticate(driver, reason: "") }
        await started { !driver.callbacks.isEmpty }
        driver.callbacks[0](.failure(SyntheticFailure.denied))
        do { _ = try await task.value
            Issue.record("Denied authentication succeeded")
        } catch { #expect(error as? SyntheticFailure == .denied) }
        #expect(driver.retireCount == 1)
    }

    @Test
    func `quiet authentication cancellation retires before late SDK reply`() async {
        let driver = AuthenticationDriver()
        let task = Task { try await PermissionRequests.authenticate(driver, reason: "") }
        await started { !driver.callbacks.isEmpty }
        task.cancel()
        do { _ = try await task.value
            Issue.record("Cancelled authentication succeeded")
        } catch { #expect(error is CancellationError) }
        #expect(driver.retireCount == 1)
        driver.callbacks[0](.success(()))
        driver.callbacks[0](.failure(SyntheticFailure.denied))
        #expect(driver.retireCount == 1)
    }

    @Test
    func `receipt cancels before installation and rejects duplicate completion`() async throws {
        let cancelled = PermissionReply()
        cancelled.cancel()
        do {
            _ = try await withCheckedThrowingContinuation { continuation in #expect(!cancelled.install(continuation)) }
            Issue.record("Precancelled receipt returned")
        } catch { #expect(error is CancellationError) }
        let completed = PermissionReply()
        let value = try await withCheckedThrowingContinuation { continuation in
            #expect(completed.install(continuation))
            completed.finish(.success(.authorized))
            completed.finish(.success(.denied))
            completed.cancel()
        }
        #expect(value == .authorized)
    }

    @Test
    func `cancellation and completion races have one terminal result`() async {
        for _ in 0 ..< 64 {
            let receipt = PermissionReply()
            let result = Task {
                try await withCheckedThrowingContinuation { continuation in
                    #expect(receipt.install(continuation))
                    Task.detached { receipt.cancel() }
                    Task.detached { receipt.finish(.success(.authorized)) }
                }
            }
            do { #expect(try await result.value == .authorized) }
            catch { #expect(error is CancellationError) }
        }
    }
}
