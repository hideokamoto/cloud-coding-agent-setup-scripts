# claude-code-web-setups

Claude Code on the web / Cursor Cloud Agent / Devin など、クラウド上で動くコーディング
エージェントの環境設定（セットアップスクリプト）に差し込む、サービスごとのセットアップ
スクリプト集です。

## 使い方

`scripts/` から使いたいサービスのスクリプトを選び、`<tag>` を固定した上で
`curl | bash` の形でエージェント環境のセットアップスクリプト欄に貼り付けるか、
その内容をそのまま貼り付けてください。

```bash
curl -fsSL https://raw.githubusercontent.com/hideokamoto/cloud-coding-agent-setup-scripts/<tag>/scripts/chunk.sh | bash
```

`<tag>` は必ず `vX.Y.Z` 形式の特定のタグに固定してください（まだタグは発行されていません。最新タグは
[Releases](https://github.com/hideokamoto/cloud-coding-agent-setup-scripts/releases) を参照してください）。
`main` など可変参照を使うと、
このコマンドはセッション開始のたびに実行される性質上、後から中身が書き換わっても気づかず
実行してしまいます。タグ固定なら同じ内容が常に取得されるため、この心配はありません。

## 収録スクリプト

| スクリプト | 何をするか | コマンド |
| --- | --- | --- |
| `scripts/chunk.sh` | chunk-cli の最新版インストール、および `chunk sidecar sync` に必要な openssh-client / rsync の導入とSSH鍵の事前生成 | `curl -fsSL https://raw.githubusercontent.com/hideokamoto/cloud-coding-agent-setup-scripts/<tag>/scripts/chunk.sh \| bash` |
| `scripts/aidlc.sh` | AI-DLC (awslabs/aidlc-workflows) のインストールと `.aidlc-version` に基づくバージョンpin。root環境では非rootユーザーへの委譲も行う。事前にプロジェクトルートへ `.aidlc-version`（pinするバージョン、例 `2.9.0`）を用意しておくこと。harnessは `claude`/`kiro`/`cursor` から環境変数 `AIDLC_HARNESS` で選択（未指定時は `claude`） | `curl -fsSL https://raw.githubusercontent.com/hideokamoto/cloud-coding-agent-setup-scripts/<tag>/scripts/aidlc.sh \| bash` |

最新タグは [Releases](https://github.com/hideokamoto/cloud-coding-agent-setup-scripts/releases) を参照してください。

## 複数のツールをまとめて使いたい場合

セットアップスクリプト欄に、必要な `curl | bash` の行を改行して並べるだけで構いません。
各スクリプトは独立して完結しているため、手元で中身を結合する必要はありません。

```bash
curl -fsSL https://raw.githubusercontent.com/hideokamoto/cloud-coding-agent-setup-scripts/<tag>/scripts/chunk.sh | bash
curl -fsSL https://raw.githubusercontent.com/hideokamoto/cloud-coding-agent-setup-scripts/<tag>/scripts/another-tool.sh | bash
```

## バージョニング

- 各スクリプトの変更は `vX.Y.Z` のタグで管理します。
- 破壊的な変更（インストールされるバイナリやパスが変わる等）はメジャーバージョンを上げます。
- 変更履歴は [CHANGELOG.md](./CHANGELOG.md) を参照してください。

詳細なリポジトリ方針・スクリプト追加時のルールは [AGENT.md](./AGENT.md) を参照。

## ライセンス

[GPL-3.0](./LICENSE)
