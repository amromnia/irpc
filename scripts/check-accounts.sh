#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
mkdir -p build
swiftc Vendor/DiscordSocialKit/Sources/DiscordSocialKit/Storage/DiscordCredentialScope.swift \
  tests/account-scope-check.swift -o build/account-scope-check
build/account-scope-check
