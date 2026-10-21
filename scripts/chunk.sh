#!/bin/bash
set -euo pipefail

REPO="CircleCI-Public/chunk-cli"

# sync の準備(手順5・6)で失敗したものを集め、最後にまとめて報告する。
# 1つ失敗しても残りの準備は続け、最後に exit 1 する。
FAILED=()

# 1. releases/latest のリダイレクト先から最新タグ名を取得
LATEST_URL=$(curl -fsS -o /dev/null -w '%{redirect_url}' "https://github.com/${REPO}/releases/latest")
LATEST_TAG="${LATEST_URL##*/}"
if [ -z "$LATEST_TAG" ]; then
  echo "error: 最新リリースのタグを取得できなかった" >&2
  exit 1
fi

# 2. バイナリをダウンロード・展開
curl -fL "https://github.com/${REPO}/releases/download/${LATEST_TAG}/chunk-cli_Linux_x86_64.tar.gz" \
  | tar xz -C /tmp

# 3. 既にPATHが通っている /usr/local/bin に配置(.bashrc非依存)
install -m 0755 /tmp/chunk /usr/local/bin/chunk

# 4. 確認
echo "installed: ${LATEST_TAG}"
chunk --version

# 5. chunk sidecar sync が使う rsync / openssh-client を用意
#    sync は外部の rsync と ssh を呼ぶ。chunk sidecar ssh は外部の ssh を使わないので、
#    これが無いと「ssh は通るのに sync だけ失敗する」状態になる。
#    apt-get update は無関係な取得元がプロキシで拒否されるだけでも失敗しうるので、
#    まず既存のパッケージリストで install を試し、失敗したときだけ update する。
#    パッケージは1つずつ入れる(片方が404だと、まとめて入れると両方入らないため)。
APT_UPDATED=""
install_pkg() {
  local cmd="$1" pkg="$2"
  command -v "$cmd" >/dev/null 2>&1 && return 0
  echo "==> installing ${pkg}"
  apt-get install -y --no-install-recommends "$pkg" && return 0
  if [ -z "$APT_UPDATED" ]; then
    apt-get update -qq || echo "warn: apt-get update failed; retrying install with available lists" >&2
    APT_UPDATED=1
  fi
  apt-get install -y --no-install-recommends "$pkg"
}
install_pkg rsync rsync || FAILED+=("rsync")
install_pkg ssh openssh-client || FAILED+=("openssh-client")

# 6. chunk のスキルを入れる
#    sync の準備(手順5)より後に回し、ここが失敗しても準備は済んでいるようにする。
chunk skill install || FAILED+=("chunk skill install")

if [ "${#FAILED[@]}" -gt 0 ]; then
  echo "error: chunk sidecar sync の準備に失敗した: ${FAILED[*]}" >&2
  exit 1
fi
