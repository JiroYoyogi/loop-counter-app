#!/usr/bin/env bash
#
# GitHub App のインストールトークンを使って git / gh コマンドを実行するラッパー。
#
# 例:
#   scripts/with-github-app.sh gh pr create --fill
#   scripts/with-github-app.sh gh repo view
#   scripts/with-github-app.sh git push -u origin HEAD
#
# 仕組み:
#   scripts/github-app-auth.ts が返すトークンを取得し、
#   - gh 用に GH_TOKEN / GITHUB_TOKEN を環境変数で渡す
#   - git の場合は HTTPS の Authorization ヘッダ（x-access-token:<token>）を
#     この呼び出しの間だけ注入する
#   その上で、渡されたコマンドをそのまま実行する。

set -euo pipefail

if [ "$#" -eq 0 ]; then
  echo "usage: scripts/with-github-app.sh <command> [args...]" >&2
  exit 2
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

TOKEN="$(cd "$SCRIPT_DIR/.." && npm run --silent gh-token)"
export GH_TOKEN="$TOKEN"
export GITHUB_TOKEN="$TOKEN"

if [ "$1" = "git" ]; then
  shift
  BASIC="$(printf 'x-access-token:%s' "$TOKEN" | base64 | tr -d '\n')"
  exec git -c "http.https://github.com/.extraheader=Authorization: Basic ${BASIC}" "$@"
fi

exec "$@"
