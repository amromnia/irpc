#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
mkdir -p build
swiftc -D IRPC_XTOOL \
  Vendor/DiscordSocialKit/Sources/DiscordSocialKit/Models/PortableDiscordToken.swift \
  tests/token-storage-check.swift -o build/token-storage-check
build/token-storage-check
