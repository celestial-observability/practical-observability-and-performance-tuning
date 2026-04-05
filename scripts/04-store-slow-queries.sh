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
  - 引数(target_host)に対して分析結果を保存する
実行方法:
  - $0 <target_host>
実行例:
  - $0 host.docker.internal
EOF
  exit 2
}

# 分析結果を保存
store() {
  local target_score_dir=$1
  local analyzed_slow_run_tsv="$target_score_dir/analyzed_slow_run.tsv"
  local analyzed_slow_queries_tsv="$target_score_dir/analyzed_slow_queries.tsv"

  # 入力ファイルの有無を確認
  if [[ ! -f "$analyzed_slow_run_tsv" || ! -f "$analyzed_slow_queries_tsv" ]]; then
    log_error "入力用のファイルが存在しません: $analyzed_slow_run_tsv or $analyzed_slow_queries_tsv"
    err
  fi

  local log_started_at
  local log_ended_at
  log_started_at=$(head -n 1 "$analyzed_slow_run_tsv" | cut -f1)
  log_ended_at=$(head -n 1 "$analyzed_slow_run_tsv" | cut -f2)
  # 重複するならINSERTしない
  local duplicated_both_count
  local duplicated_started_at_count
  duplicated_both_count=$(COMPOSE_PROGRESS=quiet docker compose -p "$DOCKER_PROJECT" -f compose.tool.yaml run --rm ch clickhouse-client --host="$TARGET_HOST" --user "$CLICKHOUSE_USER" --password "$CLICKHOUSE_PASSWORD" --query="
    SELECT COUNT(1)
    FROM default.slow_runs
    WHERE log_started_at = parseDateTimeBestEffort('$log_started_at')
      AND log_ended_at = parseDateTimeBestEffort('$log_ended_at');
  ")
  if [[ "$duplicated_both_count" -gt 0 ]]; then
    return
  fi
  duplicated_started_at_count=$(COMPOSE_PROGRESS=quiet docker compose -p "$DOCKER_PROJECT" -f compose.tool.yaml run --rm ch clickhouse-client --host="$TARGET_HOST" --user "$CLICKHOUSE_USER" --password "$CLICKHOUSE_PASSWORD" --query="
    SELECT COUNT(1)
    FROM default.slow_runs
    WHERE log_started_at = parseDateTimeBestEffort('$log_started_at');
  ")
  if [[ "$duplicated_started_at_count" -gt 0 ]]; then
    log_error "同じ開始時刻の分析結果を保存しようとしています: $log_started_at"
    log_error 'ログの洗い替えをせずにベンチマーク実行した可能性があります'
    log_error "このベンチ結果ディレクトリ($target_score_dir)を削除してから、再度実行してください"
    log_error 'もし既存の方を削除する場合は、slow_runsテーブルとslow_queriesテーブルをTRUNCATEを忘れずに行ってください'
    err
  fi

  before_slow_runs_count=$(COMPOSE_PROGRESS=quiet    docker compose -p "$DOCKER_PROJECT" -f compose.tool.yaml run --rm ch clickhouse-client --host="$TARGET_HOST" --user "$CLICKHOUSE_USER" --password "$CLICKHOUSE_PASSWORD" --query="SELECT COUNT(1) FROM default.slow_runs;")
  before_slow_queries_count=$(COMPOSE_PROGRESS=quiet docker compose -p "$DOCKER_PROJECT" -f compose.tool.yaml run --rm ch clickhouse-client --host="$TARGET_HOST" --user "$CLICKHOUSE_USER" --password "$CLICKHOUSE_PASSWORD" --query="SELECT COUNT(1) FROM default.slow_queries;")

  COMPOSE_PROGRESS=quiet docker compose -p "$DOCKER_PROJECT" -f compose.tool.yaml run --rm -T ch clickhouse-client --host="$TARGET_HOST" --user "$CLICKHOUSE_USER" --password "$CLICKHOUSE_PASSWORD" --query="INSERT INTO slow_runs FORMAT TSV" <"$analyzed_slow_run_tsv"
  COMPOSE_PROGRESS=quiet docker compose -p "$DOCKER_PROJECT" -f compose.tool.yaml run --rm -T ch clickhouse-client --host="$TARGET_HOST" --user "$CLICKHOUSE_USER" --password "$CLICKHOUSE_PASSWORD" --query="INSERT INTO slow_queries FORMAT TSV" <"$analyzed_slow_queries_tsv"

  after_slow_runs_count=$(COMPOSE_PROGRESS=quiet    docker compose -p "$DOCKER_PROJECT" -f compose.tool.yaml run --rm ch clickhouse-client --host="$TARGET_HOST" --user "$CLICKHOUSE_USER" --password "$CLICKHOUSE_PASSWORD" --query="SELECT COUNT(1) FROM default.slow_runs;")
  after_slow_queries_count=$(COMPOSE_PROGRESS=quiet docker compose -p "$DOCKER_PROJECT" -f compose.tool.yaml run --rm ch clickhouse-client --host="$TARGET_HOST" --user "$CLICKHOUSE_USER" --password "$CLICKHOUSE_PASSWORD" --query="SELECT COUNT(1) FROM default.slow_queries;")
  log_info "保存完了($target_score_dir): slow_runs: $before_slow_runs_count → $after_slow_runs_count 行, slow_queries: $before_slow_queries_count → $after_slow_queries_count 行"
}

start_timer "$@"
(($# == 1)) || (echo '引数は1つだけ必要です' >&2 && usage)
readonly TARGET_HOST="$1"
readonly DOCKER_PROJECT='store-slow-queries'
if ! COMPOSE_PROGRESS=quiet docker compose -p "$DOCKER_PROJECT" -f compose.tool.yaml run --rm ch bash -c "clickhouse-client --host='$TARGET_HOST' --user '$CLICKHOUSE_USER' --password '$CLICKHOUSE_PASSWORD' --query=\"SELECT 'OK'\"" >/dev/null 2>&1; then
  log_error "Error: ClickHouse($TARGET_HOST:9000)に接続できません in $0"
  exit 1
fi

for line in results/*; do
  store "$line"
done

slow_runs_count=$(COMPOSE_PROGRESS=quiet    docker compose -p "$DOCKER_PROJECT" -f compose.tool.yaml run --rm ch clickhouse-client --host="$TARGET_HOST" --user "$CLICKHOUSE_USER" --password "$CLICKHOUSE_PASSWORD" --query="SELECT COUNT(1) FROM default.slow_runs;")
slow_queries_count=$(COMPOSE_PROGRESS=quiet docker compose -p "$DOCKER_PROJECT" -f compose.tool.yaml run --rm ch clickhouse-client --host="$TARGET_HOST" --user "$CLICKHOUSE_USER" --password "$CLICKHOUSE_PASSWORD" --query="SELECT COUNT(1) FROM default.slow_queries;")
log_info "現在のテーブル: slow_runs=$slow_runs_count 行, slow_queries=$slow_queries_count 行"

end_timer "$@"
