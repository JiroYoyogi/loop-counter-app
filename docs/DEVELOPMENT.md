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
   - 必要な権限の目安: `Contents: Read and write`、`Pull requests: Read and write`、
     `Metadata: Read-only`
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

### 使い方

トークンだけ取得（stdout に1行）:

```bash
npm run gh-token
```

`git` / `gh` を App トークンで実行:

```bash
scripts/with-github-app.sh gh pr create --fill
scripts/with-github-app.sh git push -u origin HEAD
```

- トークンは `~/.config/github-apps/claude-code.token.json`（`0600`、親ディレクトリ
  `0700`）にキャッシュされ、有効期限まで5分以上あれば再利用する。切れていれば
  自動で再発行する。保存先は固定で、変更用の設定は用意していない。
- 秘密鍵・環境変数が無い場合は原因を示すメッセージを出して非ゼロ終了する。
- `with-github-app.sh` の `git` 実行には **git 2.31 以上**が必要（トークンを
  argv に載せず `GIT_CONFIG_*` 環境変数でヘッダを渡すため）。
- `origin` が HTTPS の GitHub リモートでない場合、`with-github-app.sh git ...` は
  「App トークンが使われない」と明示エラーで停止する。
  `git remote set-url origin https://github.com/OWNER/REPO.git` で切り替える。

### 制約

- `.claude/settings.json` の deny リスト（`gh pr merge` / `gh pr review` /
  force push など）は App 化後も維持する。App 化の目的は操作主体の分離であり、
  権限を広げるものではない。
- `with-github-app.sh` は、これらの禁止操作をラッパー経由で回避できないよう
  同等のコマンドを検出して拒否する（終了コード 3）。

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
- レビュー方針は `AGENTS.md` を参照。
- レビューコメントへの返信は日本語で、対応内容と対応コミットを簡潔に書く。

## 数字表示の仕様（再掲）

- カウント範囲は `0`〜`999`。負数にしない。`999` で頭打ち。
- ディスプレイは3桁固定。`.digit` に `data-value="0"`〜`"9"` を与えると点灯、
  与えないと全消灯（先頭の余分な桁を表現）。
- 例: `5` → `[消灯][消灯][5]` / `42` → `[消灯][4][2]` / `999` → `[9][9][9]`
