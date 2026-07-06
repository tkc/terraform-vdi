# 定期レビューログ

30 分ごとの自動レビューループの記録。観点は「問題の有無 / セキュリティ / コード可読性 / ドキュメント完全性」をローテーションする。
指摘は**次の回**で修正する（レビューと修正を同一回で行わない）。

書式: 新しいエントリを先頭に追加。各エントリは「確認事項 / 気づいた点 / 今回修正したこと / 次回の確認事項」。

---

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
