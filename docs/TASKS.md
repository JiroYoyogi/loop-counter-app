# タスク

## 1. プロジェクトの初期化

- index.htmlなど必要なファイルを準備する
- ./docs/design/style.jpg を参考にしたシンプルなカウンターをHTMLとCSSで作成する
- JavaScriptはこの段階では実装しない

### 完成条件

- ブラウザでページを表示できる
- 初期値として 0 が表示される
- マイナス、リセット、プラスのボタンが表示される
- JavaScriptによるカウンター機能は実装されていない

## 2. 3桁までの数字表示に対応する

- 7セグメント風の桁を3桁ぶん用意する（HTML / CSS のみ、JavaScriptは実装しない）
- 数値の桁数に応じて表示し、先頭の余分な桁は消灯させる（例: 5 → 「  5」、42 → 「 42」、999 → 「999」）
- 負数は扱わないため、符号「−」の表示要素は不要
- 初期表示は 0

### 完成条件

- 3桁ぶんのディスプレイが表示される
- 初期値として 0 が表示される（先頭2桁は消灯）
- JavaScriptによるカウンター機能は実装されていない

## 3. JSでカウンター機能を入れる

- プラスボタンを押すとカウントアップ（上限 999、999で頭打ち）
- マイナスボタンを押すとカウントダウン（下限 0、0で頭打ち。負数にしない）
- リセットボタンを押すとカウントが0になる
- カウント変更時にスクリーンリーダー向けテキスト（aria-live）も更新する
- Jestを導入してPRでテストが実行される

### 完成条件

- +ボタンでカウントが1増える。999のとき+を押しても999のまま
- -ボタンでカウントが1減る。0のとき-を押しても0のまま（負数にならない）
- RESETボタンでカウントが0になる
- カウントの変化がディスプレイの3桁表示に正しく反映される（先頭の余分な桁は消灯）
- カウント変更時に `.sr-only` の aria-live テキストも現在値に更新される
- `npm test` でカウントロジックのテストが通る
- PR作成時に GitHub Actions でテストが実行される
- localStorage への保存・復元は実装しない（タスク4のスコープ）

## 4. 保存出来る

- 保存ボタンを押すとローカルストレージに現在の数字が保存される
- リロードすると保存した数字がロードされる

### 完成条件

- SAVEボタンを押すと、その時点のカウント値が localStorage に保存される
- ページをリロードすると、保存済みの値があればその値から表示・カウントを再開する
- 保存済みの値が無い場合は従来どおり 0 から開始する
- localStorage の値が不正（数値でない・範囲外など）な場合は 0 にフォールバックし、アプリが壊れない
- 読み込んだ値もディスプレイの3桁表示と `.sr-only` の aria-live テキストに正しく反映される
- localStorage が使えない環境（無効化・例外）でもエラーで停止せず、保存なしとして動作する
- 保存・読み込みロジックは DOM 非依存の純粋関数に分離し、`npm test` でテストが通る
- SAVE 以外（+ / - / RESET）の操作では自動保存しない（明示的な保存のみ）

## 5. 追加実装

未定

### 完成条件

- （タスク着手時に記載する）

## 6. Claude Code の GitHub 操作を GitHub App 経由にする

- Claude Code から `git` / `gh` で行う GitHub 操作の認証を、個人アカウントの
  トークンではなく **GitHub App のインストールトークン**で行えるようにする。
- 秘密鍵（`.pem`）はリポジトリ外（`~/.config/github-apps/claude-code.pem`）に置く。
- 認証スクリプト `scripts/github-app-auth.ts` を追加する。
  - App ID / インストール ID / 秘密鍵パスは環境変数で受け取る。
  - App JWT を生成し、インストールアクセストークンを取得する。
  - 取得したトークンはキャッシュ（`~/.config/github-apps/claude-code.token.json` 等、
    リポジトリ外）し、有効期限内なら再利用、期限切れ・残り僅かなら再発行する。
  - 標準出力に有効なトークンだけを返す（`git` / `gh` から利用できる形）。
- `git` は credential helper（`scripts/git-credential-github-app.sh`）で認証する。
  クローンごとに `git config` で登録する（手順は `docs/DEVELOPMENT.md`）。
  ラッパーで `git` をくるまないため、deny リストの照合は従来どおり効く。
- `gh` は `scripts/with-github-app.sh` 経由で実行する（`GH_TOKEN` を注入）。
  ラッパーは `gh` 以外を実行できず、deny 相当（`gh pr merge` 等）を拒否する。
- ライブラリ追加あり。`@octokit/auth-app`（App 認証）と `tsx`（TS 実行）を
  `devDependencies` に追加する。`node_modules/` は `.gitignore` 済み。
- `docs/DEVELOPMENT.md` に GitHub App のセットアップ手順と使い方を追記する。
- `.claude/settings.json` の deny リストは変更しない（現状維持）。
  App 化の目的は操作主体の分離であり、`gh pr merge` / `gh pr review` /
  force push 等の禁止はこれまで通り維持する。
- アプリ本体（`index.html` / `src` / カウンター機能）には手を加えない。

### 完成条件

- `~/.config/github-apps/claude-code.pem` と必要な環境変数
  （App ID・インストール ID・秘密鍵パス）を用意した状態で
  `npx tsx scripts/github-app-auth.ts` を実行すると、有効なインストール
  アクセストークンが標準出力に1行で返る。
- credential helper 登録後、`git ls-remote origin` / `git push`（HTTPS）が
  App トークンで成功する（`git credential fill` の password が `ghs_` で始まる）。
- `scripts/with-github-app.sh gh ...` で読み取り（例: `gh repo view`）と
  PR 作成が成功する。
- `scripts/with-github-app.sh` に `git` や `sh -c ...`、`gh pr merge` 等を
  渡すと、トークン取得前に終了コード 3 で拒否される。
- 2回目以降の実行では、キャッシュした未期限切れトークンを再利用し、
  GitHub への新規リクエストを行わない。
- キャッシュされたトークンが期限切れ（または残り 5 分未満）の場合は
  自動で再発行され、新しいトークンが返る。
- 秘密鍵・トークンキャッシュはいずれもリポジトリ配下に出力されず、
  `git status` に現れない。
- 秘密鍵ファイルや環境変数が無い場合は、原因が分かるエラーメッセージを
  表示して非ゼロ終了する（スタックトレースだけで落ちない）。
- `@octokit/auth-app` と `tsx` が `package.json` の `devDependencies` に
  追加されている。`npm test`（既存の Jest）はこれまで通り通る。
- `docs/DEVELOPMENT.md` にセットアップ手順が記載されている。
- `.claude/settings.json` の deny リストが変更されていない。