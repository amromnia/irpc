#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
mkdir -p build
swiftc Vendor/DiscordSocialKit/Sources/DiscordSocialKit/PresenceTimeline.swift \
  tests/presence-check.swift -o build/presence-check
build/presence-check
