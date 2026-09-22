#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"

FIREBASE_PROJECT="${1:-"neuroyukti"}"
NOTES="${2:-"Sensio PPG Analysis Studio Release: Interactive Gapless Analysis Window, 28-feature clinical dictionary, and research-grade CSV exports."}"
APP_ID="${FIREBASE_APP_ID:-"1:883026449955:android:4a64a52bebdc63424f4396"}"

echo "=================================================="
echo "🔥 Deploying to Firebase App Distribution"
echo "Project: $FIREBASE_PROJECT"
echo "App ID:  $APP_ID"
echo "Notes:   $NOTES"
echo "=================================================="

APK_PATH="build/app/outputs/flutter-apk/app-release.apk"
if [ ! -f "$APK_PATH" ]; then
  echo "📦 APK not found at $APK_PATH, building now..."
  ./scripts/build_android.sh
fi

echo "🚀 Uploading APK to Firebase App Distribution..."
npx firebase-tools appdistribution:distribute "$APK_PATH" \
  --project "$FIREBASE_PROJECT" \
  --app "$APP_ID" \
  --testers "arunsasi84@gmail.com" \
  --release-notes "$NOTES"

echo "=================================================="
echo "🎉 Firebase App Distribution release published!"
echo "=================================================="
