# tests

`scripts/` 配下のセットアップスクリプトが壊れていないかを検査するためのもの。

## なぜ専用の検査が必要か

クラウドエージェント（Claude Code on the web など）のセットアップスクリプトには、
次の性質がある（Claude Code の公式ドキュメント
[Configure cloud environments](https://code.claude.com/docs/en/cloud-environments) で確認）。

- 0 以外で終了すると、その環境のセッションが起動しない
- 結果はファイルシステムのスナップショットとしてキャッシュされ、再実行されるのは
  スクリプトや許可ホストを変更したときか、キャッシュの期限（約7日）が切れたときだけ

そのため、upstream（chunk-cli の最新リリースなど）や実行環境の変化でスクリプトが
壊れても、キャッシュが作り直されて作業しようとしたその場でセッションが起動しなくなる
まで気づけず、そのときログも手元に残らない。

`selftest.sh` はスクリプトをセットアップスクリプトとしてではなく、セッション内の通常の
コマンドとして実行する。スクリプトが壊れていても検査側のセッションは落ちず、
どのスクリプトのどのコマンドが何のエラーで落ちたかを報告できる。

## selftest.sh

```bash
bash tests/selftest.sh            # scripts/ 配下の *.sh をすべて検査
bash tests/selftest.sh <dir>      # 任意のディレクトリを検査
```

使い捨ての git ディレクトリを作って `.aidlc-version` を置き、各スクリプトを
`bash -x` で実行する。出力はスクリプトごとに1行の `PASS` / `FAIL` と、失敗時は
落ちる直前のコマンドとエラー出力のみ。1本でも失敗すれば終了コード 1。

出力例（2026-10-01 に Claude Code on the web のセッション内で実行した実際の出力）:

```
PASS aidlc.sh
FAIL chunk.sh (exit 22)
  trace: ++ curl -fsS -o /dev/null -w '%{redirect_url}' https://github.com/CircleCI-Public/chunk-cli/releases/latest
  trace: + LATEST_URL=
  curl: (22) The requested URL returned error: 403
```

| 環境変数 | 用途 | 既定値 |
| --- | --- | --- |
| `AIDLC_TEST_VERSION` | `aidlc.sh` 検査時に `.aidlc-version` へ書くバージョン。実際に使うプロジェクトのpinに合わせる | `2.9.0` |

注意: スクリプトを実際にインストールまで実行するため、`/usr/local/bin` への配置や
`apt-get install` などシステムへの変更を伴う。使い捨てのコンテナ（クラウドセッション）
で実行すること。

## Claude Code の Routine で週1回実行する

### 1. 監視専用の環境を作る

[claude.ai/code](https://claude.ai/code) の環境設定で、新しいクラウド環境を作る。

- **Setup script**: 空にする。ここに `chunk.sh` などを入れると、スクリプトが壊れた
  ときに検査用のセッションごと起動しなくなり、検査の意味がなくなる
- **Network access**: 普段スクリプトを使っている環境と同じレベルにする（既定は Trusted）

### 2. Routine を作る

[claude.ai/code/routines](https://claude.ai/code/routines) の **New routine**、または
ローカルの Claude Code CLI で `/schedule` を実行して作る
（手順の詳細は公式ドキュメント [Routines](https://code.claude.com/docs/en/routines)）。

- **Repository**: `hideokamoto/cloud-coding-agent-setup-scripts`
- **Environment**: 手順1で作った監視専用の環境
- **Trigger**: Schedule → Weekly。時刻はちょうど0分を避ける（公式ドキュメントに
  「0分ちょうどだと数分遅れることがある」とある）
- **Connectors**: 不要なものは外す（既定で全コネクタが含まれ、実行中は確認なしで使われる）

### 3. Routine に設定するプロンプト例

結果を報告するだけのもの:

```text
このリポジトリのセットアップスクリプトの定期検査です。

1. リポジトリのルートで `bash tests/selftest.sh` を実行してください。
2. 出力を加工せずそのままコードブロックで報告し、最後に終了コードを書いてください。
3. スクリプトの修正、ブランチの作成、プルリクエストの作成は一切しないでください。
4. FAIL があった場合のみ、失敗したスクリプト名と、出力のエラー行から読み取れる
   原因を1〜2文で添えてください。推測の場合は推測と明記してください。
```

結果を GitHub の Issue に残すもの（実行履歴を Routine の外に残したい場合）。
事前に記録用の Issue を1つ作り、`<ISSUE_NUMBER>` を置き換える:

```text
このリポジトリのセットアップスクリプトの定期検査です。

1. リポジトリのルートで `bash tests/selftest.sh` を実行してください。
2. hideokamoto/cloud-coding-agent-setup-scripts の Issue #<ISSUE_NUMBER> に、
   実行日時（UTC）、終了コード、出力全文（コードブロック）をコメントしてください。
   全件 PASS の回もコメントしてください（コメントが途絶えたら検査自体が
   止まっていると判断するため）。
3. スクリプトの修正、ブランチの作成、プルリクエストの作成は一切しないでください。
```

### 4. 動作確認

作成後、Routine の詳細ページの **Run now** で一度実行し、報告（または Issue コメント）
に `selftest.sh` の出力が載ることを確認する。

公式ドキュメントにある通り、Routine の実行一覧の緑ステータスは「セッションが
インフラエラーなく起動・終了した」ことしか意味しない。検査結果は実行のセッション
（トランスクリプト）か、上記の Issue コメントで確認すること。

## この検査で再現できないこと

- **GitHub 以外の通信経路**: 公式ドキュメントによると、セットアップスクリプトの
  実行中は Claude Code のエージェント用プロキシに接続していない（接続は Claude Code
  起動時でセットアップの後）。セッション内で実行するこの検査はそのプロキシを通るため、
  GitHub 以外への通信はセットアップ実行時と条件が異なりうる。
  GitHub への通信は、紐づいていないリポジトリのリリース取得が 403 になる制限が
  セットアップスクリプトにも適用されると明記されており、同じ条件で検査できる
- **Cursor Cloud Agent / Devin など他のプラットフォーム**: 検査対象外
