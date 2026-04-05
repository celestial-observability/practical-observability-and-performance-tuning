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
  - スロークエリ分析をする
実行方法:
  - $0
実行例:
  - $0
EOF
  exit 2
}

# Nginxアクセスログ分析(alpは直接TSV出力可能)
analyze_nginx_access_log() {
  local target_score_dir=$1
  local input_access_log="$target_score_dir/var/log/nginx/access.log"

  COMPOSE_PROGRESS=quiet docker compose -p "$DOCKER_PROJECT" -f compose.tool.yaml run --rm alp alp ltsv --config alp.yaml --file "$input_access_log" >"$target_score_dir/analyzed_nginx_access.tsv"
}

# MySQLのスロークエリログ分析
analyze_slowquery() {
  local target_score_dir=$1
  local input_slowquery_log="$target_score_dir/var/log/mysql/mysql-slow.log"
  local output_analyzed_slowquery="$target_score_dir/analyzed_slowquery"
  local output_analyzed_slowquery_json="$target_score_dir/analyzed_slowquery.json"

  if [[ -s "$output_analyzed_slowquery" && -s "$output_analyzed_slowquery_json" ]]; then
    log_info "分析済み: $target_score_dir"
    return
  fi

  # 人間が閲覧 & 開始/終了日時を取得するために利用: output_analyzed_slowquery
  # ClickHouseにINSERTで利用: output_analyzed_slowquery_json
  COMPOSE_PROGRESS=quiet docker compose -p "$DOCKER_PROJECT" -f compose.tool.yaml run --rm pt pt-query-digest --limit 3 "$input_slowquery_log" >"$output_analyzed_slowquery" &
  COMPOSE_PROGRESS=quiet docker compose -p "$DOCKER_PROJECT" -f compose.tool.yaml run --rm pt pt-query-digest --limit 10 --output json "$input_slowquery_log" | jq '.' >"$output_analyzed_slowquery_json" &
  wait
  if [[ -s "$output_analyzed_slowquery" && -s "$output_analyzed_slowquery_json" ]]; then
    log_info "分析成功: $target_score_dir"
  else
    log_error "分析失敗: $target_score_dir"
    exit 1
  fi
}

# 分析結果(人間用)からベンチ開始・終了日時(スロークエリログの開始・終了)をresult.jsonにマージ
merge_time_range_to_result_json() {
  local target_score_dir=$1
  local input_analyzed_slowquery="$target_score_dir/analyzed_slowquery"
  local input_analyzed_slowquery_json="$target_score_dir/analyzed_slowquery.json"

  # inputファイルの有無を確認
  if [[ ! -f "$input_analyzed_slowquery" || ! -f "$input_analyzed_slowquery_json" ]]; then
    log_error "分析結果が存在しません: $input_analyzed_slowquery or $input_analyzed_slowquery_json"
    err
  fi

  # Time rangeから開始日時・終了日時を抽出
  # grep結果
  # # Time range: 2025-12-31T08:12:16 to 2025-12-31T08:13:31
  # # Time range: 2025-12-31T08:12:16 to 2025-12-31T08:13:31
  # ...
  local time_range_line
  local started_at
  local ended_at
  time_range_line="$(grep '# Time range:' "$input_analyzed_slowquery" | head -n 1)"
  if [[ -z "$time_range_line" ]]; then
    log_error "Time rangeの情報が見つかりません: $input_analyzed_slowquery"
    err
  fi
  started_at="$(echo "$time_range_line" | cut -d ' ' -f4)"
  ended_at="$(echo "$time_range_line" | cut -d ' ' -f6)"

  # マージ処理
  jq --arg started_at "$started_at" --arg ended_at "$ended_at" \
    '.started_at = $started_at | .ended_at = $ended_at' \
    "$target_score_dir/result.json" >"$target_score_dir/result.tmp.json"

  if [[ -s "$target_score_dir/result.tmp.json" ]]; then
    log_info "result.jsonにベンチマーク開始・終了日時のマージ成功: $target_score_dir"
    mv "$target_score_dir/result.tmp.json" "$target_score_dir/result.json"
  else
    log_error "result.jsonへのマージ失敗: $target_score_dir"
    err
  fi
}
start_timer "$@"
(($# == 0)) || (echo '引数の数は0である必要があります' >&2 && usage)
readonly DOCKER_PROJECT='analyze'

# 分析
for line in results/*; do
  analyze_slowquery "$line" &
  analyze_nginx_access_log "$line" &
done
wait

# 分析結果をマージ・TSV変換
for line in results/*; do
  merge_time_range_to_result_json "$line" &
done
wait

end_timer "$@"
