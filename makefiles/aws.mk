################################################################################
# 一覧
################################################################################
.PHONY: aws.status
aws.status: ## AWSのインスタンス状態とCFnスタック一覧
	@aws cloudformation list-stacks --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE --query 'StackSummaries[].{Name:StackName,Created:CreationTime}' --output table
	@aws ec2 describe-instances --filters 'Name=tag:Name,Values=web,bench,perf' --query 'Reservations[].Instances[].{Name:Tags[?Key==`Name`]|[0].Value,State:State.Name,PublicIp:PublicIpAddress,InstanceId:InstanceId}' --output table

################################################################################
# CFnスタック作成と削除
################################################################################
.PHONY: aws.create-cfn
aws.create-cfn: validate-ssh-private-key ## AWSのCFnスタックを作成
	$(eval MY_IP := $(shell curl -fsS https://checkip.amazonaws.com))
	@aws cloudformation create-stack --stack-name $(STACK_NAME) --template-body file://private-isu.yaml --parameters \
		ParameterKey=GitHubUsername,ParameterValue="${GITHUB_USERNAME}" \
		ParameterKey=MyIp,ParameterValue=$(MY_IP)
	@echo "$(STACK_NAME): 作成中です(約1分かかります)"
	@time aws cloudformation wait stack-create-complete --stack-name $(STACK_NAME)

.PHONY: aws.create-perf-cfn
aws.create-perf-cfn: validate-ssh-private-key ## AWSのパフォーマンス用CFnスタック
	@aws cloudformation create-stack --stack-name $(PERF_STACK_NAME) --template-body file://perf.yaml --parameters \
		ParameterKey=GitHubUsername,ParameterValue="${GITHUB_USERNAME}"
	@time aws cloudformation wait stack-create-complete --stack-name $(PERF_STACK_NAME)
	@make aws.add-myip-inbound-rule
	@make aws.setup-ssh-config

.PHONY: aws.delete-cfn
aws.delete-cfn: ## AWSのCFnスタックを削除(約1.5分)
	$(eval PERF_STACK_ID := $(shell aws cloudformation describe-stacks --stack-name $(PERF_STACK_NAME) --query 'Stacks[0].StackId' --output text 2>/dev/null || true))
	@echo 'Before status'
	@make aws.status
	@if [[ "$(PERF_STACK_ID)" != '' ]]; then \
		echo "ERROR: $(STACK_NAME)スタックを削除できません" >&2; \
		echo "理由: $(PERF_STACK_NAME)スタックが存在しているため" >&2; \
		echo "'make aws-delete-perf-cfn' で先に$(PERF_STACK_NAME)を削除するか 'make aws.down' や 'make aws.down-〇〇' でEC2を停止できます" >&2; \
		exit 1; \
	fi
	@aws cloudformation delete-stack --stack-name $(STACK_NAME)
	@echo '削除中です(約1.5~2分かかります)'
	@time aws cloudformation wait stack-delete-complete --stack-name $(STACK_NAME)
	@echo 'After status'
	@make aws.status

.PHONY: aws.delete-perf-cfn
aws.delete-perf-cfn: ## AWSのパフォーマンス用CFnスタックを削除(約1.5分)
	@aws cloudformation delete-stack --stack-name $(PERF_STACK_NAME)
	@echo '削除中です(約1.5~2分かかります)'
	@time aws cloudformation wait stack-delete-complete --stack-name $(PERF_STACK_NAME)
	@make aws.status

################################################################################
# 停止
################################################################################
.PHONY: aws.down
aws.down: ## AWSのインスタンスを停止
	@make aws.down-web
	@make aws.down-bench
	@make aws.down-perf

.PHONY: aws.down-web
aws.down-web: ## webインスタンスを停止
	$(eval STACK_ID := $(shell aws cloudformation describe-stacks --stack-name $(STACK_NAME) --query 'Stacks[0].StackId' --output text))
	$(eval WEB_INSTANCE_ID := $(shell aws ec2 describe-instances --filters "Name=tag:aws:cloudformation:stack-id,Values=$(STACK_ID)" 'Name=tag:Name,Values=web' --query 'Reservations[].Instances[].InstanceId' --output text))
	@aws ec2 stop-instances --instance-ids $(WEB_INSTANCE_ID)

.PHONY: aws.down-bench
aws.down-bench: ## benchインスタンスを停止
	$(eval STACK_ID := $(shell aws cloudformation describe-stacks --stack-name $(STACK_NAME) --query 'Stacks[0].StackId' --output text))
	$(eval BENCH_INSTANCE_ID := $(shell aws ec2 describe-instances --filters "Name=tag:aws:cloudformation:stack-id,Values=$(STACK_ID)" 'Name=tag:Name,Values=bench' --query 'Reservations[].Instances[].InstanceId' --output text))
	@aws ec2 stop-instances --instance-ids $(BENCH_INSTANCE_ID)

.PHONY: aws.down-perf
aws.down-perf: ## perfインスタンスを停止
	$(eval PERF_STACK_ID := $(shell aws cloudformation describe-stacks --stack-name $(PERF_STACK_NAME) --query 'Stacks[0].StackId' --output text 2>/dev/null || true))
	$(eval PERF_INSTANCE_ID := $(if $(PERF_STACK_ID), $(shell aws ec2 describe-instances --filters "Name=tag:aws:cloudformation:stack-id,Values=$(PERF_STACK_ID)" 'Name=tag:Name,Values=perf' --query 'Reservations[].Instances[].InstanceId' --output text), none))
	@if [[ '$(PERF_INSTANCE_ID)' != 'none' ]]; then \
		aws ec2 stop-instances --instance-ids $(PERF_INSTANCE_ID); \
	fi

################################################################################
# 起動
################################################################################
.PHONY: aws.up
aws.up: ## AWSのインスタンスを起動
	@make aws.up-perf
	@make aws.up-web
	@make aws.up-bench

.PHONY: aws.up-web
aws.up-web: ## webインスタンスを起動
	$(eval STACK_ID := $(shell aws cloudformation describe-stacks --stack-name $(STACK_NAME) --query 'Stacks[0].StackId' --output text))
	$(eval WEB_INSTANCE_ID := $(shell aws ec2 describe-instances --filters "Name=tag:aws:cloudformation:stack-id,Values=$(STACK_ID)" 'Name=tag:Name,Values=web' --query 'Reservations[].Instances[].InstanceId' --output text))
	@aws ec2 start-instances --instance-ids $(WEB_INSTANCE_ID)
	@aws ec2 wait instance-running --instance-ids $(WEB_INSTANCE_ID)
	@make aws.add-myip-inbound-rule

.PHONY: aws.up-bench
aws.up-bench: ## benchインスタンスを起動
	$(eval STACK_ID := $(shell aws cloudformation describe-stacks --stack-name $(STACK_NAME) --query 'Stacks[0].StackId' --output text))
	$(eval BENCH_INSTANCE_ID := $(shell aws ec2 describe-instances --filters "Name=tag:aws:cloudformation:stack-id,Values=$(STACK_ID)" 'Name=tag:Name,Values=bench' --query 'Reservations[].Instances[].InstanceId' --output text))
	@aws ec2 start-instances --instance-ids $(BENCH_INSTANCE_ID)
	@aws ec2 wait instance-running --instance-ids $(BENCH_INSTANCE_ID)
	@make aws.add-myip-inbound-rule

.PHONY: aws.up-perf
aws.up-perf: ## perfインスタンスを起動
	$(eval PERF_STACK_ID := $(shell aws cloudformation describe-stacks --stack-name $(PERF_STACK_NAME) --query 'Stacks[0].StackId' --output text 2>/dev/null || true))
	$(eval PERF_INSTANCE_ID := $(if $(PERF_STACK_ID), $(shell aws ec2 describe-instances --filters "Name=tag:aws:cloudformation:stack-id,Values=$(PERF_STACK_ID)" 'Name=tag:Name,Values=perf' --query 'Reservations[].Instances[].InstanceId' --output text), none))
	@if [[ '$(PERF_INSTANCE_ID)' != 'none' ]]; then \
		aws ec2 start-instances --instance-ids $(PERF_INSTANCE_ID); \
		aws ec2 wait instance-running --instance-ids $(PERF_INSTANCE_ID); \
		make aws.add-myip-inbound-rule; \
		make aws.setup-ssh-config; \
	fi

################################################################################
# MY_IPの追加と掃除
################################################################################
.PHONY: aws.add-myip-inbound-rule
aws.add-myip-inbound-rule: ## AWSのSecurityGroupのMY_IP関連のインバウンドルールを追加
	$(eval SG_ID := $(shell aws ec2 describe-security-groups --filters "Name=tag:aws:cloudformation:stack-name,Values=$(STACK_NAME)" --query 'SecurityGroups[0].GroupId' --output text))
	$(eval MY_IP := $(shell curl -fsS https://checkip.amazonaws.com))
	@if aws ec2 describe-security-groups --group-ids "$(SG_ID)" --query 'SecurityGroups[0].IpPermissions[].IpRanges[].CidrIp' --output text | grep -q "$(MY_IP)/32"; then \
		echo "MY_IP許可済み: $(MY_IP)/32"; \
	else \
		aws ec2 authorize-security-group-ingress --group-id "$(SG_ID)" --ip-permissions '[{"IpProtocol": "-1", "IpRanges": [{"CidrIp": "$(MY_IP)/32"}]}]'; \
	fi
	@ssh web   -F "${SSH_CONFIG_FILE}" 'echo "ssh web:   OK"' || echo 'ssh web:   SSH NG'
	@ssh bench -F "${SSH_CONFIG_FILE}" 'echo "ssh bench: OK"' || echo 'ssh bench: SSH NG'
	@ssh perf  -F "${SSH_CONFIG_FILE}" 'echo "ssh perf: OK"'  || echo 'ssh perf:  SSH NG'

.PHONY: aws.clean-and-add-myip-inbound-rule
aws.clean-and-add-myip-inbound-rule: ## AWSのSecurityGroupのMY_IP関連のインバウンドルールを全削除して、追加
	$(eval SG_ID := $(shell aws ec2 describe-security-groups --filters "Name=tag:aws:cloudformation:stack-name,Values=$(STACK_NAME)" --query 'SecurityGroups[0].GroupId' --output text))
	@for cidr in $(shell aws ec2 describe-security-groups --group-ids $(SG_ID) --query 'SecurityGroups[0].IpPermissions[].IpRanges[].CidrIp' --output json | jq -r '.[] | select(endswith("/32"))'); do \
		aws ec2 revoke-security-group-ingress --group-id $(SG_ID) --ip-permissions '[{"IpProtocol": "-1", "IpRanges": [{"CidrIp": "'$$cidr'"}]}]'; \
	done
	@make aws.add-myip-inbound-rule

################################################################################
# SSHの設定
################################################################################
.PHONY: aws.setup-ssh-config
aws.setup-ssh-config: validate-ssh-private-key ## SSH設定をセットアップ
	$(eval STACK_ID := $(shell aws cloudformation describe-stacks --stack-name $(STACK_NAME) --query 'Stacks[0].StackId' --output text))
	$(eval WEB_HOST_IP := $(shell aws ec2 describe-instances --filters "Name=tag:aws:cloudformation:stack-id,Values=$(STACK_ID)" 'Name=tag:Name,Values=web' --query 'Reservations[0].Instances[0].PublicIpAddress' --output text))
	$(eval BENCH_HOST_IP := $(shell aws ec2 describe-instances --filters "Name=tag:aws:cloudformation:stack-id,Values=$(STACK_ID)" 'Name=tag:Name,Values=bench' --query 'Reservations[0].Instances[0].PublicIpAddress' --output text))
	$(eval PERF_STACK_ID := $(shell aws cloudformation describe-stacks --stack-name $(PERF_STACK_NAME) --query 'Stacks[0].StackId' --output text 2>/dev/null || true))
	$(eval PERF_HOST_IP := $(if $(PERF_STACK_ID), $(shell aws ec2 describe-instances --filters "Name=tag:aws:cloudformation:stack-id,Values=$(PERF_STACK_ID)" 'Name=tag:Name,Values=perf' --query 'Reservations[0].Instances[0].PublicIpAddress' --output text), perf-not-exist))
	@mkdir -p .ssh
	@sed \
		-e "s|{{SSH_PRIVATE_KEY_PATH}}|${SSH_PRIVATE_KEY_PATH}|g" \
		-e "s|{{WEB_HOST_IP}}|$(WEB_HOST_IP)|g" \
		-e "s|{{BENCH_HOST_IP}}|$(BENCH_HOST_IP)|g" \
		-e "s|{{PERF_HOST_IP}}|$(PERF_HOST_IP)|g" \
		.ssh/ssh_config.tmpl > .ssh/config
	@ssh web   -F "${SSH_CONFIG_FILE}" 'echo "ssh web:   OK"' || echo 'ssh web:   SSH NG'
	@ssh bench -F "${SSH_CONFIG_FILE}" 'echo "ssh bench: OK"' || echo 'ssh bench: SSH NG'
	@ssh perf  -F "${SSH_CONFIG_FILE}" 'echo "ssh perf:  OK"' || echo 'ssh perf:  SSH NG'

# SSH秘密鍵の検証
# SSH_PRIVATE_KEY_PATHが指す秘密鍵の公開鍵がGitHubアカウントに登録されているか確認
# 理由: EC2に登録する公開鍵は https://github.com/${GITHUB_USERNAME}.keys を利用しているため
# GITHUB_USERNAMEは.envrc.overrideに記載
validate-ssh-private-key:
	$(eval PUBLIC_KEY := $(shell ssh-keygen -y -f ${SSH_PRIVATE_KEY_PATH} | cut -d ' ' -f1,2))
	@test -n "$${GITHUB_USERNAME:-}" || { \
		echo '----[ERROR]----' >&2; \
		echo 'GITHUB_USERNAMEが設定されていません' >&2; \
		echo 'cp .envrc.override.sample .envrc.overrideを実施し、' >&2; \
		echo 'GitHubアカウント名(GITHUB_USERNAME)を.envrc.overrideに設定してdirenv allowをしてください' >&2; \
		exit 1; \
	}
	@curl -fsS "https://github.com/${GITHUB_USERNAME}.keys" | grep -q "$(PUBLIC_KEY)" || ( \
		echo '----[ERROR]----' >&2; \
		echo "秘密鍵=${SSH_PRIVATE_KEY_PATH} に対応する公開鍵が https://github.com/${GITHUB_USERNAME}.keys にありません" >&2; \
		echo '登録済みの公開鍵に対応する秘密鍵のパスを.envrc.overrideに設定してください' >&2; \
		echo 'もしくはGitHubアカウント名(GITHUB_USERNAME)を.envrc.overrideに設定してください' >&2; \
		exit 1)
