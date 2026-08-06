# Local App Installation and Update Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 1コマンドでPDF漫画ビューアーをユーザー用Applicationsフォルダへ初回インストールまたは安全に更新し、READMEだけで利用方法が分かる状態にする。

**Architecture:** `scripts/install-app.sh` が既存のReleaseビルドを呼び、アプリ終了と再起動を管理する。実際のファイル置換は `scripts/lib/install-app-bundle.sh` に分離し、一時ディレクトリを使う統合テストで初回配置・更新・ステージング失敗時の既存版保全・対象パス拒否を検証する。

**Tech Stack:** zsh、macOS AppKitアプリバンドル、Swift Package Manager、XCTest、Git

## Global Constraints

- 利用者はこのMacの現在のユーザーのみとする。
- 正式なインストール先は `~/Applications/PDF漫画ビューアー.app` とする。
- Apple Developer Program、コード署名、公証、第三者への配布、自動更新フィードは対象外とする。
- `git pull` は自動化せず、現在のローカルソースをインストールする。
- 強制終了は行わず、通常終了しない場合は既存アプリを保持して更新を中止する。
- 未解決のglobや空の変数を削除・置換対象に使わない。

---

### Task 1: アプリバンドルの安全な配置・置換

**Files:**
- Create: `scripts/lib/install-app-bundle.sh`
- Create: `Tests/InstallAppScriptTests/install-app-bundle-tests.sh`

**Interfaces:**
- Consumes: 第1引数に存在する `.app` の絶対パス、第2引数に親ディレクトリ名が `Applications` かつファイル名が `PDF漫画ビューアー.app` の絶対パス
- Produces: `scripts/lib/install-app-bundle.sh <source-app> <destination-app>`。成功時0、入力不正・配置失敗時は非0を返す

- [ ] **Step 1: 初回配置・更新・ステージング失敗時の既存版保全・危険なパス拒否の失敗テストを書く**

`Tests/InstallAppScriptTests/install-app-bundle-tests.sh` を作成する。テスト用ルートは `mktemp -d` で作り、終了時にその明示パスだけを削除する。

```zsh
#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="${0:A:h:h:h}"
INSTALLER="$PROJECT_ROOT/scripts/lib/install-app-bundle.sh"
TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/pdf-comic-installer-tests.XXXXXX")"
trap 'rm -rf -- "$TEST_ROOT"' EXIT

make_app() {
    local path="$1"
    local marker="$2"
    mkdir -p "$path/Contents/MacOS"
    print -r -- "$marker" > "$path/Contents/MacOS/PDFComicViewer"
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
```

- [ ] **Step 2: テストを実行し、配置スクリプト未作成で失敗することを確認する**

Run: `zsh Tests/InstallAppScriptTests/install-app-bundle-tests.sh`

Expected: FAIL with `no such file or directory: scripts/lib/install-app-bundle.sh`

- [ ] **Step 3: 最小限の安全な配置スクリプトを実装する**

`scripts/lib/install-app-bundle.sh` は次の振る舞いを実装する。

```zsh
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
```

- [ ] **Step 4: 配置テストと構文検査を実行して成功を確認する**

Run: `zsh Tests/InstallAppScriptTests/install-app-bundle-tests.sh`

Expected: exit 0

Run: `zsh -n scripts/lib/install-app-bundle.sh Tests/InstallAppScriptTests/install-app-bundle-tests.sh`

Expected: exit 0

- [ ] **Step 5: 配置処理をコミットする**

```bash
git add scripts/lib/install-app-bundle.sh Tests/InstallAppScriptTests/install-app-bundle-tests.sh
git commit -m "feat: install app bundles safely"
```

### Task 2: 初回インストールと更新を行う1コマンド

**Files:**
- Create: `scripts/install-app.sh`

**Interfaces:**
- Consumes: `scripts/build-app.sh` が生成する `build/PDFComicViewer.app`、Task 1の `install-app-bundle.sh`
- Produces: 引数なしの `scripts/install-app.sh`。成功時に `~/Applications/PDF漫画ビューアー.app` を起動する

- [ ] **Step 1: ビルド・通常終了・有限待機・配置・再起動を実装する**

このファイルは既存のビルド、Task 1の配置処理、macOSの終了・起動コマンドだけを順に呼ぶ薄いオーケストレーションとする。テスト専用の分岐や環境変数は本番スクリプトへ追加せず、構文検査と実機での初回・更新確認を検証とする。

`scripts/install-app.sh` を作成する。

```zsh
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
```

- [ ] **Step 2: シェルテスト、構文検査、Swift全テストを実行する**

Run: `zsh Tests/InstallAppScriptTests/install-app-bundle-tests.sh`

Expected: exit 0

Run: `zsh -n scripts/install-app.sh scripts/build-app.sh`

Expected: exit 0

Run: `swift test`

Expected: 104 tests plus any newly discovered tests, 0 failures

- [ ] **Step 3: 実機の初回インストールを確認する**

Run: `scripts/install-app.sh`

Expected: Releaseビルド後に `~/Applications/PDF漫画ビューアー.app` が存在し、そのパスのアプリが起動する

- [ ] **Step 4: 同じコマンドによる更新を確認する**

Run: `scripts/install-app.sh`

Expected: 実行中アプリが通常終了し、同じインストール先へ更新されたアプリが起動する

- [ ] **Step 5: インストールコマンドをコミットする**

```bash
git add scripts/install-app.sh
git commit -m "feat: install and update the local app"
```

### Task 3: 利用者向けREADMEの再構成

**Files:**
- Modify: `README.md`

**Interfaces:**
- Consumes: Task 2の `scripts/install-app.sh` と既存の `scripts/build-app.sh`
- Produces: 初見の利用者がインストール・更新・操作・開発手順を判断できる日本語README

- [ ] **Step 1: READMEを利用者中心の順序へ書き換える**

次の見出しと内容を記載する。

```markdown
# PDF漫画ビューアー

PDF漫画をmacOSで1ページ表示・見開き表示して読むためのネイティブビューアーです。

## 主な特徴

- 右綴じ・左綴じ
- 1ページ・見開き表示の即時切り替え
- 横長ページの自動単独表示
- PDFごとのページ位置・表示設定の保存
- キーボード、クリック、ドラッグによる操作

## インストール

```sh
scripts/install-app.sh
```

`~/Applications/PDF漫画ビューアー.app` にインストールされ、自動的に起動します。

## 更新

ソースを更新した後、インストール時と同じコマンドを実行します。

```sh
scripts/install-app.sh
```
```

既存の必要環境・基本操作は内容を維持し、「開発者向け」の節へ `swift test`、`scripts/build-app.sh`、`build/PDFComicViewer.app` の説明をまとめる。未署名・未公証で個人利用向けであることを明記する。

- [ ] **Step 2: READMEのコマンドと実ファイルが一致することを確認する**

Run: `test -x scripts/install-app.sh && test -x scripts/build-app.sh && test -f README.md`

Expected: exit 0

- [ ] **Step 3: 最終検証を実行する**

Run: `zsh Tests/InstallAppScriptTests/install-app-bundle-tests.sh`

Expected: exit 0

Run: `swift test`

Expected: 0 failures

Run: `scripts/build-app.sh`

Expected: `build/PDFComicViewer.app` を出力してexit 0

Run: `git diff --check`

Expected: exit 0

- [ ] **Step 4: READMEをコミットする**

```bash
git add README.md
git commit -m "docs: explain local installation and updates"
```

### Task 4: GitHubへの公開

**Files:**
- No repository file changes

**Interfaces:**
- Consumes: cleanな `main`、有効なGitHub認証、設定済みの `origin`
- Produces: GitHub上の `main` にローカルコミットをpushした状態

- [ ] **Step 1: GitHub認証を復旧する**

Run: `gh auth login -h github.com`

Expected: `gh auth status` がアカウント `srkppa` を有効と表示する

- [ ] **Step 2: push先を確認または設定する**

Run: `git remote -v`

Expected: `origin` が `srkppa/pdfComicViewer` を指す。未設定なら、認証方式に合わせて次のいずれかを設定する。

```bash
git remote add origin https://github.com/srkppa/pdfComicViewer.git
```

```bash
git remote add origin git@github.com:srkppa/pdfComicViewer.git
```

- [ ] **Step 3: mainをpushする**

Run: `git push -u origin main`

Expected: `main -> main` と表示され、upstreamが `origin/main` に設定される
