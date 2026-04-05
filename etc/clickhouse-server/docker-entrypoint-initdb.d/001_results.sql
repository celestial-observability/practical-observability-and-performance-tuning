--
-- ベンチマークのスコアとcommit idなどベンチマークの結果を載せるテーブル
-- スコアの伸び具合を可視化するために利用
--
use default;
CREATE TABLE IF NOT EXISTS results (
  started_at DateTime         COMMENT 'スロークエリ分析結果の開始日時。ベンチマークの開始日時として採用',
  ended_at   DateTime         COMMENT 'スロークエリ分析結果の終了日時。ベンチマークの終了日時として採用',
  score      UInt64           COMMENT 'ベンチマークのスコア'
)
ENGINE = MergeTree
ORDER BY (started_at, ended_at)
COMMENT 'ベンチマークの結果'
;
-- log_started_at でスロークエリ分析とJOIN可能にする
