# Cloud Coding Agent Setup Scripts

Claude Code on the web / Cursor Cloud Agent / Devin など、クラウド上で動くコーディング
エージェントの環境設定（セットアップスクリプト）に差し込む、サービスごとのセットアップ
スクリプト集。

## 使い方

1. `scripts/` から使いたいサービスのスクリプトを選ぶ（例: `scripts/chunk.sh`）。
2. その内容を利用中のエージェント環境のセットアップスクリプト欄（Claude Code on the web
   の「セットアップスクリプト」など）に貼り付ける。

## 収録スクリプト

- `scripts/chunk.sh`: CircleCI MCP サーバー用 CLI（chunk-cli）のインストール

詳細なリポジトリ方針・スクリプト追加時のルールは [AGENT.md](./AGENT.md) を参照。
