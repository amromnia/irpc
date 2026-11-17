import Foundation

@main
struct AccountScopeCheck {
    static func main() {
        let primary = DiscordCredentialScope(applicationID: 1572242579049808028, slot: 1)
        let secondary = DiscordCredentialScope(applicationID: 1572242579049808028, slot: 2)
        let oldClient = DiscordCredentialScope(applicationID: 1370062110272520313, slot: 1)
        let bundle = "com.amromnia.afterglow"
        precondition(primary.account != secondary.account)
        precondition(primary.storeName != secondary.storeName)
        precondition(primary.service(bundle: bundle) != oldClient.service(bundle: bundle))
        precondition(primary.storeName != oldClient.storeName)
        precondition(primary.service(bundle: bundle) != primary.service(bundle: "com.other.app"))
        print("PASS: account slots, application IDs, and bundle IDs isolate credentials")
    }
}
