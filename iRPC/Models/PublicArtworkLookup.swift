import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Apple's public store metadata needs neither a MusicKit developer token nor
/// account credentials. Library/store IDs are intentionally kept separate.
actor PublicArtworkLookup {
    struct Track: Sendable {
        let title: String
        let artist: String
        let album: String?
        let duration: TimeInterval
        let storeID: String?
    }
    struct Result: Sendable {
        let url: URL?
        let status: String
    }
    struct Response: Decodable { let results: [Item] }
    struct Item: Decodable {
        let kind: String?
        let trackId: UInt64?
        let trackName: String?
        let artistName: String?
        let collectionName: String?
        let trackTimeMillis: Double?
        let artworkUrl100: URL?
    }

    private let session: URLSession
    private var nextRequest = Date.distantPast

    init(session: URLSession? = nil) {
        if let session { self.session = session }
        else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.httpShouldSetCookies = false
            configuration.httpCookieStorage = nil
            configuration.urlCredentialStorage = nil
            configuration.timeoutIntervalForRequest = 8
            configuration.timeoutIntervalForResource = 10
            self.session = URLSession(configuration: configuration)
        }
    }

    func resolve(_ track: Track) async throws -> Result {
        if let id = track.storeID, let numeric = UInt64(id), numeric > 0 {
            let response = try await fetch(path: "lookup", query: [URLQueryItem(name: "id", value: id)])
            if let item = response.results.first(where: { $0.kind == "song" && $0.trackId == numeric }),
               let url = PublicArtworkPolicy.url(item.artworkUrl100) {
                return Result(url: url, status: "Public Apple artwork: exact store ID \(id)")
            }
        }
        guard !track.title.isEmpty, !track.artist.isEmpty else {
            return Result(url: nil, status: "Public lookup needs track and artist metadata")
        }
        let artist = track.artist.components(separatedBy: " / ").first ?? track.artist
        let response = try await fetch(path: "search", query: [
            URLQueryItem(name: "term", value: track.title + " " + artist),
            URLQueryItem(name: "limit", value: "25")
        ])
        guard let item = Self.match(track, in: response.results),
              let url = PublicArtworkPolicy.url(item.artworkUrl100) else {
            return Result(url: nil, status: "Public lookup: no unambiguous metadata match")
        }
        return Result(url: url, status: "Public Apple artwork: verified metadata match (\(item.trackId ?? 0))")
    }

    static func normalized(_ value: String) -> String {
        let folded = value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        return folded.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) }.map(String.init).joined()
    }

    static func match(_ track: Track, in items: [Item]) -> Item? {
        let artist = normalized(track.artist)
        let album = track.album.map(normalized)
        let matches = items.filter { item in
            guard item.kind == "song", normalized(item.trackName ?? "") == normalized(track.title),
                  normalized(item.artistName ?? "") == artist,
                  PublicArtworkPolicy.url(item.artworkUrl100) != nil else { return false }
            if let album, !album.isEmpty, normalized(item.collectionName ?? "") != album { return false }
            if track.duration.isFinite && track.duration > 0 {
                guard let milliseconds = item.trackTimeMillis,
                      abs(milliseconds / 1000 - track.duration) <= 2 else { return false }
            }
            return true
        }
        // Multiple editions with different covers cannot be disambiguated safely.
        guard let first = matches.first,
              Set(matches.compactMap(\.artworkUrl100)).count == 1 else { return nil }
        return first
    }

    private func fetch(path: String, query: [URLQueryItem]) async throws -> Response {
        // The public service is rate limited. Space requests across all accounts
        // and diagnostics, not once per Discord client.
        let now = Date()
        let scheduled = max(now, nextRequest)
        nextRequest = scheduled.addingTimeInterval(3.1)
        let delay = scheduled.timeIntervalSince(now)
        if delay > 0 { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
        try Task.checkCancellation()
        var url = URLComponents(string: "https://itunes.apple.com/" + path)!
        url.queryItems = query + [URLQueryItem(name: "entity", value: "song"), URLQueryItem(name: "country", value: "us")]
        let (data, response) = try await session.data(from: url.url!)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            if code == 429 { nextRequest = max(nextRequest, Date().addingTimeInterval(60)) }
            throw NSError(domain: "ApplePublicArtworkHTTP", code: code)
        }
        guard data.count <= 2_000_000 else { throw URLError(.dataLengthExceedsMaximum) }
        return try JSONDecoder().decode(Response.self, from: data)
    }
}
