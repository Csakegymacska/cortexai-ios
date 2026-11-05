#!/bin/bash
# CortexAI — egyparancsos, aláíratlan IPA macOS-en.
#
#   ./Scripts/build_ipa.sh
#
# Kell hozzá: Xcode (App Store-ból), és első futáskor a Homebrew. Aláírás nem kell:
# a kimenet sideloadolható (Sideloadly / AltStore / Esign, saját Apple ID-vel).
#
# Kell hozzá Xcode 26 vagy újabb: az app iOS 26-os API-kat használ (Liquid Glass).
# Ha a helyi SDK régebbi, a szkript azonnal megáll, mert a deployment target nem fordul le.

set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$(pwd)"
echo "▸ projekt: $ROOT"

command -v xcodebuild >/dev/null || { echo "✗ Nincs Xcode. Telepítsd az App Store-ból."; exit 1; }
xcodebuild -version

# 1. SDK-felderítés
SDK=$(xcrun --sdk iphoneos --show-sdk-version)
MAJ=${SDK%%.*}
echo "▸ iOS SDK: $SDK"
FLAGS=""
if [ "$MAJ" -lt 26 ]; then
  echo "  ! Az app iOS 26-ra épül (Liquid Glass), de az SDK itt $SDK."
  echo "    Kompatibilitási build készül: a felület a régi anyagot használja."
  cp project.yml project.yml.bak
  sed -i '' -e "s/iOS: \"26.0\"/iOS: \"$SDK\"/" -e "s/deploymentTarget: \"26.0\"/deploymentTarget: \"$SDK\"/g" project.yml
  FLAGS='SWIFT_ACTIVE_COMPILATION_CONDITIONS=COMPAT_SDK'
fi

# 2. Projekt generálás
if ! command -v xcodegen >/dev/null; then
  echo "▸ xcodegen telepítése"
  HOMEBREW_NO_AUTO_UPDATE=1 brew install xcodegen
fi
xcodegen generate

# 3. Build (aláírás nélkül)
rm -rf build out
xcodebuild build \
  -project CortexAI.xcodeproj -scheme CortexAI \
  -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" $FLAGS \
  -derivedDataPath build

# 4. Csomagolás
APP=$(find build/Build/Products/Release-iphoneos -maxdepth 1 -name '*.app' | head -1)
[ -n "$APP" ] || { echo "✗ Nem készült .app"; exit 1; }
VER=$(grep -m1 'MARKETING_VERSION' project.yml | sed -E 's/.*"([^"]+)".*/\1/')
BUILD=$(grep -m1 'CURRENT_PROJECT_VERSION' project.yml | sed -E 's/.*"([^"]+)".*/\1/')
mkdir -p out/Payload
cp -R "$APP" out/Payload/
(
  cd out
  NAME="CortexAI-$VER-b$BUILD-unsigned.ipa"
  zip -qry "$NAME" Payload
  rm -rf Payload
  shasum -a 256 "$NAME" | tee "$NAME.sha256"
  ls -lh "$NAME"
  echo "✓ kész: $ROOT/out/$NAME"
)

[ -f project.yml.bak ] && mv project.yml.bak project.yml || true
