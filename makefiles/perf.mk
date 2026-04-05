################################################################################
# ブラウザで開く
# ################################################################################
.PHONY: perf.open-ch
perf.open-ch: ## ClickHouseのWebUIをブラウザで開く
	$(eval TARGET_HOST=localhost)
	@open "http://$(TARGET_HOST):8123/play?user=${CLICKHOUSE_USER}&password=${CLICKHOUSE_PASSWORD}"
