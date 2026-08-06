#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="${0:A:h:h:h}"
INSTALLER="$PROJECT_ROOT/scripts/lib/install-app-bundle.sh"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/pdf-comic-installer-tests.XXXXXX")"
trap 'rm -rf -- "$TEST_ROOT"' EXIT

make_app() {
    local app_path="$1"
    local marker="$2"
    mkdir -p "$app_path/Contents/MacOS"
    print -r -- "$marker" > "$app_path/Contents/MacOS/PDFComicViewer"
}

APPLICATIONS_DIR="$TEST_ROOT/Applications"
SOURCE_APP="$TEST_ROOT/source/PDFComicViewer.app"
TARGET_APP="$APPLICATIONS_DIR/PDF漫画ビューアー.app"
mkdir -p "$APPLICATIONS_DIR" "${SOURCE_APP:h}"

make_app "$SOURCE_APP" "version-1"
"$INSTALLER" "$SOURCE_APP" "$TARGET_APP"
[[ "$(<"$TARGET_APP/Contents/MacOS/PDFComicViewer")" == "version-1" ]]

rm -rf -- "$SOURCE_APP"
make_app "$SOURCE_APP" "version-2"
"$INSTALLER" "$SOURCE_APP" "$TARGET_APP"
[[ "$(<"$TARGET_APP/Contents/MacOS/PDFComicViewer")" == "version-2" ]]

if "$INSTALLER" "$TEST_ROOT/missing.app" "$TARGET_APP"; then
    print -u2 -- "存在しないソースを受理しました"
    exit 1
fi
[[ "$(<"$TARGET_APP/Contents/MacOS/PDFComicViewer")" == "version-2" ]]

if "$INSTALLER" "$SOURCE_APP" "$TEST_ROOT/unsafe/PDF漫画ビューアー.app"; then
    print -u2 -- "Applications外への配置を受理しました"
    exit 1
fi
