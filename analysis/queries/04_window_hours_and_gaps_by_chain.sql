-- 04_window_hours_and_gaps_by_chain
-- Question: Is the export window complete on every source chain: does every hour have
--           rows, and what is the largest gap between consecutive events?
-- Grain:    one row per source chain (6), plus a last row for all chains together.
-- Definition applied:
--   - Window: 2026-10-13 00:00:00 to 2026-10-20 00:00:00 UTC, exclusive end
--     (data/README_data_final.md), so 168 hours; hour = block_time floored to the hour, UTC.
--   - Consecutive events: rows of the chain ordered by block_time, then log_index; the gap
--     is the difference of their block times in seconds. The all-chains row orders every
--     row of the file the same way.
--   - min_rows_in_an_hour is over the 168 hours, so 0 would mean an empty hour.
-- Inputs:   transfers (provided data only).

WITH hours AS (
    SELECT range AS hour_utc
    FROM range(TIMESTAMP '2026-10-13 00:00:00', TIMESTAMP '2026-10-20 00:00:00', INTERVAL 1 HOUR)
),
chains AS (
    SELECT DISTINCT chain FROM transfers
    UNION ALL
    SELECT '(all chains)'
),
rows_tagged AS (
    SELECT chain, block_time, log_index FROM transfers
    UNION ALL
    SELECT '(all chains)', block_time, log_index FROM transfers
),
per_hour AS (
    SELECT c.chain, h.hour_utc, count(r.block_time) AS n_rows
    FROM chains c
    CROSS JOIN hours h
    LEFT JOIN rows_tagged r
           ON r.chain = c.chain AND date_trunc('hour', r.block_time) = h.hour_utc
    GROUP BY c.chain, h.hour_utc
),
hour_stats AS (
    SELECT chain,
           count(*)                            AS hours_in_window,
           count(*) FILTER (WHERE n_rows > 0)  AS hours_with_rows,
           min(n_rows)                         AS min_rows_in_an_hour
    FROM per_hour
    GROUP BY chain
),
gaps AS (
    SELECT chain,
           lag(block_time) OVER w                         AS gap_from,
           block_time                                     AS gap_to,
           epoch(block_time) - epoch(lag(block_time) OVER w) AS gap_seconds
    FROM rows_tagged
    WINDOW w AS (PARTITION BY chain ORDER BY block_time, log_index)
),
gap_stats AS (
    SELECT chain,
           max(gap_seconds)                  AS max_gap_seconds,
           arg_max(gap_from, gap_seconds)    AS max_gap_from,
           arg_max(gap_to, gap_seconds)      AS max_gap_to
    FROM gaps
    WHERE gap_seconds IS NOT NULL
    GROUP BY chain
),
span AS (
    SELECT chain,
           count(*)        AS n_rows,
           min(block_time) AS first_row,
           max(block_time) AS last_row,
           count(*) FILTER (WHERE block_time <  TIMESTAMP '2026-10-13 00:00:00'
                               OR block_time >= TIMESTAMP '2026-10-20 00:00:00') AS rows_outside_window
    FROM rows_tagged
    GROUP BY chain
)
SELECT s.chain,
       s.n_rows,
       s.first_row,
       s.last_row,
       s.rows_outside_window,
       h.hours_in_window,
       h.hours_with_rows,
       h.min_rows_in_an_hour,
       g.max_gap_seconds,
       round(g.max_gap_seconds / 60, 1) AS max_gap_minutes,
       g.max_gap_from,
       g.max_gap_to
FROM span s
JOIN hour_stats h USING (chain)
JOIN gap_stats g USING (chain)
ORDER BY s.chain = '(all chains)', g.max_gap_seconds, s.chain
