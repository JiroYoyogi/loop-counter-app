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

# CDPATH が export されていると cd が解決先を stdout に出し、コマンド置換に
# 混入して SCRIPT_DIR が壊れる。CDPATH= で無効化し、-- でパスを引数として固定する。
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

die() {
  echo "[with-github-app] $1" >&2
  exit "${2:-1}"
}

[ "$#" -ge 1 ] || die "usage: scripts/with-github-app.sh gh <args...>" 2
[ "$1" = "gh" ] || die "このラッパーで実行できるのは gh のみ（git は credential helper 経由）。指定: $1" 3
shift
args=("$@")

# --- フラグ方針: ロングオプションのみ受け付ける -----------------------------
# 引数の見た目から「フラグか値か」を推測すると、-dw のような結合形を取りこぼす
# 一方で -bFixed のような値の連結を誤検知する。どちらに寄せても破綻するので、
# 推測をやめて入力の形を絞る:
#   - 短縮フラグ（- に英字が続くもの）は一律拒否 → -w / -e / -dw / -de も自動的に不可
#   - --web / --editor は個別に拒否（ブラウザ／外部エディタが個人アカウントで
#     動くため。理由が分かるメッセージを出す）
# 値そのものはダッシュで始まらない限り影響を受けない（"- 箇条書き" 等は通る）。
# なお安全性の最終的な担保は exec 直前の環境変数の無害化（下部）であり、
# ここでの拒否は入力を単純に保ち、分かりやすいエラーを出すためのもの。
for a in "${args[@]}"; do
  case "$a" in
    --web|--web=*)
      die "--web は使えません（ブラウザ上の個人アカウントで操作されるため）: ${a}" 3 ;;
    --editor|--editor=*)
      die "--editor は使えません（外部エディタが GH_TOKEN を継承して起動するため）。本文は --body / --body-file で渡してください: ${a}" 3 ;;
    --*)
      : ;;
    -[A-Za-z]*)
      die "短縮フラグは使えません。ロングオプションを使ってください（例: -q→--jq, -L→--limit, -b→--body, -R→--repo）: ${a}" 3 ;;
  esac
done

# --- 実効サブコマンド（先頭2語）を特定 -------------------------------------
# 値を取るのは --repo だけ（短縮フラグは上で拒否済みなので考慮不要）。
# 位置に依存せず読み飛ばすので `gh --repo o/r pr view` も `pr view` と判定できる。
words=()
skip_next=0
for a in "${args[@]}"; do
  if [ "$skip_next" -eq 1 ]; then skip_next=0; continue; fi
  case "$a" in
    --repo) skip_next=1 ;;
    -*)     : ;;                    # 値なしフラグ（--json など）は読み飛ばす
    *)      words+=("$a"); [ "${#words[@]}" -ge 2 ] && break ;;
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
      graphql)
        die "gh api graphql は許可されていません" 3 ;;
    esac
  done

  # Authorization ヘッダの指定を拒否する。-H / --header で渡されると注入した
  # App トークンより優先され、個人アカウントの認証で実行されてしまう。
  # どのフラグ経由かを解析せず、引数のどこかに現れた時点で拒否する
  # （gh api の引数はエンドポイント・ヘッダ・jq フィルタ程度で、本文フラグは
  #   既に禁止しているため、この単純な判定で誤検知しない）。
  for a in "${args[@]}"; do
    case "$(printf '%s' "$a" | tr '[:upper:]' '[:lower:]')" in
      *authorization:*)
        die "Authorization ヘッダの指定は許可されていません（注入した App トークンを上書きして個人認証になるため）: ${a}" 3 ;;
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
#
# その前に、呼び出し元から継承した git のコマンドライン設定を破棄する。
# 環境変数だけで（ファイルの配置なしに）次の2つが成立してしまうため:
#   - GIT_CONFIG_PARAMETERS は GIT_CONFIG_COUNT より優先されるので、
#     残すと下の hooksPath 無効化がそのまま上書きされる
#   - http.<url>.extraheader に個人の Authorization を注入されると、
#     gh が内部で行う git push が個人の資格情報で実行される
# GIT_CONFIG_COUNT=1 に固定することで、git が読むのは下で設定する
# KEY_0 / VALUE_0 だけになり、継承された KEY_1 以降は参照されない。
# （この env は gh とその子プロセスにのみ効き、手元の git 操作には影響しない）
unset GIT_CONFIG_PARAMETERS GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM
# gh はカレントディレクトリの git リモートから対象リポジトリを決める。
# GIT_DIR は `git -C` より優先されるため、残すと解決先を差し替えられる。
unset GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR GIT_CEILING_DIRECTORIES
export GIT_CONFIG_COUNT=1
export GIT_CONFIG_KEY_0=core.hooksPath
export GIT_CONFIG_VALUE_0=/nonexistent/with-github-app-no-hooks

# --- トークンを注入して実行 -------------------------------------------------
# 空トークンを export すると gh は「未設定」とみなして保存済みの個人認証へ
# フォールバックする。取得できなければ fail closed で止める。
if ! TOKEN="$(CDPATH= cd -- "$SCRIPT_DIR/.." && npm run --silent gh-token)" || [ -z "$TOKEN" ]; then
  die "App トークンを取得できませんでした。個人認証へフォールバックせず中断します" 4
fi
export GH_TOKEN="$TOKEN"
export GITHUB_TOKEN="$TOKEN"

exec gh "$@"
