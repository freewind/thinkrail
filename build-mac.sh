#!/usr/bin/env bash
# Build the Intel (x86_64) macOS ThinkRail desktop app.
#
# Electrobun publishes no macOS x64 core, so `apps/desktop` cannot be packaged for an
# Intel Mac. This script produces the Intel desktop app instead: the CLI single-file
# launcher (the same `thinkrail` executable `install.sh` fetches on the other platforms)
# shipped as a sidecar of the Tauri shell in `macos-intel-app/`, so the app opens its own
# window with a normal macOS menu bar instead of a browser tab.
#
# Usage: ./build-mac.sh   (from anywhere; the app bundle is revealed in Finder at the end)

set -euo pipefail

TARGET="bun-darwin-x64"
RUST_TARGET="x86_64-apple-darwin"
ENGINE_NAME="thinkrail-${TARGET#bun-}"

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$repo_root"

app_dir="$repo_root/macos-intel-app"
src_tauri="$app_dir/src-tauri"
engine_path="$repo_root/apps/cli/dist/$ENGINE_NAME"
sidecar_path="$src_tauri/binaries/thinkrail-$RUST_TARGET"
bundle_path="$src_tauri/target/$RUST_TARGET/release/bundle/macos/ThinkRail.app"

fail() {
	echo "Error: $*" >&2
	exit 1
}

require_x86_64() {
	file "$1" | grep -q "x86_64" || fail "$1 is not an x86_64 executable"
}

echo "==> Installing dependencies"
bun install

echo "==> Building the web UI"
bun run build:web

echo "==> Compiling the ThinkRail engine (--target=$TARGET)"
bun apps/cli/scripts/build-binary.ts --target="$TARGET"
[ -f "$engine_path" ] || fail "expected the engine at $engine_path"
require_x86_64 "$engine_path"
chmod +x "$engine_path"

echo "==> Staging the engine as the shell's sidecar"
mkdir -p "$src_tauri/binaries"
cp "$engine_path" "$sidecar_path"
chmod +x "$sidecar_path"

echo "==> Installing the Tauri shell dependencies"
(cd "$app_dir" && bun install)

echo "==> Building ThinkRail.app (Tauri, $RUST_TARGET)"
(cd "$app_dir" && bun x tauri build --target "$RUST_TARGET" --bundles app)
[ -d "$bundle_path" ] || fail "expected the app bundle at $bundle_path"

require_x86_64 "$bundle_path/Contents/MacOS/ThinkRail"
require_x86_64 "$bundle_path/Contents/MacOS/thinkrail"
[ -f "$bundle_path/Contents/Resources/icon.icns" ] || fail "the bundle carries no app icon"

echo
echo "Built Intel macOS desktop app:"
echo "  $bundle_path"

echo "==> Revealing the app in Finder"
open -R "$bundle_path"
