import Foundation

public enum FetcherError: Error, Equatable {
    case http(Int)
    case notHTTP
}

/// Minimal async byte-fetcher, injectable so the EPG/playlist loaders can be
/// tested against fixtures without the network.
public protocol Fetcher: Sendable {
    func data(from url: URL) async throws -> Data
}

public struct URLSessionFetcher: Fetcher {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func data(from url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw FetcherError.notHTTP }
        guard (200..<300).contains(http.statusCode) else { throw FetcherError.http(http.statusCode) }
        return data
    }
}
