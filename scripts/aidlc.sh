#!/bin/bash
set -euo pipefail

# AI-DLC (awslabs/aidlc-workflows) のインストール・プロジェクト設定
# https://github.com/awslabs/aidlc-workflows
#
# 対応harness: claude / kiro / cursor
#   環境変数 AIDLC_HARNESS で選択(未指定時は claude)。
#
# バージョンは呼び出し元プロジェクトルートの .aidlc-version でpinする
# (例: echo "2.9.0" > .aidlc-version)。
#
# 注意: upstream install.sh は root 実行を拒否する
#   ( releases/*/install.sh に `[ "$(id -u)" -ne 0 ] || fail 4 ... "refusing a
#     root install; run as the target user"` があることを実機で確認済み )。
# 多くのクラウドコーディングエージェントのセットアップスクリプトは root で
# 走るため、その場合はインストールだけ非rootユーザーに委譲し、共有パス
# (AIDLC_BIN_DIR / AIDLC_INSTALL_ROOT。install.sh 側が読むことを確認済み)
# を通じて root セッションからも同じ aidlc を参照する。

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
PROJECT_DIR="$(pwd)"

if [ "$(id -u)" -eq 0 ]; then
  RUN_AS="${AIDLC_INSTALL_USER:-}"
  if [ -z "$RUN_AS" ]; then
    for candidate in ubuntu claude; do
      id -u "$candidate" >/dev/null 2>&1 && RUN_AS="$candidate" && break
    done
  fi
  if [ -z "$RUN_AS" ] || ! id -u "$RUN_AS" >/dev/null 2>&1; then
    echo "root実行中ですが委譲先の非rootユーザーが見つかりません(upstream install.sh はrootインストールを拒否します)。AIDLC_INSTALL_USER で既存の非rootユーザーを指定してください。" >&2
    exit 1
  fi
  export AIDLC_INSTALL_ROOT="${AIDLC_INSTALL_ROOT:-/opt/aidlc}"
  export AIDLC_BIN_DIR="${AIDLC_BIN_DIR:-/opt/aidlc/bin}"
  mkdir -p "$AIDLC_INSTALL_ROOT" "$AIDLC_BIN_DIR"
  chown "$RUN_AS" "$AIDLC_INSTALL_ROOT" "$AIDLC_BIN_DIR"
else
  export AIDLC_INSTALL_ROOT="${AIDLC_INSTALL_ROOT:-$HOME/.local/share/aidlc}"
  export AIDLC_BIN_DIR="${AIDLC_BIN_DIR:-$HOME/.local/bin}"
fi

export PATH="$AIDLC_BIN_DIR:$PATH"
grep -qF "$AIDLC_BIN_DIR" "$HOME/.bashrc" 2>/dev/null || \
  echo "export PATH=\"$AIDLC_BIN_DIR:\$PATH\"" >> "$HOME/.bashrc"

# 1. インストール(導入済みでpinバージョンを含んでいればスキップ)
#    `aidlc --version` の厳密な出力フォーマットは未検証のため、
#    完全一致ではなく部分一致で判定する(フォーマット差異に強くする)。
if ! "$AIDLC_BIN_DIR/aidlc" --version 2>/dev/null | grep -qF "$AIDLC_PIN"; then
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  curl -fsSL "https://github.com/${REPO}/releases/download/v${AIDLC_PIN}/install.sh" \
    -o "$tmp/install.sh"
  if [ "$(id -u)" -eq 0 ]; then
    su "$RUN_AS" -s /bin/sh -c \
      "AIDLC_INSTALL_ROOT=\"$AIDLC_INSTALL_ROOT\" AIDLC_BIN_DIR=\"$AIDLC_BIN_DIR\" sh \"$tmp/install.sh\" --version \"$AIDLC_PIN\" --yes"
  else
    sh "$tmp/install.sh" --version "$AIDLC_PIN" --yes
  fi
fi

# 2. 確認
"$AIDLC_BIN_DIR/aidlc" --version

# 3. プロジェクト設定
#    --pin と --harness は別操作(GitHub Issue #1047 で実在を確認済み)。
#    --pin はマシンにこのバージョンの使用を登録するために必須。
#    --harness は各harness用の設定を生成/更新するが、進行中のワークフローが
#    あるプロジェクトでは失敗する可能性があるため、全体を止めずに警告に留める。
"$AIDLC_BIN_DIR/aidlc" config --pin "$AIDLC_PIN" --project-dir "$PROJECT_DIR"
"$AIDLC_BIN_DIR/aidlc" config --harness "$HARNESS" --project-dir "$PROJECT_DIR" || \
  echo "warning: aidlc config --harness が失敗しました。進行中のワークフローがある場合は手動で再実行してください。" >&2
