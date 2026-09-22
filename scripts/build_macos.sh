#!/usr/bin/env bash
set -euo pipefail

echo "=================================================="
echo "🍏 Building Sensio PPG Studio for macOS"
echo "=================================================="

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"

echo "🔨 [1/4] Compiling Rust native engine (aarch64-apple-darwin)..."
cd rust
cargo build --release --target aarch64-apple-darwin
cd ..

echo "📦 [2/4] Staging macOS dynamic library..."
mkdir -p macos/Frameworks bin
cp rust/target/aarch64-apple-darwin/release/libsensio_ppg_core.dylib macos/Frameworks/libsensio_ppg_core.dylib
cp rust/target/aarch64-apple-darwin/release/libsensio_ppg_core.dylib bin/libsensio_ppg_core.dylib

echo "🚀 [3/4] Building Flutter macOS application..."
flutter build macos --release

echo "🔒 [4/4] Injecting native engine & codesigning app bundle..."
APP="build/macos/Build/Products/Release/sensio_ppg_app.app"
mkdir -p "$APP/Contents/Frameworks"
cp macos/Frameworks/libsensio_ppg_core.dylib "$APP/Contents/Frameworks/libsensio_ppg_core.dylib"
codesign --force --sign - "$APP/Contents/Frameworks/libsensio_ppg_core.dylib"
codesign --force --deep --sign - --entitlements macos/Runner/Release.entitlements "$APP"

mkdir -p dist
ditto -c -k --sequesterRsrc --keepParent "$APP" dist/SensioPPGStudio-macOS.zip

echo "=================================================="
echo "✅ macOS build completed: dist/SensioPPGStudio-macOS.zip"
echo "=================================================="
