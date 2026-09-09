#!/usr/bin/env bash
#
# git の credential helper。github.com への HTTPS 接続時に、GitHub App の
# インストールアクセストークンを git へ渡す。
#
# 登録（クローンごとに1回、絶対パスで）:
#   git config credential.https://github.com.helper ""
#   git config --add credential.https://github.com.helper \
#     "$PWD/scripts/git-credential-github-app.sh"
#
# 以降、このリポジトリでの `git push` / `git fetch`（HTTPS・github.com）は
# 自動で App トークンを使う。トークンは scripts/github-app-auth.ts が発行・
# キャッシュする。

set -euo pipefail

# get 以外（store / erase）は何もしない。
[ "${1:-}" = "get" ] || exit 0

protocol=""
host=""
while IFS='=' read -r key value; do
  case "$key" in
    protocol) protocol="$value" ;;
    host) host="$value" ;;
    "") break ;;   # 空行で入力終わり
  esac
done

# ホストは正規化してから判定する。git は URL の表記をそのまま渡してくるため、
# https://GitHub.com/... なら host=GitHub.com、https://github.com:443/... なら
# host=github.com:443 になる。完全一致で判定すると、これらで資格情報を返さず
# askpass / 対話入力（＝個人認証）へフォールバックしてしまう。
protocol_norm="$(printf '%s' "$protocol" | tr '[:upper:]' '[:lower:]')"
host_norm="$(printf '%s' "$host" | tr '[:upper:]' '[:lower:]')"
host_norm="${host_norm%:443}"   # https の既定ポートは付いていても同一ホスト

# github.com の HTTPS 以外には関与しない（他の helper / 対話にフォールバック）。
if [ "$protocol_norm" != "https" ] || [ "$host_norm" != "github.com" ]; then
  exit 0
fi

# CDPATH が export されていると cd が解決先を stdout に出し、コマンド置換に
# 混入して SCRIPT_DIR が壊れる。CDPATH= で無効化し、-- でパスを引数として固定する。
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# stderr は credential helper のプロトコル（stdout の key=value）を壊さないので、
# 設定不備の原因メッセージがそのまま git 利用者に見えるよう伝播させる。
if ! token="$(CDPATH= cd -- "$SCRIPT_DIR/.." && npm run --silent gh-token)" || [ -z "$token" ]; then
  # fail closed。ここで単に失敗すると git は後続の helper / GIT_ASKPASS /
  # 対話入力へ進み、個人アカウントの資格情報で push が成功してしまう
  # （＝操作主体を App に分離する目的に反する）。
  # quit=1 を返すと git は以降の helper も対話も行わずに処理を中断する。
  echo "quit=1"
  echo "[git-credential-github-app] App トークンを取得できませんでした。個人認証へフォールバックせず中断します。" >&2
  exit 0
fi

printf 'username=x-access-token\npassword=%s\n' "$token"
