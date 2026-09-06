# Claude Code Instructions

このプロジェクトの仕様・タスク・開発フローは以下を参照してください。

- `docs/REQUIREMENTS.md` … 仕様
- `docs/TASKS.md` … タスク一覧
- `docs/DEVELOPMENT.md` … 開発フロー・ブランチ運用・権限制約（作業前に必読）

## 実装方針

- 指定されたタスクだけを実装する
- 後続タスクの機能を先回りして実装しない
- シンプルな実装を優先する
- 不要なライブラリを追加しない

## Git

- 1タスクにつき1ブランチで作業する
- 実装後にcommitする
- GitHubへpushする
- main向けのPull Requestを作成する
