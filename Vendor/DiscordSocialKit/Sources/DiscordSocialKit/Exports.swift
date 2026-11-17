//
//  Exports.swift
//  DiscordSocialKit
//
//  Created by Adrian Castro on 13/5/25.
//

import Foundation
#if !IRPC_XTOOL
import SwiftData

// Re-export SwiftData types needed for model usage
@_exported import class SwiftData.ModelContainer
@_exported import class SwiftData.ModelContext
@_exported import class SwiftData.Schema

#endif

// Explicitly re-export the DiscordToken model
// This ensures it's visible to importers even if module boundaries cause issues
public typealias DiscordTokenModel = DiscordToken
