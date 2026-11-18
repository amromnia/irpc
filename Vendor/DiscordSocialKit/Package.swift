// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription
import Foundation

let portable = ProcessInfo.processInfo.environment["IRPC_XTOOL"] == "1"

let package = Package(
	name: "DiscordSocialKit",
	platforms: [
		.iOS(.v17),
		.macOS(.v14),
	],
	products: [
		.library(
			name: "DiscordSocialKit",
			targets: ["DiscordSocialKit"])
	],
	targets: [
		.target(
			name: "DiscordSocialKit",
			dependencies: [
				"discord_partner_sdk",
			],
            swiftSettings: portable ? [.define("IRPC_XTOOL")] : []),
		.binaryTarget(
			name: "discord_partner_sdk",
			path: "Frameworks/discord_partner_sdk.xcframework"
		),
		.testTarget(
			name: "DiscordSocialKitTests",
			dependencies: ["DiscordSocialKit"]
		),
	]
)
