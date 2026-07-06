# 定期レビューログ

30 分ごとの自動レビューループの記録。観点は「問題の有無 / セキュリティ / コード可読性 / ドキュメント完全性」をローテーションする。
指摘は**次の回**で修正する（レビューと修正を同一回で行わない）。

書式: 新しいエントリを先頭に追加。各エントリは「確認事項 / 気づいた点 / 今回修正したこと / 次回の確認事項」。

---

## #2 2026-07-06 — 観点: コードの読みやすさ

### 確認事項

- 未使用コード（dead code）の有無
- マジックナンバー・ハードコード値の妥当性
- 変数の description / validation の網羅性
- 理解しにくい構文（count の直積等）

### 気づいた点（未修正 → 次回対応）

| # | 深刻度 | 場所 | 内容 |
|---|---|---|---|
| 2-1 | LOW | `pool_updater.py:14` | `ec2 = boto3.client("ec2")` が未使用（dead code）。削除すべき |
| 2-2 | **MEDIUM** | `pool_updater.py` | `IngestionProcess="BYOL_GRAPHICS_G4DN"` がハードコード。GPU 非搭載の Bundle では誤り の可能性が高く、根拠コメントもない。環境変数化 + 値の妥当性確認が必要 |
| 2-3 | LOW | `workspaces-pools/main.tf` | セッションタイムアウト（3600/1800/28800）がハードコード。同じ値が docs/architecture.md にも重複しており、変更時にドリフトする。変数化して stack_vars に出すべき |
| 2-4 | LOW | `tgw-attachment/main.tf` | ルートの count 直積（`count.index % ...` / `floor(...)`）が読みにくい。`for_each` + `setproduct` の方が意図が明確 |
| 2-5 | LOW | `live/.../stack_vars.hcl` | プレースホルダー値（`tgw-XXXX...`）に validation がなく、plan 時に不親切なエラーになる。variables 側に validation を追加して早期に明確なメッセージを出すべき |
| 2-6 | INFO | 各 variables.tf | 24 変数中 5 個に description がない（managed-ad の vpc_id 等） |

### 今回修正したこと

- **1-1 修正済み**: EventBridge を `window-id` / イメージ ARN プレフィックスでフィルタ（`3df326d`）
- **1-2 修正済み**: SAML ロールを `workspaces:Stream` + userId 条件のみに縮小（同上）
- 付随修正: pool_updater.py のイベント ARN 取得を `event["resources"][0]` に修正（Image Builder イベントの実際の形式に合わせた）

### 次回の確認事項

1. **修正**: 2-1（dead code）・2-2（IngestionProcess）・1-3（SG 全ポート egress）を修正
2. **新規レビュー観点**: ドキュメントの不完全さ（README とコードの乖離・architecture.md の未記載事項・引き継ぎ表の鮮度）

## #1 2026-07-06 — 観点: セキュリティ

### 確認事項

- IAM ポリシーのワイルドカード（`Resource = "*"` / `Action = "*"`）
- セキュリティグループの過剰許可
- EventBridge ルールのイベントフィルタリング範囲
- シークレットの扱い（state への漏出・ログ出力）
- S3 バケットの破壊防止設定

### 気づいた点（未修正 → 次回対応）

| # | 深刻度 | 場所 | 内容 |
|---|---|---|---|
| 1-1 | **HIGH** | `golden-image-updater` EventBridge ×2 | イベントパターンが**アカウント内の全イベントにマッチ**する。他の Maintenance Window の SUCCESS や無関係な Image Builder イメージの AVAILABLE でも Lambda が起動し、**無関係な AMI が Pool に適用されうる**。Maintenance Window ID / パイプライン ARN でフィルタすべき |
| 1-2 | **HIGH** | `saml-provider/main.tf:48` | SAML ロールが `workspaces:* / Resource *`。フェデレーションユーザーに Pool 削除・ディレクトリ変更まで許可している。Stream 系アクションに絞るべき |
| 1-3 | MEDIUM | `vpc/main.tf` workspaces SG | 他アカウント向け egress が **TCP 全ポート (0-65535)**。接続先サービスの必要ポートに絞るべき（stack_vars でポート指定できる設計に） |
| 1-4 | MEDIUM | `golden-image-updater/main.tf:184` | pool_updater Lambda の IAM が `Resource "*"`。imagebuilder:GetImage は自パイプラインの image ARN プレフィックスに絞れる |
| 1-5 | LOW | `image-builder/main.tf:182` | ログバケット `force_destroy = true`。本番で監査ログが terraform destroy で消える。false にすべき |
| 1-6 | LOW | `managed-ad` | AD パスワードが Terraform state に平文で入る（provider の既知挙動）。state バケットは暗号化済みだが、**state へのアクセス制御を README に明記**しておくべき |
| 1-7 | INFO | `vpc` VPC エンドポイント | エンドポイントポリシー未設定（デフォルト全許可）。多層防御として絞る余地あり（優先度低） |

### 今回修正したこと

- なし（初回のためレビューのみ。1-1・1-2 を次回の最優先とする）

### 次回の確認事項

1. **修正**: 1-1（EventBridge フィルタ）と 1-2（SAML ロール権限）を修正して `make check` + push
2. **新規レビュー観点**: コードの読みやすさ（命名一貫性・コメントの過不足・変数の validation 有無・マジックナンバー）
