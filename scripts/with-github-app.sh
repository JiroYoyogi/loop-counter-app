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
#   - git の場合は GIT_CONFIG_* 環境変数で HTTPS の Authorization ヘッダを
#     この呼び出しの間だけ注入する（トークンを argv に載せない）
#   その上で、渡されたコマンドをそのまま実行する。
#
# 制約:
#   .claude/settings.json の deny リストに相当する操作（マージ・レビュー承認・
#   force push など）はこのラッパー経由でも実行できないようガードする。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

die() {
  echo "[with-github-app] $1" >&2
  exit "${2:-1}"
}

if [ "$#" -eq 0 ]; then
  die "usage: scripts/with-github-app.sh <command> [args...]" 2
fi

cmd="$1"
sub="${2:-}"
sub2="${3:-}"
# 前後にスペースを付けて「単語境界」で部分一致できるようにする。
all=" $* "

# --- #1: deny 相当の操作をガード（トークン発行より前に弾く） ---------------
deny() { die "禁止された操作です（.claude/settings.json の deny 相当）: $1" 3; }

if [ "$cmd" = "gh" ]; then
  case "$sub $sub2" in
    "pr merge")   deny "gh pr merge" ;;
    "pr review")  deny "gh pr review" ;;
    "repo delete") deny "gh repo delete" ;;
  esac
  case "$all" in
    *" --method DELETE "*|*" --method=DELETE "*|*" -X DELETE "*|*" -X=DELETE "*)
      deny "gh api DELETE" ;;
  esac
fi

if [ "$cmd" = "git" ]; then
  case "$all" in
    *" push "*)
      case "$all" in
        *" --force "*|*" -f "*|*" --force-with-lease"*|*" --mirror "*|*" --delete "*|*" -d "*)
          deny "git push (force/delete/mirror)" ;;
      esac
      case "$all" in
        *" main "*|*" main:"*|*":main "*|*" HEAD:main "*)
          deny "git push で main を対象にする操作" ;;
      esac
      ;;
    *" branch "*)
      case "$all" in
        *" -D "*|*" --delete "*|*" -d "*) deny "git branch の削除" ;;
      esac
      ;;
  esac
fi

# --- #2: 非 HTTPS の github リモートを検出して明示エラー --------------------
if [ "$cmd" = "git" ]; then
  remote_url="$(git remote get-url origin 2>/dev/null || true)"
  case "$remote_url" in
    https://github.com/*) : ;;                 # OK
    "") : ;;                                   # origin 無し。git 側の挙動に任せる
    *github.com*|*github.com:*)
      die "origin が HTTPS ではないため App トークンが使われません: ${remote_url}
  次のように HTTPS へ切り替えてください:
    git remote set-url origin https://github.com/OWNER/REPO.git" 5 ;;
    *) : ;;                                    # github 以外のリモートは対象外
  esac
fi

# --- トークン取得 ---------------------------------------------------------
TOKEN="$(cd "$SCRIPT_DIR/.." && npm run --silent gh-token)"
export GH_TOKEN="$TOKEN"
export GITHUB_TOKEN="$TOKEN"

# --- #3: git は GIT_CONFIG_* 経由でヘッダ注入（argv に載せない） -----------
if [ "$cmd" = "git" ]; then
  gitver="$(git --version | awk '{print $3}')"
  gmajor="${gitver%%.*}"
  gminor="${gitver#*.}"; gminor="${gminor%%.*}"
  case "$gmajor" in ''|*[!0-9]*) gmajor=0 ;; esac
  case "$gminor" in ''|*[!0-9]*) gminor=0 ;; esac
  if [ "$gmajor" -lt 2 ] || { [ "$gmajor" -eq 2 ] && [ "$gminor" -lt 31 ]; }; then
    die "git >= 2.31 が必要です（GIT_CONFIG_* を使用）。現在: ${gitver}" 4
  fi

  basic="$(printf 'x-access-token:%s' "$TOKEN" | base64 | tr -d '\n')"
  base="${GIT_CONFIG_COUNT:-0}"
  case "$base" in ''|*[!0-9]*) base=0 ;; esac
  eval "export GIT_CONFIG_KEY_${base}='http.https://github.com/.extraheader'"
  eval "export GIT_CONFIG_VALUE_${base}=\"Authorization: Basic \${basic}\""
  export GIT_CONFIG_COUNT="$((base + 1))"
fi

exec "$@"
