# Runbook — Golden Image 自動更新チェーンの障害対応

対象: `vdi-golden-image-pipeline`（週次ビルド）→ EventBridge → `vdi-workspaces-pool-updater` Lambda → Pool 更新。
アラーム `vdi-pool-updater-errors` / `vdi-pool-updater-dlq-not-empty`（SNS: `vdi-golden-image-alerts`）が発報したらここを見る。

## 1. まず状況確認

```bash
# Lambda の直近エラーログ
aws logs tail /aws/lambda/vdi-workspaces-pool-updater --since 24h --filter-pattern ERROR

# DLQ に滞留しているイベント（削除せず中身だけ見る）
aws sqs receive-message \
  --queue-url "$(aws sqs get-queue-url --queue-name vdi-pool-updater-dlq --query QueueUrl --output text)" \
  --visibility-timeout 0 --max-number-of-messages 10
```

よくある失敗と対処:

| ログの症状 | 原因 | 対処 |
|---|---|---|
| `TimeoutError: Image ... still PENDING` | 画像取り込みが 15 分 × リトライ 2 回でも終わらない | 取り込み完了後に §2 の手動再実行（Lambda は冪等なので途中から再開する） |
| `Image ... import failed` (State=ERROR) | AMI が WorkSpaces 取り込み要件を満たさない（言語・エージェント等） | Image Builder レシピを修正 → レシピ version を上げて再ビルド |
| `ResourceLimitExceededException` | Bundle / Image のクォータ超過 | §4 で古い Bundle・Image を棚卸し削除 |
| `AccessDenied` | IAM 変更の退行 | 直近の IAM 変更コミットを確認して差し戻し |

## 2. チェーンの手動再実行

Lambda は**冪等**（Image / Bundle は AMI ID ベースの名前で照合・再利用）。同じイベントを再投入すれば途中から再開する。

```bash
# DLQ のメッセージ本文（= 元の EventBridge イベント）をそのまま再投入
aws lambda invoke --function-name vdi-workspaces-pool-updater \
  --invocation-type Event \
  --payload file://dlq-message-body.json /dev/null

# 処理できたら DLQ から該当メッセージを削除
aws sqs delete-message --queue-url <QueueUrl> --receipt-handle <ReceiptHandle>
```

ビルド自体からやり直す場合:

```bash
aws imagebuilder start-image-pipeline-execution \
  --image-pipeline-arn "$(aws imagebuilder list-image-pipelines \
    --query "imagePipelineList[?name=='vdi-golden-image-pipeline'].arn" --output text)"
```

## 3. Golden Image のロールバック（旧 Bundle に戻す）

自動更新で作られた Bundle は `vdi-bundle-<AMI ID>` の名前で残っている。

```bash
# 過去の Bundle を新しい順に列挙
aws workspaces describe-workspace-bundles --owner SELF \
  --query "Bundles[?starts_with(Name, 'vdi-bundle-')].[BundleId,Name,CreationTime]" \
  --output table

# Pool を 1 世代前の Bundle に戻す
aws workspaces update-workspaces-pool \
  --pool-id <POOL_ID> --bundle-id <前世代の BundleId>
```

> Pool ID: `aws workspaces describe-workspaces-pools --query "WorkspacesPools[?PoolName=='vdi-pool-prod'].PoolId" --output text`

ロールバック後は**原因の新イメージを特定してから**次の週次ビルドを迎えること（そのままだと同じイメージがまた適用される）。

## 4. Bundle / Image の棚卸し（クォータ対策）

自動更新は世代ごとに Image と Bundle を残す。四半期に一度、直近 3 世代を残して削除する:

```bash
aws workspaces delete-workspace-bundle --bundle-id <古い BundleId>
aws workspaces delete-workspace-image --image-id <古い ImageId>  # Bundle 削除後のみ可
```

## 5. Terraform state のロック解除（plan/apply が固まったとき）

```bash
cd live/prod/ap-northeast-1/vdi
terragrunt force-unlock <LOCK_ID>   # LOCK_ID はエラーメッセージに表示される
```

> ロックの主が本当に死んでいるか（CI ジョブ実行中でないか）を確認してから実行すること。
