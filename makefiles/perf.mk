################################################################################
# デプロイ
################################################################################
.PHONY: perf.deploy
perf.deploy: ## パフォーマンス計測環境をデプロイ
	@if docker compose exec clickhouse echo 'true' 2>/dev/null; then \
		echo "パフォーマンス計測環境はローカルにデプロイされています"; \
	else \
		scripts/05-deploy-perf-gateway.sh web; \
	fi

################################################################################
# ブラウザで開く
# ################################################################################
.PHONY: perf.open
perf.open: perf.define-variables ## Grafana/ClickHouseをブラウザで開く
	@open "http://$(TARGET_HOST):8123/play?user=${CLICKHOUSE_USER}&password=${CLICKHOUSE_PASSWORD}"
	@open "http://$(TARGET_HOST):3000/dashboards"

.PHONY: perf.open-ch
perf.open-ch: perf.define-variables ## ClickHouseのWebUIをブラウザで開く
	@open "http://$(TARGET_HOST):8123/play?user=${CLICKHOUSE_USER}&password=${CLICKHOUSE_PASSWORD}"

.PHONY: perf.open-grafana
perf.open-grafana: perf.define-variables ## Grafanaをブラウザで開く
	@open "http://$(TARGET_HOST):3000/dashboards"

################################################################################
# 変数定義
################################################################################
.PHONY: perf.show-defined-variables
perf.show-defined-variables: perf.define-variables ## makeで定義する変数の表示(デバッグ用)
	@echo "WEB_HOST_IP:   $(WEB_HOST_IP)"
	@echo "TARGET_HOST:   $(TARGET_HOST)"

perf.define-variables:
	$(eval WEB_HOST_IP   := $(shell ssh -F ${SSH_CONFIG_FILE} -G web  | grep '^hostname ' | cut -d ' ' -f2))
	$(eval TARGET_HOST   := $(if $(shell docker compose exec clickhouse echo 'true' 2>/dev/null),localhost,$(WEB_HOST_IP)))
