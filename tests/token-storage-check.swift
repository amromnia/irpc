import Foundation

@main
struct TokenStorageCheck {
    static func main() throws {
        let token = DiscordToken(accessToken: "test-access", refreshToken: "test-refresh", expiresIn: 3600)
        let restored = try JSONDecoder().decode(DiscordToken.self, from: JSONEncoder().encode(token))
        precondition(restored.tokenId == token.tokenId)
        precondition(restored.accessToken == token.accessToken && restored.refreshToken == token.refreshToken)
        precondition(restored.initialExpiresIn == token.initialExpiresIn)
        precondition(restored.expiresAt == token.expiresAt)
        precondition(restored.isValid && !restored.needsRefresh)
        restored.expiresAt = Date().addingTimeInterval(1700)
        precondition(restored.isValid && restored.needsRefresh)
        restored.expiresAt = Date().addingTimeInterval(-1)
        precondition(!restored.isValid && restored.needsRefresh)
        restored.refreshToken = nil
        precondition(restored.needsRefresh)
        restored.expiresAt = nil
        precondition(!restored.isValid)
        do {
            _ = try JSONDecoder().decode(DiscordToken.self, from: Data("corrupt".utf8))
            fatalError("Corrupt credentials must fail decoding")
        } catch is DecodingError {}
        print("PASS: portable credentials round-trip, expiry/refresh policy, and corrupt-data rejection")
    }
}
