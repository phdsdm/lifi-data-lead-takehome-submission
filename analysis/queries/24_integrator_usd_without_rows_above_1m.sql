-- 24_integrator_usd_without_rows_above_1m
-- Question: How much of each integrator string's USD comes from rows above $1M, and how do
--           the shares and the ranking change when those rows are left out?
-- Grain:    one row per raw integrator string (598), after a first row for the whole file;
--           ordered by USD with every row.
-- Definition applied:
--   - USD: amount_usd, the headline (transfers_priced). A row above $1M has
--     amount_usd > 1,000,000 (22 rows; the same 22 under the provided feed alone, every
--     one priced by prices.csv; 28_usd_concentration).
--   - Shares are of the file's total with every row and without the rows above $1M.
--   - rank_*: dense rank by USD, 1 = largest; strings with no priced row have no rank.
--   - Integrator: the raw string, no normalisation map.
-- Inputs:   transfers_priced (headline column; reference data for its CoinGecko-priced rows).
-- The 22 rows themselves: 29_rows_above_1m_usd.

WITH t AS (
    SELECT integrator, amount_usd, amount_usd > 1000000 AS above_1m FROM transfers_priced
),
per_string AS (
    SELECT integrator,
           count(*)                                              AS n_rows,
           count(*) FILTER (WHERE above_1m)                      AS rows_above_1m,
           sum(amount_usd)                                       AS usd,
           coalesce(sum(amount_usd) FILTER (WHERE above_1m), 0)  AS usd_above_1m,
           sum(amount_usd) FILTER (WHERE NOT above_1m)           AS usd_without_rows_above_1m
    FROM t
    GROUP BY integrator
),
total AS (
    SELECT sum(n_rows) AS n_rows, sum(rows_above_1m) AS rows_above_1m, sum(usd) AS usd,
           sum(usd_above_1m) AS usd_above_1m, sum(usd_without_rows_above_1m) AS usd_without_rows_above_1m
    FROM per_string
),
together AS (
    SELECT '(every string)' AS integrator, 0 AS is_string, n_rows, rows_above_1m, usd, usd_above_1m, usd_without_rows_above_1m
    FROM total
    UNION ALL
    SELECT integrator, 1, n_rows, rows_above_1m, usd, usd_above_1m, usd_without_rows_above_1m FROM per_string
)
SELECT g.integrator,
       g.n_rows,
       g.rows_above_1m,
       round(g.usd, 2)                                                           AS usd,
       round(100.0 * g.usd / total.usd, 2)                                       AS pct_usd,
       round(g.usd_above_1m, 2)                                                  AS usd_above_1m,
       round(g.usd_without_rows_above_1m, 2)                                     AS usd_without_rows_above_1m,
       round(100.0 * g.usd_without_rows_above_1m / total.usd_without_rows_above_1m, 2) AS pct_usd_without_rows_above_1m,
       CASE WHEN g.is_string = 1 AND g.usd IS NOT NULL
            THEN dense_rank() OVER (PARTITION BY g.is_string ORDER BY g.usd DESC NULLS LAST) END AS rank_with_every_row,
       CASE WHEN g.is_string = 1 AND g.usd_without_rows_above_1m IS NOT NULL
            THEN dense_rank() OVER (PARTITION BY g.is_string ORDER BY g.usd_without_rows_above_1m DESC NULLS LAST) END AS rank_without_rows_above_1m
FROM together g
CROSS JOIN total
ORDER BY g.is_string, g.usd DESC NULLS LAST, g.n_rows DESC, g.integrator
