-- analyzed_nginx_access.tsvを直接INSERTできるClickHouse用スキーマ
-- カラム順はalp.yamlのoutput順に合わせる
-- ※ 1列目は、スロークエリログの開始日時を入れることで、JOINしたりフィルタしやすくする

CREATE TABLE IF NOT EXISTS nginx_access_runs (
-- スロークエリログの開始時刻
  slow_run_started_at DateTime COMMENT 'スロークエリログの開始日時(ベンチマークの開始時刻として採用)',

-- 回数系
  count  UInt64 COMMENT '総リクエスト数',
  c_1xx  UInt64 COMMENT '1xx数',
  c_2xx  UInt64 COMMENT '2xx数',
  c_3xx  UInt64 COMMENT '3xx数',
  c_4xx  UInt64 COMMENT '4xx数',
  c_5xx  UInt64 COMMENT '5xx数',
  method LowCardinality(String) COMMENT 'HTTPメソッド',
  uri    LowCardinality(String) COMMENT 'URI（必要なら正規化済みパターンを入れる）',
-- レスポンス時間系
  min    Float64 COMMENT '最小レスポンスタイム',
  max    Float64 COMMENT '最大レスポンスタイム',
  sum    Float64 COMMENT '合計レスポンスタイム',
  avg    Float64 COMMENT '平均レスポンスタイム',
  p90    Float64 COMMENT 'P90レスポンスタイム',
  p95    Float64 COMMENT 'P95レスポンスタイム',
  p99    Float64 COMMENT 'P99レスポンスタイム',
  stddev Float64 COMMENT 'レスポンスタイム標準偏差',
-- レスポンスサイズ系
  min_body Float64  COMMENT '最小レスポンスサイズ(byte)',
  max_body Float64  COMMENT '最大レスポンスサイズ(byte)',
  sum_body Float64  COMMENT '合計レスポンスサイズ(byte)',
  avg_body Float64 COMMENT '平均レスポンスサイズ(byte)'
)
ENGINE = MergeTree
ORDER BY (slow_run_started_at, sum)
COMMENT 'alpのnginxアクセス集計結果（TSV直INSERT用）'
;
