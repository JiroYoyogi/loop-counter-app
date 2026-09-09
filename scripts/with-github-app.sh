#!/usr/bin/env bash
#
# gh を GitHub App のインストールトークンで実行するラッパー。
# git は credential helper（scripts/git-credential-github-app.sh）で認証するため、
# このラッパーは gh 専用。
#
# 設計方針: 許可リスト（default-deny）
#   実行できるのは下記の gh サブコマンドだけ:
#     pr create|view|list|status|checks|diff|comment|ready / repo view
#     api （読み取り専用。メソッド/本文フラグを含む呼び出しは拒否）
#   未知のサブコマンド・エイリアス・拡張は一律拒否。
#   （deny リストを模倣するより、許可を絞るほうが穴が出にくい）
#
#   書き込みは「引数を解析して安全か判定する」のではなく、URL とメソッドを
#   スクリプト側が組み立てる専用コマンドで行う:
#     - レビュースレッドへの返信 … scripts/gh-review-reply.sh
#     - PR 作成 / PR コメント     … gh pr create / gh pr comment（下記の例）
#
#   App トークンの権限は contents:write / pull_requests:write / metadata:read /
#   （actions/issues/statuses は read）を前提。workflows 権限は付与しない
#   （ワークフロー変更を含む push は GitHub 側で拒否される）。
#
# 例:
#   scripts/with-github-app.sh gh pr create --fill
#   scripts/with-github-app.sh gh pr view 7
#   scripts/with-github-app.sh gh pr comment 7 --body '...'
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

# --- ブラウザ / エディタ経由の抜け道を塞ぐ ----------------------------------
# --web はブラウザを開くため、注入した GH_TOKEN ではなくブラウザにログイン中の
# 個人アカウントで PR やコメントが作成される。
# -e/--editor は外部エディタを起動するため、そのプロセスが GH_TOKEN を継承し、
# 任意のエディタが指定されていれば許可リストの外へ出られてしまう。
#
# フラグの拒否は「分かりやすいエラーを出す」ためのもので、安全性はこれに
# 依存しない（結合形や値の付き方で取りこぼしうるため）。実際の担保は
# exec 直前の環境変数の無害化で行う（下部参照）。
for a in "${args[@]}"; do
  case "$a" in
    --web|--web=*|-w)
      die "--web / -w は使えません（ブラウザ上の個人アカウントで操作されるため）: ${a}" 3 ;;
    --editor|--editor=*|-e)
      die "-e / --editor は使えません（外部エディタが GH_TOKEN を継承して起動するため）。本文は --body / --body-file で渡してください: ${a}" 3 ;;
  esac
done

# --- gh api は「読み取り専用（GET）」に限定 --------------------------------
# 方針: 引数を解析して「実際に飛ぶリクエスト」を推測するのは信頼できない
#   （--input の値・結合フラグ・フラグメント等でいくらでも誤判定させられる）。
#   そこで推測をやめ、「本文やメソッドを指定しうるフラグが1つでもあれば拒否」
#   という保守的な判定にする。これらが無ければ gh api は必ず GET になるため、
#   宛先を問わず書き込みは発生しない。
#   書き込みが必要な操作は専用スクリプト（scripts/gh-review-reply.sh）や
#   許可済みサブコマンド（gh pr create / gh pr comment）を使う。
if [ "$sub1" = "api" ]; then
  for a in "${args[@]}"; do
    case "$a" in
      --method|--method=*|--field|--field=*|--raw-field|--raw-field=*|--input|--input=*)
        die "gh api は読み取り専用です（${a} は使えません）。書き込みは scripts/gh-review-reply.sh か gh pr create / gh pr comment を使ってください" 3 ;;
      --*)
        : ;;
      -*[XfF]*)
        die "gh api は読み取り専用です（${a} にメソッド/本文フラグが含まれます）。書き込みは scripts/gh-review-reply.sh か gh pr create / gh pr comment を使ってください" 3 ;;
      graphql)
        die "gh api graphql は許可されていません" 3 ;;
    esac
  done
fi

# --- gh が起動する外部プロセスを無害化 ---------------------------------------
# gh はエディタ・ブラウザ・ページャを子プロセスとして起動することがあり
# （--body を省いた `gh pr comment` は既定でエディタを開く）、それらは
# 注入した GH_TOKEN を環境ごと継承する。任意のスクリプトが指定されていると
# そこから禁止操作を実行でき、許可リストを迂回できてしまう。
# 引数の形に依存せず塞ぐため、起動先そのものを無害なものに固定する。
export GH_EDITOR=false EDITOR=false VISUAL=false GIT_EDITOR=false
export GH_BROWSER=false BROWSER=false
export GH_PAGER=cat PAGER=cat

# gh は内部で git を起動することがある（未 push ブランチでの gh pr create など）。
# その git のフック（pre-push 等）も GH_TOKEN を継承するため、フック経由での
# 迂回を防ぐ目的で gh の子プロセスではフックを無効化する。
# （この env は gh とその子プロセスにのみ効き、手元の git 操作には影響しない）
_gc_n="${GIT_CONFIG_COUNT:-0}"
case "$_gc_n" in ''|*[!0-9]*) _gc_n=0 ;; esac
eval "export GIT_CONFIG_KEY_${_gc_n}=core.hooksPath"
eval "export GIT_CONFIG_VALUE_${_gc_n}=/nonexistent/with-github-app-no-hooks"
export GIT_CONFIG_COUNT="$((_gc_n + 1))"

# --- トークンを注入して実行 -------------------------------------------------
TOKEN="$(cd "$SCRIPT_DIR/.." && npm run --silent gh-token)"
export GH_TOKEN="$TOKEN"
export GITHUB_TOKEN="$TOKEN"

exec gh "$@"
