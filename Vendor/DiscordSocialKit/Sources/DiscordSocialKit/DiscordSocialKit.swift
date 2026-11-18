//
//  DiscordSocialKit.swift
//  DiscordSocialKit
//
//  Created by Adrian Castro on 8/5/25.
//

import Combine
import Foundation
#if !IRPC_XTOOL
import SwiftData
#endif
import discord_partner_sdk

private let discordCallbackQueue = DispatchQueue(label: "afterglow.discord.callbacks", qos: .utility)
private final class DiscordCallbackReference {
    weak var manager: DiscordManager?
    init(_ manager: DiscordManager) { self.manager = manager }
}
private func callbackManager(_ pointer: UnsafeMutableRawPointer?) -> DiscordManager? {
    guard let pointer else { return nil }
    return Unmanaged<DiscordCallbackReference>.fromOpaque(pointer).takeUnretainedValue().manager
}
private let releaseDiscordCallback: Discord_FreeFn = { pointer in
    if let pointer { Unmanaged<DiscordCallbackReference>.fromOpaque(pointer).release() }
}

@MainActor
public final class DiscordManager: ObservableObject {
    public static var sdkVersion: String {
        "\(Discord_Client_GetVersionMajor()).\(Discord_Client_GetVersionMinor()).\(Discord_Client_GetVersionPatch())"
    }

	// Thread-safe client reference using a lock
	private let clientLock = NSLock()
	private var _client: UnsafeMutablePointer<Discord_Client>?

	private var applicationId: UInt64
	private var verifier: Discord_AuthorizationCodeVerifier?
	private var tokenStorage: (any TokenStorage)?
    private var acceptsTokenUpdates = true

    private var timeline = PresenceTimeline()
    private var transition = PresenceTransition()
    private var lastPresence: (title: String, artist: String, artwork: URL?)?
    public var trackTransitionSeconds: TimeInterval = 30
    private var presenceGeneration = 0
    private var presenceExpiry: Task<Void, Never>?
    @Published public private(set) var presenceStatus = "No presence update sent yet."
    @Published public private(set) var lastPresenceAcknowledgedAt: Date?

	@Published public private(set) var isReady = false
	@Published public private(set) var isAuthenticated = false
	@Published public private(set) var errorMessage: String? = nil
	@Published public private(set) var isAuthorizing = false
	@Published public var isRunning = false
	@Published public private(set) var username: String?
	@Published public private(set) var globalName: String?
	@Published public private(set) var userId: UInt64 = 0
	@Published public private(set) var avatarURL: URL?

	// Add user data cache structure
	private struct UserData {
		var username: String
		var globalName: String?
		var avatarURL: URL?
		var userId: UInt64
	}
	private var cachedUserData: UserData?

	public func startPresenceUpdates() {
		print("🎮 Starting Discord Rich Presence")
		isRunning = true
		Task { @MainActor in
			await startUpdates()
		}
	}

	public func stopPresenceUpdates() {
		print("🛑 Stopping Discord Rich Presence")
		isRunning = false
		Task { @MainActor in
			await stopUpdates()
		}
	}

	private var updateTimer: Timer?
	private var lastId: String = ""
	private var lastTitle: String = ""
	private var lastArtist: String = ""
	private var lastArtwork: URL? = nil
	private var lastDuration: TimeInterval = 0
	private var lastCurrentTime: TimeInterval = 0

	private var currentPlaybackInfo:
		(
			id: String, title: String, artist: String, duration: TimeInterval,
			currentTime: TimeInterval,
			artworkURL: URL?
		)? = nil
	private let presenceUpdateInterval: TimeInterval = 15

	private func fetchUserInfo() {
		guard let client = getClient() else { return }

		var userHandle = Discord_UserHandle(opaque: nil)
        guard Discord_Client_GetCurrentUserV2(client, &userHandle) else { return }
        defer { Discord_UserHandle_Drop(&userHandle) }

		// Get user ID first
		let userId = Discord_UserHandle_Id(&userHandle)
		print("🆔 Got user ID: \(userId)")

		// Get username
		var usernameStr = Discord_String()
        defer { Discord_Free(usernameStr.ptr) }
		let _ = Discord_UserHandle_Username(&userHandle, &usernameStr)

		let username = {
			if let usernamePtr = usernameStr.ptr {
				return String(
					bytes: UnsafeRawBufferPointer(
						start: usernamePtr,
						count: Int(usernameStr.size)
					),
					encoding: .utf8
				) ?? "Unknown User"
			}
			return "Unknown User"
		}()

		print("👤 Got username: \(username)")

		// Get display name
		var displayNameStr = Discord_String()
        defer { Discord_Free(displayNameStr.ptr) }
		let _ = Discord_UserHandle_DisplayName(&userHandle, &displayNameStr)

		let globalName = {
			if let displayNamePtr = displayNameStr.ptr {
				return String(
					bytes: UnsafeRawBufferPointer(
						start: displayNamePtr,
						count: Int(displayNameStr.size)
					),
					encoding: .utf8
				)
			}
			return nil
		}()

		print("📝 Got display name: \(globalName ?? "none")")

		// Get avatar URL
		var avatarUrlStr = Discord_String()
        defer { Discord_Free(avatarUrlStr.ptr) }
		let _ = Discord_UserHandle_AvatarUrl(
			&userHandle,
			Discord_UserHandle_AvatarType_Gif,
			Discord_UserHandle_AvatarType_Png,
			&avatarUrlStr
		)

		let avatarURL = {
			if let urlPtr = avatarUrlStr.ptr {
				let urlString =
					String(
						bytes: UnsafeRawBufferPointer(
							start: urlPtr,
							count: Int(avatarUrlStr.size)
						),
						encoding: .utf8
					) ?? ""
				return URL(string: urlString)
			}
			return nil
		}()

		print("🖼️ Got avatar URL: \(avatarURL?.absoluteString ?? "none")")

		// Cache and update
		let userData = UserData(
			username: username,
			globalName: globalName,
			avatarURL: avatarURL,
			userId: userId
		)

		Task { @MainActor in
			self.cachedUserData = userData
			self.username = username
			self.globalName = globalName
			self.avatarURL = avatarURL
			self.userId = userId

			print("✅ User info updated in UI")
		}
	}

	private let statusCallback: Discord_Client_OnStatusChanged = {
		status, error, errorDetail, userData in
		guard let manager = callbackManager(userData) else { return }
		print("🔄 Status changed: \(status)")

		Task { @MainActor in
			if error != Discord_Client_Error_None {
				print("❌ Connection Error: \(error) - Details: \(errorDetail)")
				manager.handleError("Connection error \(error): \(errorDetail)")
				return
			}

			switch status {
			case Discord_Client_Status_Ready:
				print("✅ Client is ready!")
				manager.isReady = true
				if manager.username == nil {
					manager.fetchUserInfo()
				}
			case Discord_Client_Status_Connected:
				print("🔗 Client connected!")
				manager.isAuthenticated = true
				manager.isAuthorizing = false
				manager.errorMessage = nil

				if let cached = manager.cachedUserData {
					manager.username = cached.username
					manager.globalName = cached.globalName
					manager.avatarURL = cached.avatarURL
					manager.userId = cached.userId
					print("📋 Restored cached user data")
				}
			case Discord_Client_Status_Disconnected:
				print("❌ Client disconnected")
				manager.isAuthenticated = false
				manager.isReady = false
			default:
				break
			}
		}
	}

	public init(applicationId: UInt64) {
		self.applicationId = applicationId
		setupClient()
	}

    public func setTokenStorage(_ storage: any TokenStorage) { tokenStorage = storage }

    public func hasStoredToken() throws -> Bool { try requireStorage().load() != nil }

    #if !IRPC_XTOOL
    public func setModelContext(_ context: ModelContext) {
        setTokenStorage(SwiftDataTokenStorage(context: context))
    }
    #endif

    private func requireStorage() throws -> any TokenStorage {
        guard let tokenStorage else {
            throw NSError(domain: "DiscordSocialKit", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Discord credential storage has not been configured."
            ])
        }
        return tokenStorage
    }

    public func signOut() throws {
        try requireStorage().delete()
        acceptsTokenUpdates = false
        Discord_Client_AbortAuthorize(getClient())
        stopPresenceUpdates()
        Discord_Client_Disconnect(getClient())
        isAuthenticated = false
        isReady = false
        isAuthorizing = false
        username = nil
        globalName = nil
        avatarURL = nil
        cachedUserData = nil
        userId = 0
    }

    private static let callbackPump: DispatchSourceTimer = {
        let timer = DispatchSource.makeTimerSource(queue: discordCallbackQueue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(10))
        timer.setEventHandler { autoreleasepool { Discord_RunCallbacks() } }
        timer.resume()
        return timer
    }()

	private func setupClient() {
		print("Initializing Discord SDK \(Self.sdkVersion)")

		// Create client and retain pointer
		let client = UnsafeMutablePointer<Discord_Client>.allocate(capacity: 1)

		// Store in our thread-safe storage
		clientLock.lock()
		_client = client
		clientLock.unlock()

		Discord_Client_Init(client)
		Discord_Client_SetApplicationId(client, applicationId)

		// Set up logging callback with proper string conversion
		let logCallback: Discord_Client_LogCallback = { message, severity, userData in
			let severityStr = { () -> String in
				switch severity {
				case Discord_LoggingSeverity_Info: return "INFO"
				case Discord_LoggingSeverity_Warning: return "WARN"
				case Discord_LoggingSeverity_Error: return "ERROR"
				default: return "DEBUG"
				}
			}()

			if let messagePtr = message.ptr,
				let messageStr = String(
					bytes: UnsafeRawBufferPointer(
						start: messagePtr,
						count: Int(message.size)
					),
					encoding: .utf8
				)
			{
				print("[Discord \(severityStr)] \(messageStr)")
			}
		}
		Discord_Client_AddLogCallback(client, logCallback, nil, nil, Discord_LoggingSeverity_Info)

		let userDataPtr = Unmanaged.passRetained(DiscordCallbackReference(self)).toOpaque()
		Discord_Client_SetStatusChangedCallback(client, statusCallback, releaseDiscordCallback, userDataPtr)

        // RunCallbacks drains all clients. One serial pump serves all accounts.
        _ = Self.callbackPump

		print("✨ Discord SDK initialized successfully")
	}

	// Thread-safe getter for the client
	private func getClient() -> UnsafeMutablePointer<Discord_Client>? {
		clientLock.lock()
		defer { clientLock.unlock() }
		return _client
	}

	public func authorize() {
        acceptsTokenUpdates = true
		guard let client = getClient() else { return }
		print("Starting auth flow...")
		isAuthorizing = true

		// Create and retain verifier
		let verifier = UnsafeMutablePointer<Discord_AuthorizationCodeVerifier>.allocate(capacity: 1)
		Discord_Client_CreateAuthorizationCodeVerifier(client, verifier)
		self.verifier = verifier.pointee

		var args = Discord_AuthorizationArgs()
		Discord_AuthorizationArgs_Init(&args)
		Discord_AuthorizationArgs_SetClientId(&args, applicationId)

		var scopes = Discord_String()
		Discord_Client_GetDefaultPresenceScopes(&scopes)
		Discord_AuthorizationArgs_SetScopes(&args, scopes)

		var challenge = Discord_AuthorizationCodeChallenge()
		Discord_AuthorizationCodeVerifier_Challenge(verifier, &challenge)
		Discord_AuthorizationArgs_SetCodeChallenge(&args, &challenge)

		let userDataPtr = Unmanaged.passRetained(DiscordCallbackReference(self)).toOpaque()
		Discord_Client_Authorize(client, &args, self.authCallback, releaseDiscordCallback, userDataPtr)
	}

	public func clearRichPresence() {
        clearRichPresence(resetTimeline: true)
    }

    private func clearRichPresence(resetTimeline: Bool) {
        presenceExpiry?.cancel()
        presenceExpiry = nil
		guard let client = getClient() else { return }
		print("🧹 Clearing rich presence...")

        presenceGeneration += 1
        if resetTimeline {
            timeline.reset()
            transition.reset()
            lastPresence = nil
        }
        presenceStatus = "Presence cleared."
        lastPresenceAcknowledgedAt = nil
		Discord_Client_ClearRichPresence(client)
	}

	struct RichPresenceContext {
		let namePtr: UnsafeMutablePointer<UInt8>
		let detailsPtr: UnsafeMutablePointer<UInt8>
		let statePtr: UnsafeMutablePointer<UInt8>
        let imagePtr: UnsafeMutablePointer<UInt8>?
        let imageTextPtr: UnsafeMutablePointer<UInt8>?
		let manager: DiscordManager
        let generation: Int
	}

    private static let releasePresenceContext: Discord_FreeFn = { pointer in
        guard let pointer else { return }
        let context = pointer.assumingMemoryBound(to: RichPresenceContext.self)
        context.pointee.namePtr.deallocate()
        context.pointee.detailsPtr.deallocate()
        context.pointee.statePtr.deallocate()
        context.pointee.imagePtr?.deallocate()
        context.pointee.imageTextPtr?.deallocate()
        context.deinitialize(count: 1)
        context.deallocate()
    }

	private static let richPresenceCallback:
		@convention(c) (UnsafeMutablePointer<Discord_ClientResult>?, UnsafeMutableRawPointer?) ->
			Void = { result, userData in
				print("📣 Rich Presence callback received")
				guard let contextPtr = userData?.assumingMemoryBound(to: RichPresenceContext.self)
				else {
					print("❌ Rich Presence callback: No context")
					return
				}

				let context = contextPtr.pointee


                let accepted = result.map { Discord_ClientResult_Successful($0) } ?? false
                let manager = context.manager
                let generation = context.generation
                Task { @MainActor in
                    guard manager.presenceGeneration == generation else { return }
                    manager.presenceStatus = accepted ? "Discord accepted the last update." : "Discord rejected the last update."
                    if accepted { manager.lastPresenceAcknowledgedAt = Date() }
                }

				if let result = result {
					if Discord_ClientResult_Successful(result) {
						print("✅ Rich Presence updated successfully!")
					} else {
						var errorStr = Discord_String()
						Discord_ClientResult_Error(result, &errorStr)
						if let ptr = errorStr.ptr {
							let errorMessage =
								String(
									bytes: UnsafeRawBufferPointer(
										start: ptr,
										count: Int(errorStr.size)
									),
									encoding: .utf8
								) ?? "Unknown error"
							print("❌ Rich Presence update failed: \(errorMessage)")
						} else {
							print("❌ Rich Presence update failed: No error message available")
						}
					}
				} else {
					print("❌ Rich Presence update failed: No result")
				}
			}


	public func updateRichPresence(
        id: String, title: String, artist: String, duration: TimeInterval,
        currentTime: TimeInterval, artworkURL: URL? = nil
    ) async {
        guard !Task.isCancelled, isAuthenticated, isRunning, !title.isEmpty, !artist.isEmpty else { return }
        let times = timeline.timestamps(id: id, duration: duration, position: currentTime,
                                        now: Date().timeIntervalSince1970)
        if let end = times.end, Double(end) / 1000 <= Date().timeIntervalSince1970 {
            waitForNextTrack()
            return
        }
        transition.reset()
        let image = PresenceTimeline.artwork(provided: artworkURL, cached: nil)
        lastPresence = (title, artist, image)
        sendRichPresence(title: title, state: "by \(artist)", image: image,
                         imageText: "\(title) by \(artist)", end: times.end,
                         expiresAt: times.end.map { Double($0) / 1000 }, clearOnExpiry: false)
    }

    /// Keep the card visible through short queue gaps, without an expired timer.
    public func waitForNextTrack() {
        guard isAuthenticated, isRunning, let lastPresence,
              transition.begin(now: Date().timeIntervalSince1970,
                               timeout: [15.0, 30.0, 60.0].contains(trackTransitionSeconds) ? trackTransitionSeconds : 30)
        else { return }
        sendRichPresence(title: "Waiting for next track", state: lastPresence.title + " — " + lastPresence.artist,
                         image: lastPresence.artwork, imageText: lastPresence.title + " by " + lastPresence.artist,
                         end: nil, expiresAt: transition.deadline, clearOnExpiry: true)
    }

    private func sendRichPresence(title: String, state: String, image: URL?, imageText: String,
                                  end: UInt64?, expiresAt: TimeInterval?, clearOnExpiry: Bool) {
        guard isAuthenticated, isRunning, let client = getClient() else { return }
        presenceGeneration += 1
        let generation = presenceGeneration
        presenceExpiry?.cancel()
        presenceExpiry = nil
        presenceStatus = "Preparing presence update…"
		var activity = Discord_Activity()
		Discord_Activity_Init(&activity)

		// Set activity type first
		Discord_Activity_SetType(&activity, Discord_ActivityTypes_Listening)

		// Set up asset
		var assets = Discord_ActivityAssets()
		Discord_ActivityAssets_Init(&assets)

        var imagePtr: UnsafeMutablePointer<UInt8>?
        var imageTextPtr: UnsafeMutablePointer<UInt8>?
        if let image {
            let imageBuffer = makeStringBuffer(from: image.absoluteString)
            let textBuffer = makeStringBuffer(from: imageText)
            imagePtr = imageBuffer.ptr
            imageTextPtr = textBuffer.ptr
            var imageString = Discord_String()
            imageString.ptr = imageBuffer.ptr
            imageString.size = Int(imageBuffer.size)
            var textString = Discord_String()
            textString.ptr = textBuffer.ptr
            textString.size = Int(textBuffer.size)
            Discord_ActivityAssets_SetLargeImage(&assets, &imageString)
            Discord_ActivityAssets_SetLargeText(&assets, &textString)
        }

		// Add assets to activity
		Discord_Activity_SetAssets(&activity, &assets)

		// Create and set name
		let namePtr = makeStringBuffer(from: "Apple Music").ptr
		var nameStr = Discord_String()
		nameStr.ptr = namePtr
		nameStr.size = "Apple Music".utf8.count
		Discord_Activity_SetName(&activity, nameStr)

		// Set details (title)
		let detailsPtr = makeStringBuffer(from: title).ptr
		var detailsStr = Discord_String()
		detailsStr.ptr = detailsPtr
		detailsStr.size = Int(Int32(title.utf8.count))
		Discord_Activity_SetDetails(&activity, &detailsStr)

		// Set state (artist)
		let statePtr = makeStringBuffer(from: state).ptr
		var stateStr = Discord_String()
		stateStr.ptr = statePtr
		stateStr.size = Int(Int32(state.utf8.count))
		Discord_Activity_SetState(&activity, &stateStr)

		// Set timestamps safely
		var timestamps = Discord_ActivityTimestamps()
		Discord_ActivityTimestamps_Init(&timestamps)

        if let end {
            Discord_ActivityTimestamps_SetEnd(&timestamps, end)
            Discord_Activity_SetTimestamps(&activity, &timestamps)
        }

		// Create context for cleanup
		let context = RichPresenceContext(
			namePtr: namePtr,
			detailsPtr: detailsPtr,
			statePtr: statePtr,
            imagePtr: imagePtr,
            imageTextPtr: imageTextPtr,
			manager: self,
            generation: generation
		)
		let contextPtr = UnsafeMutablePointer<RichPresenceContext>.allocate(capacity: 1)
		contextPtr.initialize(to: context)

        presenceStatus = "Waiting for Discord acknowledgement…"
		print("🎵 Sending activity update to Discord...")
		Discord_Client_UpdateRichPresence(
			client, &activity, Self.richPresenceCallback, Self.releasePresenceContext, contextPtr)
        if let expiresAt {
            let delay = max(0, expiresAt - Date().timeIntervalSince1970)
            presenceExpiry = Task { @MainActor [weak self] in
                do { try await Task.sleep(for: .seconds(delay)) } catch { return }
                guard let self, self.presenceGeneration == generation else { return }
                // Keep the timeline and transition deadline after timeout so
                // stale polls cannot revive either the timer or the waiting card.
                if clearOnExpiry { self.clearRichPresence(resetTimeline: false) }
                else { self.waitForNextTrack() }
            }
        }
	}

	public func updateCurrentPlayback(
		id: String,
		title: String,
		artist: String,
		duration: TimeInterval,
		currentTime: TimeInterval,
		artworkURL: URL?
	) {
		currentPlaybackInfo = (id, title, artist, duration, currentTime, artworkURL)
	}

	public func clearPlayback() {
		currentPlaybackInfo = nil
		clearRichPresence()
	}

	private func makeStringBuffer(from string: String) -> (
		ptr: UnsafeMutablePointer<UInt8>, size: Int32
	) {
		let data = Array(string.utf8) + [0]
		let ptr = UnsafeMutablePointer<UInt8>.allocate(capacity: data.count)
		ptr.initialize(from: data, count: data.count)
		return (ptr, Int32(string.utf8.count))
	}

	private func makeDiscordString(from string: String) -> Discord_String {
		var discordStr = Discord_String()
		let buffer = makeStringBuffer(from: string)
		discordStr.ptr = buffer.ptr
		discordStr.size = Int(buffer.size)
		return discordStr
	}

    private func updateStoredToken(
        accessToken: String, refreshToken: String, expiresIn: TimeInterval
    ) async throws {
        guard acceptsTokenUpdates else { throw CancellationError() }
        try requireStorage().save(DiscordToken(
            accessToken: accessToken, refreshToken: refreshToken, expiresIn: expiresIn
        ))
    }

    private func loadExistingToken() -> DiscordToken? {
        do { return try requireStorage().load() }
        catch {
            handleError("Unable to read Discord credentials. Check storage access or sign out.")
            return nil
        }
    }

	private func refreshRichPresence() {
		Task {
			await updateRichPresence(
				id: lastId,
				title: lastTitle,
				artist: lastArtist,
				duration: lastDuration,
				currentTime: lastCurrentTime,
				artworkURL: lastArtwork
			)
		}
	}

	private func stopUpdates() async {
		print("⏹️ Stopping presence updates")
		// Stop timer first
		updateTimer?.invalidate()
		updateTimer = nil

		// Clear state
		currentPlaybackInfo = nil
		lastTitle = ""
		lastArtist = ""
		lastArtwork = nil
		lastDuration = 0
		lastCurrentTime = 0

		// Clear presence last
		clearRichPresence()
	}

	private func startUpdates() async {
		await stopUpdates()  // Clear any existing timer first

		print("▶️ Starting presence updates")

		// Perform an immediate update if we have playback info
		if let info = self.currentPlaybackInfo,
			self.isAuthenticated,
			self.isReady,
			self.isRunning
		{
			print("⚡ Performing immediate presence update")
			await self.updateRichPresence(
				id: info.id,
				title: info.title,
				artist: info.artist,
				duration: info.duration,
				currentTime: info.currentTime,
				artworkURL: info.artworkURL
			)
		}

		// Set up timer for periodic updates
		updateTimer = Timer.scheduledTimer(withTimeInterval: presenceUpdateInterval, repeats: true)
		{ [weak self] _ in
			guard let self = self else { return }
			Task { @MainActor in
				guard let info = self.currentPlaybackInfo,
					self.isAuthenticated,
					self.isReady,
					self.isRunning
				else { return }

				await self.updateRichPresence(
					id: info.id,
					title: info.title,
					artist: info.artist,
					duration: info.duration,
					currentTime: info.currentTime,
					artworkURL: info.artworkURL
				)
			}
		}
	}

	private func handleError(_ message: String) {
		DispatchQueue.main.async {
			self.errorMessage = message
			self.isReady = false
			self.isAuthenticated = false
			self.isAuthorizing = false
		}
	}

	public func refreshTokenIfNeeded() async {
        guard getClient() != nil else { return }
		guard let token = loadExistingToken(),
			let refreshToken = token.refreshToken,
			token.needsRefresh
		else {
			print("⚠️ No valid refresh token available")
			return
		}
		let refreshStr = makeDiscordString(from: refreshToken)

		print("🔄 Refreshing token using refresh token")
		Discord_Client_RefreshToken(
			getClient(),
			applicationId,
			refreshStr,
			tokenCallback,
			releaseDiscordCallback,
			Unmanaged.passRetained(DiscordCallbackReference(self)).toOpaque()
		)
	}

	public func setupWithExistingToken() async {
		await MainActor.run {
            guard getClient() != nil else { return }
			guard let token = loadExistingToken(),
				let accessToken = token.accessToken
			else {
				print("⚠️ No existing token found or token invalid")
				return
			}

            isAuthorizing = true
			if token.needsRefresh {
                guard let refresh = token.refreshToken, !refresh.isEmpty else {
                    handleError("Saved sign-in has expired. Reconnect this account.")
                    return
                }
				print("🔄 Token needs refresh, initiating refresh flow")
				Task { await refreshTokenIfNeeded() }
			} else {
				print("✅ Using existing valid token")
				let accessStr = makeDiscordString(from: accessToken)
				Discord_Client_UpdateToken(
					getClient(),
					Discord_AuthorizationTokenType_Bearer,
					accessStr,
					{ result, userData in
						guard let manager = callbackManager(userData) else { return }
						print("🔑 Loaded token from storage, connecting to Discord...")
						if let client = manager.getClient() { Discord_Client_Connect(client) }
					},
					releaseDiscordCallback,
					Unmanaged.passRetained(DiscordCallbackReference(self)).toOpaque()
				)
			}
		}
	}

	private let tokenCallback: Discord_Client_TokenExchangeCallback = {
		result, token, refreshToken, tokenType, expiresIn, scope, userData in
		guard let manager = callbackManager(userData) else { return }

        guard let result, Discord_ClientResult_Successful(result) else {
            manager.handleError("Discord token exchange failed.")
            return
        }

		if let tokenPtr = token.ptr,
			let refreshPtr = refreshToken.ptr,
			let tokenStr = String(
				bytes: UnsafeRawBufferPointer(start: tokenPtr, count: Int(token.size)),
				encoding: .utf8),
			let refreshStr = String(
				bytes: UnsafeRawBufferPointer(start: refreshPtr, count: Int(refreshToken.size)),
				encoding: .utf8)
		{

			print("🎟️ Received new token from Discord")
			Task { @MainActor in
				do {
				    try await manager.updateStoredToken(
					accessToken: tokenStr,
					refreshToken: refreshStr,
					expiresIn: TimeInterval(expiresIn)
				    )
				} catch {
				    manager.handleError("Unable to save Discord credentials.")
				    return
				}

				guard let client = manager.getClient() else { return }
                let accessStr = manager.makeDiscordString(from: tokenStr)
				Discord_Client_UpdateToken(
					client,
					Discord_AuthorizationTokenType_Bearer,
					accessStr,
					{ result, userData in
						guard let manager = callbackManager(userData) else { return }
						print("🔑 Token updated, connecting to Discord...")
						if let client = manager.getClient() { Discord_Client_Connect(client) }
					},
					releaseDiscordCallback,
					Unmanaged.passRetained(DiscordCallbackReference(manager)).toOpaque()
				)
			}
		} else {
			print("❌ Failed to parse token data from Discord")
		}
	}

	private let authCallback: Discord_Client_AuthorizationCallback = {
		result, code, redirectUri, userData in
		guard let manager = callbackManager(userData) else { return }

		guard let result = result else {
			manager.handleError("Authentication failed: No result received")
			return
		}

		if !Discord_ClientResult_Successful(result) {
			var errorStr = Discord_String()
			Discord_ClientResult_Error(result, &errorStr)
			if let errorPtr = errorStr.ptr,
				let messageStr = String(
					bytes: UnsafeRawBufferPointer(
						start: errorPtr,
						count: Int(errorStr.size)
					),
					encoding: .utf8
				)
			{
				manager.handleError(messageStr.contains("invalid_scope")
                    ? "Discord rejected the scopes. Enable Social SDK in your application's Getting Started page and submit the form. Required scopes: openid sdk.social_layer_presence."
                    : "Authentication error: \(messageStr)")
			} else {
				manager.handleError("Authentication failed with unknown error")
			}
			return
		}

		guard var verifier = manager.verifier else {
			manager.handleError("❌ Authentication Error: No verifier available")
			return
		}

		var verifierStr = Discord_String()
		Discord_AuthorizationCodeVerifier_Verifier(&verifier, &verifierStr)

		// Token exchange callback
		let tokenCallback: Discord_Client_TokenExchangeCallback = {
			result, token, refreshToken, tokenType, expiresIn, scope, userData in
			guard let manager = callbackManager(userData) else { return }

            guard let result, Discord_ClientResult_Successful(result) else {
                manager.handleError("Discord token exchange failed.")
                return
            }

			if let tokenPtr = token.ptr,
				let refreshPtr = refreshToken.ptr,
				let tokenStr = String(
					bytes: UnsafeRawBufferPointer(start: tokenPtr, count: Int(token.size)),
					encoding: .utf8),
				let refreshStr = String(
					bytes: UnsafeRawBufferPointer(start: refreshPtr, count: Int(refreshToken.size)),
					encoding: .utf8)
			{
				print("🎟️ Received token from auth flow")

				// Save token first
				Task { @MainActor in
					do {
					    try await manager.updateStoredToken(
						accessToken: tokenStr,
						refreshToken: refreshStr,
						expiresIn: TimeInterval(expiresIn)
					    )
					} catch {
					    manager.handleError("Unable to save Discord credentials.")
					    return
					}

					// Then update client token
					print("🔑 Updating client with new token...")
					guard let client = manager.getClient() else { return }
                let accessStr = manager.makeDiscordString(from: tokenStr)
					Discord_Client_UpdateToken(
						client,
						Discord_AuthorizationTokenType_Bearer,
						accessStr,
						{ result, userData in
							print("🔌 Connecting with new token...")
							guard let manager = callbackManager(userData) else { return }
							if let client = manager.getClient() { Discord_Client_Connect(client) }
						},
						releaseDiscordCallback,
						Unmanaged.passRetained(DiscordCallbackReference(manager)).toOpaque()
					)
				}
			}
		}

		guard let client = manager.getClient() else { return }
		Discord_Client_GetToken(
			client,
			manager.applicationId,
			code,
			verifierStr,
			redirectUri,
			tokenCallback,
			releaseDiscordCallback,
			Unmanaged.passRetained(DiscordCallbackReference(manager)).toOpaque()
		)
	}

    /// Close a removed account's client after draining the callback queue.
    /// Stored credentials are handled separately by TokenStorage.delete().
    public func shutdown() {
        presenceExpiry?.cancel()
        presenceExpiry = nil
        acceptsTokenUpdates = false
        presenceGeneration += 1
        isRunning = false
        updateTimer?.invalidate()
        updateTimer = nil
        clientLock.lock()
        let client = _client
        _client = nil
        clientLock.unlock()
        guard let client else { return }
        discordCallbackQueue.sync {
            Discord_Client_AbortAuthorize(client)
            Discord_Client_Disconnect(client)
            Discord_Client_Drop(client)
            client.deallocate()
        }
    }

    deinit {
        presenceExpiry?.cancel()
        clientLock.lock()
        let client = _client
        _client = nil
        clientLock.unlock()
        if let client {
            discordCallbackQueue.async {
                Discord_Client_Drop(client)
                client.deallocate()
            }
        }
    }
}
