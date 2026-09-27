#!/usr/bin/env bash
set -euo pipefail
LLAMA_TAG="${LLAMA_TAG:-b11218}"
DEST="Vendor/llama.xcframework"
if [ -d "$DEST" ]; then
  echo "already present: $DEST"
  exit 0
fi
URL="https://github.com/ggml-org/llama.cpp/releases/download/${LLAMA_TAG}/llama-${LLAMA_TAG}-xcframework.zip"
TMP="$(mktemp -d)"
echo "downloading $URL"
curl -fL --retry 3 -o "$TMP/llama.zip" "$URL"
unzip -q "$TMP/llama.zip" -d "$TMP/x"
mkdir -p Vendor
cp -R "$TMP/x/build-apple/llama.xcframework" "$DEST"
rm -rf "$DEST"/*/dSYMs "$DEST"/*/*/dSYMs
rm -rf "$TMP"
du -sh "$DEST"
ls "$DEST/ios-arm64/llama.framework" | head
