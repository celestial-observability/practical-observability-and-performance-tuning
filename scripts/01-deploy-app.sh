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
  - 引数(target_host)に対してappをデプロイする
実行方法:
  - $0 <target_host>
実行例:
  - $0 web
EOF
  exit 2
}

start_timer "$@"
(($# == 1)) || (echo '引数は1つだけ必要です' >&2 && usage)
readonly TARGET_HOST="$1"
ssh -F "$SSH_CONFIG_FILE" "$TARGET_HOST" 'touch ~/.hushlogin' 2>&1 || {
  log_info "${TARGET_HOST}へのssh失敗($0 $*): "
  exit 0
}

# アップロード(上書き)
rsync -az ./private_isu/webapp/golang/ "$TARGET_HOST":~/private_isu/webapp/golang/
# ビルドと再起動
ssh -F "$SSH_CONFIG_FILE" "$TARGET_HOST" <<'EOF'
export PATH="/home/isucon/.local/go/bin/:$PATH" && cd ~/private_isu/webapp/golang/ && go mod tidy && make -B app

sudo -n systemctl disable --now isu-ruby
sudo -n systemctl enable --now isu-go
sudo -n systemctl restart isu-go
EOF
# go.sumをダウンロード
rsync -az "$TARGET_HOST":~/private_isu/webapp/golang/go.sum ./private_isu/webapp/golang/go.sum

end_timer "$@"
