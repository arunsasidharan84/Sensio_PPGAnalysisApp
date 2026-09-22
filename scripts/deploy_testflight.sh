#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"

API_KEY="${APP_STORE_CONNECT_API_KEY_ID:-"FUFCA5L597"}"
API_ISSUER="${APP_STORE_CONNECT_ISSUER_ID:-"9aa55f61-d92c-449b-af2f-2a885bd16b42"}"

echo "=================================================="
echo "✈️ Deploying Sensio PPG Studio to TestFlight"
echo "API Key: $API_KEY"
echo "Issuer:  $API_ISSUER"
echo "=================================================="

echo "🔨 [1/3] Building Rust static library for iOS..."
cd rust
cargo build --release --target aarch64-apple-ios
mkdir -p ../ios/Frameworks
cp target/aarch64-apple-ios/release/libsensio_ppg_core.a ../ios/Frameworks/libsensio_ppg_core.a
cd ..

echo "📦 [2/3] Archiving Flutter iOS IPA..."
flutter build ipa --release

IPA_PATH=$(find build/ios/ipa -name "*.ipa" | head -n 1)

if [ -z "$IPA_PATH" ] || [ ! -f "$IPA_PATH" ]; then
  echo "❌ Error: IPA file not found in build/ios/ipa/"
  exit 1
fi

echo "🚀 [3/3] Uploading $IPA_PATH to App Store Connect / TestFlight..."
xcrun altool --upload-app --type ios \
  --file "$IPA_PATH" \
  --apiKey "$API_KEY" \
  --apiIssuer "$API_ISSUER"

echo "=================================================="
echo "🎉 TestFlight release upload completed successfully!"
echo "=================================================="
