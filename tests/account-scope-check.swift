import Foundation

@main
struct AccountScopeCheck {
    static func main() throws {
        let primary = DiscordCredentialScope(applicationID: 1572242579049808028, slot: 1)
        let secondary = DiscordCredentialScope(applicationID: 1572242579049808028, slot: 2)
        let oldClient = DiscordCredentialScope(applicationID: 1370062110272520313, slot: 1)
        let bundle = "com.amromnia.afterglow"
        precondition(primary.account != secondary.account)
        precondition(primary.storeName != secondary.storeName)
        precondition(primary.service(bundle: bundle) != oldClient.service(bundle: bundle))
        precondition(primary.storeName != oldClient.storeName)
        precondition(primary.service(bundle: bundle) != primary.service(bundle: "com.other.app"))
        var registry = AccountRegistry(legacySlots: [1, 2])
        registry.remove(1)
        var services: Set<String> = []
        for _ in 0..<1000 {
            let slot = try registry.add()
            precondition(slot > 2)
            let scope = DiscordCredentialScope(applicationID: 1572242579049808028, slot: slot)
            precondition(services.insert(scope.account).inserted)
        }
        let restored = try AccountRegistry(data: registry.data())
        precondition(restored.slots == registry.slots && restored.nextSlot == registry.nextSlot)
        do {
            _ = try AccountRegistry(data: Data(#"{"slots":[1,1],"nextSlot":2}"#.utf8))
            preconditionFailure("Corrupt registry accepted")
        } catch AccountRegistry.RegistryError.invalid { }
        var policy = AutoStartPolicy()
        precondition(!policy.claim(enabled: true, ready: true, authorized: true))
        policy.enterForeground()
        precondition(!policy.claim(enabled: true, ready: false, authorized: true))
        precondition(policy.claim(enabled: true, ready: true, authorized: true))
        precondition(!policy.claim(enabled: true, ready: true, authorized: true))
        policy.leaveForeground()
        precondition(!policy.claim(enabled: true, ready: true, authorized: true))
        policy.enterForeground()
        policy.suppress() // A manual stop must survive subsequent foreground ticks.
        policy.enterForeground()
        precondition(!policy.claim(enabled: true, ready: true, authorized: true))
        policy.rearm()
        precondition(policy.claim(enabled: true, ready: true, authorized: true))
        print("PASS: 1,000 account slots, persistence, credential isolation, corruption rejection, and auto-start policy")
    }
}
