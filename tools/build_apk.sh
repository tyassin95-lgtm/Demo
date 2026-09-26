#!/usr/bin/env bash
# Builds the signed release APK for Neon Rift.
#
# Requirements: Godot 4.7.2 editor on PATH as `godot`, Android export templates
# installed, Android SDK (build-tools 36.x) and a JDK. Signing uses a release
# keystore passed through the standard Godot environment variables:
#   GODOT_ANDROID_KEYSTORE_RELEASE_PATH / _USER / _PASSWORD
# If they are unset, a local keystore is generated in build/ (never committed).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GAME="$ROOT/game"
OUT="$ROOT/build"
mkdir -p "$OUT"
export ANDROID_HOME="${ANDROID_HOME:-/opt/android-sdk}"
export JAVA_HOME="${JAVA_HOME:-$(dirname "$(dirname "$(readlink -f "$(which java)")")")}"
if [ -z "${GODOT_ANDROID_KEYSTORE_RELEASE_PATH:-}" ]; then
  KS="$OUT/release.keystore"
  if [ ! -f "$KS" ]; then
    keytool -genkeypair -keystore "$KS" -storepass neonrift -alias neonrift -keypass neonrift \
      -keyalg RSA -keysize 2048 -validity 10000 -dname "CN=Neon Rift Demo,O=Indie,C=US" -deststoretype pkcs12 >/dev/null 2>&1
  fi
  export GODOT_ANDROID_KEYSTORE_RELEASE_PATH="$KS"
  export GODOT_ANDROID_KEYSTORE_RELEASE_USER=neonrift
  export GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD=neonrift
fi
cd "$GAME"
# 1. Regenerate the extracted character assets if the sources changed.
if [ assets/characters/UAL1_Standard.glb -nt assets/characters/mannequin_anims.res ] || \
   [ assets/characters/UAL2_Standard.glb -nt assets/characters/mannequin_anims.res ]; then
  godot --headless --path . --import >/dev/null 2>&1 || true
  godot --headless --path . --script res://tools/build_character_assets.gd
fi
# 2. Import and export. The shader baker (precompiled shaders, no first-use stutter
#    on phones) needs a real rendering device, so export through a (virtual)
#    display with Vulkan when one is available; otherwise fall back to headless.
godot --headless --path . --import >/dev/null 2>&1 || true
if command -v xvfb-run >/dev/null 2>&1; then
  xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-method mobile --export-release "Android" "$OUT/NeonRift.apk"
else
  godot --headless --path . --export-release "Android" "$OUT/NeonRift.apk"
fi
# 3. Verify the signature.
"$ANDROID_HOME"/build-tools/*/apksigner verify --print-certs "$OUT/NeonRift.apk" | head -3
ls -lh "$OUT/NeonRift.apk"
