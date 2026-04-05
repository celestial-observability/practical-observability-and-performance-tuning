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
  - 引数(target_host)に対してスコアを保存する
実行方法:
  - $0 <target_host>
実行例:
  - $0 host.docker.internal
EOF
  exit 2
}

# result.jsonから抽出し、保存
store() {
  local target_score_dir=$1
  local input_result_json="$target_score_dir/result.json"

  # 入力ファイルの有無を確認
  if [[ ! -f "$input_result_json" ]]; then
    log_error "入力用のファイルが存在しません: $input_result_json"
    err
  fi

  # テーブルにINSERTする値を取得
  local started_at
  local ended_at
  local score
  started_at=$(jq -r '.started_at' "$input_result_json")
  ended_at=$(jq -r '.ended_at' "$input_result_json")
  score=$(jq -r '.score' "$input_result_json")
  # started_at, ended_at, scoreのバリデーション
  if [[ -z "$started_at" || -z "$ended_at" || -z "$score" || "$started_at" == 'null' || "$ended_at" == 'null' || "$score" == 'null' ]]; then
    log_error "result.jsonからスコア・開始・終了日時を取得できません: $input_result_json"
    err
  fi

  # 重複するならINSERTしない
  local duplicated_count
  duplicated_count=$(COMPOSE_PROGRESS=quiet docker compose -p "$DOCKER_PROJECT" -f compose.tool.yaml run --rm -T ch clickhouse-client --host="$TARGET_HOST" --user "$CLICKHOUSE_USER" --password "$CLICKHOUSE_PASSWORD" --query="
    SELECT COUNT(1)
    FROM default.results
    WHERE started_at = parseDateTimeBestEffort('$started_at')
      AND ended_at = parseDateTimeBestEffort('$ended_at');
  ")
  if [[ "$duplicated_count" -gt 0 ]]; then
    return
  fi

  before_count=$(COMPOSE_PROGRESS=quiet docker compose -p "$DOCKER_PROJECT" -f compose.tool.yaml run --rm -T ch clickhouse-client --host="$TARGET_HOST" --user "$CLICKHOUSE_USER" --password "$CLICKHOUSE_PASSWORD" --query="SELECT COUNT(1) FROM default.results;")

  COMPOSE_PROGRESS=quiet docker compose -p "$DOCKER_PROJECT" -f compose.tool.yaml run --rm ch clickhouse-client --host="$TARGET_HOST" --user "$CLICKHOUSE_USER" --password "$CLICKHOUSE_PASSWORD" --query="
    INSERT INTO results (started_at, ended_at, score)
    VALUES (parseDateTimeBestEffort('$started_at'), parseDateTimeBestEffort('$ended_at'), $score);
  "

  after_count=$(COMPOSE_PROGRESS=quiet docker compose -p "$DOCKER_PROJECT" -f compose.tool.yaml run --rm -T ch clickhouse-client --host="$TARGET_HOST" --user "$CLICKHOUSE_USER" --password "$CLICKHOUSE_PASSWORD" --query="SELECT COUNT(1) FROM default.results;")
  log_info "ベンチ結果を保存完了($target_score_dir): results: $before_count → $after_count 行"
}

start_timer "$@"
(($# == 1)) || (echo '引数は1つだけ必要です' >&2 && usage)
readonly TARGET_HOST="$1"
readonly DOCKER_PROJECT='store-results'
if ! COMPOSE_PROGRESS=quiet docker compose -p "$DOCKER_PROJECT" -f compose.tool.yaml run --rm -T ch bash -c "clickhouse-client --host='$TARGET_HOST' --user '$CLICKHOUSE_USER' --password '$CLICKHOUSE_PASSWORD' --query=\"SELECT 'OK'\"" >/dev/null 2>&1; then
  log_error "Error: ClickHouse($TARGET_HOST:9000)に接続できません in $0"
  exit 1
fi

for line in results/*; do
  store "$line"
done

echo '最新の3件(開始日時, 終了日時, スコア):'
COMPOSE_PROGRESS=quiet docker compose -p "$DOCKER_PROJECT" -f compose.tool.yaml run --rm -T ch clickhouse-client --host="$TARGET_HOST" --user "$CLICKHOUSE_USER" --password "$CLICKHOUSE_PASSWORD" --query="SELECT toTimeZone(started_at, 'Asia/Tokyo'), toTimeZone(ended_at, 'Asia/Tokyo'), score FROM default.results ORDER BY started_at DESC LIMIT 3;"

end_timer "$@"
