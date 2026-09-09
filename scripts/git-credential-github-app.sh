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

# github.com の HTTPS 以外には関与しない（他の helper / 対話にフォールバック）。
if [ "$protocol" != "https" ] || [ "$host" != "github.com" ]; then
  exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
token="$(cd "$SCRIPT_DIR/.." && npm run --silent gh-token 2>/dev/null)"

printf 'username=x-access-token\npassword=%s\n' "$token"
