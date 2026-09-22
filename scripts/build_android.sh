#!/usr/bin/env bash
set -euo pipefail

echo "=================================================="
echo "🤖 Building Sensio PPG Studio for Android"
echo "=================================================="

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"

export ANDROID_HOME="${ANDROID_HOME:-/opt/homebrew/share/android-commandlinetools}"
export ANDROID_NDK_HOME="${ANDROID_NDK_HOME:-/opt/homebrew/share/android-commandlinetools/ndk/27.2.12479018}"

echo "🔨 [1/3] Compiling Rust native engine for Android..."
mkdir -p android/app/src/main/jniLibs/arm64-v8a \
         android/app/src/main/jniLibs/armeabi-v7a \
         android/app/src/main/jniLibs/x86_64

if command -v cargo-ndk >/dev/null 2>&1; then
  cd rust
  cargo ndk -t arm64-v8a -t armeabi-v7a -t x86_64 -o ../android/app/src/main/jniLibs build --release
  cd ..
else
  echo "⚠️ cargo-ndk not found, installing cargo-ndk..."
  cargo install cargo-ndk
  cd rust
  cargo ndk -t arm64-v8a -t armeabi-v7a -t x86_64 -o ../android/app/src/main/jniLibs build --release
  cd ..
fi

echo "🚀 [2/3] Building Flutter Android Release APK..."
flutter build apk --release

echo "📦 [3/3] Building Flutter Android AppBundle (AAB)..."
flutter build appbundle --release

mkdir -p dist
cp build/app/outputs/flutter-apk/app-release.apk dist/SensioPPGStudio-Android.apk
cp build/app/outputs/bundle/release/app-release.aab dist/SensioPPGStudio-Android.aab

echo "=================================================="
echo "✅ Android build completed:"
echo "   APK: dist/SensioPPGStudio-Android.apk"
echo "   AAB: dist/SensioPPGStudio-Android.aab"
echo "=================================================="
