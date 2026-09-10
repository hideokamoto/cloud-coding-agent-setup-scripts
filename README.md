# claude-code-web-setups

Claude Code on the web の環境設定にある「セットアップスクリプト」に差し込む、
サービスごとのセットアップスクリプト集。

## 使い方

1. `scripts/` から使いたいサービスのスクリプトを選ぶ（例: `scripts/chunk.sh`）。
2. その内容を Claude Code on the web の環境設定 →「セットアップスクリプト」欄に貼り付ける。

## 収録スクリプト

- `scripts/chunk.sh`: CircleCI MCP サーバー用 CLI（chunk-cli）のインストール

詳細なリポジトリ方針・スクリプト追加時のルールは [AGENT.md](./AGENT.md) を参照。
