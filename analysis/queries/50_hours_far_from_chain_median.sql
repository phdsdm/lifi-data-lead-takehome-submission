-- 50_hours_far_from_chain_median
-- Question: Which hours of a source chain carry far fewer or far more rows than that chain's
--           median hour, and who carried the spikes?
-- Grain:    one row per (chain, hour) below 30% or above 300% of the chain's median rows per
--           hour (5 in this file), with the chain's median.
-- Definition applied (the 30% / 300% band is a reading aid, not a definition):
--   - Rows per hour per chain over the 168 hours of the window, hour = block_time floored, UTC;
--     an hour with no row counts as 0 (none occurs; 04_window_hours_and_gaps_by_chain).
--   - ratio_to_median: the hour's rows over the chain's median rows per hour.
--   - top_integrator / top_integrator_rows, senders, usd: the string with most rows in the
--     hour, the distinct tx_from of the hour and its headline USD (amount_usd).
-- Inputs:   transfers_priced (rows: provided data; usd: headline column).

WITH hours AS (
    SELECT range AS hour_utc
    FROM range(TIMESTAMP '2026-10-13 00:00:00', TIMESTAMP '2026-10-20 00:00:00', INTERVAL 1 HOUR)
),
counts AS (
    SELECT chain, hour AS hour_utc, count(*) AS n_rows, count(DISTINCT tx_from) AS senders, sum(amount_usd) AS usd
    FROM transfers_priced
    GROUP BY chain, hour
),
grid AS (
    SELECT c.chain, h.hour_utc, coalesce(n.n_rows, 0) AS n_rows, n.senders, n.usd
    FROM (SELECT DISTINCT chain FROM transfers) c
    CROSS JOIN hours h
    LEFT JOIN counts n ON n.chain = c.chain AND n.hour_utc = h.hour_utc
),
medians AS (
    SELECT chain, median(n_rows) AS median_rows_per_hour FROM grid GROUP BY chain
),
top_string AS (
    SELECT chain, hour AS hour_utc, integrator, count(*) AS n
    FROM transfers_priced
    GROUP BY chain, hour, integrator
    QUALIFY row_number() OVER (PARTITION BY chain, hour ORDER BY count(*) DESC, integrator) = 1
)
SELECT g.chain,
       g.hour_utc,
       g.n_rows,
       m.median_rows_per_hour,
       round(g.n_rows / m.median_rows_per_hour, 2)   AS ratio_to_median,
       g.senders,
       round(g.usd, 2)                               AS usd,
       t.integrator                                  AS top_integrator,
       t.n                                           AS top_integrator_rows
FROM grid g
JOIN medians m USING (chain)
LEFT JOIN top_string t ON t.chain = g.chain AND t.hour_utc = g.hour_utc
WHERE g.n_rows < 0.3 * m.median_rows_per_hour OR g.n_rows > 3 * m.median_rows_per_hour
ORDER BY g.chain, g.hour_utc
