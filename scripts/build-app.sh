#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="${0:A:h:h}"

swift build --package-path "$PROJECT_ROOT" -c release
BIN_PATH="$(swift build --package-path "$PROJECT_ROOT" -c release --show-bin-path)"

APP_PATH="$PROJECT_ROOT/build/PDFComicViewer.app"
mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
cp "$BIN_PATH/PDFComicViewer" "$APP_PATH/Contents/MacOS/PDFComicViewer"
cp "$PROJECT_ROOT/Resources/Info.plist" "$APP_PATH/Contents/Info.plist"

echo "$APP_PATH"
