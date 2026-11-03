-- 28_usd_concentration
-- Question: How concentrated is the week's USD in large rows, how many rows are dust, and
--           what is the distribution of a row's USD, under each price policy?
-- Grain:    one row per price policy (2): 'headline' (amount_usd) and 'provided'
--           (amount_usd_provided).
-- Definition applied:
--   - Headline: the headline column (prices.csv, else the CoinGecko snapshot); provided:
--     prices.csv only. Each row of the output applies its policy to every measure.
--   - Thresholds are strict: above $1M means > 1,000,000; below $1 means < 1.
--   - Shares of USD are of the policy's own total. Shares of rows are of all 124,858 rows,
--     unpriced rows included (an unpriced row is neither above nor below a threshold).
--   - exact_10m_usdc: rows whose token amount is exactly 10,000,000 and whose symbol is USDC.
--   - Percentiles are quantile_cont over the policy's priced rows.
-- Inputs:   transfers_priced (headline: reference data for its CoinGecko-priced rows).
-- The rows above $1M one by one: 29_rows_above_1m_usd.

WITH r AS (
    SELECT 'headline' AS policy, 1 AS ord, amount_usd AS usd, symbol, amount_token FROM transfers_priced
    UNION ALL
    SELECT 'provided', 2, amount_usd_provided, symbol, amount_token FROM transfers_priced
)
SELECT policy,
       count(*)                                                                        AS n_rows,
       count(usd)                                                                      AS rows_priced,
       round(sum(usd), 2)                                                              AS usd_total,
       count(*) FILTER (WHERE usd > 1000000)                                           AS rows_above_1m,
       round(sum(usd) FILTER (WHERE usd > 1000000), 2)                                 AS usd_above_1m,
       round(100.0 * sum(usd) FILTER (WHERE usd > 1000000) / sum(usd), 2)              AS pct_usd_above_1m,
       count(*) FILTER (WHERE usd > 100000)                                            AS rows_above_100k,
       round(sum(usd) FILTER (WHERE usd > 100000), 2)                                  AS usd_above_100k,
       round(100.0 * sum(usd) FILTER (WHERE usd > 100000) / sum(usd), 2)               AS pct_usd_above_100k,
       count(*) FILTER (WHERE symbol = 'USDC' AND amount_token = 10000000)             AS rows_exact_10m_usdc,
       round(100.0 * sum(usd) FILTER (WHERE symbol = 'USDC' AND amount_token = 10000000) / sum(usd), 2) AS pct_usd_exact_10m_usdc,
       count(*) FILTER (WHERE usd < 1)                                                 AS rows_below_1_usd,
       round(100.0 * count(*) FILTER (WHERE usd < 1) / count(*), 2)                    AS pct_rows_below_1_usd,
       count(*) FILTER (WHERE usd < 0.01)                                              AS rows_below_1_cent,
       round(median(usd), 2)                                                           AS median_row_usd,
       round(avg(usd), 2)                                                              AS mean_row_usd,
       round(quantile_cont(usd, 0.9), 2)                                               AS p90_row_usd,
       round(quantile_cont(usd, 0.99), 2)                                              AS p99_row_usd,
       round(quantile_cont(usd, 0.999), 2)                                             AS p999_row_usd,
       round(max(usd), 2)                                                              AS max_row_usd
FROM r
GROUP BY policy, ord
ORDER BY ord
