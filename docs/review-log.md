# 定期レビューログ

30 分ごとの自動レビューループの記録。観点は「問題の有無 / セキュリティ / コード可読性 / ドキュメント完全性」をローテーションする。
指摘は**次の回**で修正する（レビューと修正を同一回で行わない）。

書式: 新しいエントリを先頭に追加。各エントリは「確認事項 / 気づいた点 / 今回修正したこと / 次回の確認事項」。
過去の解決済みエントリ（#1〜#4）は [review-log-archive.md](review-log-archive.md) へ。

## 未解決バックログ（常設・毎回更新）

| # | 深刻度 | 内容 | 初出 |
|---|---|---|---|
| 1-7 | INFO | VPC エンドポイントポリシー未設定（デフォルト全許可）。多層防御として絞る余地 | #1 |
| 9-1 | HIGH（要検証） | 閉鎖網で update-windows が Microsoft Update に到達できない疑い。対応候補: (a) ビルド専用 NAT + FQDN 制限 (b) WSUS (c) ベース AMI の月次更新へ依存し update-windows を外す | #9 |
| 8-2 | MEDIUM（要検証） | WorkSpaces ディレクトリ登録型（PERSONAL/POOLS）の実機確認 | #8 |

---

## #10 2026-07-06 — 観点: コードの読みやすさ（3 巡目）

### 今回修正したこと（前回指摘の解消、コミット `86a61bb`）

- **9-2 修正済み (HIGH)**: workspaces SG に AD 必須ポートセットを追加（DNS 53 / Kerberos 88・464 / NTP 123 / RPC 135 + 動的 49152-65535 / SMB 445 / Global Catalog 3268-3269）。既存 LDAP/LDAPS も含め宣言的な `local.ad_ports` マップに統合。これまでドメイン参加・GPO・Office の AD 連携が成立しない構成だった
- **9-1 保留（設計判断待ち）**: update-windows の閉鎖網到達性。選択肢 3 案を引き継ぎ表に記録済み。ユーザー判断が出たら実装

### 確認事項

- runbook のコマンド例とコードのリソース名整合
- 設定値の単一情報源（region / environment の二重管理）
- SG・IAM 分割後の可読性

### 気づいた点（未修正 → 次回対応）

| # | 深刻度 | 場所 | 内容 |
|---|---|---|---|
| 10-1 | LOW | `vpc/variables.tf` | `region` 変数（default: ap-northeast-1）が root.hcl の region と**二重管理**。VPC エンドポイントの service_name は `data.aws_region` で導出でき、変数ごと削除できる |
| 10-2 | LOW | stack_vars | local `environment = "prod"` が**どこからも参照されていない**（root.hcl の default_tags はハードコード）。削除するか、root.hcl / workspaces-pools の tags と接続して単一情報源にすべき |
| 10-3 | INFO | runbook 整合結果 | アラーム名・DLQ 名・Lambda 名・パイプライン名・Pool 名のコマンド例はすべて現行コードと一致 |
| 10-4 | INFO | `workspaces-pools` | タイムアウト 3 変数は unit 既定値で運用中（stack_vars 非公開）。変更需要が出たら stack 配線を追加する（現状は YAGNI で妥当） |

### 次回の確認事項

1. **修正**: 10-1（region 二重管理の解消）・10-2（environment の接続 or 削除）
2. **保留継続**: 9-1（設計判断待ち）・8-2 / update-windows 到達性（要実機検証）・1-7（価値低）
3. **新規レビュー観点**: ドキュメントの不完全さ（3 巡目 — AD ポート追加後の architecture.md ネットワーク表・9-1 の判断材料が伝わる形になっているか）

---

## #9 2026-07-06 — 観点: セキュリティ（3 巡目・SG 整理後の再確認）

### 今回修正したこと（前回指摘の解消、コミット `13be263`）

- **8-1 修正済み (MEDIUM)**: 未アタッチの `managed_ad` SG を削除（誤解を生む死にリソースだった）
- **4-4 修正済み**: ビルドインスタンス専用 SG を新設し WorkSpaces SG との共有を解消。**S3 Gateway エンドポイント向け prefix list egress を追加**（旧構成の vpc_cidr 縛りでは S3 に届かずログ書込が失敗していた疑いも同時解消）
- **1-4 修正済み (MEDIUM)**: Lambda IAM を絞り込み — `imagebuilder:GetImage` = 自パイプラインの image ARN プレフィックス、`UpdateWorkspacesPool` = 自 Pool ARN のみ。動的リソースのみ `"*"` 維持（理由コメント付き）
- **2-3 修正済み**: セッションタイムアウト 3 値を変数化
- **8-2 記録済み**: 引き継ぎ表に要検証 2 行（ディレクトリ登録型・update-windows 到達性）を追加

### 確認事項

- SG 整理後の最小権限の過不足（絞りすぎ含む）
- ドメイン参加に必要な AD 通信ポートセット
- 閉鎖網と update-windows コンポーネントの整合性

### 気づいた点（未修正 → 次回対応）

| # | 深刻度 | 場所 | 内容 |
|---|---|---|---|
| 9-1 | **HIGH（要検証）** | `image-builder` レシピ × 閉鎖網 | **update-windows コンポーネントが Microsoft Update に到達できない疑い**。VPC に IGW/NAT が無く、ビルド SG の egress も VPC 内 + S3 のみ。週次ビルドのパッチ適用が失敗するか「更新ゼロで成功」する可能性。対応候補: (a) ビルド専用サブネット + NAT + FQDN 制限（Network Firewall）(b) WSUS / オフライン更新 (c) **ベース AMI（Amazon 月次更新）への依存に切り替え update-windows を外す**（閉鎖網と最も整合・推奨）。設計判断が必要なため引き継ぎ表に記録済み |
| 9-2 | **HIGH** | `vpc` workspaces SG | **ドメイン参加に必要なポートが不足**。現行 egress は 443/389/636 + 他アカウントのみで、**DNS(53 TCP/UDP)・Kerberos(88)・RPC(135 + 動的)・SMB(445)・NTP(123) が無い**。このままではドメイン参加・GPO 適用・Office の AD 連携が失敗する。AD 通信ポートセットの egress 追加が必要 |
| 9-3 | INFO | 再確認結果 | SG 整理後の構成に退行なし・Lambda IAM の絞り込み反映確認・Trivy HIGH/CRITICAL 0 件継続 |

### 次回の確認事項

1. **修正（最優先）**: 9-2 — workspaces SG に AD 必須ポートセット（53/88/123/135/445/49152-65535）の egress を追加
2. **判断待ち**: 9-1 は設計判断（推奨は案 c）。ユーザー確認が取れるまで引き継ぎ表で保留
3. **新規レビュー観点**: コードの読みやすさ（3 巡目 — SG 整理・IAM 分割後の可読性・runbook とコードの整合）

---

## #8 2026-07-06 — 観点: 問題の有無（3 巡目・バックログ棚卸し）

### 今回修正したこと（前回指摘の解消、コミット `1377344`）

- **7-1 修正済み (MEDIUM)**: `alert_email` を stack に配線 + stack_vars に掲載。これまで**アラームは発報しても SNS 購読が無く誰にも届かなかった**
- **7-2 修正済み**: review-log を再構成 — 解決済み #1〜#4 を `review-log-archive.md` へ、先頭に未解決バックログ常設表を新設（265 → 133 行）
- **7-3 修正済み**: 引き継ぎ表に `alert_email` 行 + Bundle ID「初回のみ使用」注記

### 確認事項

- vpc の `managed_ad` SG が実際にアタッチされているか（#7 で疑義）
- WorkSpaces ディレクトリ登録の型（Pools 対応）
- 未解決バックログ 4 件の実行可能性・優先度の棚卸し

### 気づいた点（未修正 → 次回対応）

| # | 深刻度 | 場所 | 内容 |
|---|---|---|---|
| 8-1 | **MEDIUM** | `vpc/main.tf:135` | `aws_security_group.managed_ad` は**どこにもアタッチされていない死にリソース**（Managed AD は自前 SG を自動作成・grep で全リポジトリにアタッチ先ゼロを確認）。読み手に「この SG が AD を守っている」と誤解させるため削除すべき。workspaces SG 側の LDAP/LDAPS/DNS egress（CIDR 宛）は有効なので維持 |
| 8-2 | **MEDIUM（要検証）** | `workspaces-pools` | `aws_workspaces_directory` は既定で PERSONAL 型として登録される可能性がある。WorkSpaces **Pools** は POOLS 型のディレクトリ登録（`workspace_type = "POOLS"`）が必要な場合があり、その場合 apply 時に Pool 作成が失敗する。**コード読解だけでは確定できない** — AWS 認証が使える環境での plan / 実機検証が必要（引き継ぎ事項に追加すべき） |
| 8-3 | INFO | バックログ棚卸し結果 | **1-4** = 実行可能（image ARN プレフィックス変数と `pool_arn` output が既に揃っている）/ **2-3** = 実行可能（小）/ **4-4** = 8-1 の SG 整理と同時対応が効率的 / **1-7** = 閉鎖網構成では価値が低く保留継続が妥当 |

### 次回の確認事項

1. **修正**: 8-1 + 4-4（SG の整理 — 死に SG 削除とビルド専用 SG 新設を同時に）
2. **修正**: 1-4（Lambda IAM 絞り込み）・2-3（タイムアウト変数化）
3. **記録**: 8-2 を architecture.md の引き継ぎ表（要検証事項）へ追加
4. **新規レビュー観点**: セキュリティ（3 巡目 — SG 整理後の最小権限再確認・runbook のコマンド権限）

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

