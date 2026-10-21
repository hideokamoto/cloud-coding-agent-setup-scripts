#!/bin/bash
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

REPO="CircleCI-Public/chunk-cli"
# 版は固定する。releases/latest はプロキシに 403 で拒否されることがあり、
# 常に最新を入れると互換性を壊すリリースでその日から全セッションが壊れるため。
# 上げるときは、リリースの checksums.txt にある値に合わせて両方を書き換える。
CHUNK_VERSION="v0.7.217"
CHUNK_SHA256="d6a9f551f8d173083686a7847bb84e408a428d676b728541432f7144ff27b024"
ASSET="chunk-cli_Linux_x86_64.tar.gz"

# sync の準備(手順2)で失敗したものを集め、最後にまとめて報告する。
# 1つ失敗しても残りの準備は続け、最後に exit 1 する。
FAILED=()

# 1. 固定した版を取得し、チェックサムを照合してから /usr/local/bin に配置する
#    同じ版が入っていればダウンロードごとスキップする。
#    tar.gz には LICENSE・README.md・share/ も入っているので、
#    mktemp -d の作業ディレクトリに chunk だけを取り出す。
if [ "$(chunk --version 2>/dev/null || true)" = "chunk version ${CHUNK_VERSION#v}" ]; then
  echo "chunk ${CHUNK_VERSION} is already installed"
else
  WORK=$(mktemp -d)
  trap 'rm -rf "$WORK"' EXIT
  curl -fsSL -o "$WORK/$ASSET" \
    "https://github.com/${REPO}/releases/download/${CHUNK_VERSION}/${ASSET}"
  echo "${CHUNK_SHA256}  $WORK/$ASSET" | sha256sum -c -
  tar xzf "$WORK/$ASSET" -C "$WORK" chunk
  install -m 0755 "$WORK/chunk" /usr/local/bin/chunk
fi
chunk --version

# 2. chunk sidecar sync が使う rsync / openssh-client を用意
#    sync は外部の rsync と ssh を呼ぶので、これが無いと sync が失敗する。
#    このイメージは apt のパッケージリストが空なので、足りないものがあるときだけ
#    update を1回してから install する。update は無関係な取得元がプロキシで
#    拒否されるだけでも失敗しうるので、失敗しても install は試す。
#    パッケージは1つずつ入れる(片方が404だと、まとめて入れると両方入らないため)。
#
#    chunk skill install はここでは実行しない。既定の --project は
#    カレントディレクトリの .claude/skills などに書き込み、セッションごとに
#    リポジトリの作業ツリーを変えてしまうため。
MISSING=()
command -v rsync >/dev/null 2>&1 || MISSING+=("rsync")
command -v ssh >/dev/null 2>&1 || MISSING+=("openssh-client")
if [ "${#MISSING[@]}" -gt 0 ]; then
  apt-get update -qq || echo "warn: apt-get update failed; trying install anyway" >&2
  for pkg in "${MISSING[@]}"; do
    echo "==> installing ${pkg}"
    apt-get install -y --no-install-recommends "$pkg" || FAILED+=("$pkg")
  done
fi
rsync --version | head -n 1 || true
ssh -V || true

if [ "${#FAILED[@]}" -gt 0 ]; then
  echo "error: chunk sidecar sync の準備に失敗した: ${FAILED[*]}" >&2
  exit 1
fi
