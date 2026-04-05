################################################################################
# 一覧
################################################################################
.PHONY: aws.status
aws.status: ## AWSのインスタンス状態とCFnスタック一覧
	@aws cloudformation list-stacks --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE --query 'StackSummaries[].{Name:StackName,Created:CreationTime}' --output table
	@aws ec2 describe-instances --filters 'Name=tag:Name,Values=web,bench' --query 'Reservations[].Instances[].{Name:Tags[?Key==`Name`]|[0].Value,State:State.Name,PublicIp:PublicIpAddress,InstanceId:InstanceId}' --output table

################################################################################
# CFnスタック作成
################################################################################
.PHONY: aws.create-cfn
aws.create-cfn: validate-ssh-private-key ## AWSのCFnスタックを作成
	$(eval MY_IP := $(shell curl -fsS https://checkip.amazonaws.com))
	@aws cloudformation create-stack --stack-name $(STACK_NAME) --template-body file://private-isu.yaml --parameters \
		ParameterKey=GitHubUsername,ParameterValue="${GITHUB_USERNAME}" \
		ParameterKey=MyIp,ParameterValue=$(MY_IP)
	@echo "$(STACK_NAME): 作成中です(約1分かかります)"
	@time aws cloudformation wait stack-create-complete --stack-name $(STACK_NAME)

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
