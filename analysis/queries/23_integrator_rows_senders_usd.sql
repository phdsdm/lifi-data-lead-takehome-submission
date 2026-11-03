-- 23_integrator_rows_senders_usd
-- Question: For each raw integrator string, how many rows, senders and USD does it carry,
--           and what share of the week's rows and USD? The same for the groups of strings
--           the definition choices concern.
-- Grain:    one row per raw integrator string (598), after three group rows: every string,
--           the strings starting with '_', and the strings starting with 'jumper.' or 'lifi-'.
-- Definition applied (a candidate definition):
--   - Integrator: the raw string, no normalisation map; the empty string is a string.
--   - USD: amount_usd of transfers_priced, the headline (prices.csv for (chain, token,
--     hour of block_time), else the CoinGecko snapshot; decimals from prices.csv, else LI.FI's
--     token list); usd_provided is amount_usd_provided, prices.csv only. Rows neither feed
--     prices add nothing to a sum and are counted in rows_unpriced.
--   - Senders: distinct tx_from. Shares are of the whole file.
--   - median_row_usd: median headline USD over the string's priced rows.
-- Inputs:   transfers_priced. The headline column depends on reference data for its
--           CoinGecko-priced rows (rows_coingecko_priced); usd_provided is provided data only.
-- Rows and senders without USD: 09_integrator_rows_and_senders.

WITH t AS (
    SELECT *,
           starts_with(integrator, '_')                                            AS underscore,
           starts_with(integrator, 'jumper.') OR starts_with(integrator, 'lifi-')  AS jumper_or_lifi
    FROM transfers_priced
),
total AS (
    SELECT count(*) AS n, sum(amount_usd) AS usd, sum(amount_usd_provided) AS usd_provided FROM t
),
rows_by_label AS (
    SELECT '(every string)' AS label, 0 AS grp, integrator, tx_from, amount_usd, amount_usd_provided, price_source FROM t
    UNION ALL
    SELECT '(strings starting with _)', 1, integrator, tx_from, amount_usd, amount_usd_provided, price_source FROM t WHERE underscore
    UNION ALL
    SELECT '(strings starting with jumper. or lifi-)', 2, integrator, tx_from, amount_usd, amount_usd_provided, price_source FROM t WHERE jumper_or_lifi
    UNION ALL
    SELECT integrator, 3, integrator, tx_from, amount_usd, amount_usd_provided, price_source FROM t
)
SELECT g.label                                                                      AS integrator,
       count(DISTINCT g.integrator)                                                 AS strings,
       count(*)                                                                     AS n_rows,
       round(100.0 * count(*) / total.n, 2)                                         AS pct_rows,
       count(DISTINCT g.tx_from)                                                    AS senders,
       round(sum(g.amount_usd), 2)                                                  AS usd,
       round(100.0 * sum(g.amount_usd) / total.usd, 2)                              AS pct_usd,
       round(sum(g.amount_usd_provided), 2)                                         AS usd_provided,
       round(100.0 * sum(g.amount_usd_provided) / total.usd_provided, 2)            AS pct_usd_provided,
       round(median(g.amount_usd), 2)                                               AS median_row_usd,
       count(*) FILTER (WHERE g.price_source = 'coingecko')                         AS rows_coingecko_priced,
       count(*) FILTER (WHERE g.price_source IS NULL)                               AS rows_unpriced
FROM rows_by_label g
CROSS JOIN total
GROUP BY g.grp, g.label, total.n, total.usd, total.usd_provided
ORDER BY g.grp, usd DESC NULLS LAST, n_rows DESC, g.label
