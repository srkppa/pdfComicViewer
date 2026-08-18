# PDF漫画ビューアー 開発メモ

macOS向けのネイティブSwiftUIアプリ。Swift 6（strict concurrency）。

## 操作を追加するときは3点セット

読書操作を1つ追加するなら、次の3つを**必ず同時に**用意する。ショートカットだけ実装して報告しない。

1. **キーボードショートカット** — `ReaderInputMonitor` の `ReaderKey` / `ReaderInputMapping.action`、`ReaderView.handleInput`
2. **ツールバーのボタン** — `ReaderToolbar` の `iconButton` と `FocusedReaderControl` へのcase追加。マウスだけで完結できることを重視している
3. **READMEの「基本操作」への追記**

サイドバー上のファイルに対する操作なら、右クリックメニュー（`DirectorySidebarView.contextMenuItems`）にも入れる。

## 設計方針

- 判断ロジックは純粋な型（`SpreadBuilder`、`SeekBarPresentation`、`ReaderInputMapping` など）に切り出してテストする。SwiftUIのView本体はテストしない
- そのため、Viewに条件式を直接書かず、テストできる関数として外に出してから呼ぶ
- 設計はまず `docs/superpowers/specs/` に仕様書を書き、`docs/superpowers/plans/` に実装計画を置いてから着手する

## 書き方

- **コード内のコメントとドキュメントコメントは日本語**。「なぜそうしたか」を書く。何をしているかの言い換えは書かない
- **コミットメッセージは英語**。件名は命令形。本文では、その変更が必要になった理由（どういう条件で何が壊れていたか）を説明する
- ユーザーへの応答は日本語

## 確認の手順

```sh
swift test                                        # Swiftのテスト
zsh Tests/InstallAppScriptTests/install-app-bundle-tests.sh
scripts/install-app.sh                            # Releaseビルド→~/Applicationsへ配置→起動
```

GUIの自動操作はできないため、実機確認はユーザーに依頼する。**依頼する前に何を確かめてほしいかを箇条書きで示す。**

コミットは `main` に直接。pushは都度ユーザーの確認を取る。
