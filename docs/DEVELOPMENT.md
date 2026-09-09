# 開発フロー

このプロジェクトを Claude Code（および後日 Codex）で継続開発するための手順とルール。
仕様は `docs/REQUIREMENTS.md`、タスクは `docs/TASKS.md` を参照。

## 全体の流れ

1. `docs/TASKS.md` から次のタスクを1つ選ぶ
2. **そのタスクの「完成条件」を `docs/TASKS.md` に明記する**（実装前。詳細は下記）
3. 最新の `main` からタスク用ブランチを作成する（1タスク1ブランチ）
4. 実装 → ローカルで動作確認 → コミット
5. GitHub へ push して `main` 向けの Pull Request を作成する
6. レビュー（当面はユーザー、のちに Codex）
7. 指摘に対応して push し直す
8. ユーザーがマージする

## 完成条件（Definition of Done）

- **各タスクに着手する前に**、そのタスクの「完成条件」を `docs/TASKS.md` の
  該当タスク配下に `### 完成条件` として書く（チェックリスト形式）。
- 完成条件は「満たしているか一目で判定できる」粒度にする（例:「+ボタンで999まで増える／999で止まる」）。
- 完成条件の追記は、実装ブランチ内で実装と同じ PR に含めてよい。
- PR 説明に完成条件を転記し、達成状況をチェックして示す。
- Codex / レビュアーはこの完成条件とタスクのスコープを基準にレビューする（`AGENTS.md`）。

## ブランチ運用

- ブランチは必ず**最新の `main` から**切る：

  ```bash
  git checkout main
  git fetch origin
  git pull --ff-only origin main
  git checkout -b feature/<task-name>
  ```

- 命名は `feature/<内容>`（例: `feature/counter-js`, `feature/save-localstorage`）
- `main` はブランチ保護済み。直接 push・force push・マージは不可。変更は必ず PR 経由。

## Claude Code の権限制約（`.claude/settings.json` の deny）

Claude からは以下が**実行できない**。意図的な制約なので回避しようとしないこと。

| 禁止 | 代替 |
| --- | --- |
| `gh pr merge` / `gh pr review` | マージ・承認はユーザーが行う |
| `git merge`（`--ff-only` 含む） | `main` の更新は `git pull --ff-only` を使う |
| `git push --force` / `-f` | やり直したい場合は**最新 `main` から新しいブランチを切り直す**（force push しない） |
| `git branch -D` / リモートブランチ削除 | 不要ブランチの削除はユーザーが GitHub UI 等で行う |

- コミット済みの内容を作り直す必要が出たら、`git push --force` ではなく
  「新しいブランチ名で main から作り直し、変更を持っていく」で対応する。

## GitHub App 認証（Claude Code / Codex からの GitHub 操作）

Claude Code などから `git` / `gh` を使う際の認証を、個人アカウントの
トークンではなく **GitHub App のインストールアクセストークン**で行う。

### セットアップ（1回だけ）

1. GitHub App を作成し、対象リポジトリにインストールする（作成済みならスキップ）。
   - 付与する権限は**最小限**にする:
     `Contents: Read and write`（push）、`Pull requests: Read and write`
     （PR 作成・コメント）、`Metadata: Read-only`。
   - `Workflows` 権限は**付与しない**（`.github/workflows/` を変更する push は
     GitHub 側で拒否される。CI 変更は人手で push する）。
   - `Actions` は付与するとしても Read のみ。
2. App の秘密鍵（`.pem`）を**リポジトリ外**に置く:

   ```bash
   mkdir -p ~/.config/github-apps
   mv /path/to/downloaded.pem ~/.config/github-apps/claude-code.pem
   chmod 600 ~/.config/github-apps/claude-code.pem
   ```

3. リポジトリ直下に `.env` を作成する（`.env.example` をコピー）:

   ```bash
   cp .env.example .env
   # .env を編集して App ID / インストール ID を実際の値にする
   ```

   - `GITHUB_APP_ID`: App 設定ページの "App ID"
   - `GITHUB_APP_INSTALLATION_ID`: `https://github.com/settings/installations/XXXXXXXX` の数字
   - `GITHUB_APP_PRIVATE_KEY_PATH`: 既定のままなら `~/.config/github-apps/claude-code.pem`
   - `.env` と `.pem`、トークンキャッシュはいずれも Git 管理外（コミットしない）

4. **git の credential helper を登録する**（クローンごとに1回）。
   HTTPS・github.com の認証を App トークンにする。

   ```bash
   git config credential.https://github.com.helper ""
   git config --add credential.https://github.com.helper \
     "$PWD/scripts/git-credential-github-app.sh"
   ```

   - 1行目の空文字は、既存 helper（osxkeychain 等）をこのホストで無効化するため。
   - 絶対パスで登録される（`.git/config`、Git 管理外）。リポジトリを移動したら
     登録し直す。

### 使い方

**git**: 追加のコマンドは不要。`git push` / `git fetch`（HTTPS・github.com）が
自動で App トークンを使う。

```bash
git push -u origin HEAD
```

**gh**: `scripts/with-github-app.sh` 経由で実行する（`GH_TOKEN` を注入）。
このラッパーは**許可リスト方式**で、実行できるのは次の操作だけ:

- `gh pr create|view|list|status|checks|diff|comment|ready`
- `gh repo view`
- `gh api` — **読み取り専用**。メソッド／本文を指定しうるフラグ
  （`-X` / `--method` / `-f` / `-F` / `--field` / `--raw-field` / `--input`、
  および `-iXPOST` のような結合形）が1つでもあれば拒否する。
  これらが無い `gh api` は必ず GET になるので、宛先を問わず書き込みは起きない

それ以外・エイリアス・拡張は終了コード 3 で拒否する。

書き込みが必要な操作は、引数を解析して安全性を判定するのではなく、
**専用スクリプト**または許可済みサブコマンドを使う:

| したいこと | 使うもの |
| --- | --- |
| PR 直下にコメント | `scripts/with-github-app.sh gh pr comment <n> --body ...` |
| PR 作成 | `scripts/with-github-app.sh gh pr create --fill` |
| レビュースレッドへ返信 | `scripts/gh-review-reply.sh <pr> <comment-id> [body-file]` |

```bash
echo '対応しました。' | scripts/gh-review-reply.sh 7 3964156069
```

`gh-review-reply.sh` は宛先を `origin` の OWNER/REPO から導出し、PR 番号と
コメント ID は数字のみを受け付け、本文は JSON で渡す（フラグとして解釈されない）。

**トークンだけ取得**（デバッグ用、stdout に1行）:

```bash
npm run gh-token
```

- トークンは `~/.config/github-apps/claude-code.token.json`（`0600`、親ディレクトリ
  `0700`）にキャッシュされ、有効期限まで5分以上あれば再利用する。切れていれば
  自動で再発行する。保存先は固定で、変更用の設定は用意していない。
- 秘密鍵・環境変数が無い場合は原因を示すメッセージを出して非ゼロ終了する。
- credential helper は github.com の HTTPS 以外には関与しない（他ホスト・SSH は
  従来どおり）。SSH リモートでは App トークンは使われないため、App 経由で
  操作したいリポジトリは HTTPS リモートにする。
- ホスト判定は正規化してから行う（`GitHub.com` のような大文字表記、
  `github.com:443` のような既定ポート付きも同一ホストとして扱う）。
  これらを取りこぼすと個人認証へフォールバックしてしまうため。
- **App トークンを取得できない場合は fail closed**。helper が `quit=1` を返し、
  git は後続の helper や `GIT_ASKPASS`・対話入力に進まずに中断する。
  個人アカウントの資格情報へ黙って切り替わることはない。原因（`.env` 未設定、
  秘密鍵の不備など）は stderr に表示されるので、それを直してから再実行する。

### 制約

- `.claude/settings.json` の deny リスト（`gh pr merge` / `gh pr review` /
  force push など）は App 化後も維持する。App 化の目的は操作主体の分離であり、
  権限を広げるものではない。
- `git` は素の `git` として実行するため、deny リストが従来どおり照合される。
- `--web` / `-w` はラッパーで一律拒否する。ブラウザ側でログイン中の個人
  アカウントとして PR やコメントが作られてしまい、App 名義という前提が
  崩れるため。
- `gh` は `with-github-app.sh` 経由でのみ App トークンを使う。ラッパーは
  許可リスト方式（default-deny）。`gh` 以外・許可外サブコマンド・エイリアス・
  拡張を拒否し、`gh api` は読み取り専用に固定する。すべてトークン取得前に
  拒否（終了コード 3）。
- 書き込みは「引数から実リクエストを推測して判定する」のではなく、URL と
  メソッドをスクリプト側が組み立てる専用コマンドとして提供する
  （`scripts/gh-review-reply.sh`）。推測に頼らないぶん迂回の余地が無い。
- App から可能な書き込みは「push（credential helper）」「PR 作成・PR コメント
  （許可済みサブコマンド）」「レビュースレッド返信（専用スクリプト）」のみ。
  マージ・force push・ブランチ削除・PR 承認・リポジトリ設定変更はいずれも
  経路が存在しない。加えて `main` のブランチ保護と App 権限の最小化
  （`workflows` 無し）で多重に守る。
- bot による PR 承認は経路が無いため起こらない。さらに厳密にしたい場合は
  CODEOWNERS で人によるレビューを必須にする。

## ローカル動作確認

フレームワークもビルドも無い。静的サーバーで開くだけ。

```bash
python3 -m http.server 8000
# http://localhost:8000 を開く
```

## テスト（タスク3以降）

- Jest を使用。`npm test` で実行。
- `package.json` / `node_modules/` を追加するのはテスト導入タスクのときのみ
  （`node_modules/` は `.gitignore` 済み）。
- PR 作成時に GitHub Actions でテストが走るようにする。

## アクセシビリティの約束

- カウント値は視覚的な7セグメント要素（`aria-hidden="true"`）とは別に、
  `.sr-only` の `role="status" aria-live="polite"` テキストで表現している。
- **カウントを変更する処理では、この `.sr-only` テキストも必ず更新する**こと。

## Codex レビュー

- PR に `@codex review` とコメントするとレビューが走る。
- **`@codex review` は必ずユーザー本人のアカウントから投稿する。**
  GitHub App（bot）名義のコメントに書いても Codex は反応しないため。
- Claude は push 後に対応内容の**サマリコメントを PR に投稿する**（bot 名義）。
  ただしその本文に `@codex review` は書かない（効かないため）。
  レビューの起動はユーザーが自分のアカウントから行う。
- レビュー方針は `AGENTS.md` を参照。
- レビューコメントへの返信は日本語で、対応内容と対応コミットを簡潔に書く。
  返信は `scripts/gh-review-reply.sh` を使う（bot 名義で投稿される）。

## 数字表示の仕様（再掲）

- カウント範囲は `0`〜`999`。負数にしない。`999` で頭打ち。
- ディスプレイは3桁固定。`.digit` に `data-value="0"`〜`"9"` を与えると点灯、
  与えないと全消灯（先頭の余分な桁を表現）。
- 例: `5` → `[消灯][消灯][5]` / `42` → `[消灯][4][2]` / `999` → `[9][9][9]`
