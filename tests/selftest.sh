#!/bin/bash
set -uo pipefail

# scripts/ 配下のセットアップスクリプトを使い捨てのプロジェクトで実行し、
# スクリプトごとの成否と、失敗時は落ちたコマンドとエラー出力だけを表示する。
#
# セットアップスクリプトは 0 以外で終了するとセッション自体が起動せず、
# ログも残らない。この検査はスクリプトをセッション内の通常コマンドとして
# 実行するため、壊れていても検査側は落ちず、失敗箇所を報告できる。
# 定期実行の手順は tests/README.md を参照。
#
# 使い方:
#   bash tests/selftest.sh            # scripts/ 配下を検査
#   bash tests/selftest.sh <dir>      # 任意のディレクトリを検査
#
# 環境変数:
#   AIDLC_TEST_VERSION  aidlc.sh 検査時に .aidlc-version へ書くバージョン
#                       (既定: 2.9.0。実際に使うプロジェクトのpinに合わせる)
#
# 終了コード: 全スクリプト成功で 0、1本でも失敗すれば 1

# -e は付けない: 個々のスクリプトの失敗で検査自体を止めず、全件の結果を出すため。

SCRIPTS_DIR="$(cd "${1:-$(dirname "$0")/../scripts}" && pwd)"
AIDLC_TEST_VERSION="${AIDLC_TEST_VERSION:-2.9.0}"

# aidlc.sh は root 実行時に非rootユーザーへ委譲してインストールするため、
# 委譲先が辿れる場所(0755)に作業ディレクトリを作る。mktemp -d の既定(0700)や
# root 専用の一時ディレクトリでは委譲先が EACCES で落ちる(実機確認済み)。
work="$(mktemp -d /var/tmp/selftest.XXXXXX)"
chmod 0755 "$work"
trap 'rm -rf "$work"' EXIT

git -C "$work" init -q
echo "$AIDLC_TEST_VERSION" > "$work/.aidlc-version"

fail=0
for script in "$SCRIPTS_DIR"/*.sh; do
  name="$(basename "$script")"
  log="$work/$name.log"
  # aidlc.sh はカレントディレクトリの git ルートをプロジェクトとして扱う
  ( cd "$work" && bash -x "$script" ) > "$log" 2>&1
  rc=$?
  if [ "$rc" -eq 0 ]; then
    echo "PASS $name"
  else
    fail=1
    echo "FAIL $name (exit $rc)"
    # bash -x のトレース行(+ で始まる)の末尾 = 落ちる直前に実行したコマンド
    grep '^+' "$log" | tail -2 | sed 's/^/  trace: /'
    grep -v '^+' "$log" | tail -3 | sed 's/^/  /'
  fi
done

exit "$fail"
