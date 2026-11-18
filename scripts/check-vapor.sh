#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
mkdir -p build
if [[ "${1:-}" == --benchmark ]]; then
  swiftc -O iRPC/Models/VaporSimulation.swift tests/vapor-benchmark.swift -o build/vapor-benchmark
  build/vapor-benchmark
else
  swiftc -O iRPC/Models/VaporSimulation.swift tests/vapor-check.swift -o build/vapor-check
  build/vapor-check
fi
