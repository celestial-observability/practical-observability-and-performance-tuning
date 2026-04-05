#!/usr/bin/env bash
set -Eeuo pipefail
#set -x
# -E: 関数やサブシェルでエラーが起きた時トラップ発動
# -e: エラーが発生した時点でスクリプトを終了
# -u: 未定義の変数を使用した場合にエラーを発生
# -x: スクリプトの実行内容を表示(debugで利用)
# -o pipefail: パイプライン内のエラーを検出

source "$(dirname "$0")/99-util.sh"

usage() {
  cat >&2 <<EOF
$0
概要:
  - 引数(agent_host)に対してパフォーマンス計測用のデプロイ
実行方法:
  - $0 <target_host>
実行例:
  - $0 web
EOF
  exit 2
}

# OTel Collector の設定を配置して再起動
deploy_otelcol() {
  local agent_or_gateway="$1"
  rsync -az --rsync-path 'sudo rsync' "./etc/otelcol-contrib/${agent_or_gateway}-config.yaml" "$TARGET_HOST":/etc/otelcol-contrib/config.yaml

  ssh -F "$SSH_CONFIG_FILE" "$TARGET_HOST" '
  set -euo pipefail
  sudo install -d -o isucon -g isucon -m 777 /var/lib/otelcol-contrib/queue
  sudo systemctl restart otelcol-contrib
  '
}

start_timer "$@"
(($# == 1)) || (echo '引数は1つだけ必要です' >&2 && usage)
readonly TARGET_HOST="$1"
ssh -F "$SSH_CONFIG_FILE" "$TARGET_HOST" "touch ~/.hushlogin" 2>&1 || {
  echo "ssh失敗: $TARGET_HOST"
  exit 0
}

deploy_otelcol agent
log_info "Agent($TARGET_HOST)のデプロイ完了"

end_timer "$@"
