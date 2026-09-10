# claude-code-web-setups

Claude Code on the web の環境設定画面にある「セットアップスクリプト」に差し込むための、
サービスごとのセットアップスクリプト集。

## 目的

Claude Code on the web は、セッション用コンテナ起動時に「セットアップスクリプト」を
一度だけ実行できる。ここには、MCPサーバーやCLIなど外部サービスを使うために必要な
インストール・初期設定処理を、サービス単位のシェルスクリプトとして置く。

利用側は `scripts/` 配下から使いたいサービスのスクリプトを選び、その内容を
Claude Code on the web の「セットアップスクリプト」欄に貼り付けるか、
そこから `curl` 等で取得して実行する。

## リポジトリ構成

```
scripts/
  chunk.sh   # CircleCI MCP (chunk-cli) のインストール・初期設定
```

- 現時点では CircleCI 用の `chunk.sh` のみ。
- 今後サービスを追加する場合は、サービスごとに1スクリプトを基本とする
  （サービスの手順が複数ファイルに分かれる場合は `scripts/<service>/` の
  サブディレクトリを切る）。

## スクリプト追加時の規約

- ファイル先頭は `#!/bin/bash` + `set -euo pipefail`。
- 冪等性を意識する。既にインストール済み・設定済みなら重い処理
  （`apt-get update` など）はスキップする（`chunk.sh` の rsync/ssh-keygen 部分を参照）。
- インストール後は簡単な動作確認コマンド（`--version` など）を実行し、
  成功したことがログでわかるようにする。
- 認証情報やトークンをスクリプトに埋め込まない。必要な環境変数は
  Claude Code on the web の環境変数設定側で渡す前提とする。

## CLAUDE.md について

`CLAUDE.md` はこのファイル（`AGENT.md`）への symlink。内容の実体は本ファイルに集約し、
二重管理を避ける。
