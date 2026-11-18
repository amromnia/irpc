import MusicKit
import SwiftUI

struct ContentView: View {
    @ObservedObject var store: PresenceStore
    @ObservedObject private var background = BackgroundController.shared
    @ObservedObject private var liveActivity = SharingActivityController.shared
    @ObservedObject private var refresh = BackgroundRefreshController.shared
    @AppStorage("presence.sessionMinutes") private var sessionMinutes = 120
    @AppStorage("sharing.pollSeconds") private var pollSeconds = 15
    @AppStorage("appearance.accent") private var accentHex = "E44950"
    @AppStorage("appearance.mode") private var appearance = 0
    @AppStorage("appearance.vaporStyle") private var vaporStyle = "wisps"
    @AppStorage("appearance.vaporColorSource") private var vaporColorSource = "custom"
    @AppStorage("appearance.vaporColor") private var vaporHex = "971B2B"
    @AppStorage("appearance.vaporOpacity") private var vaporOpacity = 0.4
    @AppStorage("appearance.vaporFrameRate") private var vaporFrameRate = 60
    @AppStorage("appearance.vaporSpeed") private var vaporSpeed = 1.0 / 1.3
    @AppStorage("appearance.followPlayback") private var followPlayback = true
    @AppStorage("appearance.buttonAnimations") private var buttonAnimations = true
    @AppStorage("appearance.haptics") private var haptics = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @State private var tab = 0
    @State private var selectedAccount: DiscordAccount?

    private var accent: Color { Color(afterglowHex: accentHex) }
    private var animateButtons: Bool { buttonAnimations && !reduceMotion }
    private var vaporColor: Color {
        switch vaporColorSource {
        case "artwork":
            if let color = store.artworkTint { return Color(uiColor: color).darkVaporTint }
            return Color(afterglowHex: vaporHex)
        case "accent": return accent.darkVaporTint
        default: return Color(afterglowHex: vaporHex)
        }
    }
    private func feedback() {
        if haptics { UIImpactFeedbackGenerator(style: .soft).impactOccurred() }
    }

    var body: some View {
        TabView(selection: $tab) {
            musicPage.tabItem { Label("Music", systemImage: "music.note") }.tag(0)
            accountsPage.tabItem { Label("Accounts", systemImage: "person.2") }.tag(1)
            settingsPage.tabItem { Label("Settings", systemImage: "gearshape") }.tag(2)
        }
        .tint(accent)
        .preferredColorScheme(appearance == 0 ? nil : (appearance == 1 ? .light : .dark))
        .sheet(item: $selectedAccount) { account in
            AccountDetailsView(account: account, accent: accent, authorizing: store.authorizing || store.isInitializing,
                connect: { store.connect(account) }, remove: {
                    if store.removeAccount(account) { selectedAccount = nil }
                })
        }
        .task {
            await store.start()
            if scenePhase == .active { await store.enteredForeground(recheck: false) }
            while !Task.isCancelled {
                store.refreshPlaybackState()
                await store.tick()
                do { try await Task.sleep(nanoseconds: 1_000_000_000) } catch { return }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { store.enteredBackground() }
            if phase == .active { Task { await store.enteredForeground() } }
        }
    }

    private var musicPage: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 25) {
                    if !store.isInitializing && store.musicAccessChecked && !store.musicAuthorized {
                        Button("Allow Music access") { Task { await store.requestMusicAccess() } }
                            .buttonStyle(.borderedProminent)
                    }
                    artwork
                    songDetails.redacted(reason: store.isInitializing ? .placeholder : [])
                    if !store.playback.id.isEmpty { timeline }
                    VStack(spacing: 12) {
                        HStack(spacing: 34) {
                            Button { feedback(); Task { await store.skipTrack(previous: true) } } label: {
                                Image(systemName: "backward.end.fill").font(.title2).frame(width: 44, height: 44)
                            }
                            .accessibilityLabel("Previous track or restart")
                            .disabled(store.isInitializing || !store.musicAuthorized || store.playback.id.isEmpty || store.controllingPlayback)
                            Button { feedback(); Task { await store.togglePlaybackAndSharing(minutes: sessionMinutes) } } label: {
                                Group {
                                    if store.isInitializing {
                                        ProgressView().tint(.white).accessibilityLabel("Loading Music")
                                    } else {
                                        PlaybackSymbol(playing: store.playing, animated: animateButtons)
                                    }
                                }
                                    .font(.system(size: 28, weight: .semibold))
                                    .frame(width: 78, height: 78)
                                    .foregroundStyle(.white)
                                    .background(accent, in: Circle())
                            }
                            .disabled(store.isInitializing || store.controllingPlayback || !store.musicAuthorized || (!store.playing && store.readyAccounts.isEmpty))
                            .opacity(!store.isInitializing && !store.playing && store.readyAccounts.isEmpty ? 0.4 : 1)
                            .accessibilityLabel(store.isInitializing ? "Loading Music" : (store.playing ? "Pause Music and stop sharing" : "Play Music and share"))
                            Button { feedback(); Task { await store.skipTrack(previous: false) } } label: {
                                Image(systemName: "forward.end.fill").font(.title2).frame(width: 44, height: 44)
                            }
                            .accessibilityLabel("Next track")
                            .disabled(store.isInitializing || !store.musicAuthorized || store.playback.id.isEmpty || store.controllingPlayback)
                        }
                        .buttonStyle(PlaybackButtonStyle(animated: animateButtons))
                        if !store.isInitializing {
                            if store.playing && !store.sharing {
                                Button("Start sharing") { feedback(); store.shareCurrentPlayback(minutes: sessionMinutes) }
                                    .font(.caption)
                                    .disabled(!store.musicAuthorized || store.readyAccounts.isEmpty)
                            } else {
                                Text(store.sharing ? "Sharing · \(store.readyAccounts.count) \(store.readyAccounts.count == 1 ? "account" : "accounts")" : "Play & share")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            if store.readyAccounts.isEmpty {
                                Button(store.accounts.isEmpty ? "Connect an account" : "Accounts") { tab = 1 }.font(.subheadline)
                            }
                        }
                    }
                    errorMessage
                }
                .disabled(store.isInitializing)
                .padding(.horizontal, 26).padding(.vertical, 24)
                .frame(maxWidth: 500).frame(maxWidth: .infinity)
            }
            .background {
                ZStack {
                    Color(uiColor: .systemGroupedBackground)
                    if ["wisps", "vapor", "vortex"].contains(vaporStyle) {
                        VaporBackground(style: vaporStyle, color: vaporColor, opacity: vaporOpacity,
                            speed: vaporSpeed, frameRate: vaporFrameRate, moving: !store.isInitializing && scenePhase == .active && tab == 0 && !reduceMotion && (!followPlayback || store.playing))
                            .allowsHitTesting(false).accessibilityHidden(true)
                    }
                }.ignoresSafeArea()
            }
            .navigationTitle(AppIdentity.name)
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private var artwork: some View {
        Group {
            if let artwork = store.currentArtwork {
                ArtworkImage(artwork, width: 270, height: 270)
            } else {
                RoundedRectangle(cornerRadius: 24)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
                    .overlay {
                        VStack(spacing: 12) {
                            Image(systemName: "music.note").font(.system(size: 42)).foregroundStyle(.secondary)
                            if !store.playback.id.isEmpty {
                                Text("No artwork supplied").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
            }
        }
        .frame(width: 270, height: 270)
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .accessibilityLabel("Album artwork")
    }

    private var songDetails: some View {
        VStack(spacing: 8) {
            Text(store.playback.title).font(.system(.title2, design: .rounded, weight: .bold))
                .multilineTextAlignment(.center).lineLimit(2)
            if !store.playback.artist.isEmpty {
                Text(store.playback.artist).font(.subheadline).foregroundStyle(.secondary)
            }
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

    private var accountsPage: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    if store.accounts.isEmpty {
                        ContentUnavailableView("No accounts", systemImage: "person.crop.circle", description: Text("Add a Discord account."))
                    }
                    ForEach(store.accounts) { account in
                        AccountRow(account: account, accent: accent, disabled: store.authorizing || store.isInitializing,
                            musicPlaying: store.playing, details: { selectedAccount = account }, connect: { store.connect(account) })
                    }
                    errorMessage
                }
                .padding(20).frame(maxWidth: 600).frame(maxWidth: .infinity)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Accounts")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add account", systemImage: "plus") {
                        if let account = store.addAccount() { store.connect(account) }
                    }
                    .disabled(store.isInitializing || store.authorizing)
                }
            }
        }
    }

    private var settingsPage: some View {
        NavigationStack {
            Form {
                Section("Sharing") {
                    Toggle("Auto-start when opened", isOn: $store.autoStart)
                    Picker("Session length", selection: $sessionMinutes) {
                        Text("30 minutes").tag(30)
                        Text("2 hours").tag(120)
                        Text("4 hours").tag(240)
                    }.disabled(background.isRunning)
                    Picker("Resend interval", selection: $pollSeconds) {
                        Text("5 seconds").tag(5)
                        Text("15 seconds").tag(15)
                        Text("30 seconds").tag(30)
                    }.disabled(background.isRunning)
                }
                Section {
                    Toggle("Background refresh", isOn: $store.backgroundRefresh)
                    LabeledContent("Last refresh", value: refresh.status)
                    Text(background.status).font(.footnote).foregroundStyle(.secondary)
                } header: { Text("Background") } footer: {
                    Text("iOS schedules short refreshes. This does not keep the app running continuously. Stop sharing cancels them.")
                }
                Section("Appearance") {
                    ColorPicker("Accent color", selection: Binding(get: { accent }, set: { accentHex = $0.afterglowHex }), supportsOpacity: false)
                    Picker("Appearance", selection: $appearance) {
                        Text("System").tag(0)
                        Text("Light").tag(1)
                        Text("Dark").tag(2)
                    }
                }
                Section("Background appearance") {
                    Picker("Style", selection: $vaporStyle) {
                        Text("Off").tag("off")
                        Text("Vapor").tag("vapor")
                        Text("Vortex").tag("vortex")
                        Text("Wisps").tag("wisps")
                    }
                    if vaporStyle != "off" {
                        Picker("Color", selection: $vaporColorSource) {
                            Text("Custom").tag("custom")
                            Text("Accent").tag("accent")
                            Text("Artwork").tag("artwork")
                        }
                        .onChange(of: vaporColorSource) { _, _ in store.refreshArtworkColor() }
                        if vaporColorSource == "custom" {
                            ColorPicker("Vapor color", selection: Binding(get: { Color(afterglowHex: vaporHex) },
                                set: { vaporHex = $0.afterglowHex }), supportsOpacity: false)
                        }
                        HStack {
                            Text("Speed")
                            Slider(value: $vaporSpeed, in: 0.25...1.5).accessibilityLabel("Vapor speed")
                            Text(vaporSpeed, format: .percent.precision(.fractionLength(0))).monospacedDigit().font(.caption).frame(width: 40)
                        }
                        HStack {
                            Text("Opacity")
                            Slider(value: $vaporOpacity, in: 0.1...0.65).accessibilityLabel("Vapor opacity")
                            Text(vaporOpacity, format: .percent.precision(.fractionLength(0))).monospacedDigit().font(.caption).frame(width: 40)
                        }
                        Picker("Frame rate", selection: $vaporFrameRate) {
                            Text("30 FPS").tag(30)
                            Text("60 FPS").tag(60)
                        }
                        Toggle("Follow playback", isOn: $followPlayback)
                    }
                    Toggle("Button animations", isOn: $buttonAnimations)
                    Toggle("Haptics", isOn: $haptics)
                }
                Section("Live Activity") {
                    Toggle("Show while sharing", isOn: $store.liveActivityEnabled)
                    if store.liveActivityEnabled, let error = liveActivity.error { Text(error).font(.footnote).foregroundStyle(.secondary) }
                }
                Section("Music") {
                    LabeledContent("Access", value: store.isInitializing || !store.musicAccessChecked ? "Checking…" : (store.musicAuthorized ? "Allowed" : "Not allowed"))
                    Button("Open iOS settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                }
                Section("Diagnostics") {
                    Button(store.checkingArtwork ? "Checking…" : "Check playback & artwork") {
                        Task { await store.diagnoseArtwork() }
                    }.disabled(store.checkingArtwork)
                    Text(store.artworkDiagnostics).font(.caption).textSelection(.enabled)
                    Button("Copy diagnostics") { UIPasteboard.general.string = store.artworkDiagnostics }
                        .disabled(store.artworkDiagnostics == "Not checked")
                }
                Section("About") {
                    LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")
                }
            }
            .navigationTitle("Settings")
        }
    }

    @ViewBuilder private var errorMessage: some View {
        if let error = store.error {
            HStack(alignment: .top) {
                Text(error).font(.footnote).frame(maxWidth: .infinity, alignment: .leading)
                Button("Dismiss", systemImage: "xmark") { store.error = nil }.labelStyle(.iconOnly)
            }
            .foregroundStyle(.red).padding(16)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        }
    }

    private func time(_ value: TimeInterval) -> String {
        let seconds = Int(max(0, value))
        return String(format: "%d:%02d", seconds / 60, seconds % 60)
    }
}
