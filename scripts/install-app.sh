#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="${0:A:h:h}"
SOURCE_APP="$PROJECT_ROOT/build/PDFComicViewer.app"
USER_APPLICATIONS_DIR="$HOME/Applications"
DESTINATION_APP="$USER_APPLICATIONS_DIR/PDF漫画ビューアー.app"
BUNDLE_ID="com.srkppa.PDFComicViewer"

"$PROJECT_ROOT/scripts/build-app.sh"

if pgrep -x PDFComicViewer > /dev/null; then
    osascript -e "tell application id \"$BUNDLE_ID\" to quit"
    for attempt in {1..50}; do
        pgrep -x PDFComicViewer > /dev/null || break
        sleep 0.2
    done
    if pgrep -x PDFComicViewer > /dev/null; then
        print -u2 -- "PDF漫画ビューアーを終了できなかったため、更新を中止しました。"
        exit 1
    fi
fi

"$PROJECT_ROOT/scripts/lib/install-app-bundle.sh" "$SOURCE_APP" "$DESTINATION_APP"
open "$DESTINATION_APP"
print -r -- "インストールしました: $DESTINATION_APP"
