# Changelog

## Unreleased

- `scripts/chunk.sh`: `chunk sidecar sync` の準備を失敗しにくくした
  - rsync / openssh-client を1つずつ導入する（まとめて導入すると、古いパッケージリストで openssh-client が 404 になるだけで両方とも入らなかった）
  - 導入に失敗しても鍵の準備まで進め、失敗は最後にまとめて報告して exit 1 する
  - SSH 鍵を OpenSSH 形式で用意する。`ssh-keygen` が無ければ python3 の cryptography で作る。既存の鍵が PKCS#8（chunk が自分で作る形式。OpenSSH 9.6 は読めない）なら、退避してから OpenSSH 形式に変換する
  - `chunk skill install` を sync の準備の後に回し、失敗しても準備が済むようにした
- `scripts/chunk.sh`: CircleCI MCP サーバー用 CLI（chunk-cli）のインストール・初期設定スクリプトを追加
- `AGENT.md`（`CLAUDE.md` の実体）でリポジトリの目的・構成・スクリプト追加時の規約を定義
- README にタグ固定での利用方法・スクリプト一覧・バージョニング方針を整理
