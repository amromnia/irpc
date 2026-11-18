#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
mkdir -p build
swiftc iRPC/Models/PlaybackPresentationState.swift tests/playback-state-check.swift -o build/playback-state-check
build/playback-state-check
