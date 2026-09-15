#!/bin/bash
set -euo pipefail

# AI-DLC (awslabs/aidlc-workflows) のインストール・プロジェクト設定
# https://github.com/awslabs/aidlc-workflows
#
# 対応harness: claude / kiro / cursor
#   環境変数 AIDLC_HARNESS で選択(未指定時は claude)。
#   --harness を明示しないと `aidlc config` が対話セットアップに入ってしまうため必須。
#
# バージョンは呼び出し元プロジェクトルートの .aidlc-version でpinする
# (例: echo "2.9.0" > .aidlc-version)。

REPO="awslabs/aidlc-workflows"
HARNESS="${AIDLC_HARNESS:-claude}"

case "$HARNESS" in
  claude|kiro|cursor) ;;
  *)
    echo "AIDLC_HARNESS must be one of: claude, kiro, cursor (got: ${HARNESS})" >&2
    exit 1
    ;;
esac

if [ ! -f .aidlc-version ]; then
  echo ".aidlc-version が見つかりません。プロジェクトルートにpinするバージョン(例: 2.9.0)を書いたファイルを用意してください。" >&2
  exit 1
fi
AIDLC_PIN="$(tr -d '[:space:]' < .aidlc-version)"

export PATH="$HOME/.local/bin:$PATH"
grep -q '.local/bin' "$HOME/.bashrc" 2>/dev/null || echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"

# 1. インストール(導入済みでバージョンが一致していればスキップ)
if ! command -v aidlc >/dev/null 2>&1 || \
   [ "$(aidlc --version 2>/dev/null | tr -dc '0-9.')" != "$AIDLC_PIN" ]; then
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  curl -fsSL "https://github.com/${REPO}/releases/download/v${AIDLC_PIN}/install.sh" \
    -o "$tmp/install.sh"
  sh "$tmp/install.sh" --version "$AIDLC_PIN" --yes
fi

# 2. 確認
aidlc --version

# 3. プロジェクト設定(harnessを明示して非対話で実行)
aidlc config --harness "$HARNESS" --project-dir "$(pwd)"
