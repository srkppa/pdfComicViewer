#!/bin/zsh
set -euo pipefail

SOURCE_APP="${1:-}"
DESTINATION_APP="${2:-}"

[[ -n "$SOURCE_APP" && -n "$DESTINATION_APP" ]] || {
    print -u2 -- "使い方: $0 <source-app> <destination-app>"
    exit 64
}
[[ "$SOURCE_APP" = /* && -d "$SOURCE_APP/Contents" ]] || {
    print -u2 -- "有効なアプリバンドルではありません: $SOURCE_APP"
    exit 66
}
[[ "$DESTINATION_APP" = /*
    && "${DESTINATION_APP:t}" == "PDF漫画ビューアー.app"
    && "${DESTINATION_APP:h:t}" == "Applications" ]] || {
    print -u2 -- "安全でないインストール先を拒否しました: $DESTINATION_APP"
    exit 64
}

APPLICATIONS_DIR="${DESTINATION_APP:h}"
mkdir -p "$APPLICATIONS_DIR"
STAGING_ROOT="$(mktemp -d "$APPLICATIONS_DIR/.PDFComicViewer.install.XXXXXX")"
STAGED_APP="$STAGING_ROOT/PDF漫画ビューアー.app"
BACKUP_APP="$STAGING_ROOT/previous.app"
RESTORE_REQUIRED=false

restore_previous_app() {
    if [[ "$RESTORE_REQUIRED" == true && -d "$BACKUP_APP" && ! -e "$DESTINATION_APP" ]]; then
        mv "$BACKUP_APP" "$DESTINATION_APP"
    fi
    rm -rf -- "$STAGING_ROOT"
}
trap restore_previous_app EXIT

ditto "$SOURCE_APP" "$STAGED_APP"
if [[ -e "$DESTINATION_APP" ]]; then
    mv "$DESTINATION_APP" "$BACKUP_APP"
    RESTORE_REQUIRED=true
fi
mv "$STAGED_APP" "$DESTINATION_APP"
RESTORE_REQUIRED=false
rm -rf -- "$STAGING_ROOT"
trap - EXIT
