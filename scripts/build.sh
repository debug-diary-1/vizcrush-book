#!/usr/bin/env bash
# Build the book on any Linux CI (Vercel, GitHub Actions, etc) without needing
# Rust or cargo. Downloads the prebuilt mdBook binary and runs `mdbook build`.
set -euo pipefail

MDBOOK_VERSION="${MDBOOK_VERSION:-v0.4.40}"
ARCHIVE="mdbook-${MDBOOK_VERSION}-x86_64-unknown-linux-gnu.tar.gz"
URL="https://github.com/rust-lang/mdBook/releases/download/${MDBOOK_VERSION}/${ARCHIVE}"

echo "Downloading mdBook ${MDBOOK_VERSION}..."
curl -sSL "$URL" -o /tmp/mdbook.tar.gz

echo "Extracting..."
mkdir -p /tmp/mdbook-bin
tar -xzf /tmp/mdbook.tar.gz -C /tmp/mdbook-bin

echo "Building book..."
/tmp/mdbook-bin/mdbook build

echo "Done. Output in ./book"
