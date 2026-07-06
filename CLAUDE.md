# CLAUDE.md

terraform-vdi は AWS WorkSpaces Pools 社内 VDI の Terragrunt IaC リポジトリ。
AI エージェントは本ファイルのハーネス規約に従って作業する。

## MUST NOT（絶対禁止）

- ❌ `terraform apply` / `terragrunt apply` / `run-all apply` を実行しない（人間の承認が必須。plan までで止まる）
- ❌ `terraform destroy` / state 操作（`state rm` / `state mv` / `import`）を実行しない
- ❌ `stack_vars.hcl` の Secrets Manager ARN・TGW ID を推測で書き換えない（不明なら「要確認」とコメント）
- ❌ `entra-id-metadata.xml` の中身をコミットしない（.gitignore 済み。プレースホルダーのまま維持）
- ❌ IAM ポリシーの `Resource = "*"` を新規追加しない（既存の pool_updater は既知の例外）

## 検証ループ（変更のたびに必ず回す）

すべての `.tf` 変更は以下の DOER → CHECKER サイクルで完結させる。
CHECKER が全て通るまで完了と報告しない。

```
1. 編集（DOER）
2. make fmt        → フォーマット自動修正
3. make validate   → 全ユニット構文検証
4. make lint       → tflint
5. 全部 PASS → 完了報告 / FAIL → 1 に戻る（最大 3 周。3 周で解決しなければ人間にエスカレーション）
```

## アーキテクチャ（3 分で把握する）

```
catalog/units/*      再利用可能な Terraform ユニット（8 個）
catalog/stacks/      ユニットを束ねるコンポジット（vdi-core）
live/                環境ごとの実体。root.hcl = S3 backend / stack_vars.hcl = 環境パラメータ
```

依存グラフ: `vpc → managed-ad → workspaces-pools ← saml-provider` / `vpc → image-builder → golden-image-updater ← workspaces-pools`

Golden Image 自動更新フロー: SSM Maintenance Window (日曜 AM2) → EventBridge → Lambda orchestrator → Image Builder → EventBridge → Lambda pool_updater → WorkSpaces Pool 更新。

## 変更時の連動ルール

- ユニットに variable を追加したら → `catalog/stacks/vdi-core/terragrunt.stack.hcl` の inputs と `live/**/stack_vars.hcl` にも追加
- output を追加/変更したら → それを参照している stack の inputs を grep で確認（`grep -r "outputs\." catalog/stacks/`）
- Lambda (.py) を変更したら → `data.archive_file` の source_code_hash が自動で差分検知するので追加作業不要
- 新ユニットを作ったら → stack への登録 + CI の validate ループは `catalog/units/*/` glob なので自動対象

## 機密

- AD パスワード: Secrets Manager 参照のみ（値をコードに書かない）
- SAML メタデータ: 実 XML は gitignore、リポジトリにはプレースホルダーのみ
