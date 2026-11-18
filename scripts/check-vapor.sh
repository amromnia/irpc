#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
mkdir -p build
swiftc -O iRPC/Models/VaporSimulation.swift tests/vapor-check.swift -o build/vapor-check
build/vapor-check
