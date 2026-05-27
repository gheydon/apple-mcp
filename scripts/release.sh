#!/usr/bin/env bash
# Build a signed universal (arm64 + x86_64) release binary and package it.
#
# Usage:
#   scripts/release.sh [version]
#
# Environment:
#   CODESIGN_IDENTITY  Hash or common-name of a code-signing identity in your
#                      keychain. If unset, the script picks the first one
#                      `security find-identity -v -p codesigning` returns.
#                      Set to "-" to ad-hoc sign (no developer identity).
#
# Output:
#   dist/apple-mcp                       — the signed universal binary
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

IDENTITY="${CODESIGN_IDENTITY:-}"
if [ -z "$IDENTITY" ]; then
    IDENTITY=$(security find-identity -v -p codesigning | awk -F'"' 'NR==1 && /1\)/ {print $2}')
fi

if [ -n "$IDENTITY" ]; then
    echo ">> Signing with: $IDENTITY"
    codesign --force --sign "$IDENTITY" --options runtime --timestamp dist/apple-mcp
    codesign --verify --verbose dist/apple-mcp
else
    echo "!! No codesigning identity found; skipping signature."
fi

TARBALL="dist/apple-mcp-${VERSION}-macos.tar.gz"
echo ">> Packaging: $TARBALL"
tar -czf "$TARBALL" -C dist apple-mcp -C .. LICENSE README.md

shasum -a 256 dist/apple-mcp "$TARBALL"
echo ">> Done."
