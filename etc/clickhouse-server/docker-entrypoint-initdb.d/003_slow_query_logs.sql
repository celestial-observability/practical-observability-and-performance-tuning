use default;
-- ========== 集計単位: pt-query-digest 1回分 (global) ==========
CREATE TABLE IF NOT EXISTS slow_runs (
-- ====== pt-query-digest --output jsonにはなく、デフォルト(--output text)で出力した時に取得可能 ======
  log_started_at     DateTime COMMENT 'Time rangeの最初の日時。1つのpt-query-digest出力ごとに一意(UTC)',
  log_ended_at       DateTime COMMENT 'Time rangeの最後の日時',

-- ====== pt-query-digest全体情報 ======
  file_name          String COMMENT '元のスローログファイル名',
  file_size          UInt64 COMMENT 'スローログファイルサイズ（バイト）',
  query_count        UInt64 COMMENT '全クエリ件数（global.query_count）',
  unique_queries     UInt64 COMMENT 'ユニークなクエリ件数（global.unique_query_count）',

-- ===== global.metrics.Query_time =====
  g_qtime_sum        Float64 COMMENT '全クエリのQuery_time合計（秒）',
  g_qtime_avg        Float64 COMMENT 'Query_time平均（秒）',
  g_qtime_pct95      Float64 COMMENT 'Query_time 95パーセンタイル（秒）',
  g_qtime_stddev     Float64 COMMENT 'Query_time 標準偏差（秒）',
  g_qtime_min        Float64 COMMENT 'Query_time 最小値（秒）',
  g_qtime_max        Float64 COMMENT 'Query_time 最大値（秒）',
  g_qtime_median     Float64 COMMENT 'Query_time 中央値（秒）',

-- ===== global.metrics.Lock_time =====
  g_lock_sum         Float64 COMMENT '全クエリのLock_time合計（秒）',
  g_lock_avg         Float64 COMMENT 'Lock_time平均（秒）',
  g_lock_pct95       Float64 COMMENT 'Lock_time 95パーセンタイル（秒）',
  g_lock_stddev      Float64 COMMENT 'Lock_time 標準偏差（秒）',
  g_lock_min         Float64 COMMENT 'Lock_time 最小値（秒）',
  g_lock_max         Float64 COMMENT 'Lock_time 最大値（秒）',
  g_lock_median      Float64 COMMENT 'Lock_time 中央値（秒）',

-- ===== global.metrics.Rows_sent =====
  g_rows_sent_sum    Float64 COMMENT 'Rows_sent 合計',
  g_rows_sent_avg    Float64 COMMENT 'Rows_sent 平均',
  g_rows_sent_pct95  Float64 COMMENT 'Rows_sent 95パーセンタイル',
  g_rows_sent_stddev Float64 COMMENT 'Rows_sent 標準偏差',
  g_rows_sent_min    Float64 COMMENT 'Rows_sent 最小値',
  g_rows_sent_max    Float64 COMMENT 'Rows_sent 最大値',
  g_rows_sent_median Float64 COMMENT 'Rows_sent 中央値',

-- ===== global.metrics.Rows_examined =====
  g_rows_exam_sum    Float64 COMMENT 'Rows_examined 合計',
  g_rows_exam_avg    Float64 COMMENT 'Rows_examined 平均',
  g_rows_exam_pct95  Float64 COMMENT 'Rows_examined 95パーセンタイル',
  g_rows_exam_stddev Float64 COMMENT 'Rows_examined 標準偏差',
  g_rows_exam_min    Float64 COMMENT 'Rows_examined 最小値',
  g_rows_exam_max    Float64 COMMENT 'Rows_examined 最大値',
  g_rows_exam_median Float64 COMMENT 'Rows_examined 中央値',

-- ===== global.metrics.Query_length =====
  g_qlen_sum         Float64 COMMENT 'Query_length 合計（バイト）',
  g_qlen_avg         Float64 COMMENT 'Query_length 平均（バイト）',
  g_qlen_pct95       Float64 COMMENT 'Query_length 95パーセンタイル（バイト）',
  g_qlen_stddev      Float64 COMMENT 'Query_length 標準偏差（バイト）',
  g_qlen_min         Float64 COMMENT 'Query_length 最小値（バイト）',
  g_qlen_max         Float64 COMMENT 'Query_length 最大値（バイト）',
  g_qlen_median      Float64 COMMENT 'Query_length 中央値（バイト）'
)
ENGINE = MergeTree
ORDER BY (log_started_at, log_ended_at)
COMMENT 'pt-query-digestのglobal集計（全体統計）'
;

-- ========== クエリ単位: queries[] ==========
CREATE TABLE IF NOT EXISTS slow_queries (
  log_started_at    DateTime COMMENT 'ログファイルの最初の日時。1つのpt-query-digest出力ごとに一意(UTC)',
  fingerprint       String  COMMENT 'クエリ指紋（pt-query-digestのクエリ正規化結果）',
  attribute         String  COMMENT 'attribute（DISTINCT, DELETEなど分類タグ）',
  checksum          String  COMMENT 'クエリ内容のチェックサム',
  query_count       UInt64  COMMENT '該当クエリの出現回数',
  ts_min            DateTime COMMENT '最初に発生した時刻',
  ts_max            DateTime COMMENT '最後に発生した時刻',

  example_ts        DateTime COMMENT '代表クエリの実行時刻（example.ts）',
  example_query     String   COMMENT '代表クエリのSQL文（example.query）',
  example_qtime     Float64  COMMENT '代表クエリの実行時間（example.Query_time）',

  m_host            String  COMMENT 'metrics.host（実行ホスト）',
  m_db              String  COMMENT 'metrics.db（データベース名）',
  m_user            String  COMMENT 'metrics.user（ユーザ名）',

-- ===== metrics.Query_time =====
  qtime_sum         Float64 COMMENT 'Query_time 合計（秒）',
  qtime_avg         Float64 COMMENT 'Query_time 平均（秒）',
  qtime_pct95       Float64 COMMENT 'Query_time 95パーセンタイル（秒）',
  qtime_stddev      Float64 COMMENT 'Query_time 標準偏差（秒）',
  qtime_min         Float64 COMMENT 'Query_time 最小値（秒）',
  qtime_max         Float64 COMMENT 'Query_time 最大値（秒）',
  qtime_median      Float64 COMMENT 'Query_time 中央値（秒）',

-- ===== metrics.Lock_time =====
  lock_sum          Float64 COMMENT 'Lock_time 合計（秒）',
  lock_avg          Float64 COMMENT 'Lock_time 平均（秒）',
  lock_pct95        Float64 COMMENT 'Lock_time 95パーセンタイル（秒）',
  lock_stddev       Float64 COMMENT 'Lock_time 標準偏差（秒）',
  lock_min          Float64 COMMENT 'Lock_time 最小値（秒）',
  lock_max          Float64 COMMENT 'Lock_time 最大値（秒）',
  lock_median       Float64 COMMENT 'Lock_time 中央値（秒）',

-- ===== metrics.Rows_sent =====
  rows_sent_sum     Float64 COMMENT 'Rows_sent 合計',
  rows_sent_avg     Float64 COMMENT 'Rows_sent 平均',
  rows_sent_pct95   Float64 COMMENT 'Rows_sent 95パーセンタイル',
  rows_sent_stddev  Float64 COMMENT 'Rows_sent 標準偏差',
  rows_sent_min     Float64 COMMENT 'Rows_sent 最小値',
  rows_sent_max     Float64 COMMENT 'Rows_sent 最大値',
  rows_sent_median  Float64 COMMENT 'Rows_sent 中央値',

-- ===== metrics.Rows_examined =====
  rows_exam_sum     Float64 COMMENT 'Rows_examined 合計',
  rows_exam_avg     Float64 COMMENT 'Rows_examined 平均',
  rows_exam_pct95   Float64 COMMENT 'Rows_examined 95パーセンタイル',
  rows_exam_stddev  Float64 COMMENT 'Rows_examined 標準偏差',
  rows_exam_min     Float64 COMMENT 'Rows_examined 最小値',
  rows_exam_max     Float64 COMMENT 'Rows_examined 最大値',
  rows_exam_median  Float64 COMMENT 'Rows_examined 中央値',

-- ===== metrics.Query_length =====
  qlen_sum          Float64 COMMENT 'Query_length 合計（バイト）',
  qlen_avg          Float64 COMMENT 'Query_length 平均（バイト）',
  qlen_pct95        Float64 COMMENT 'Query_length 95パーセンタイル（バイト）',
  qlen_stddev       Float64 COMMENT 'Query_length 標準偏差（バイト）',
  qlen_min          Float64 COMMENT 'Query_length 最小値（バイト）',
  qlen_max          Float64 COMMENT 'Query_length 最大値（バイト）',
  qlen_median       Float64 COMMENT 'Query_length 中央値（バイト）'
)
ENGINE = MergeTree
ORDER BY (log_started_at, qtime_sum)
COMMENT 'pt-query-digestのクエリごとの統計'
;
-- log_started_atは、slow_runsテーブルとの結合用。qtime_sumは、クエリごとの実行時間合計でソート
