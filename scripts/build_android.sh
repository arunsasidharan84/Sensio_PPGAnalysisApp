#!/usr/bin/env bash
set -euo pipefail

echo "=================================================="
echo "🤖 Building Sensio PPG Studio for Android"
echo "=================================================="

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_DIR"

NDK_DEFAULT="/opt/homebrew/share/android-commandlinetools/ndk/28.2.13676358"
if [ ! -d "$NDK_DEFAULT" ]; then
  NDK_DEFAULT="/opt/homebrew/share/android-commandlinetools/ndk/27.2.12479018"
fi
NDK="${ANDROID_NDK_HOME:-$NDK_DEFAULT}"
API="${ANDROID_API:-24}"

HOST_TAG="darwin-x86_64"
case "$(uname -s)" in
  Linux) HOST_TAG="linux-x86_64" ;;
esac
TOOLCHAIN="$NDK/toolchains/llvm/prebuilt/$HOST_TAG/bin"

if [ ! -d "$TOOLCHAIN" ]; then
  echo "ERROR: NDK toolchain not found at $TOOLCHAIN" >&2
  exit 1
fi

TARGETS=(
  "arm64-v8a:aarch64-linux-android:aarch64-linux-android"
  "armeabi-v7a:armv7-linux-androideabi:armv7a-linux-androideabi"
  "x86_64:x86_64-linux-android:x86_64-linux-android"
)

echo "🔨 [1/3] Compiling Rust native engine for Android..."
for entry in "${TARGETS[@]}"; do
  IFS=":" read -r ABI TARGET CLANG_PREFIX <<< "$entry"
  echo "  --> Compiling $ABI ($TARGET)..."
  rustup target add "$TARGET" >/dev/null 2>&1 || true

  LINKER="$TOOLCHAIN/${CLANG_PREFIX}${API}-clang"
  ENV_TARGET="$(echo "$TARGET" | tr 'a-z-' 'A-Z_')"
  TOOL_ENV_TARGET="${TARGET//-/_}"
  export CARGO_TARGET_${ENV_TARGET}_LINKER="$LINKER"
  export AR_${TOOL_ENV_TARGET}="$TOOLCHAIN/llvm-ar"
  export CC_${TOOL_ENV_TARGET}="$LINKER"

  (cd rust && cargo build --release --target "$TARGET")

  OUT="android/app/src/main/jniLibs/$ABI"
  mkdir -p "$OUT"
  cp "rust/target/$TARGET/release/libsensio_ppg_core.so" "$OUT/"
done

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
