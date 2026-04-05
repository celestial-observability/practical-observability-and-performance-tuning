################################################################################
# SSH
################################################################################
.PHONY: ssh.web
ssh.web: ## webインスタンスにSSH接続
	@ssh -F "${SSH_CONFIG_FILE}" web

.PHONY: ssh.bench
ssh.bench: ## benchインスタンスにSSH接続
	@ssh -F "${SSH_CONFIG_FILE}" bench

.PHONY: ssh.perf
ssh.perf: ## perfインスタンスにSSH接続
	@ssh -F "${SSH_CONFIG_FILE}" perf
