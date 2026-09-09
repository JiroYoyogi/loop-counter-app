#!/usr/bin/env bash
#
# gh を GitHub App のインストールトークンで実行するラッパー。
# git は credential helper（scripts/git-credential-github-app.sh）で認証するため、
# このラッパーは gh 専用。
#
# 設計方針: 許可リスト（default-deny）
#   実行できるのは下記の gh サブコマンドだけ:
#     pr create|view|list|status|checks|diff|comment|ready / repo view
#     api （GET は任意。書き込み（GET 以外）はコメント／リアクション系の
#           エンドポイントに限定。PUT / DELETE / graphql、および
#           ref 更新・merges・PR 編集などその他の書き込みは不可）
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

# --- gh api: GET は任意 / 書き込みはコメント系エンドポイントに限定 -----------
# メソッド名だけでは PATCH /git/refs（force 更新）や POST /merges のような
# 破壊的書き込みを止められないため、「書き込み先エンドポイントの許可リスト」で
# 判定する（default-deny）。
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

  # 2) メソッドは GET / POST / PATCH のみ（PUT / DELETE は宛先を問わず拒否）
  case "$method" in
    GET|POST|PATCH) : ;;
    *) die "gh api の ${method} メソッドは許可されていません（GET / POST / PATCH のみ）" 3 ;;
  esac

  # 3) エンドポイント（最初の位置引数）を特定。値を取る api フラグは読み飛ばす。
  #    クラスタ形式（-iXDELETE 等）は値フラグ一覧に一致しないので素通りするが、
  #    その場合は次の引数が本来のエンドポイントになるため問題ない。
  endpoint=""
  skip=0
  seen_api=0
  for a in "${args[@]}"; do
    if [ "$seen_api" -eq 0 ]; then seen_api=1; continue; fi   # "api" 自体
    if [ "$skip" -eq 1 ]; then skip=0; continue; fi
    case "$a" in
      -X|--method|-f|--raw-field|-F|--field|-H|--header|-q|--jq|-t|--template|--input|-p|--preview|--cache|--hostname)
        skip=1 ;;
      -*) : ;;
      *) endpoint="$a"; break ;;
    esac
  done
  ep="${endpoint%%\?*}"   # クエリ除去
  ep="${ep%/}"            # 末尾スラッシュ除去

  if [ "$method" != "GET" ]; then
    # 書き込みを許可するエンドポイント（コメント本体 / スレッド返信 / リアクション）
    case "$ep" in
      */pulls/*/comments|*/issues/*/comments|\
      */pulls/comments/*|*/issues/comments/*|\
      */pulls/*/comments/*/replies|\
      */pulls/comments/*/reactions|*/issues/comments/*/reactions|\
      */pulls/*/comments/*/reactions|*/issues/*/comments/*/reactions)
        : ;;
      *reviews*)
        die "gh api でのレビュー投稿（${endpoint}）は許可されていません（bot 承認の防止）" 3 ;;
      *)
        die "gh api の書き込みは ${method} ${endpoint:-（宛先不明）} — コメント／リアクション系エンドポイント以外は許可されていません" 3 ;;
    esac
  fi
fi

# --- トークンを注入して実行 -------------------------------------------------
TOKEN="$(cd "$SCRIPT_DIR/.." && npm run --silent gh-token)"
export GH_TOKEN="$TOKEN"
export GITHUB_TOKEN="$TOKEN"

exec gh "$@"
