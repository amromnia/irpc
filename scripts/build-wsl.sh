#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
if [[ "$(uname -s)" != Linux || "$PWD" == /mnt/* ]]; then
  echo 'Run from a checkout on the native WSL/Linux filesystem, not /mnt/c.' >&2
  exit 1
fi
export IRPC_XTOOL=1
for argument in "$@"; do
  if [[ "$argument" == --sign || "$argument" == -s ]]; then
    echo 'This script verifies an unsigned IPA. Use the signed xtool command in docs/BUILD-WSL.md.' >&2
    exit 1
  fi
done
python3 scripts/prepare-xtool-resources.py
mkdir -p build
xtool dev build --scheme iRPC-Xtool --configuration release --ipa --verbose "$@" \
  2>&1 | tee build/xtool-build.log
python3 scripts/verify-ipa.py
