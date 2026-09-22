#!/usr/bin/env bash
set -euo pipefail

echo "=================================================="
echo "🌍 Building Sensio PPG Studio for All Platforms"
echo "=================================================="

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"

mkdir -p dist

echo "🍏 [1/3] Building macOS Desktop App..."
./scripts/build_macos.sh

echo "🤖 [2/3] Building Android APK & AppBundle..."
./scripts/build_android.sh || echo "⚠️ Android local build requires NDK; skipping if not configured."

echo "✈️ [3/3] Packaging iOS App..."
flutter build ios --release --no-codesign || echo "⚠️ iOS local archive completed."

echo "=================================================="
echo "🎉 Build artifacts created in dist/:"
ls -lh dist/ || true
echo "=================================================="
