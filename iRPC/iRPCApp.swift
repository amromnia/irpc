//
//  iRPCApp.swift
//  iRPC
//
//  Created by Adrian Castro on 8/5/25.
//

import DiscordSocialKit
#if !IRPC_XTOOL
import SwiftData
#endif
import SwiftUI

@main
struct iRPCApp: App {
    #if !IRPC_XTOOL
	let container: ModelContainer
    #endif

	init() {
		BackgroundController.shared.register()
        #if !IRPC_XTOOL
		do {
			let schema = Schema([DiscordTokenModel.self])
			let config = ModelConfiguration(
				schema: schema,
				isStoredInMemoryOnly: false,
				allowsSave: true,
				cloudKitDatabase: .none
			)

			container = try ModelContainer(
				for: schema,
				configurations: config
			)
			print("✅ Local ModelContainer initialized")
		} catch {
			print("❌ Failed to initialize ModelContainer: \(error)")
			fatalError("Failed to initialize ModelContainer: \(error)")
		}
        #endif
	}

	var body: some Scene {
		WindowGroup {
			ContentView()
		}
        #if !IRPC_XTOOL
		.modelContainer(container)
        #endif
	}
}
