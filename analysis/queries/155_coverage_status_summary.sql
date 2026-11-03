-- 155_coverage_status_summary
-- Question: Tested on the sample, how often does the proposed coverage status give a status,
--           and how are those windows split between operational, degraded and outage, per tool, per
--           source chain, per destination chain and for LI.FI overall?
--
--           THIS IS A PROXY, NOT THE TARGET METRIC. The target metric counts successful transfers
--           against the median of the same 3-hour window over the last 4 weeks (illustrative).
--           The sample has one week and no status on every row, so this query counts STARTED rows
--           against the same window 24 HOURS EARLIER. It cannot see transfers that started and then
--           failed.
-- Grain:    per dimension type (tool, source chain, destination chain, overall): one row_kind
--           'dimension' row, then one row_kind 'value' row per value. The overall dimension has one
--           value, so its two rows carry the same figures.
-- Definition applied (a proposal; bridge_volume_usd in task_1.md for the scope):
--   - Scope: bridge rows only, destination_chain_id differs from the source chain's id. The
--     three *Dex tools have only same-chain rows, so they are not values of the tool dimension.
--   - Window: 3 hours, UTC, on a fixed grid from 00:00 (56 in the week). Size and grid were chosen
--     for this test; a daily window for low-volume tools was not tested.
--   - rows: started bridge rows of the value in the window. The grid holds every (window, value)
--     pair, so a window with no rows counts as 0, not as missing; a value's grid starts with the
--     week even if its first row comes later.
--   - baseline: rows of the same value in the window 24 hours earlier. The first day's 8 windows
--     have none, which leaves 48 per value (windows_with_baseline).
--   - status: no status when baseline < 20. Otherwise operational when rows >= 50% of baseline,
--     degraded when rows >= 20% and < 50%, outage when rows < 20%. Compared in integers, so exactly
--     50% is operational and exactly 20% is degraded. The thresholds are a proposal to be tested.
--   - Values: tool = bridge in the event; source chain = chain in the event; destination chain =
--     the name in LI.FI's chain registry, so Tron's two ids are one value; overall = all rows.
--   - pct_windows_with_status: of windows_with_baseline. pct_operational, pct_degraded, pct_outage:
--     of windows_with_status. rows_with_baseline: rows in windows that have a baseline;
--     pct_rows_in_status_windows: the share of them in windows with a status.
--   - The windows that are not operational: 156_coverage_status_not_operational_windows.
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
),
per_value AS (
    SELECT dimension_type, value,
           count(*) FILTER (WHERE baseline IS NOT NULL)               AS windows_with_baseline,
           count(*) FILTER (WHERE status IS NOT NULL)                 AS windows_with_status,
           count(*) FILTER (WHERE status = 'operational')             AS operational,
           count(*) FILTER (WHERE status = 'degraded')                AS degraded,
           count(*) FILTER (WHERE status = 'outage')                  AS outage,
           sum(n_rows) FILTER (WHERE baseline IS NOT NULL)            AS rows_with_baseline,
           coalesce(sum(n_rows) FILTER (WHERE status IS NOT NULL), 0) AS rows_in_status_windows
    FROM scored
    GROUP BY dimension_type, value
),
unioned AS (
    SELECT dimension_type, '(all values)' AS value, 0 AS kind_ord, 'dimension' AS row_kind,
           count(*)                                        AS values_total,
           count(*) FILTER (WHERE windows_with_status > 0) AS values_with_status,
           sum(windows_with_baseline)                      AS windows_with_baseline,
           sum(windows_with_status)                        AS windows_with_status,
           sum(operational)                                AS operational,
           sum(degraded)                                   AS degraded,
           sum(outage)                                     AS outage,
           sum(rows_with_baseline)                         AS rows_with_baseline,
           sum(rows_in_status_windows)                     AS rows_in_status_windows
    FROM per_value
    GROUP BY dimension_type
    UNION ALL
    SELECT dimension_type, value, 1, 'value', 1,
           CASE WHEN windows_with_status > 0 THEN 1 ELSE 0 END,
           windows_with_baseline, windows_with_status, operational, degraded, outage,
           rows_with_baseline, rows_in_status_windows
    FROM per_value
)
SELECT u.dimension_type,
       u.row_kind,
       u.value,
       u.values_total,
       u.values_with_status,
       u.windows_with_baseline,
       u.windows_with_status,
       round(100.0 * u.windows_with_status / u.windows_with_baseline, 1)            AS pct_windows_with_status,
       u.operational,
       round(100.0 * u.operational / nullif(u.windows_with_status, 0), 1)           AS pct_operational,
       u.degraded,
       round(100.0 * u.degraded / nullif(u.windows_with_status, 0), 1)              AS pct_degraded,
       u.outage,
       round(100.0 * u.outage / nullif(u.windows_with_status, 0), 1)                AS pct_outage,
       u.rows_with_baseline,
       round(100.0 * u.rows_in_status_windows / nullif(u.rows_with_baseline, 0), 1) AS pct_rows_in_status_windows
FROM unioned u
JOIN dims d USING (dimension_type)
ORDER BY d.dim_ord, u.kind_ord, u.windows_with_status DESC, u.rows_with_baseline DESC, u.value
