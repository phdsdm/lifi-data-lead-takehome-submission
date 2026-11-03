-- 15_bridge_activity_span
-- Question: For each bridge, when is its first and last row, in how many of the 168 hours
--           does it carry rows, and what is its longest silence (by whole hours and by the
--           gap between consecutive rows)?
-- Grain:    one row per bridge string (31).
-- Definition applied:
--   - Hour: block_time floored to the hour, UTC; window 2026-10-13 00:00 to
--     2026-10-20 00:00 UTC (168 hours).
--   - median_rows_per_hour: median over all 168 hours, empty hours counted as 0.
--   - Longest empty run: the longest run of consecutive hours with no row of the bridge,
--     including runs at the start or end of the window; ties go to the earliest run.
--   - Longest gap: the longest time between two consecutive rows of the bridge
--     (ordered by block_time, then chain, then log_index). It ignores the time before the
--     first and after the last row; those are first_row and last_row.
-- Inputs:   transfers (provided data only).

WITH hours AS (
    SELECT range AS hour_utc
    FROM range(TIMESTAMP '2026-10-13 00:00:00', TIMESTAMP '2026-10-20 00:00:00', INTERVAL 1 HOUR)
),
counts AS (
    SELECT bridge, date_trunc('hour', block_time) AS hour_utc, count(*) AS n_rows
    FROM transfers
    GROUP BY bridge, date_trunc('hour', block_time)
),
grid AS (
    SELECT b.bridge, h.hour_utc, coalesce(c.n_rows, 0) AS n_rows
    FROM (SELECT DISTINCT bridge FROM transfers) b
    CROSS JOIN hours h
    LEFT JOIN counts c ON c.bridge = b.bridge AND c.hour_utc = h.hour_utc
),
runs AS (
    SELECT *, sum(CASE WHEN n_rows > 0 THEN 1 ELSE 0 END) OVER (PARTITION BY bridge ORDER BY hour_utc) AS run_id
    FROM grid
),
empty_runs AS (
    SELECT bridge, min(hour_utc) AS run_start, max(hour_utc) AS run_end, count(*) AS run_hours
    FROM runs
    WHERE n_rows = 0
    GROUP BY bridge, run_id
),
longest_empty AS (
    SELECT * FROM empty_runs
    QUALIFY row_number() OVER (PARTITION BY bridge ORDER BY run_hours DESC, run_start) = 1
),
hour_stats AS (
    SELECT bridge,
           sum(n_rows)                          AS n_rows,
           count(*) FILTER (WHERE n_rows > 0)   AS hours_with_rows,
           median(n_rows)                       AS median_rows_per_hour
    FROM grid
    GROUP BY bridge
),
gaps AS (
    SELECT bridge,
           lag(block_time) OVER w                                 AS gap_from,
           block_time                                             AS gap_to,
           epoch(block_time) - epoch(lag(block_time) OVER w)      AS gap_seconds
    FROM transfers
    WINDOW w AS (PARTITION BY bridge ORDER BY block_time, chain, log_index)
),
longest_gap AS (
    SELECT bridge,
           max(gap_seconds)                AS gap_seconds,
           arg_max(gap_from, gap_seconds)  AS gap_from,
           arg_max(gap_to, gap_seconds)    AS gap_to
    FROM gaps
    WHERE gap_seconds IS NOT NULL
    GROUP BY bridge
),
span AS (
    SELECT bridge, min(block_time) AS first_row, max(block_time) AS last_row
    FROM transfers
    GROUP BY bridge
)
SELECT h.bridge,
       h.n_rows,
       s.first_row,
       s.last_row,
       h.hours_with_rows,
       h.median_rows_per_hour,
       e.run_start                         AS longest_empty_run_start,
       e.run_end + INTERVAL 59 MINUTE + INTERVAL 59 SECOND AS longest_empty_run_end,
       coalesce(e.run_hours, 0)            AS longest_empty_run_hours,
       g.gap_from                          AS longest_gap_from,
       g.gap_to                            AS longest_gap_to,
       round(g.gap_seconds / 3600, 2)      AS longest_gap_hours
FROM hour_stats h
JOIN span s USING (bridge)
LEFT JOIN longest_empty e USING (bridge)
LEFT JOIN longest_gap g USING (bridge)
ORDER BY h.n_rows DESC, h.bridge
