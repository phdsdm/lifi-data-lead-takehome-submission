-- 156_coverage_status_not_operational_windows
-- Question: Which windows does the proposed coverage status mark degraded or outage on the
--           sample, per tool, per source chain, per destination chain and for LI.FI overall?
--
--           THIS IS A PROXY, NOT THE TARGET METRIC. The target metric counts successful transfers
--           against the median of the same 3-hour window over the last 4 weeks (illustrative).
--           The sample has one week and no status on every row, so this query counts STARTED rows
--           against the same window 24 HOURS EARLIER. It cannot see transfers that started and then
--           failed.
-- Grain:    one row per (dimension type, value, window) with status degraded or outage.
-- Definition applied (a proposal; bridge_volume_usd in task_1.md for the scope):
--   the same logic as 155_coverage_status_summary, whose header gives it in full:
--   - Scope: bridge rows only. Window: 3 hours, UTC, fixed grid from 00:00. A window with no rows
--     counts as 0. baseline: rows of the same value in the window 24 hours earlier.
--   - status: no status when baseline < 20; operational at rows >= 50% of baseline; degraded at 20%
--     to below 50%; outage below 20%. Compared in integers.
--   - Values: tool = bridge; source chain = chain; destination chain = the name in LI.FI's chain
--     registry, Tron's two ids one value; overall = all rows.
--   - ratio: rows / baseline, rounded to 3 decimals for display; the status uses the exact counts.
-- Inputs:   transfers (provided data), ref_lifi_chain_id_registry (reference data, destination names).

WITH source_ids(chain, chain_id) AS (
    VALUES ('ethereum', 1), ('optimism', 10), ('bnb', 56), ('polygon', 137), ('base', 8453), ('arbitrum', 42161)
),
dims(dimension_type, dim_ord) AS (
    VALUES ('tool', 1), ('source chain', 2), ('destination chain', 3), ('overall', 4)
),
t AS (
    SELECT time_bucket(INTERVAL 3 HOUR, p.block_time, TIMESTAMP '2026-10-13 00:00:00') AS window_start,
           p.bridge, p.chain, r.name AS destination_chain
    FROM transfers p
    JOIN source_ids s USING (chain)
    LEFT JOIN ref_lifi_chain_id_registry r ON r.chain_id = p.destination_chain_id
    WHERE p.destination_chain_id <> s.chain_id
),
long AS (
    SELECT 'tool' AS dimension_type, bridge AS value, window_start FROM t
    UNION ALL SELECT 'source chain', chain, window_start FROM t
    UNION ALL SELECT 'destination chain', destination_chain, window_start FROM t
    UNION ALL SELECT 'overall', 'LI.FI overall', window_start FROM t
),
windows AS (
    SELECT range AS window_start
    FROM range(TIMESTAMP '2026-10-13 00:00:00', TIMESTAMP '2026-10-20 00:00:00', INTERVAL 3 HOUR)
),
grid AS (
    SELECT v.dimension_type, v.value, w.window_start, count(l.window_start) AS n_rows
    FROM (SELECT DISTINCT dimension_type, value FROM long) v
    CROSS JOIN windows w
    LEFT JOIN long l
           ON l.dimension_type = v.dimension_type AND l.value = v.value AND l.window_start = w.window_start
    GROUP BY v.dimension_type, v.value, w.window_start
),
scored AS (
    SELECT g.dimension_type, g.value, g.window_start, g.n_rows, b.n_rows AS baseline,
           CASE WHEN b.n_rows IS NULL OR b.n_rows < 20 THEN NULL
                WHEN g.n_rows * 2 >= b.n_rows          THEN 'operational'
                WHEN g.n_rows * 5 >= b.n_rows          THEN 'degraded'
                ELSE 'outage' END AS status
    FROM grid g
    LEFT JOIN grid b
           ON b.dimension_type = g.dimension_type AND b.value = g.value
          AND b.window_start = g.window_start - INTERVAL 24 HOUR
)
SELECT s.dimension_type,
       s.value,
       s.window_start,
       s.n_rows,
       s.baseline,
       round(1.0 * s.n_rows / s.baseline, 3) AS ratio,
       s.status
FROM scored s
JOIN dims d USING (dimension_type)
WHERE s.status IN ('degraded', 'outage')
ORDER BY d.dim_ord, s.value, s.window_start
