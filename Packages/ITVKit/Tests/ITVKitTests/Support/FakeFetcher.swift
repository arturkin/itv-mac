import Foundation
@testable import ITVKit

/// Test double for `Fetcher`: returns canned responses per URL and counts calls.
final class FakeFetcher: Fetcher, @unchecked Sendable {
    private let lock = NSLock()
    private var responses: [URL: Result<Data, Error>] = [:]
    private(set) var callCount = 0

    func stub(_ url: URL, data: Data) { lock.withLock { responses[url] = .success(data) } }
    func stub(_ url: URL, error: Error) { lock.withLock { responses[url] = .failure(error) } }

    func data(from url: URL) async throws -> Data {
        let response: Result<Data, Error> = lock.withLock {
            callCount += 1
            return responses[url] ?? .failure(FetcherError.http(404))
        }
        return try response.get()
    }
}
