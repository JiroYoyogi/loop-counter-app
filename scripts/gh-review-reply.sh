#!/usr/bin/env bash
#
# PR のレビュースレッドに GitHub App（bot）名義で返信する専用スクリプト。
#
# 使い方:
#   scripts/gh-review-reply.sh <pr-number> <comment-id> [body-file]
#   （body-file 省略または "-" のとき本文は stdin から読む）
#
#   echo '対応しました。' | scripts/gh-review-reply.sh 7 3964156069
#   scripts/gh-review-reply.sh 7 3964156069 reply.md
#
# 設計:
#   with-github-app.sh の `gh api` は読み取り専用に固定してある。書き込みは
#   引数を解析して安全性を判定するのではなく、このように「URL とメソッドを
#   スクリプト側が組み立てる」専用コマンドとして提供する。
#   - 宛先は origin の OWNER/REPO から導出（呼び出し側は指定できない）
#   - PR 番号・コメント ID は数字のみを許可（パス差し込みを防ぐ）
#   - 本文は JSON として渡す（フラグとして解釈されない）

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

die() {
  echo "[gh-review-reply] $1" >&2
  exit "${2:-1}"
}

[ "$#" -ge 2 ] || die "usage: scripts/gh-review-reply.sh <pr-number> <comment-id> [body-file]" 2

pr="$1"
comment_id="$2"
body_src="${3:--}"

case "$pr" in ''|*[!0-9]*) die "PR 番号は数字で指定してください: ${pr}" 2 ;; esac
case "$comment_id" in ''|*[!0-9]*) die "コメント ID は数字で指定してください: ${comment_id}" 2 ;; esac

# 宛先リポジトリは origin から導出する（呼び出し側に選ばせない）。
origin="$(git -C "$SCRIPT_DIR/.." remote get-url origin 2>/dev/null || true)"
case "$origin" in
  https://github.com/*)
    slug="${origin#https://github.com/}"
    slug="${slug%.git}"
    slug="${slug%/}" ;;
  *)
    die "origin が HTTPS の GitHub リモートではありません: ${origin:-（未設定）}" 5 ;;
esac
case "$slug" in
  */*/*|"") die "origin の OWNER/REPO を解釈できません: ${origin}" 5 ;;
  */*) : ;;
  *)   die "origin の OWNER/REPO を解釈できません: ${origin}" 5 ;;
esac

if [ "$body_src" = "-" ]; then
  body_json="$(node -e 'const fs=require("fs");process.stdout.write(JSON.stringify({body:fs.readFileSync(0,"utf8")}))')"
else
  [ -f "$body_src" ] || die "本文ファイルが見つかりません: ${body_src}" 2
  body_json="$(node -e 'const fs=require("fs");process.stdout.write(JSON.stringify({body:fs.readFileSync(process.argv[1],"utf8")}))' "$body_src")"
fi

TOKEN="$(cd "$SCRIPT_DIR/.." && npm run --silent gh-token)"
export GH_TOKEN="$TOKEN"
export GITHUB_TOKEN="$TOKEN"

printf '%s' "$body_json" | gh api \
  --method POST \
  "repos/${slug}/pulls/${pr}/comments/${comment_id}/replies" \
  --input - \
  --jq '.html_url'
