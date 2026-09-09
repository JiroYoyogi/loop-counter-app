#!/usr/bin/env bash
#
# gh を GitHub App のインストールトークンで実行するラッパー。
# git は credential helper（scripts/git-credential-github-app.sh）で認証するため、
# このラッパーは gh 専用。
#
# 設計方針: 許可リスト（default-deny）
#   実行できるのは下記の gh サブコマンドだけ:
#     pr create|view|list|status|checks|diff|comment|ready / repo view / api(GET)
#   未知のサブコマンド・エイリアス・拡張・`gh api` のメソッド指定は一律拒否。
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

# --- 実効サブコマンド（先頭2語）を特定 -------------------------------------
# 値を取るフラグは -R / --repo のみ（gh のグローバル/継承フラグで値を取るのは
# これだけ）。位置に依存せず読み飛ばすので `gh -R o/r pr view` /
# `gh pr -R o/r view` のどちらも `pr view` と判定できる。
words=()
skip_next=0
for a in "${args[@]}"; do
  if [ "$skip_next" -eq 1 ]; then skip_next=0; continue; fi
  case "$a" in
    -R|--repo) skip_next=1 ;;
    -*)        : ;;                 # 値なしフラグ（--json など）は読み飛ばす
    *)         words+=("$a"); [ "${#words[@]}" -ge 2 ] && break ;;
  esac
done
sub1="${words[0]:-}"
sub2="${words[1]:-}"

# --- 許可リスト（default-deny）----------------------------------------------
case "$sub1 $sub2" in
  "pr create"|"pr view"|"pr list"|"pr status"|"pr checks"|"pr diff"|"pr comment"|"pr ready"|\
  "repo view"|\
  "api "*)
    : ;;
  *)
    die "許可されていない gh 操作です: gh $* （許可リストは ${0} を参照）" 3 ;;
esac

# --- gh api は GET のみ許可（メソッド指定は一律不可）------------------------
# -X / --method のあらゆる形式（-X DELETE / --method=PUT / 結合された -iXDELETE 等）
# を、値を解析せず「メソッドフラグの存在」だけで拒否する。GET は既定なので不要。
if [ "$sub1" = "api" ]; then
  for a in "${args[@]}"; do
    case "$a" in
      --method|--method=*) die "gh api はメソッド指定不可（GET のみ許可）" 3 ;;
      -*X*)                die "gh api はメソッド指定不可（GET のみ許可）" 3 ;;
    esac
  done
fi

# --- トークンを注入して実行 -------------------------------------------------
TOKEN="$(cd "$SCRIPT_DIR/.." && npm run --silent gh-token)"
export GH_TOKEN="$TOKEN"
export GITHUB_TOKEN="$TOKEN"

exec gh "$@"
