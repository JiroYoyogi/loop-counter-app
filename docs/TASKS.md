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
  ラッパーは許可リスト方式（default-deny）。許可 gh サブコマンド以外・
  エイリアス・拡張を拒否し、`gh api` は**読み取り専用**に固定する。
- 書き込みは専用スクリプトで提供する（`scripts/gh-review-reply.sh`）。
  URL とメソッドをスクリプト側が組み立てるため、引数解析による判定漏れが無い。
  → bot 名義のレビュー返信は可能、force 更新やマージ等は不可。
- App の権限は最小限（`contents:write` / `pull_requests:write` / `metadata:read`）。
  `workflows` は付与しない。
- ライブラリ追加あり。`@octokit/auth-app`（App 認証）と `tsx`（TS 実行）を
  `devDependencies` に追加する。`node_modules/` は `.gitignore` 済み。
- `docs/DEVELOPMENT.md` に GitHub App のセットアップ手順と使い方を追記する。
- `.claude/settings.json` の deny リストは変更しない（現状維持）。
  App 化の目的は操作主体の分離であり、`gh pr merge` / `gh pr review` /
  force push 等の禁止はこれまで通り維持する。
  なお deny リスト自体の抜け穴（refspec 先頭の `+` による force push など）は
  App 化以前から存在するものなので、タスク7として切り出す。
- アプリ本体（`index.html` / `src` / カウンター機能）には手を加えない。

### 完成条件

- `~/.config/github-apps/claude-code.pem` と必要な環境変数
  （App ID・インストール ID・秘密鍵パス）を用意した状態で
  `npx tsx scripts/github-app-auth.ts` を実行すると、有効なインストール
  アクセストークンが標準出力に1行で返る。
- credential helper 登録後、`git ls-remote origin` / `git push`（HTTPS）が
  App トークンで成功する（`git credential fill` の password が `ghs_` で始まる）。
- `scripts/with-github-app.sh gh ...` で許可リスト内の操作（`gh pr create` /
  `gh pr comment` / `gh pr view` / `gh api` の GET）が成功する。
- `scripts/gh-review-reply.sh <pr> <comment-id>` でレビュースレッドに
  App（bot）名義の返信が投稿できる。
- `scripts/with-github-app.sh` に次を渡すと、トークン取得前に終了コード 3 で拒否される:
  `gh pr merge`、`gh -R o/r pr merge`、エイリアス、`git`、`sh -c ...`、
  `gh api` にメソッド／本文フラグを含むもの
  （`--method` / `--field` / `--raw-field` / `--input`）、`gh api graphql`、
  `gh api` に `Authorization:` を含む引数
  （App トークンを上書きして個人認証になるため）。
- `scripts/gh-review-reply.sh` は PR 番号・コメント ID が数字でなければ拒否し、
  宛先は `origin` から導出する（呼び出し側がリポジトリを指定できない）。
  ホストは credential helper と同様に正規化し（`GitHub.com` / `github.com:443`
  も受け付ける）、`user:token@` が埋め込まれた origin は拒否する。
  `GIT_DIR` 等でリポジトリ解決先を差し替えられないよう、git 関連の環境変数を
  破棄してから `origin` を読む。
- ラッパーはロングオプションのみ受け付ける。`-` に英字が続く引数
  （`-w` / `-e` / `-dw` / `-de` / `-q` / `-bFixed` など）は一律で終了コード 3
  で拒否され、`--web` / `--editor` は理由付きのメッセージで拒否される。
  外部プロセス（エディタ・ブラウザ・ページャ）の起動は、フラグ判定ではなく
  環境変数の無害化で防ぐ。
- `GH_EDITOR` / `EDITOR` に任意のスクリプトを指定しても、ラッパー経由では
  そのスクリプトが起動しない（外部プロセスの指定先を無害化して exec する）。
- `GIT_CONFIG_PARAMETERS` / `GIT_CONFIG_COUNT` に git 設定を仕込んでラッパーを
  起動しても、gh から見える git の実効設定に `core.hooksPath` の上書きや
  `extraheader` の注入が現れない。
- `CDPATH` が export された環境でも、3スクリプトすべてが正常に動作する
  （`cd` の出力がスクリプトのパス解決やトークン取得に混入しない）。
- `GIT_DIR` に別クローンを指定して `scripts/gh-review-reply.sh` を実行しても、
  投稿先は `origin`（このリポジトリ）のままになる。
- `GITHUB_APP_PRIVATE_KEY_PATH` がディレクトリを指す場合も、キャッシュが
  有効なうちに原因を表示して非ゼロ終了する。
- App トークンを取得できないとき、credential helper は `quit=1` を返して
  git を中断させる（個人認証へフォールバックしない）。
- credential helper は `github.com` / `github.com:443` / `GitHub.com` の
  いずれの表記でも App トークンを返す。`gitlab.com` や
  `github.com.evil.example` のような別ホストには関与しない。
- 2回目以降の実行では、キャッシュした未期限切れトークンを再利用し、
  GitHub への新規リクエストを行わない。
- キャッシュされたトークンが期限切れ（または残り 5 分未満）の場合は
  自動で再発行され、新しいトークンが返る。
- 秘密鍵・トークンキャッシュはいずれもリポジトリ配下に出力されず、
  `git status` に現れない。
- キャッシュファイル／親ディレクトリの権限が `0600` / `0700` と異なる場合、
  **キャッシュの鮮度に関わらず**その値に揃えられる（再利用時も再発行時も）。
  緩い権限（`0644` / `0755`）だけでなく厳しすぎる権限（`0400` / `0500`）も対象
  （後者のままだと再発行時の書き込みが `EACCES` で失敗するため）。
  揃えられない場合はトークンを返さず非ゼロ終了する。
- 秘密鍵ファイルや環境変数が無い場合は、原因が分かるエラーメッセージを
  表示して非ゼロ終了する（スタックトレースだけで落ちない）。
  キャッシュが有効な場合でも秘密鍵の存在を確認するため、鍵の削除・移動は
  その場で検知される。
- キャッシュのトークンが空・空白のみの場合はキャッシュミスとして扱って
  再発行する。ラッパーは空トークンなら gh を実行せず終了コード 4 で中断する。
- `@octokit/auth-app` と `tsx` が `package.json` の `devDependencies` に
  追加されている。`npm test`（既存の Jest）はこれまで通り通る。
- `docs/DEVELOPMENT.md` にセットアップ手順が記載されている。
- `.claude/settings.json` の deny リストが変更されていない。
## 7. `.claude/settings.json` の deny リストの棚卸し

- タスク6のレビューで、refspec 先頭の `+`（強制更新）が現在の deny で
  捕捉されないことが判明した（例: `git push origin +HEAD:refs/heads/x`）。
  これは**タスク6以前から存在する穴**で、App 化とは独立している。
- 1行足すのではなく、部分一致ベースのパターン全体を棚卸しする。
  取りこぼし（拒否すべきものが通る）と過剰拒否（正当な操作が止まる）の
  両方を見る。

既知の懸念（実装前に実機で要確認）:

| パターン | 懸念 |
| --- | --- |
| `Bash(git push:*--force*)` / `*-f*` | `+refspec` 形式を捕捉しない。`-f` の部分一致は `--follow-tags` 等まで拒否する可能性 |
| `Bash(git push origin main:*)` | `git push origin HEAD:main` を捕捉しない |
| `Bash(gh api:*--method DELETE*)` / `*-X DELETE*` | `-XDELETE`（連結形）や `--method=DELETE` を捕捉しない |

- 実装前に Claude Code の deny パターンの照合仕様（前方一致か部分一致か、
  `:` の意味、大小文字の扱い）を**実機で確認**する。推測で書かない。
- `.claude/settings.json` は Claude 自身の権限設定なので、変更内容は
  ユーザーが必ずレビューしてからマージする。
- アプリ本体（`index.html` / `counter.js` / `storage.js` 等）には手を加えない。

### 完成条件

- deny パターンの照合仕様を実機で確認した結果が PR 説明に記載されている。
- 次がいずれも拒否される:
  - `git push origin +HEAD:refs/heads/<branch>`（refspec による force push）
  - `git push origin HEAD:main`
  - `gh api -XDELETE ...` / `gh api --method=DELETE ...`
- 次がいずれも**拒否されない**（過剰拒否の確認）:
  - `git push -u origin HEAD`（feature ブランチへの通常 push）
  - `git push origin feature/<name>`
  - `gh api repos/OWNER/REPO`（GET）
- 既存の禁止が引き続き拒否される:
  `gh pr merge` / `gh pr review` / `git merge` / `git push --force` /
  `git branch -D` / `gh repo delete`
- `docs/DEVELOPMENT.md` の「Claude Code の権限制約」表が更新後の内容と一致する。
- `npm test` が通り、アプリ本体に変更がない。

## 8. GitHub App 認証の設計判断をドキュメントに残す

- タスク6で得た設計判断を `docs/github-app-auth-design.md` に記録する。
  次のプロジェクト（リモートサーバーで Claude Code を動かして GitHub へ
  push する構成）の冒頭で読ませ、同じ試行錯誤を繰り返さないため。
- 読み物ではなく**次回の作業指示として使える形**で書く。
  - 採用した判断を理由つきの Do / Don't で列挙する
  - **却下した案とその理由**を必ず含める（これが無いと再提案される）
  - `AGENTS.md` に貼れる脅威モデルの雛形をコピペ可能な形で置く
  - 検証済みの範囲と、サーバー版で再検討が必要な点を分けて書く
- 実装済みのスクリプトには手を加えない（記録のみ）。

### 完成条件

- `docs/github-app-auth-design.md` が存在し、次を含む:
  - 採用した設計判断と、それぞれの理由
  - 却下した案と、なぜ破綻したか
  - `AGENTS.md` 用の脅威モデル雛形（そのまま貼れる形）
  - この設計で**防げないこと**の明示
  - 検証済みの範囲 / サーバー版での未検証項目
  - `scripts/` の3スクリプトへの参照
- 既存のスクリプト（`scripts/*.ts` / `scripts/*.sh`）に変更がない。
- アプリ本体（`index.html` / `counter.js` / `storage.js` 等）に変更がない。
- `npm test` がこれまで通り通る。
