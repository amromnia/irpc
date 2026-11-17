import DiscordSocialKit
import MusicKit
import NowPlayingKit
import SwiftUI

struct ContentView: View {
    @StateObject private var store = PresenceStore()
    @ObservedObject private var background = BackgroundController.shared
    @AppStorage("presence.sessionMinutes") private var sessionMinutes = 120
    @AppStorage("appearance.accent") private var accentHex = "E44950"
    @AppStorage("appearance.mode") private var appearance = 0
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @State private var settingsOpen = false
    @State private var selectedAccount: DiscordAccount?

    private var accent: Color { Color(afterglowHex: accentHex) }
    private var surface: Color { Color(uiColor: .secondarySystemGroupedBackground) }
    private var durationLabel: String { sessionMinutes == 30 ? "30 min" : "\(sessionMinutes / 60) hours" }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 30) {
                    header
                    if !store.musicAuthorized { musicPermission }
                    artwork
                    songDetails
                    if !store.playback.id.isEmpty { timeline }
                    accountSection
                    if let error = store.error {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(accent)
                            Text(error).font(.footnote).frame(maxWidth: .infinity, alignment: .leading)
                            Button("Dismiss", systemImage: "xmark") { store.error = nil }
                                .labelStyle(.iconOnly).font(.caption)
                        }
                        .padding(18).background(surface, in: RoundedRectangle(cornerRadius: 20))
                    }
                }
                .padding(.horizontal, 24).padding(.top, 14).padding(.bottom, 26)
                .frame(maxWidth: 560)
                .frame(maxWidth: .infinity)
            }
            .background {
                ZStack(alignment: .topLeading) {
                    Color(uiColor: .systemGroupedBackground)
                    Circle().fill(accent.opacity(colorScheme == .dark ? 0.16 : 0.09))
                        .frame(width: 340, height: 340).blur(radius: 90)
                        .offset(x: -130, y: -100)
                }.ignoresSafeArea()
            }
            .safeAreaInset(edge: .bottom) { sharingDock }
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $settingsOpen) { settings }
            .sheet(item: $selectedAccount) { account in
                AccountDetailsView(account: account, accent: accent,
                                   authorizing: store.authorizing, connect: { store.connect(account) })
            }
        }
        .tint(accent)
        .preferredColorScheme(appearance == 0 ? nil : (appearance == 1 ? .light : .dark))
        .task {
            await store.start()
            while !Task.isCancelled {
                if !background.isRunning { await store.tick() }
                do { try await Task.sleep(nanoseconds: 1_000_000_000) } catch { return }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if #unavailable(iOS 26.0), phase == .background { store.stopSharing() }
            if phase == .active { Task { await store.refreshPlayback() } }
        }
    }

    private var header: some View {
        HStack {
            HStack(spacing: 11) {
                AfterglowMark(color: accent).scaleEffect(0.75).frame(width: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(AppIdentity.name).font(.system(.title2, design: .rounded, weight: .bold))
                    Text("One soundtrack. Every profile.").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button("Settings", systemImage: "slider.horizontal.3") { settingsOpen = true }
                .labelStyle(.iconOnly).font(.system(size: 17, weight: .medium))
                .frame(width: 44, height: 44)
                .background(surface.opacity(0.8), in: Circle())
        }
    }

    private var musicPermission: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("A little permission. A lot of music.", systemImage: "music.note")
                .font(.headline)
            Text("Allow Music access to share the song playing on your iPhone.")
                .font(.subheadline).foregroundStyle(.secondary)
            Button("Connect Apple Music") { Task { await store.requestMusicAccess() } }
                .buttonStyle(.borderedProminent).buttonBorderShape(.capsule)
            if let url = URL(string: UIApplication.openSettingsURLString) {
                Button("Open Settings") { openURL(url) }.font(.footnote)
            }
        }
        .padding(22).frame(maxWidth: .infinity, alignment: .leading)
        .background(surface, in: RoundedRectangle(cornerRadius: 26))
    }

    private var artwork: some View {
        ZStack(alignment: .bottomLeading) {
            AsyncImage(url: store.playback.artworkURL) { phase in
                if case .success(let image) = phase {
                    image.resizable().scaledToFill()
                } else {
                    ZStack {
                        LinearGradient(colors: [accent.opacity(0.8), accent.opacity(0.3), Color(uiColor: .systemBackground)],
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                        AfterglowMark().scaleEffect(2.7)
                    }
                }
            }
            .frame(width: 270, height: 270).clipped()
            HStack(spacing: 7) {
                Circle().fill(store.playing ? Color.green : Color.white.opacity(0.6)).frame(width: 6, height: 6)
                Text(store.playing ? "NOW PLAYING" : (store.playback.id.isEmpty ? "READY WHEN YOU ARE" : (store.recentPlayback ? "RECENTLY PLAYED" : "PAUSED")))
                    .font(.system(size: 9, weight: .bold)).tracking(1.6)
            }
            .foregroundStyle(.white).padding(.horizontal, 12).padding(.vertical, 9)
            .background(.black.opacity(0.55), in: Capsule()).padding(16)
        }
        .clipShape(RoundedRectangle(cornerRadius: 30))
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.35 : 0.13), radius: 24, y: 14)
        .padding(.top, 8)
        .accessibilityLabel(store.playing ? "Now playing artwork" : "Music artwork")
    }

    private var songDetails: some View {
        VStack(spacing: 8) {
            Text(store.playback.title).font(.system(.title2, design: .rounded, weight: .bold))
                .multilineTextAlignment(.center).lineLimit(2)
            Text(store.playback.artist.isEmpty ? "Play something you love in Apple Music." : store.playback.artist)
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            if let album = store.playback.album {
                Text(album).font(.caption).foregroundStyle(.tertiary).lineLimit(1)
            }
        }
    }

    private var timeline: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let duration = store.playback.duration.isFinite ? max(1, store.playback.duration) : 1
            let reported = store.playback.playbackTime.isFinite ? max(0, store.playback.playbackTime) : 0
            let elapsed = store.playing ? min(30, max(0, context.date.timeIntervalSince(store.observedAt))) : 0
            let position = min(duration, reported + elapsed)
            VStack(spacing: 9) {
                ProgressView(value: position, total: duration).tint(accent)
                HStack {
                    Text(time(position))
                    Spacer()
                    Button("Open Music", systemImage: "arrow.up.right") {
                        if let url = URL(string: "music://") { openURL(url) }
                    }
                    .font(.caption2).foregroundStyle(.secondary)
                    Spacer()
                    Text("−" + time(duration - position))
                }
                .font(.caption2).monospacedDigit().foregroundStyle(.secondary)
            }
            .padding(.horizontal, 16)
        }
    }

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("YOUR ACCOUNTS").font(.system(size: 10, weight: .bold)).tracking(2).foregroundStyle(.secondary)
                Spacer()
                Text("\(store.readyAccounts.count) ready").font(.caption2).foregroundStyle(.secondary)
            }
            ForEach(store.accounts) { account in
                AccountRow(account: account, accent: accent, disabled: store.authorizing, musicPlaying: store.playing,
                           details: { selectedAccount = account }, connect: { store.connect(account) })
            }
            Text("One song, both profiles. Connect each Discord account separately.")
                .font(.caption2).foregroundStyle(.secondary).padding(.horizontal, 3)
        }
    }

    private var sharingDock: some View {
        VStack(spacing: 13) {
            HStack {
                HStack(spacing: 7) {
                    Circle().fill(store.sharing ? Color.green : Color.secondary.opacity(0.5)).frame(width: 6, height: 6)
                    Text(store.sharing ? "Sharing your soundtrack" : "Your soundtrack, shared.")
                        .font(.caption).fontWeight(.medium)
                }
                Spacer(minLength: 8)
                if #available(iOS 26.0, *) {
                    Menu {
                        Picker("Session length", selection: $sessionMinutes) {
                            Text("30 minutes").tag(30)
                            Text("2 hours").tag(120)
                            Text("4 hours").tag(240)
                        }
                    } label: {
                        Label(durationLabel, systemImage: "clock").font(.caption)
                    }.disabled(store.sharing)
                }
            }
            SharingButton(sharing: store.sharing,
                          disabled: !store.sharing && (!store.musicAuthorized || store.readyAccounts.isEmpty)) {
                store.toggleSharing(minutes: sessionMinutes)
            }
            Text(sharingHint)
                .font(.system(size: 10)).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(20).modifier(AfterglowGlass())
        .padding(.horizontal, 18).padding(.top, 10).padding(.bottom, 8)
        .frame(maxWidth: 560)
    }

    private var sharingHint: String {
        if #unavailable(iOS 26.0) { return "Keep \(AppIdentity.name) open while sharing on this iOS version." }
        return store.sharing ? "iOS may end this session early." : "Choose which profiles receive your music."
    }

    private var settings: some View {
        NavigationStack {
            Form {
                Section("Make it yours") {
                    ColorPicker("Accent color", selection: Binding(get: { accent }, set: { accentHex = $0.afterglowHex }), supportsOpacity: false)
                    HStack(spacing: 18) {
                        ForEach(["E44950", "B56BDB", "468EE5", "258976"], id: \.self) { color in
                            Button { accentHex = color } label: {
                                Circle().fill(Color(afterglowHex: color)).frame(width: 28, height: 28)
                                    .overlay(Circle().strokeBorder(.primary.opacity(accentHex == color ? 0.8 : 0), lineWidth: 2))
                            }
                            .buttonStyle(.plain).accessibilityLabel("Choose accent \(color)")
                        }
                    }.padding(.vertical, 5)
                    Picker("Appearance", selection: $appearance) {
                        Text("System").tag(0); Text("Light").tag(1); Text("Dark").tag(2)
                    }
                }
                Section("Sharing session") {
                    Text(background.status).font(.footnote)
                    if #unavailable(iOS 26.0) {
                        Text("On this iOS version, keep \(AppIdentity.name) open while sharing.")
                    }
                }
                Section("About") {
                    LabeledContent("App", value: AppIdentity.name)
                    LabeledContent("Discord application", value: String(AppIdentity.applicationID))
                        .font(.caption).textSelection(.enabled)
                    Text("Built on open-source foundations. Original project and license details are in the repository README.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Your space")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { settingsOpen = false } } }
        }
    }

    private func time(_ value: TimeInterval) -> String {
        let seconds = Int(max(0, value))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
