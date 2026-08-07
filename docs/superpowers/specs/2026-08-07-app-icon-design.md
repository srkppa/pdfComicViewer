# PDF漫画ビューアー アプリアイコン設計

## 目的

`build/PDFComicViewer.app` に固有のアプリアイコンがなく、macOSの汎用実行ファイルアイコンで表示されている。アプリの内容（PDFを漫画のように読むビューアー）が一目で伝わる絵柄のアイコンを追加する。

## 対象範囲

- macOS用の `.icns` アイコンを新規作成し、アプリバンドルに組み込む。
- Dock・Finder・アプリ切り替え(⌘Tab)での表示を対象とする。
- コード署名・公証は対象外（既存の運用を踏襲）。
- アイコンの元データはこのリポジトリ内で再生成可能なスクリプトとして管理する（バイナリの絵だけを一方的に追加しない）。

## ビジュアルデザイン

- **形状**: macOSネイティブ風の角丸スクエア。1024×1024キャンバス中央に、余白を持たせた角丸スクエアの絵柄を配置する。
- **背景**: オレンジ→赤の斜めグラデーション。
- **モチーフ**: 中央に開いた本（クリーム色/白）。本の右上に小さな吹き出しを重ね、「PDFを漫画のように読む」ことを示す。
- **視認性**: Dockの小さいサイズ（16〜32px）でもシルエットで「本」と分かるよう、細部を減らした単純な形状にする。

## 生成方法

新しい `scripts/generate-icon.py`（Pillowを使用）を追加し、次の手順でアイコンを作る。

1. `scripts/generate-icon.py` が1024×1024の `AppIcon-1024.png` をプログラム的に描画する（背景グラデーション、角丸マスク、本と吹き出しの図形）。
2. `sips` で1024pxのマスターから、`.iconset` に必要な各サイズ（16, 32, 64, 128, 256, 512, 1024の@1x/@2x）を書き出す。
3. `iconutil -c icns` で `.iconset` から `Resources/AppIcon.icns` を生成する。

この一連の処理は `scripts/generate-icon.py` 実行後にシェルコマンドで行う手動フローとし、`build-app.sh` の通常ビルドフローには含めない（アイコンの絵柄変更は頻繁ではないため、`.icns` は生成物としてリポジトリにコミットする）。

## アプリバンドルへの組み込み

- `Resources/Info.plist` に `CFBundleIconFile` キー（値 `AppIcon`）を追加する。
- `scripts/build-app.sh` の中で、`Resources/AppIcon.icns` を `Contents/Resources/AppIcon.icns` へコピーする処理を追加する。

## テスト・検証

- `scripts/generate-icon.py` 実行後、生成した `AppIcon-1024.png` を目視確認する。
- `scripts/build-app.sh` を実行し、`build/PDFComicViewer.app/Contents/Resources/AppIcon.icns` が存在することを確認する。
- Finderでビルド済み `.app` のアイコンが更新されていることを確認する（Finderのアイコンキャッシュにより反映が遅れる場合がある点に留意）。

## 完了条件

- `scripts/generate-icon.py` を実行すればアイコン画像一式を再生成できる。
- `Resources/AppIcon.icns` がアプリバンドルの `Contents/Resources/` に含まれる。
- `Info.plist` の `CFBundleIconFile` がアイコンを正しく参照している。
- Dock/Finder上でPDF漫画ビューアー固有のアイコンが表示される。
