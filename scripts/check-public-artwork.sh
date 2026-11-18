#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
mkdir -p build
swiftc iRPC/Models/PublicArtworkPolicy.swift iRPC/Models/PublicArtworkLookup.swift \
  tests/public-artwork-check.swift -o build/public-artwork-check
build/public-artwork-check "$@"
