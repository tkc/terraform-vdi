# terraform-vdi ハーネス — AI エージェント/人間 共通の検証エントリポイント
# CI (.github/workflows/validate.yml) と同一のチェックをローカルで回す

UNITS := $(wildcard catalog/units/*/)

.PHONY: check fmt fmt-check validate lint scan plan clean

## check: fmt + validate + lint + scan を一括実行（CHECKER のフルサイクル）
check: fmt validate lint scan
	@echo "✅ all checks passed"

## fmt: フォーマット自動修正
fmt:
	terraform fmt -recursive catalog/

## fmt-check: フォーマット検査のみ（CI 用、修正しない）
fmt-check:
	terraform fmt -check -recursive catalog/

## validate: 全ユニットの構文検証（backend 不要）
validate:
	@for dir in $(UNITS); do \
		echo "=== validate $$dir ==="; \
		terraform -chdir=$$dir init -backend=false -input=false > /dev/null || exit 1; \
		terraform -chdir=$$dir validate || exit 1; \
	done

## lint: tflint（インストール済み前提）
lint:
	@command -v tflint >/dev/null || { echo "tflint 未インストール: brew install tflint"; exit 1; }
	@for dir in $(UNITS); do \
		echo "=== tflint $$dir ==="; \
		tflint --chdir=$$dir || exit 1; \
	done

## scan: trivy による IaC セキュリティスキャン（CI と同一）
scan:
	@command -v trivy >/dev/null || { echo "trivy 未インストール: curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh -s -- -b ~/.local/bin"; exit 1; }
	trivy config --severity HIGH,CRITICAL --exit-code 1 catalog/

## plan: 本番環境の dry-run（AWS 認証が必要。apply はここに存在しない = 意図的）
plan:
	cd live/prod/ap-northeast-1/vdi && terragrunt run-all plan --terragrunt-non-interactive

## clean: キャッシュ削除
clean:
	find . -type d -name ".terraform" -exec rm -rf {} + 2>/dev/null || true
	find . -type d -name ".terragrunt-cache" -exec rm -rf {} + 2>/dev/null || true
