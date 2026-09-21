#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HERE"

echo "Building native sensio_ppg_core library..."
cargo build --release

mkdir -p "$HERE/../bin"
mkdir -p "$HERE/../macos/Frameworks"

if [[ "$OSTYPE" == "darwin"* ]]; then
  cp "$HERE/target/release/libsensio_ppg_core.dylib" "$HERE/../bin/"
  cp "$HERE/target/release/libsensio_ppg_core.dylib" "$HERE/../macos/Frameworks/"
  echo "Copied libsensio_ppg_core.dylib to bin/ and macos/Frameworks/"
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
  cp "$HERE/target/release/libsensio_ppg_core.so" "$HERE/../bin/"
  echo "Copied libsensio_ppg_core.so to bin/"
elif [[ "$OSTYPE" == "msys"* || "$OSTYPE" == "win32"* ]]; then
  cp "$HERE/target/release/sensio_ppg_core.dll" "$HERE/../bin/"
  echo "Copied sensio_ppg_core.dll to bin/"
fi
echo "Build complete."
