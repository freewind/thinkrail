#!/usr/bin/env bash
# Build the Intel (x86_64) macOS ThinkRail launcher.
#
# Electrobun publishes no macOS x64 core, so the desktop .app/.dmg cannot be
# built for an Intel Mac. The supported Intel artifact is the CLI single-file
# binary — the same `thinkrail` executable `install.sh` fetches on the other
# platforms (it boots the host in-process and opens the browser to the app).
#
# Usage: ./build-mac.sh   (from anywhere; artifact path is printed at the end)

set -euo pipefail

TARGET="bun-darwin-x64"
ARTIFACT_NAME="thinkrail-${TARGET#bun-}"

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$repo_root"

echo "==> Installing dependencies"
bun install

echo "==> Building the web UI"
bun run build:web

echo "==> Compiling the Intel macOS binary (--target=$TARGET)"
bun apps/cli/scripts/build-binary.ts --target="$TARGET"

artifact="$repo_root/apps/cli/dist/$ARTIFACT_NAME"
if [ ! -f "$artifact" ]; then
	echo "Error: expected artifact not found at $artifact" >&2
	exit 1
fi

if ! file "$artifact" | grep -q "x86_64"; then
	echo "Error: $artifact is not an x86_64 executable" >&2
	file "$artifact" >&2
	exit 1
fi

chmod +x "$artifact"

echo
echo "Built Intel macOS launcher:"
echo "  $artifact"
file "$artifact"

echo "==> Revealing the artifact in Finder"
open -R "$artifact"
