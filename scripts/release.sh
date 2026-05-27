#!/usr/bin/env bash
# Build a signed (and optionally notarized) universal release binary and
# package it for upload to GitHub releases.
#
# Usage:
#   scripts/release.sh [version]
#
# Environment:
#   CODESIGN_IDENTITY   Hash or common-name of a code-signing identity in your
#                       keychain. If unset, the script prefers a
#                       "Developer ID Application" identity, falling back to
#                       any available codesigning identity. Set to "-" to
#                       ad-hoc sign.
#
#   NOTARY_PROFILE      Name of a keychain profile stored via
#                       `xcrun notarytool store-credentials`. If set, the
#                       script will submit the signed binary for notarization
#                       and wait for the verdict. If unset, notarization is
#                       skipped.
#
# Output:
#   dist/apple-mcp                        — the signed (and notarized) universal binary
#   dist/apple-mcp-<version>-macos.tar.gz — the tarball uploaded to releases

set -euo pipefail

cd "$(dirname "$0")/.."

VERSION="${1:-$(git describe --tags --abbrev=0 2>/dev/null || echo "dev")}"
VERSION="${VERSION#v}"

echo ">> Building universal release binary (arm64 + x86_64)…"
swift build -c release --arch arm64 --arch x86_64

SRC=".build/apple/Products/Release/apple-mcp"
if [ ! -x "$SRC" ]; then
    echo "!! Expected universal binary at $SRC was not produced." >&2
    exit 1
fi

mkdir -p dist
cp "$SRC" dist/apple-mcp

echo ">> Architectures:"
lipo -info dist/apple-mcp

# Pick a code-signing identity.
IDENTITY="${CODESIGN_IDENTITY:-}"
if [ -z "$IDENTITY" ]; then
    IDENTITY=$(security find-identity -v -p codesigning \
        | awk -F'"' '/"Developer ID Application:/ {print $2; exit}')
fi
if [ -z "$IDENTITY" ]; then
    IDENTITY=$(security find-identity -v -p codesigning \
        | awk -F'"' 'NR==1 && /^[[:space:]]*1\)/ {print $2}')
fi

if [ -n "$IDENTITY" ]; then
    echo ">> Signing with: $IDENTITY"
    codesign --force --options runtime --timestamp --sign "$IDENTITY" dist/apple-mcp
    codesign --verify --verbose=2 dist/apple-mcp
else
    echo "!! No codesigning identity found; skipping signature."
fi

# Notarize if a profile is configured.
if [ -n "${NOTARY_PROFILE:-}" ]; then
    echo ">> Notarizing via keychain profile: $NOTARY_PROFILE"
    NOTARIZE_ZIP="dist/apple-mcp-notarize.zip"
    rm -f "$NOTARIZE_ZIP"
    ditto -c -k --keepParent dist/apple-mcp "$NOTARIZE_ZIP"
    xcrun notarytool submit "$NOTARIZE_ZIP" \
        --keychain-profile "$NOTARY_PROFILE" \
        --wait
    rm -f "$NOTARIZE_ZIP"
    echo ">> Notarization complete."
else
    echo "!! NOTARY_PROFILE not set; skipping notarization."
fi

TARBALL="dist/apple-mcp-${VERSION}-macos.tar.gz"
echo ">> Packaging: $TARBALL"
tar -czf "$TARBALL" -C dist apple-mcp -C .. LICENSE README.md

shasum -a 256 dist/apple-mcp "$TARBALL"
echo ">> Done."
