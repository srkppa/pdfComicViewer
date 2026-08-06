#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="${0:A:h:h}"

swift build --package-path "$PROJECT_ROOT" -c release
BIN_PATH="$(swift build --package-path "$PROJECT_ROOT" -c release --show-bin-path)"

BUILD_ROOT="$PROJECT_ROOT/build"
APP_PATH="$BUILD_ROOT/PDFComicViewer.app"
mkdir -p "$BUILD_ROOT"

STAGING_ROOT="$(mktemp -d "$BUILD_ROOT/.PDFComicViewer.XXXXXX")"
trap 'rm -rf -- "$STAGING_ROOT"' EXIT
STAGED_APP_PATH="$STAGING_ROOT/PDFComicViewer.app"

mkdir -p "$STAGED_APP_PATH/Contents/MacOS" "$STAGED_APP_PATH/Contents/Resources"
cp "$BIN_PATH/PDFComicViewer" "$STAGED_APP_PATH/Contents/MacOS/PDFComicViewer"
cp "$PROJECT_ROOT/Resources/Info.plist" "$STAGED_APP_PATH/Contents/Info.plist"

if [[ "$APP_PATH" != "$PROJECT_ROOT/build/PDFComicViewer.app" ]]; then
    echo "安全でない出力先を拒否しました: $APP_PATH" >&2
    exit 1
fi
rm -rf -- "$APP_PATH"
mv "$STAGED_APP_PATH" "$APP_PATH"

echo "$APP_PATH"
