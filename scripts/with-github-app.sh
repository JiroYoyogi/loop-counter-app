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
#   - 実行できるのは `git` / `gh` のみ（`sh -c ...` 等での迂回を防ぐ）。
#   - .claude/settings.json の deny リストに相当する操作（マージ・レビュー承認・
#     force push など）はこのラッパー経由でも実行できないようガードする。
#   - push/取得に使われる URL が HTTPS の github でなければ明示的に失敗する。

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

# --- #1: 実行対象を git / gh に限定（トークン発行より前に弾く） -------------
# これ以外（sh -c ... や env ... など）を許すと、GH_TOKEN を継承したまま
# 任意コマンドを実行でき、deny ガードを迂回できてしまう。
deny() { die "禁止された操作です（.claude/settings.json の deny 相当）: $1" 3; }

case "$cmd" in
  git|gh) : ;;
  *) deny "git / gh 以外のコマンド（${cmd}）" ;;
esac

# --- #1: deny 相当の操作をガード（トークン発行より前に弾く） ---------------

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

# --- #2: 実際に使われる push/取得 URL が非 HTTPS の github なら明示エラー ----
# fetch URL だけでなく push URL（remote.<name>.pushurl）も検査する。
# 対象リモートは push/fetch/pull/ls-remote の引数から推定（無ければ origin）。
if [ "$cmd" = "git" ]; then
  target_remote=""
  case "$all" in
    *" push "*|*" fetch "*|*" pull "*|*" ls-remote "*)
      seen_sub=0
      for a in "$@"; do
        if [ "$seen_sub" -eq 0 ]; then
          case "$a" in push|fetch|pull|ls-remote) seen_sub=1 ;; esac
          continue
        fi
        case "$a" in
          -*) continue ;;
          *) target_remote="$a"; break ;;
        esac
      done
      [ -z "$target_remote" ] && target_remote="origin"
      ;;
  esac

  if [ -n "$target_remote" ]; then
    case "$target_remote" in
      *://*|*@*:*)
        # URL を直接指定している場合はそのまま検査対象にする。
        check_urls="$target_remote" ;;
      *)
        # リモート名: fetch URL と push URL の両方を検査する。
        check_urls="$(git remote get-url "$target_remote" 2>/dev/null || true)
$(git remote get-url --push "$target_remote" 2>/dev/null || true)" ;;
    esac
    while IFS= read -r u; do
      [ -z "$u" ] && continue
      case "$u" in
        https://github.com/*) : ;;              # OK
        *github.com*)
          die "App トークンが使われない GitHub リモートです（HTTPS ではありません）: ${u}
  リモート '${target_remote}' を HTTPS に切り替えてください:
    git remote set-url --push ${target_remote} https://github.com/OWNER/REPO.git" 5 ;;
        *) : ;;                                 # github 以外のリモートは対象外
      esac
    done <<EOF
${check_urls}
EOF
  fi
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
