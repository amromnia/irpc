//
//  iRPCApp.swift
//  iRPC
//
//  Created by Adrian Castro on 8/5/25.
//

import DiscordSocialKit
import SwiftData
import SwiftUI

@main
struct iRPCApp: App {
	let container: ModelContainer

	init() {
		BackgroundController.shared.register()
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
	}

	var body: some Scene {
		WindowGroup {
			ContentView()
		}
		.modelContainer(container)
	}
}
