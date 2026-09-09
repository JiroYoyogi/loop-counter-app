#!/usr/bin/env bash
#
# gh を GitHub App のインストールトークンで実行するラッパー。
# git は credential helper（scripts/git-credential-github-app.sh）で認証するため、
# このラッパーは gh 専用。
#
# 設計方針: 許可リスト（default-deny）
#   このラッパー経由で実行できるのは下記 ALLOW の gh サブコマンドだけ。
#   未知のサブコマンド・エイリアス・拡張・`gh api` の書き込みメソッドは一律拒否。
#   （deny リストを模倣するより、許可を絞るほうが穴が出にくい）
#
# 例:
#   scripts/with-github-app.sh gh pr create --fill
#   scripts/with-github-app.sh gh pr view 7
#   scripts/with-github-app.sh gh api repos/OWNER/REPO/pulls/7/comments

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

die() {
  echo "[with-github-app] $1" >&2
  exit "${2:-1}"
}

[ "$#" -ge 1 ] || die "usage: scripts/with-github-app.sh gh <args...>" 2
[ "$1" = "gh" ] || die "このラッパーで実行できるのは gh のみ（git は credential helper 経由）。指定: $1" 3
shift
args=("$@")

# --- gh のグローバルフラグを読み飛ばして実効サブコマンドを特定 -------------
# 値を取るグローバルフラグは -R / --repo のみ。フラグ位置に依存しないため
# `gh -R o/r pr merge` も `gh pr merge` と同様に判定できる。
idx=0
while [ "$idx" -lt "${#args[@]}" ]; do
  case "${args[$idx]}" in
    -R|--repo) idx=$((idx + 2)) ;;
    --repo=*)  idx=$((idx + 1)) ;;
    -*)        idx=$((idx + 1)) ;;
    *)         break ;;
  esac
done
sub1="${args[$idx]:-}"
sub2="${args[$((idx + 1))]:-}"

# --- 許可リスト ---------------------------------------------------------
case "$sub1 $sub2" in
  "pr create"|"pr view"|"pr list"|"pr status"|"pr checks"|"pr diff"|"pr comment"|"pr ready"|\
  "repo view"|\
  "api"|"api "*)
    : ;;
  *)
    die "許可されていない gh 操作です: gh $* （許可リストは ${0} を参照）" 3 ;;
esac

# --- gh api は書き込みメソッド（PUT / DELETE）を拒否（GET / POST / PATCH は許可）---
# -X DELETE / --method=DELETE / -XDELETE など gh が受理する全形式を正規化する。
if [ "$sub1" = "api" ]; then
  expect_method=0
  for a in "${args[@]}"; do
    m=""
    if [ "$expect_method" -eq 1 ]; then
      m="$a"; expect_method=0
    else
      case "$a" in
        -X|--method)  expect_method=1; continue ;;
        -X*)          m="${a#-X}" ;;
        --method=*)   m="${a#--method=}" ;;
        *)            continue ;;
      esac
    fi
    [ -n "$m" ] || continue
    case "$(printf '%s' "$m" | tr '[:lower:]' '[:upper:]')" in
      PUT|DELETE) die "gh api の ${m} メソッドは許可されていません" 3 ;;
    esac
  done
fi

# --- トークンを注入して実行 -------------------------------------------------
TOKEN="$(cd "$SCRIPT_DIR/.." && npm run --silent gh-token)"
export GH_TOKEN="$TOKEN"
export GITHUB_TOKEN="$TOKEN"

exec gh "$@"
