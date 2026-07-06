# terraform-vdi

AWS WorkSpaces Pools による VDI 基盤の Terragrunt IaC。

- **認証**: Entra ID（SAML 2.0）でログイン、AWS Managed Microsoft AD でドメイン参加・Office 認証
- **同時利用**: 最大 2 セッション
- **ネットワーク**: 完全閉鎖網（インターネット遮断、VPC エンドポイント + Transit Gateway のみ）
- **Golden Image**: Windows Update を検知して自動リビルド → Pool 自動更新

詳細は [docs/architecture.md](docs/architecture.md)（構成図・認証フロー・更新フロー）。

## リポジトリ構成

```
catalog/
├── units/                 # 再利用可能な Terraform ユニット（7 個）
│   ├── vpc/               #   閉鎖網 VPC + VPC エンドポイント
│   ├── managed-ad/        #   ドメイン参加用 Managed Microsoft AD
│   ├── tgw-attachment/    #   他アカウントへの Transit Gateway 経路
│   ├── saml-provider/     #   Entra ID SAML フェデレーション
│   ├── workspaces-pools/  #   VDI 本体（WorkSpaces Pools）
│   ├── image-builder/     #   Golden Image 週次ビルド（日曜 02:00 JST に Windows Update 焼き込み）
│   └── golden-image-updater/  # AMI 完成 → Pool 反映の EventBridge + Lambda
└── stacks/vdi-core/       # ユニットの依存関係・配線

live/
├── root.hcl               # backend / provider / versions の共通生成
└── prod/ap-northeast-1/vdi/
    ├── terragrunt.stack.hcl
    └── stack_vars.hcl     # 環境パラメータ（CIDR・TGW ID・Bundle ID 等）
```

## 前提ツール

| ツール | 用途 |
|---|---|
| Terraform >= 1.6 | 本体 |
| Terragrunt >= 0.68 | オーケストレーション |
| tflint | Lint（`make lint`） |
| trivy | IaC セキュリティスキャン（`make scan`） |

## 使い方

```bash
# 検証（fmt + validate + tflint + trivy — CI と同一チェック）
make check

# 本番環境の dry-run（AWS 認証が必要）
export AWS_PROFILE=<your-profile>   # または aws sso login / 環境変数で認証
make plan
```

`make` に **apply は存在しません（意図的）**。apply は人間がレビューのうえ手動で実行します：

```bash
cd live/prod/ap-northeast-1/vdi
terragrunt run-all apply
```

## デプロイ前に必要な準備

コード外で用意するもの（詳細は [docs/architecture.md の引き継ぎ事項](docs/architecture.md#未設定引き継ぎ事項)）：

0. **Terraform state 用の S3 バケットと DynamoDB ロックテーブルを作成**（root.hcl が参照。未作成だと初回 plan が失敗する）:

   ```bash
   ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
   aws s3api create-bucket --bucket "tfstate-vdi-${ACCOUNT_ID}" \
     --region ap-northeast-1 \
     --create-bucket-configuration LocationConstraint=ap-northeast-1
   aws s3api put-bucket-versioning --bucket "tfstate-vdi-${ACCOUNT_ID}" \
     --versioning-configuration Status=Enabled
   aws s3api put-bucket-encryption --bucket "tfstate-vdi-${ACCOUNT_ID}" \
     --server-side-encryption-configuration \
     '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
   aws dynamodb create-table --table-name tfstate-lock-vdi \
     --attribute-definitions AttributeName=LockID,AttributeType=S \
     --key-schema AttributeName=LockID,KeyType=HASH \
     --billing-mode PAY_PER_REQUEST
   ```

1. **Secrets Manager** に AD 管理者パスワードを登録
2. **Entra ID** で Enterprise Application (SAML) を作成し、メタデータ XML を `catalog/units/saml-provider/entra-id-metadata.xml` に配置（手順はプレースホルダー内コメント）
3. `live/prod/ap-northeast-1/vdi/stack_vars.hcl` の **TGW ID / Bundle ID / ドメイン名** を実値に更新
4. 接続先アカウント側で **Transit Gateway の RAM 共有** と戻りルートを設定

### Bundle ID の意味（自動更新との関係）

`stack_vars.hcl` の `workspaces_bundle_id` は**初回構築時の Bundle** を指す。稼働後は Golden Image 自動更新チェーンが `vdi-bundle-<AMI ID>` という Bundle を作成して Pool を置き換えていくため、Terraform 側は `lifecycle.ignore_changes = [bundle_id]` で追随しない設計になっている。取り込み方式は `ingestion_process`（既定 `BYOL_REGULAR`）、Bundle のスペックは `bundle_compute_type`（既定 `STANDARD`）で調整できる。

## CI

push / PR ごとに GitHub Actions（[.github/workflows/validate.yml](.github/workflows/validate.yml)）が実行：

| ジョブ | 内容 |
|---|---|
| validate | `make fmt-check` + `make validate` + `make lint` |
| security-scan | `trivy config`（HIGH/CRITICAL で fail） |
| plan | `terragrunt run-all plan`（Variables に `AWS_ROLE_ARN` 設定後に有効化） |

ローカルの `make check` と CI は同一の Makefile ターゲットを使うため、ローカルで通れば CI も通ります。

## AI エージェントでの運用

このリポジトリは Claude Code などの AI エージェントによる保守を想定したハーネスを備えています：

- [CLAUDE.md](CLAUDE.md) — 検証ループ（DOER/CHECKER）と禁止事項
- `.claude/settings.json` — `terraform apply` / `destroy` / state 操作 / シークレット読み取りを権限レベルでブロック
- エージェントは **plan まで**。apply の判断は常に人間が行います
