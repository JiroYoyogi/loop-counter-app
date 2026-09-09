#!/usr/bin/env bash
#
# gh を GitHub App のインストールトークンで実行するラッパー。
# git は credential helper（scripts/git-credential-github-app.sh）で認証するため、
# このラッパーは gh 専用。
#
# 設計方針: 許可リスト（default-deny）
#   実行できるのは下記の gh サブコマンドだけ:
#     pr create|view|list|status|checks|diff|comment|ready / repo view
#     api （REST の GET / POST / PATCH のみ。PUT / DELETE / graphql は不可。
#           レビュー投稿 *(.../reviews)* への書き込みも不可）
#   未知のサブコマンド・エイリアス・拡張は一律拒否。
#   （deny リストを模倣するより、許可を絞るほうが穴が出にくい）
#
#   App トークンの権限は contents:write / pull_requests:write / metadata:read /
#   （actions/issues/statuses は read）を前提。workflows 権限は付与しない
#   （ワークフロー変更を含む push は GitHub 側で拒否される）。
#
# 例:
#   scripts/with-github-app.sh gh pr create --fill
#   scripts/with-github-app.sh gh pr view 7
#   scripts/with-github-app.sh gh api repos/OWNER/REPO/pulls/7/comments
#   scripts/with-github-app.sh gh api --method POST repos/O/R/pulls/7/comments/123/replies -f body=...

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

# --- gh api: REST の GET / POST / PATCH のみ許可 ---------------------------
# 拒否するもの:
#   - PUT / DELETE（マージ・ファイル直書き・ブランチ削除など）
#   - graphql エンドポイント（任意 mutation を実行できる）
#   - */reviews への書き込み（bot による PR 承認の防止）
# 引数の位置解析はせず、「危険を示すトークンが含まれるか」で判定する。
if [ "$sub1" = "api" ]; then
  # 1) メソッド抽出（-X M / -XM / --method M / --method=M / 結合クラスタ -iXM）。
  #    明示メソッドが無く -f/-F/--field 等があれば gh は POST になる。
  method=""
  has_fields=0
  expect_method=0
  for a in "${args[@]}"; do
    if [ "$expect_method" -eq 1 ]; then method="$a"; expect_method=0; continue; fi
    case "$a" in
      --method)                          expect_method=1 ;;
      --method=*)                        method="${a#--method=}" ;;
      --field|--raw-field|--input)       has_fields=1 ;;
      --field=*|--raw-field=*|--input=*) has_fields=1 ;;
      --*)                               : ;;
      -[!-]*)
        rest="${a#-}"
        case "$rest" in
          *X*)
            after="${rest#*X}"
            case "${rest%%X*}" in *[fF]*) has_fields=1 ;; esac
            if [ -n "$after" ]; then method="$after"; else expect_method=1; fi ;;
          *[fF]*) has_fields=1 ;;
        esac ;;
    esac
  done
  method="$(printf '%s' "$method" | tr '[:lower:]' '[:upper:]')"
  [ -z "$method" ] && [ "$has_fields" -eq 1 ] && method="POST"
  [ -z "$method" ] && method="GET"

  case "$method" in
    GET|POST|PATCH) : ;;
    *) die "gh api の ${method} メソッドは許可されていません（GET / POST / PATCH のみ）" 3 ;;
  esac

  # 2) graphql / reviews への書き込みを含むか（全引数を走査）
  for a in "${args[@]}"; do
    case "$a" in
      graphql|/graphql|graphql\?*|/graphql\?*)
        die "gh api graphql は許可されていません（任意 mutation を実行できるため）" 3 ;;
    esac
    if [ "$method" != "GET" ]; then
      case "$a" in
        */reviews|*/reviews/*|*/reviews\?*)
          die "gh api でのレビュー投稿（${a}）は許可されていません（bot 承認の防止）" 3 ;;
      esac
    fi
  done
fi

# --- トークンを注入して実行 -------------------------------------------------
TOKEN="$(cd "$SCRIPT_DIR/.." && npm run --silent gh-token)"
export GH_TOKEN="$TOKEN"
export GITHUB_TOKEN="$TOKEN"

exec gh "$@"
