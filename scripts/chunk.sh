#!/bin/bash
set -euo pipefail

REPO="CircleCI-Public/chunk-cli"

# 1. releases/latest のリダイレクト先から最新タグ名を取得
LATEST_URL=$(curl -fsS -o /dev/null -w '%{redirect_url}' "https://github.com/${REPO}/releases/latest")
LATEST_TAG="${LATEST_URL##*/}"

# 2. バイナリをダウンロード・展開
curl -fL "https://github.com/${REPO}/releases/download/${LATEST_TAG}/chunk-cli_Linux_x86_64.tar.gz" \
  | tar xz -C /tmp

# 3. 既にPATHが通っている /usr/local/bin に配置(.bashrc非依存)
install -m 0755 /tmp/chunk /usr/local/bin/chunk

# 4. 確認
echo "installed: ${LATEST_TAG}"
chunk --version
chunk skill install

# 5. chunk sidecar sync が使う openssh-client / rsync を用意
#    (未導入の場合のみ apt を叩く。導入済みなら毎回のupdateを避ける)
#    apt-get update は無関係なサードパーティ源(PPA等)がプロキシで拒否される
#    だけでも失敗しうる。まず既存のパッケージリストで install を試し、
#    失敗したときだけ update する。update の失敗は致命扱いにせず、最終的な
#    成否は install の結果で判定する。
if ! command -v rsync >/dev/null 2>&1 || ! command -v ssh-keygen >/dev/null 2>&1; then
  echo "==> installing openssh-client / rsync"
  if ! apt-get install -y --no-install-recommends openssh-client rsync; then
    apt-get update -qq || echo "warn: apt-get update failed; retrying install with available lists" >&2
    apt-get install -y --no-install-recommends openssh-client rsync
  fi
fi

# 6. sidecar用SSH鍵を事前生成(未生成時のみ)
#    登録(chunk sidecar add-ssh-key)はsidecar作成後にその都度行うためここではしない
mkdir -p ~/.ssh
if [ ! -f ~/.ssh/chunk_ai ]; then
  ssh-keygen -t ed25519 -f ~/.ssh/chunk_ai -N "" -q
fi

# 7. 確認
rsync --version | sed -n 1p
ssh-keygen -y -f ~/.ssh/chunk_ai >/dev/null && echo "chunk_ai key: ok"
