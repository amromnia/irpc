import Foundation

/// Only remotely fetchable URLs can be used as Discord image assets.
enum PublicArtworkPolicy {
    static func url(_ candidate: URL?) -> URL? {
        guard let candidate, candidate.scheme?.lowercased() == "https",
              let host = candidate.host, !host.isEmpty,
              candidate.user == nil, candidate.password == nil else { return nil }
        return candidate
    }
}
