#!/bin/bash
# Sync prebuilt yaml-cpp (lib + include) into controller_component/3rdparty.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

detect_arch() {
    case "$(uname -m)" in
        x86_64|amd64) echo x86_64 ;;
        aarch64|arm64) echo aarch64 ;;
        *) echo "$(uname -m)" ;;
    esac
}

ARCH="$(detect_arch)"
SRC="$SCRIPT_DIR/install/$ARCH/yaml-cpp"
DEST="$ROOT_DIR/inexus/components/controller_component/3rdparty/yaml-cpp"

if [ ! -f "$SRC/lib/libyaml-cpp.a" ]; then
    echo "missing $SRC/lib/libyaml-cpp.a; run: ./build.sh build --only yaml-cpp" >&2
    exit 1
fi

rm -rf "$DEST"
mkdir -p "$(dirname "$DEST")"
cp -a "$SRC" "$DEST"
echo "staged yaml-cpp ($ARCH) -> $DEST"
