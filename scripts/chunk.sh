#!/bin/bash
set -euo pipefail

REPO="CircleCI-Public/chunk-cli"
SSH_KEY="$HOME/.ssh/chunk_ai"

# sync の準備（手順5〜7）で失敗したものを集め、最後にまとめて報告する。
# 1つ失敗しても残りの準備は続け、最後に exit 1 する（失敗はセットアップの失敗として見える）。
FAILED=()

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

# 5. chunk sidecar sync が使う openssh-client / rsync を用意
#    sync は外部コマンドの rsync と ssh(-i ~/.ssh/chunk_ai)を呼ぶ。chunk sidecar ssh は
#    外部の ssh を使わないので、これが無いと「ssh は通るのに sync だけ失敗する」状態になる。
#    (未導入の場合のみ apt を叩く。導入済みなら毎回のupdateを避ける)
#    apt-get update は無関係なサードパーティ源(PPA等)がプロキシで拒否される
#    だけでも失敗しうる。まず既存のパッケージリストで install を試し、
#    失敗したときだけ update する。update の失敗は致命扱いにせず、最終的な
#    成否は install の結果で判定する。
#    パッケージは1つずつ入れる。まとめて入れると、片方が取得できないだけ
#    (古いパッケージリストで openssh-client が 404 になる例を Claude Code on the web で確認)
#    で両方とも入らない。
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
install_pkg ssh-keygen openssh-client || FAILED+=("openssh-client")

# 6. sidecar用SSH鍵を OpenSSH 形式で用意する
#    鍵が無いまま chunk を使うと、chunk は PKCS#8 形式の ed25519 鍵
#    (先頭行が "-----BEGIN PRIVATE KEY-----")を自分で作る。OpenSSH(9.6 で確認)は
#    これを "invalid format" で読めず、sync が Permission denied (publickey) で失敗する。
#    chunk 自身は OpenSSH 形式の鍵も読めるので、先に OpenSSH 形式で作っておく。
#    すでに PKCS#8 の鍵がある場合は OpenSSH 形式にそろえる(元の鍵は .bak に退避)。
#    登録(chunk sidecar add-ssh-key)はしない: 作り直した鍵でも既存の sidecar に
#    接続できることを確認済み。
mkdir -p ~/.ssh
chmod 700 ~/.ssh

has_py_crypto() { python3 -c 'import cryptography' >/dev/null 2>&1; }

# python の cryptography で OpenSSH 形式の鍵を書く。
# 第1引数 convert: 既存の PKCS#8 鍵を同じ鍵のまま変換 / generate: 新しく作る
write_openssh_key_py() {
  python3 - "$SSH_KEY" "$1" <<'PY'
import os, sys
from cryptography.hazmat.primitives import serialization as s
from cryptography.hazmat.primitives.asymmetric import ed25519
path, mode = sys.argv[1], sys.argv[2]
if mode == "convert":
    key = s.load_pem_private_key(open(path, "rb").read(), password=None)
else:
    key = ed25519.Ed25519PrivateKey.generate()
tmp = path + ".tmp"
with open(tmp, "wb") as f:
    f.write(key.private_bytes(s.Encoding.PEM, s.PrivateFormat.OpenSSH, s.NoEncryption()))
os.chmod(tmp, 0o600)
os.replace(tmp, path)
with open(path + ".pub", "wb") as f:
    f.write(key.public_key().public_bytes(s.Encoding.OpenSSH, s.PublicFormat.OpenSSH) + b" chunk-ai\n")
PY
}

if [ ! -f "$SSH_KEY" ]; then
  if command -v ssh-keygen >/dev/null 2>&1; then
    ssh-keygen -t ed25519 -f "$SSH_KEY" -N "" -q || FAILED+=("chunk_ai key (ssh-keygen での作成に失敗)")
  elif has_py_crypto; then
    # openssh-client を入れられなかった場合でも、chunk に PKCS#8 の鍵を作らせない
    write_openssh_key_py generate || FAILED+=("chunk_ai key (python3 での作成に失敗)")
  else
    FAILED+=("chunk_ai key (ssh-keygen も python3 の cryptography も無い)")
  fi
elif head -1 "$SSH_KEY" | grep -q "BEGIN PRIVATE KEY"; then
  BACKUP="$SSH_KEY.bak.$(date +%Y%m%d%H%M%S)"
  cp -p "$SSH_KEY" "$BACKUP"
  [ -f "$SSH_KEY.pub" ] && cp -p "$SSH_KEY.pub" "$BACKUP.pub"
  echo "==> chunk_ai key is PKCS#8; converting to OpenSSH format (backup: $BACKUP)"
  if has_py_crypto; then
    write_openssh_key_py convert || FAILED+=("chunk_ai key (PKCS#8 からの変換に失敗。元の鍵は $BACKUP)")
  elif command -v ssh-keygen >/dev/null 2>&1; then
    rm -f "$SSH_KEY" "$SSH_KEY.pub"
    ssh-keygen -t ed25519 -f "$SSH_KEY" -N "" -q || FAILED+=("chunk_ai key (ssh-keygen での再作成に失敗。元の鍵は $BACKUP)")
  else
    FAILED+=("chunk_ai key (PKCS#8 のまま。変換手段が無い)")
  fi
fi

# 7. chunk のスキルを入れる
#    sync の準備(手順5・6)より後に回し、ここが失敗しても準備は済んでいるようにする。
chunk skill install || FAILED+=("chunk skill install")

# 8. 確認
if command -v rsync >/dev/null 2>&1; then
  rsync --version | sed -n 1p
fi
if command -v ssh-keygen >/dev/null 2>&1 && [ -f "$SSH_KEY" ]; then
  if ssh-keygen -y -P "" -f "$SSH_KEY" >/dev/null 2>&1; then
    echo "chunk_ai key: ok"
  else
    FAILED+=("chunk_ai key (OpenSSH で読めない)")
  fi
fi

if [ "${#FAILED[@]}" -gt 0 ]; then
  echo "error: chunk sidecar sync の準備に失敗した: ${FAILED[*]}" >&2
  exit 1
fi
