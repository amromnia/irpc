import SwiftUI

struct AccountRow: View {
    @ObservedObject var account: DiscordAccount
    let accent: Color
    let disabled: Bool
    let musicPlaying: Bool
    let details: () -> Void
    let connect: () -> Void

    var body: some View {
        HStack(spacing: 13) {
            Button(action: details) {
                HStack(spacing: 13) {
                    AccountAvatar(account: account, accent: accent)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(account.name).font(.subheadline.weight(.semibold)).foregroundStyle(.primary).lineLimit(1)
                        HStack(spacing: 5) {
                            Circle().fill(account.ready ? Color.green : Color.secondary.opacity(0.4)).frame(width: 5, height: 5)
                            Text(deliveryStatus)
                                .font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(account.name), \(account.status), account details")

            if account.discord.isAuthorizing {
                ProgressView().controlSize(.small)
            } else if account.discord.isAuthenticated {
                Toggle("Share to \(account.name)", isOn: $account.selected).labelsHidden().tint(accent)
            } else {
                Button("Connect", action: connect)
                    .font(.caption.weight(.semibold)).buttonStyle(.bordered).buttonBorderShape(.capsule)
                    .disabled(disabled || account.storageError != nil)
            }
        }
        .padding(16)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 22))
    }
    private var deliveryStatus: String {
        guard account.discord.isRunning, account.ready else { return account.status }
        if !musicPlaying { return "Waiting for music" }
        return account.discord.lastPresenceAcknowledgedAt == nil ? "Waiting for Discord…" : "Sharing now"
    }

}

private struct AccountAvatar: View {
    @ObservedObject var account: DiscordAccount
    let accent: Color
    var body: some View {
        AsyncImage(url: account.discord.avatarURL) { phase in
            if case .success(let image) = phase {
                image.resizable().scaledToFill()
            } else {
                ZStack {
                    accent.opacity(0.1)
                    Image(systemName: account.id == 1 ? "person.fill" : "person.crop.circle.badge.plus")
                        .font(.system(size: 18, weight: .medium)).foregroundStyle(accent)
                }
            }
        }
        .frame(width: 44, height: 44).clipShape(Circle()).accessibilityHidden(true)
    }
}

struct AccountDetailsView: View {
    @ObservedObject var account: DiscordAccount
    let accent: Color
    let authorizing: Bool
    let connect: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var confirmingDisconnect = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 14) {
                        AccountAvatar(account: account, accent: accent)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(account.name).font(.headline)
                            if let username = account.discord.username {
                                Text("@\(username)").font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                    }.padding(.vertical, 6)
                    Text(account.status).font(.footnote).foregroundStyle(.secondary)
                    if account.discord.isAuthenticated { Toggle("Share music to this account", isOn: $account.selected) }
                }
                if account.discord.isAuthenticated || account.discord.isAuthorizing {
                    Section("Last update") {
                        Text(account.discord.presenceStatus).font(.footnote)
                        if let accepted = account.discord.lastPresenceAcknowledgedAt {
                            LabeledContent("Accepted", value: accepted.formatted(date: .omitted, time: .standard))
                        }
                        Text("Accepted means Discord received the update. Your profile may take a moment to refresh.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section {
                    Button(account.discord.isAuthenticated ? "Reconnect" : "Connect Discord", action: connect)
                        .disabled(authorizing || account.storageError != nil)
                    Button("Disconnect and remove saved credentials", role: .destructive) { confirmingDisconnect = true }
                } footer: {
                    Text("Adding your other account? Switch accounts in Discord first. If a browser opens, sign into the account you want there. Each account authorizes separately.")
                }
            }
            .tint(accent)
            .navigationTitle("Account \(account.id)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .confirmationDialog("Disconnect \(account.name)?", isPresented: $confirmingDisconnect, titleVisibility: .visible) {
                Button("Disconnect account", role: .destructive) { account.signOut() }
            } message: {
                Text("This clears presence and saved credentials for this account only.")
            }
        }
    }
}
