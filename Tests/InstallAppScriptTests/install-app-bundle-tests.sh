#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="${0:A:h:h:h}"
INSTALLER="${INSTALLER_UNDER_TEST:-$PROJECT_ROOT/scripts/lib/install-app-bundle.sh}"
INSTALL_PATH_LIB="$PROJECT_ROOT/scripts/lib/install-path.sh"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/pdf-comic-installer-tests.XXXXXX")"
trap 'rm -rf -- "$TEST_ROOT"' EXIT

make_app() {
    local app_path="$1"
    local marker="$2"
    mkdir -p "$app_path/Contents/MacOS"
    print -r -- "$marker" > "$app_path/Contents/MacOS/PDFComicViewer"
}

fail() {
    print -u2 -- "$1"
    exit 1
}

source "$INSTALL_PATH_LIB"

EXPECTED_USER_APP="$HOME/Applications/PDF漫画ビューアー.app"
[[ "$(validated_install_destination "$HOME" "$EXPECTED_USER_APP")" == "$EXPECTED_USER_APP" ]] || {
    fail "現在のHOMEに対する正規のインストール先を拒否しました"
}
for invalid_home in "" "/" "relative/home"; do
    if validated_install_destination "$invalid_home" "$EXPECTED_USER_APP" > /dev/null 2>&1; then
        fail "安全でないHOMEを受理しました: ${invalid_home:-<empty>}"
    fi
done
if validated_install_destination "$HOME" "$TEST_ROOT/Applications/PDF漫画ビューアー.app" > /dev/null 2>&1; then
    fail "HOMEと一致しないインストール先を受理しました"
fi

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

if "$INSTALLER" "$TEST_ROOT/missing.app" "$TARGET_APP" 2> /dev/null; then
    print -u2 -- "存在しないソースを受理しました"
    exit 1
fi
[[ "$(<"$TARGET_APP/Contents/MacOS/PDFComicViewer")" == "version-2" ]]

if "$INSTALLER" "$SOURCE_APP" "$TEST_ROOT/unsafe/PDF漫画ビューアー.app" 2> /dev/null; then
    print -u2 -- "Applications外への配置を受理しました"
    exit 1
fi

SOURCE_WITHOUT_APP_EXTENSION="$TEST_ROOT/source/PDFComicViewer"
make_app "$SOURCE_WITHOUT_APP_EXTENSION" "invalid-source"
if "$INSTALLER" "$SOURCE_WITHOUT_APP_EXTENSION" "$TARGET_APP" 2> /dev/null; then
    fail ".app拡張子のないソースを受理しました"
fi
[[ "$(<"$TARGET_APP/Contents/MacOS/PDFComicViewer")" == "version-2" ]] || {
    fail "不正なソースの拒否時に既存アプリを変更しました"
}

FAIL_DITTO_DIR="$TEST_ROOT/fail-ditto-bin"
FAIL_DITTO_CALL="$TEST_ROOT/fail-ditto.call"
mkdir -p "$FAIL_DITTO_DIR"
cat > "$FAIL_DITTO_DIR/ditto" <<'SHIM'
#!/bin/zsh
print -r -- "$1" > "$DITTO_CALL_LOG"
print -r -- "$2" >> "$DITTO_CALL_LOG"
exit 73
SHIM
chmod +x "$FAIL_DITTO_DIR/ditto"
if PATH="$FAIL_DITTO_DIR:$PATH" DITTO_CALL_LOG="$FAIL_DITTO_CALL" \
    "$INSTALLER" "$SOURCE_APP" "$TARGET_APP"; then
    fail "コピー失敗時に成功しました"
fi
[[ "$(sed -n '1p' "$FAIL_DITTO_CALL")" == "$SOURCE_APP" ]] || {
    fail "有効なソースからのコピーを試行しませんでした"
}
[[ "$(sed -n '2p' "$FAIL_DITTO_CALL")" == "$APPLICATIONS_DIR"/.PDFComicViewer.install.*/PDF漫画ビューアー.app ]] || {
    fail "専用staging先へのコピーを試行しませんでした"
}
[[ -f "$TARGET_APP/Contents/MacOS/PDFComicViewer" \
    && "$(<"$TARGET_APP/Contents/MacOS/PDFComicViewer")" == "version-2" ]] || {
    fail "コピー失敗時に既存アプリを保持しませんでした"
}

rm -rf -- "$TARGET_APP"
mkdir -p "$TARGET_APP"
print -r -- "not-an-app" > "$TARGET_APP/marker"
if "$INSTALLER" "$SOURCE_APP" "$TARGET_APP" 2> /dev/null; then
    fail "有効なapp bundleではない既存インストール先を受理しました"
fi
[[ "$(<"$TARGET_APP/marker")" == "not-an-app" ]] || {
    fail "不正な既存インストール先を変更しました"
}

rm -rf -- "$TARGET_APP"
make_app "$TARGET_APP" "version-2"
FAIL_MV_DIR="$TEST_ROOT/fail-activation-bin"
FAIL_MV_STDERR="$TEST_ROOT/fail-activation.stderr"
REAL_MV="$(command -v mv)"
mkdir -p "$FAIL_MV_DIR"
cat > "$FAIL_MV_DIR/mv" <<'SHIM'
#!/bin/zsh
if [[ "$1" == ${~FAIL_ACTIVATION_SOURCE} && "$2" == "$FAIL_ACTIVATION_DESTINATION" ]]; then
    mkdir -p "$2"
    exit 74
fi
exec "$REAL_MV" "$@"
SHIM
chmod +x "$FAIL_MV_DIR/mv"

STAGING_PATTERN="$APPLICATIONS_DIR/.PDFComicViewer.install.*/PDF漫画ビューアー.app"
if PATH="$FAIL_MV_DIR:$PATH" \
    REAL_MV="$REAL_MV" \
    FAIL_ACTIVATION_SOURCE="$STAGING_PATTERN" \
    FAIL_ACTIVATION_DESTINATION="$TARGET_APP" \
    "$INSTALLER" "$SOURCE_APP" "$TARGET_APP" 2> "$FAIL_MV_STDERR"; then
    fail "activation失敗時に成功しました"
fi

BACKUP_APPS=("$APPLICATIONS_DIR"/.PDFComicViewer.install.*/previous.app(N))
(( ${#BACKUP_APPS} == 1 )) || fail "復元不能時のバックアップが保持されませんでした"
BACKUP_APP="${BACKUP_APPS[1]}"
[[ "$(<"$BACKUP_APP/Contents/MacOS/PDFComicViewer")" == "version-2" ]] || {
    fail "保持されたバックアップの内容が既存版と一致しません"
}
grep -F -- "$BACKUP_APP" "$FAIL_MV_STDERR" > /dev/null || {
    fail "復旧用バックアップの具体的なパスがstderrにありません"
}
