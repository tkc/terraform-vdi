# 定期レビューログ

30 分ごとの自動レビューループの記録。観点は「問題の有無 / セキュリティ / コード可読性 / ドキュメント完全性」をローテーションする。
指摘は**次の回**で修正する（レビューと修正を同一回で行わない）。

書式: 新しいエントリを先頭に追加。各エントリは「確認事項 / 気づいた点 / 今回修正したこと / 次回の確認事項」。

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

## #4 2026-07-06 — 観点: 問題の有無（全般整合性）

### 今回修正したこと（前回指摘の解消、コミット `45d1eac`）

- **3-1 修正済み (HIGH)**: README に state バケット + DynamoDB ロックテーブルの作成コマンドを追加（初回 plan の必須前提）
- **3-3 修正済み**: `make plan` の AWS 認証方法（AWS_PROFILE / SSO）を明記
- **3-4 修正済み**: CLAUDE.md に定期レビューループの存在・ローテーション・書式を追記
- **3-5 修正済み**: README に `workspaces_bundle_id` =「初期 Bundle」の意味と自動更新の関係、新変数 2 つを記載
- **1-5 修正済み**: ログバケット `force_destroy = false`（監査証跡保護）
- **2-4 修正済み**: tgw ルートを `for_each + setproduct` 化（CIDR 変更時の全ルート再作成を防止）

### 確認事項

- stack が参照する outputs とユニット定義の整合（機械的照合）
- default なし変数が stack inputs で全て供給されているか
- SSM Maintenance Window のターゲット実在性
- provider 最小バージョン宣言と実使用機能の整合
- CI の健全性

### 気づいた点（未修正 → 次回対応）

| # | 深刻度 | 場所 | 内容 |
|---|---|---|---|
| 4-1 | **HIGH** | `ssm-patch` / `image-builder` | **Maintenance Window のターゲット（tag `Purpose=ImageBuilder-VDI`）に一致するインスタンスがどこにも存在しない**。infrastructure_configuration は resource_tags を付けておらず、ビルドインスタンスはビルド中しか生きていない。つまり週次パッチは空振りし、チェーンは実質「週次スケジューラ」として動くだけ（実際の更新はレシピ内の update-windows コンポーネントが担っている）。修正案: (a) MW を廃止して EventBridge Scheduler から直接パイプラインを起動する簡素化（機能は同等・部品 2 つ削減）、または (b) 常駐のパッチ基準インスタンスを立ててタグ付け。(a) を推奨 |
| 4-2 | MEDIUM | `image-builder/main.tf` | レシピ version が `1.0.0` 固定。コンポーネントやレシピを変更するたびに手動バージョンアップが必要（忘れると apply エラー）。運用注意点としてコメント + README 記載が必要 |
| 4-3 | LOW | `catalog/units/*/versions.tf` | `data.aws_region.current.region` 属性は provider 5.86 以降の機能だが、required_providers は `>= 5.50` を宣言。古い 5.x に明示ピンした利用者の validate が壊れる。最小バージョンを実要件（>= 5.86）に引き上げるべき |
| 4-4 | INFO | `image-builder` | ビルドインスタンスが WorkSpaces 用 SG（sg_workspaces_id）を借用。現状の egress で動作はするが、役割の異なるリソースの SG 共有は将来の変更で壊れやすい。専用 SG の分離が望ましい |
| 4-5 | INFO | 整合性チェック結果 | stack 参照 outputs 9 件すべてユニット側に定義あり・default なし変数はすべて stack inputs で供給・CI 直近 2 ラン green。構造的な不整合なし |

### 補追（並行レビューセッションの追加発見）

| # | 深刻度 | 場所 | 内容 |
|---|---|---|---|
| 4-6 | **MEDIUM** | `live/root.hcl` | versions には awscc を宣言しているのに **generate "provider" に `provider "awscc"` ブロックが無い**。awscc は region 設定が必要で、現状は環境変数（AWS_REGION）頼み。CI やクリーン環境での plan が失敗しうる |
| 4-7 | **MEDIUM** | `pool_updater.py` `find_or_create_bundle` | `describe_workspace_bundles` を**ページネーションしていない**（images 側は paginator 使用で非対称）。自動更新の蓄積で Bundle が 1 ページを超えると既存 Bundle を見逃し、同名 Create が ResourceAlreadyExistsException → 更新チェーン停止 |
| 4-8 | LOW | `pool_updater.py:102-103` | `UserStorage "50"` / `RootStorage "80"` がハードコード。ComputeType と不整合な組合せだと CreateWorkspaceBundle が失敗する。環境変数化すべき |

### 次回の確認事項

1. **修正（最優先）**: 4-1 — 推奨案 (a) で MW + patch-baseline を EventBridge Scheduler 起動に簡素化（architecture.md の更新込み）
2. **修正**: 4-6（awscc provider 生成）・4-7（Bundle ページネーション）・4-3（provider 最小バージョン）・4-2（レシピバージョンの注意書き）・4-8（ストレージ変数化）
3. **残バックログ**: 3-2（runbook）・1-4（pool_updater IAM の Resource 絞り込み）・1-6（state アクセス制御の README 記載）・1-7（VPC エンドポイントポリシー）・2-3（タイムアウト変数化）・2-5（validation）・2-6（description）
4. **新規レビュー観点**: セキュリティ（2 巡目 — 修正済み項目の再確認 + Lambda 権限・S3 ポリシー・タグ戦略）

---

## #3 2026-07-06 — 観点: ドキュメントの不完全さ

### 今回修正したこと（前回指摘の解消、コミット `fe3a5e1`）

- **2-7 修正済み (HIGH)**: pool_updater に `CreateWorkspaceBundle` ステップを追加。Import → AVAILABLE 待機 → Bundle 作成 → Pool 更新の完全チェーンに書き直し。名前規約ベースの冪等設計で、Lambda 15 分超過時は EventBridge 非同期リトライで続きから再開
- **2-1 修正済み**: 未使用の `ec2` クライアント削除
- **2-2 修正済み**: `IngestionProcess` / `ComputeType` を変数化（既定 `BYOL_REGULAR` / `STANDARD`）、環境依存である旨をコメント明記
- **1-3 修正済み**: WorkSpaces SG の他アカウント向け egress を全ポート → `other_account_ports`（既定 [443]）に縮小
- 付随: architecture.md のシーケンス図を新チェーン（Bundle 経由）に追随

### 確認事項

- README / architecture.md とコードの乖離
- デプロイ前提条件の網羅性（初見の人が README だけで plan まで到達できるか）
- 運用ドキュメント（障害対応・ロールバック手順）の有無
- CLAUDE.md（エージェント向けハーネス）の情報鮮度

### 気づいた点（未修正 → 次回対応）

| # | 深刻度 | 場所 | 内容 |
|---|---|---|---|
| 3-1 | **HIGH** | README | **state バケット（`tfstate-vdi-<account>`）と DynamoDB ロックテーブル（`tfstate-lock-vdi`）の事前作成手順が未記載**。root.hcl が参照するため、初回 `terragrunt plan` はここで必ず失敗する。「デプロイ前に必要な準備」に手順（または bootstrap スクリプト）を追加すべき |
| 3-2 | MEDIUM | docs/ | 運用 runbook が無い。最低限: ① Lambda 失敗時の手動リカバリ（チェーンの途中再開方法）② Golden Image のロールバック手順（旧 Bundle に戻す）③ EventBridge の手動再実行方法 |
| 3-3 | LOW | README | `make plan` の AWS 認証方法（AWS_PROFILE / SSO など）が未記載。「AWS 認証が必要」とだけ書かれている |
| 3-4 | LOW | CLAUDE.md | 定期レビューループ（docs/review-log.md）の存在と書式が未記載。別のエージェントセッションが重複レビューを始めたり、ログ形式を無視する恐れ |
| 3-5 | INFO | README / stack_vars | 2-7 修正後、`workspaces_bundle_id` は「初期 Bundle」の意味に変わった（以後は Lambda が作る Bundle に自動置換）。この仕様が未記載。新変数 `ingestion_process` / `bundle_compute_type` も stack_vars の例に未掲載 |

### 次回の確認事項

1. **修正**: 3-1（state バケット手順 — デプロイの必須前提）・3-4（CLAUDE.md 追記）・3-5（README 追記）
2. **修正（余力があれば）**: 3-2（runbook 骨子）・2-4（tgw ルート for_each 化）・1-5（force_destroy = false）
3. **新規レビュー観点**: 問題の有無（全般 — CI の健全性・ユニット間の outputs/inputs 整合・stack_vars と variables の対応漏れ）— これで 4 観点ローテーション一巡

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
| 2-7 | **HIGH** | `pool_updater.py:52` | `update_workspaces_pool(BundleId=ws_image_id)` — **イメージ ID を Bundle ID として渡している**。WorkSpaces は Image → Bundle 作成（`create_workspace_bundle`）を挟まないと Pool に適用できないため、自動更新チェーンの最終段が実行時に失敗する可能性が高い。機能バグとして 2-1〜2-6 より優先 |

### 今回修正したこと

- **1-1 修正済み**: EventBridge を `window-id` / イメージ ARN プレフィックスでフィルタ（`3df326d`）
- **1-2 修正済み**: SAML ロールを `workspaces:Stream` + userId 条件のみに縮小（同上）
- 付随修正: pool_updater.py のイベント ARN 取得を `event["resources"][0]` に修正（Image Builder イベントの実際の形式に合わせた）

### 次回の確認事項

1. **修正（最優先）**: 2-7（Bundle 作成ステップ欠落の機能バグ）
2. **修正**: 2-1（dead code）・2-2（IngestionProcess）・1-3（SG 全ポート egress）を修正
3. **新規レビュー観点**: ドキュメントの不完全さ（README とコードの乖離・architecture.md の未記載事項・引き継ぎ表の鮮度）

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
