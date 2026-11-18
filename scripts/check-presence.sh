#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
mkdir -p build
swiftc Vendor/DiscordSocialKit/Sources/DiscordSocialKit/PresenceTimeline.swift \
  iRPC/Models/PublicArtworkPolicy.swift tests/presence-check.swift -o build/presence-check
build/presence-check
swiftc iRPC/Models/PresenceUpdatePolicy.swift tests/presence-update-check.swift -o build/presence-update-check
build/presence-update-check
