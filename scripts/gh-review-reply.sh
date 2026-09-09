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
#
# その前に、git のリポジトリ解決先と設定を差し替える環境変数を破棄する。
# GIT_DIR は `git -C` より優先されるため、これを残すと呼び出し側が別クローンを
# 指定でき、そのクローンの origin から slug が作られて意図しないリポジトリへ
# 投稿できてしまう（＝宛先を固定するという前提が崩れる）。
# いずれも環境変数だけで成立し、ファイルの配置を必要としない。
unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_CEILING_DIRECTORIES
unset GIT_CONFIG_PARAMETERS GIT_CONFIG_COUNT GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM

# `git remote get-url` は url.<base>.insteadOf による書き換えを適用してしまう。
# ここで欲しいのは接続時に使われる URL ではなく、リポジトリに保存された生の
# origin なので、ローカル設定から直接読む。
# （例: url."git@github.com:".insteadOf=https://github.com/ という一般的な設定が
#   あると、get-url は https の origin を SSH 形式で返し、正しい origin が
#   拒否されてしまう）
origin="$(git -C "$SCRIPT_DIR/.." config --local --get remote.origin.url 2>/dev/null || true)"
[ -n "$origin" ] || die "origin が設定されていません" 5

# スキームとホストは正規化してから判定する（credential helper と同じ扱い）。
# https://GitHub.com/... や https://github.com:443/... も同一ホストとみなす。
# パス部分は OWNER/REPO なので大小文字を保持する。
case "$origin" in
  *://*) : ;;
  *) die "origin が HTTPS の GitHub リモートではありません: ${origin}" 5 ;;
esac
scheme="$(printf '%s' "${origin%%://*}" | tr '[:upper:]' '[:lower:]')"
rest="${origin#*://}"
hostpart="${rest%%/*}"
path="${rest#*/}"

# user:token@ が埋め込まれていると、git は credential helper を呼ばずに
# その個人資格情報で操作してしまう（＝ App 名義に分離できない）。明示的に拒否する。
case "$hostpart" in
  *@*) die "origin に認証情報が埋め込まれています。App 名義で操作できないため拒否します（origin から user:token@ を取り除いてください）" 5 ;;
esac

host="$(printf '%s' "$hostpart" | tr '[:upper:]' '[:lower:]')"
host="${host%:443}"
if [ "$scheme" != "https" ] || [ "$host" != "github.com" ]; then
  die "origin が HTTPS の GitHub リモートではありません: ${origin}" 5
fi

# 末尾スラッシュを先に落としてから .git を外す。順序が逆だと
# https://github.com/owner/repo.git/ で .git が一致せず、slug が
# owner/repo.git のまま残ってしまう。
slug="$path"
while [ "$slug" != "${slug%/}" ]; do slug="${slug%/}"; done
slug="${slug%.git}"
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
