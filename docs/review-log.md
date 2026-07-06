# 定期レビューログ

30 分ごとの自動レビューループの記録。観点は「問題の有無 / セキュリティ / コード可読性 / ドキュメント完全性」をローテーションする。
指摘は**次の回**で修正する（レビューと修正を同一回で行わない）。

書式: 新しいエントリを先頭に追加。各エントリは「確認事項 / 気づいた点 / 今回修正したこと / 次回の確認事項」。
過去の解決済みエントリ（#1〜#4）は [review-log-archive.md](review-log-archive.md) へ。

## 未解決バックログ（常設・毎回更新）

| # | 深刻度 | 内容 | 初出 |
|---|---|---|---|
| 1-4 | MEDIUM | pool_updater Lambda IAM の `Resource "*"` 絞り込み（imagebuilder:GetImage は image ARN プレフィックスに、workspaces 系は Pool/Bundle ARN に） | #1 |
| 1-7 | INFO | VPC エンドポイントポリシー未設定（デフォルト全許可）。多層防御として絞る余地 | #1 |
| 2-3 | LOW | セッションタイムアウト（3600/1800/28800）のハードコード。変数化して stack_vars へ | #2 |
| 4-4 | INFO | ビルドインスタンスが WorkSpaces 用 SG を借用。専用 SG 分離が望ましい | #4 |

---

## #7 2026-07-06 — 観点: ドキュメントの不完全さ（2 巡目）

### 今回修正したこと（前回指摘の解消、コミット `5c90bf4`）

- **6-2 修正済み**: architecture.md に DLQ + アラーム + runbook 導線を反映
- **6-1 修正済み**: stack 未参照 outputs 8 件に用途コメント（Entra ID 設定用 / DNS フォワーダ用 / runbook 手動実行用を明示）
- **1-6 修正済み**: README に state アクセス制御の警告（AD パスワードが state に平文で入る）
- **2-5 修正済み**: `transit_gateway_id` / `bundle_id` / `max_user_sessions` に validation（プレースホルダー plan の早期明確失敗）
- **2-6 修正済み**: description 欠落 5 変数を補完
- **6-4 修正済み**: .gitignore に lock ファイル ignore の意図コメント

### 確認事項

- 新規追加分（DLQ・アラーム・runbook・新変数）のドキュメント反映漏れ
- 引き継ぎ表の鮮度
- review-log 自体の肥大化
- README ⇔ runbook ⇔ architecture の導線

### 気づいた点（未修正 → 次回対応）

| # | 深刻度 | 場所 | 内容 |
|---|---|---|---|
| 7-1 | **MEDIUM** | stack / stack_vars | **`alert_email` が stack に配線されておらず、SNS 購読が作られない = アラームは発報しても誰にも届かない**（5-1 の実効性が未完）。stack 配線 + stack_vars 掲載 + 引き継ぎ表への追加が必要 |
| 7-2 | LOW | review-log.md | 230 行に肥大。解決済みエントリ（#1〜#3 あたり）を `docs/review-log-archive.md` へ移し、先頭に「未解決バックログ一覧表」を常設する構成に改めるべき（毎回全文を読まずに残タスクが見える） |
| 7-3 | LOW | architecture.md 引き継ぎ表 | `alert_email` の行が無い（7-1 と対）。Bundle ID 行にも「初期 Bundle の意味」の注記があると初見に親切 |
| 7-4 | INFO | 導線確認結果 | README → runbook / architecture の相互リンク OK・runbook のコマンド例と stack_vars の Pool 名整合 OK・引き継ぎ表の既存 5 行は全て現状と一致 |

### 次回の確認事項

1. **修正**: 7-1（alert_email 配線 — アラートの実効性確保）・7-3（引き継ぎ表更新）
2. **修正**: 7-2（review-log のアーカイブ分割 + 未解決バックログ表の常設）
3. **新規レビュー観点**: 問題の有無（3 巡目）— 残バックログの棚卸し（1-4 / 1-7 / 2-3 / 4-4）+ vpc の managed_ad SG が実際に使われているかの検証（Managed AD は自前 SG を持つため未アタッチの疑い）

---

## #6 2026-07-06 — 観点: コードの読みやすさ（2 巡目・簡素化後の取り残し）

### 今回修正したこと（前回指摘の解消、コミット `a5d6a91`）

- **5-1 修正済み (MEDIUM)**: pool_updater に DLQ（SQS・14 日保持・SSE）+ SNS トピック + CloudWatch アラーム 2 本（Lambda Errors / DLQ 滞留）。SNS は CMK 暗号化（Trivy の HIGH 検出に対応。AWS 管理キーだと CloudWatch アラームが発行できない落とし穴も回避）
- **5-5 修正済み (MEDIUM)**: ビルドインスタンスロールに S3 put + KMS 権限を明示付与（AWS 管理ポリシーのパターン不一致でログが書けなかった疑いに対応）
- **5-2 修正済み**: ログバケットに TLS 強制ポリシー
- **5-3 修正済み**: awscc Pool に明示タグ（`tags` 変数・default_tags 非継承対策）
- **3-2 修正済み (MEDIUM)**: `docs/runbook.md` 新設 — 状況確認 / 手動再実行 / ロールバック / 棚卸し / state ロック解除の 5 章。アラーム説明文と README から参照

### 確認事項

- 削除済み要素（orchestrator / ssm-patch / Maintenance Window）への残存参照
- stack から参照されない outputs の妥当性
- コメントの鮮度（簡素化前の記述が残っていないか）

### 気づいた点（未修正 → 次回対応）

| # | 深刻度 | 場所 | 内容 |
|---|---|---|---|
| 6-1 | LOW | 各 outputs.tf | stack 未参照の outputs が 8 件。用途があるもの（`saml_role_arn` = Entra ID の Role 属性設定に必要・`dns_ip_addresses` = DNS フォワーダ設定用）と旧設計の名残（`pipeline_arn` / `pipeline_name` は orchestrator 削除で未参照化）が混在。outputs に用途コメントを付けて区別すべき |
| 6-2 | LOW | architecture.md | #6 で追加した DLQ + アラーム + runbook がまだ構成図・本文に未反映 |
| 6-3 | INFO | 取り残しチェック結果 | 削除済み要素への残存参照は歴史的注記 1 箇所のみ（意図的・review-log 参照付き）。コード側の取り残しなし。コメント鮮度も問題なし |
| 6-4 | INFO | `.gitignore:3` | `.terraform.lock.hcl` を一律 ignore している。provider は root.hcl の `~> 5.50` ピンで実質固定されているため実害は小さいが、完全な再現性（パッチバージョンまで固定 + ハッシュ検証）を求めるなら live 側のロックファイルはコミットする方針もある。現状維持なら「意図的に ignore」の旨をコメントすべき（並行レビューセッションの発見） |

### 次回の確認事項

1. **修正**: 6-2（architecture.md へ DLQ/アラーム/runbook 反映）・6-1（outputs 用途コメント）・1-6（state アクセス制御の README 記載）
2. **修正（余力があれば）**: 2-5（validation）・2-6（description 補完）
3. **残バックログ**: 1-4（Lambda IAM 絞り込み）・1-7（VPC エンドポイントポリシー）・2-3（タイムアウト変数化）・4-4（ビルド用 SG 分離）
4. **新規レビュー観点**: ドキュメントの不完全さ（2 巡目 — runbook 追加後の README 導線・引き継ぎ表の鮮度・review-log 自体の肥大化対策）

---

## #5 2026-07-06 — 観点: セキュリティ（2 巡目）

### 今回修正したこと（前回指摘の解消、コミット `dcacfd8`）

- **4-1 修正済み (HIGH)**: 空振りしていた SSM Maintenance Window 構成を撤去し、Image Builder のネイティブ週次スケジュール（土曜 17:00 UTC = 日曜 02:00 JST）に簡素化。**ssm-patch ユニットと orchestrator Lambda を削除**し、チェーンを 6 段 → 3 段に（部品が減る = 攻撃面と故障点も減る）
- **4-6 修正済み**: root.hcl に `provider "awscc"`（region 明示）を生成追加
- **4-7 修正済み**: Bundle 照合を全ページ走査に（蓄積時の同名 Create 停止を防止）
- **4-8 修正済み**: Bundle ストレージ容量を変数化（既定 50/80 GB）
- **4-3 修正済み**: image-builder の provider 最小バージョンを実要件（>= 5.86）に
- **4-2 修正済み**: レシピ immutable の注意書きをコメント + architecture.md に追加
- ドキュメント追随: architecture.md の要件表・シーケンス図、README ユニット一覧（8→7）、CLAUDE.md

### 確認事項

- #1 で修正した項目の退行有無（SAML 権限・EventBridge フィルタ・SG ポート）
- Lambda 失敗時の最終防衛（DLQ・アラーム）
- S3 バケットポリシー（TLS 強制）
- タグ戦略（コスト配賦・棚卸し観点）

### 気づいた点（未修正 → 次回対応）

| # | 深刻度 | 場所 | 内容 |
|---|---|---|---|
| 5-1 | **MEDIUM** | `golden-image-updater` | **pool_updater 失敗の最終防衛がない**。EventBridge 非同期リトライ（2 回）を使い切るとイベントは通知なしに消え、Pool が古いイメージのまま誰も気づけない = パッチ適用の実効性が静かに失われる。Lambda の DLQ（SQS）+ CloudWatch アラーム（Errors > 0 と DLQ 滞留）を追加すべき |
| 5-2 | LOW | `image-builder` ログバケット | TLS 強制（`aws:SecureTransport` = false を Deny）のバケットポリシーがない。多層防御として追加推奨 |
| 5-3 | LOW | `workspaces-pools` | awscc provider は default_tags 非対応のため **Pool 本体にタグが一切付かない**。コスト配賦・棚卸しから漏れる。awscc リソースに明示 tags を付与すべき |
| 5-4 | INFO | 再確認結果 | #1〜#4 の修正済み項目に退行なし（SAML = Stream+userId 条件維持・EventBridge フィルタ維持・SG ポート制限維持）。Trivy HIGH/CRITICAL 0 件継続 |

### 補追（並行レビューセッションの追加発見）

| # | 深刻度 | 場所 | 内容 |
|---|---|---|---|
| 5-5 | **MEDIUM** | `image-builder` ログ設定 | **ビルドログが実際には書けない疑い**。インスタンスプロファイルは AWS 管理ポリシーのみで、`EC2InstanceProfileForImageBuilder` の S3 書込許可は `*imagebuilder*` パターンのバケットに限られる — バケット名 `vdi-image-builder-logs-*`（ハイフン入り）はこのパターンに**一致しない**可能性が高い。さらに SSE-KMS のため書き手に `kms:GenerateDataKey` が必要だが、KMS キーポリシー・IAM のどちらにも付与がない。修正: インスタンスロールに明示の S3 put + KMS ポリシーを追加（または plan/実機で権限を検証してから判断） |

### 次回の確認事項

1. **修正**: 5-1（DLQ + アラーム）— 3-2（runbook）と対で実施すると効果的
2. **修正**: 5-5（ビルドログ書込権限）・5-2（TLS 強制ポリシー）・5-3（Pool タグ）
3. **残バックログ**: 3-2（runbook）・1-4（Lambda IAM Resource 絞り込み）・1-6（state アクセス制御 README）・1-7（VPC エンドポイントポリシー）・2-3（タイムアウト変数化）・2-5（validation）・2-6（description）・4-4（ビルド用 SG 分離）
4. **新規レビュー観点**: コードの読みやすさ（2 巡目 — 簡素化後の構造・削除の取り残し・コメントの鮮度）

---

