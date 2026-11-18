import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

@main
struct PublicArtworkCheck {
    static func main() async throws {
        let data = try Data(contentsOf: URL(fileURLWithPath: "tests/fixtures/public-artwork-persona.json"))
        let response = try JSONDecoder().decode(PublicArtworkLookup.Response.self, from: data)
        let title = "It's Going Down Now"
        let artist = "Azumi Takahashi / Lotus Juice / ATLUS Sound Team / ATLUS GAME MUSIC"
        let album = "Persona 3 Reload (Original Soundtrack)"
        let track = PublicArtworkLookup.Track(title: title, artist: artist, album: album, duration: 186.093, storeID: nil)
        let selected = PublicArtworkLookup.match(track, in: response.results)
        precondition(selected?.trackId == 1733408557)
        precondition(PublicArtworkLookup.match(track, in: Array(response.results.dropFirst())) == nil,
                     "Do not select the live rendition or a cover")
        let wrongAlbum = PublicArtworkLookup.Track(title: title, artist: artist, album: "Different album", duration: 186.093, storeID: nil)
        precondition(PublicArtworkLookup.match(wrongAlbum, in: response.results) == nil)
        let wrongDuration = PublicArtworkLookup.Track(title: title, artist: artist, album: album, duration: 240, storeID: nil)
        precondition(PublicArtworkLookup.match(wrongDuration, in: response.results) == nil)
        let punctuation = PublicArtworkLookup.Track(title: "It’s Going Down Now", artist: artist, album: "Persona 3 Reload Original Soundtrack", duration: 186, storeID: nil)
        precondition(PublicArtworkLookup.match(punctuation, in: response.results)?.trackId == 1733408557)
        let alternative = PublicArtworkLookup.Item(kind: "song", trackId: 1, trackName: title, artistName: artist,
            collectionName: album, trackTimeMillis: 186093, artworkUrl100: URL(string: "https://example.com/different-cover.jpg"))
        precondition(PublicArtworkLookup.match(track, in: [selected!, alternative]) == nil,
                     "Ambiguous covers must not be guessed")
        print("PASS: reported soundtrack metadata, punctuation, cover/live rejection, album/duration checks, and ambiguity")

        if CommandLine.arguments.contains("--live") {
            let lookup = PublicArtworkLookup()
            let byID = try await lookup.resolve(.init(title: title, artist: artist, album: album, duration: 186.093, storeID: "1733408557"))
            precondition(byID.url != nil && byID.status.contains("exact store ID"))
            let search = try await lookup.resolve(track)
            precondition(search.url == byID.url && search.status.contains("verified metadata"))
            let (image, response) = try await URLSession.shared.data(from: search.url!)
            precondition((response as? HTTPURLResponse)?.statusCode == 200)
            precondition(response.mimeType?.hasPrefix("image/") == true && image.count > 100)
            print("PASS: live Apple lookup and verified search without MusicKit tokens; artwork image HTTP 200")
        }
    }
}
