#!/usr/bin/env bash
#
# gh を GitHub App のインストールトークンで実行するラッパー。
#
# git は credential helper（scripts/git-credential-github-app.sh）側で認証するため、
# このラッパーは gh 専用。git を渡すとエラーにする。
#
# 例:
#   scripts/with-github-app.sh gh pr create --fill
#   scripts/with-github-app.sh gh pr view 7
#   scripts/with-github-app.sh gh api /repos/OWNER/REPO
#
# 仕組み:
#   scripts/github-app-auth.ts が返すトークンを GH_TOKEN / GITHUB_TOKEN として
#   渡し、gh をそのまま実行する。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

die() {
  echo "[with-github-app] $1" >&2
  exit "${2:-1}"
}

[ "$#" -ge 1 ] || die "usage: scripts/with-github-app.sh gh <args...>" 2

cmd="$1"
sub="${2:-}"
sub2="${3:-}"
all=" $* "

# gh のみ許可（sh -c ... / env ... 等での迂回を防ぐ）。git は credential helper 経由。
[ "$cmd" = "gh" ] || die "このラッパーで実行できるのは gh のみです（git は credential helper 経由）。指定: ${cmd}" 3

# .claude/settings.json の deny 相当をラッパー経由でも維持する。
deny() { die "禁止された操作です（.claude/settings.json の deny 相当）: $1" 3; }
case "$sub $sub2" in
  "pr merge")    deny "gh pr merge" ;;
  "pr review")   deny "gh pr review" ;;
  "repo delete") deny "gh repo delete" ;;
esac
case "$all" in
  *" --method DELETE "*|*" --method=DELETE "*|*" -X DELETE "*|*" -X=DELETE "*)
    deny "gh api DELETE" ;;
esac

TOKEN="$(cd "$SCRIPT_DIR/.." && npm run --silent gh-token)"
export GH_TOKEN="$TOKEN"
export GITHUB_TOKEN="$TOKEN"

exec "$@"
