#!/bin/bash
set -euo pipefail

# AI-DLC (awslabs/aidlc-workflows) のインストール・プロジェクト設定
# https://github.com/awslabs/aidlc-workflows
#
# 対応harness: claude / kiro / cursor
#   環境変数 AIDLC_HARNESS で選択(未指定時は claude)。
#   このスクリプトはインストールとバージョンpinのみ行い、`aidlc config
#   --harness` (各harness用設定ファイルの生成・上書き)は自動実行しない
#   (理由は後述コメント参照)。実行コマンドはスクリプト末尾に案内される。
#
# バージョンは呼び出し元プロジェクトルートの .aidlc-version でpinする
# (例: echo "2.9.0" > .aidlc-version)。
#
# 注意: upstream install.sh は root 実行を拒否する
#   ( releases/*/install.sh に `[ "$(id -u)" -ne 0 ] || fail 4 ... "refusing a
#     root install; run as the target user"` があることを実機で確認済み )。
# 多くのクラウドコーディングエージェントのセットアップスクリプトは root で
# 走るため、その場合はインストール・pin登録・doctorをすべて非rootユーザーに
# 委譲し、共有パス(AIDLC_BIN_DIR / AIDLC_INSTALL_ROOT。install.sh 側が読む
# ことを確認済み)を通じて root セッションからも同じ aidlc を参照する
# (`aidlc config`/`doctor` がユーザー所有のファイルに書き込む可能性がある
#  ため、install だけでなくすべての aidlc 呼び出しを委譲する)。

REPO="awslabs/aidlc-workflows"
HARNESS="${AIDLC_HARNESS:-claude}"

case "$HARNESS" in
  claude|kiro|cursor) ;;
  *)
    echo "AIDLC_HARNESS must be one of: claude, kiro, cursor (got: ${HARNESS})" >&2
    exit 1
    ;;
esac

PROJECT_DIR="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
if [ ! -f "$PROJECT_DIR/.aidlc-version" ]; then
  echo ".aidlc-version が見つかりません($PROJECT_DIR)。プロジェクトルートにpinするバージョン(例: 2.9.0)を書いたファイルを用意してください。" >&2
  exit 1
fi
AIDLC_PIN="$(tr -d '[:space:]' < "$PROJECT_DIR/.aidlc-version")"
if [ -z "$AIDLC_PIN" ]; then
  echo ".aidlc-version が空です($PROJECT_DIR)。pinするバージョン(例: 2.9.0)を書いてください。" >&2
  exit 1
fi

RUN_AS=""
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
  chown -R "$RUN_AS" "$AIDLC_INSTALL_ROOT" "$AIDLC_BIN_DIR"
else
  export AIDLC_INSTALL_ROOT="${AIDLC_INSTALL_ROOT:-$HOME/.local/share/aidlc}"
  export AIDLC_BIN_DIR="${AIDLC_BIN_DIR:-$HOME/.local/bin}"
fi

# root実行時は $RUN_AS として、非root実行時はそのままコマンドを実行する。
# `su ... -c 'exec "$0" "$@"' -- /usr/bin/env ...` は argv をそのまま保った
# まま渡せるため、パスやバージョン文字列を su の -c 文字列内で再クオート
# する必要がなく、引用符ネストによる事故を避けられる(実機で動作確認済み)。
run_as() {
  if [ -n "$RUN_AS" ]; then
    su "$RUN_AS" -s /bin/sh -c 'exec "$0" "$@"' -- /usr/bin/env \
      AIDLC_INSTALL_ROOT="$AIDLC_INSTALL_ROOT" \
      AIDLC_BIN_DIR="$AIDLC_BIN_DIR" \
      PATH="$AIDLC_BIN_DIR:$PATH" \
      "$@"
  else
    "$@"
  fi
}

export PATH="$AIDLC_BIN_DIR:$PATH"
# 注意: .bashrc の `[ -z "$PS1" ] && return`(非対話シェルでは即return)により、
# この登録はフックなど非対話プロセスからの `aidlc` 呼び出しには効かない
# (実機で確認済み)。以降のセッションでもPATHを通す必要がある場合は、
# エージェント環境側の環境変数設定に PATH=$AIDLC_BIN_DIR:$PATH と
# AIDLC_INSTALL_ROOT / AIDLC_BIN_DIR を恒久的に設定すること。
grep -qF "$AIDLC_BIN_DIR" "$HOME/.bashrc" 2>/dev/null || \
  echo "export PATH=\"$AIDLC_BIN_DIR:\$PATH\"" >> "$HOME/.bashrc"
# root実行時、上の行は root の $HOME/.bashrc にしか効かず、実際にバイナリを
# 使う委譲先ユーザーには反映されない(root の $HOME はそのユーザーの
# ホームではないため)。委譲先ユーザー自身に、そのユーザーの $HOME/.bashrc
# へ追記させる。
if [ -n "$RUN_AS" ]; then
  run_as sh -c 'grep -qF "$AIDLC_BIN_DIR" "$HOME/.bashrc" 2>/dev/null || printf "export PATH=\"%s:\$PATH\"\n" "$AIDLC_BIN_DIR" >> "$HOME/.bashrc"'
fi

# 1. インストール(導入済みでpinバージョンを含んでいればスキップ)
#    `aidlc --version` の厳密な出力フォーマットは未検証のため完全一致は
#    避けるが、単なる部分一致(grep -qF)だと "2.9.0" が "12.9.0" のような
#    無関係な文字列にもマッチしてしまう。前後が数字/ピリオドでないことを
#    要求して、部分一致の誤検知を防ぐ。
AIDLC_PIN_RE="$(printf '%s' "$AIDLC_PIN" | sed 's/[.[\*^$]/\\&/g')"
if ! run_as "$AIDLC_BIN_DIR/aidlc" --version 2>/dev/null | \
     grep -qE "(^|[^0-9.])${AIDLC_PIN_RE}([^0-9.]|\$)"; then
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  curl -fsSL "https://github.com/${REPO}/releases/download/v${AIDLC_PIN}/install.sh" \
    -o "$tmp/install.sh"
  # root の mktemp -d は 0700/root 所有のため、委譲先の非rootユーザーが
  # ディレクトリを辿れない(実機で Permission denied を確認済み)。
  chmod 0755 "$tmp"
  run_as sh "$tmp/install.sh" --version "$AIDLC_PIN" --yes
fi

# 2. 確認
run_as "$AIDLC_BIN_DIR/aidlc" --version

# 3. プロジェクト設定
#    --pin と --harness は別操作(GitHub Issue #1047 で実在を確認済み)。
#    --pin はマシンにこのバージョンの使用を登録するために必要。
#
#    --harness は各harness用の設定ファイル(.claude/ 等)を生成・上書きする
#    ownership採用操作であり、既存の手動カスタマイズを巻き戻す可能性がある。
#    また進行中のAI-DLCワークフローがあると失敗しうる。これらはリポジトリ
#    ごとに事情が異なり自動実行すべきでないため、setup scriptからは外し、
#    必要な人が意図したタイミングで手動実行する運用にする:
#      aidlc config --harness "$AIDLC_HARNESS" --project-dir .
run_as "$AIDLC_BIN_DIR/aidlc" config --pin "$AIDLC_PIN" --project-dir "$PROJECT_DIR"

# 4. 確認
run_as "$AIDLC_BIN_DIR/aidlc" doctor || true

echo "note: harness設定は未実行です。必要なら手動で実行してください: aidlc config --harness ${HARNESS} --project-dir ${PROJECT_DIR}" >&2
