#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"

FIREBASE_PROJECT="${1:-"ccs-ppg-studio"}"
NOTES="${2:-"CCS PPGStudio Release: Interactive Gapless Analysis Window, 28-feature clinical dictionary, and research-grade CSV exports."}"
APP_ID="${FIREBASE_APP_ID:-"1:625498974111:android:0404b3c6e15ce5afc47faa"}"

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
