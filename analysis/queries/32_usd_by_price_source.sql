-- 32_usd_by_price_source
-- Question: How many rows and how much USD does each price source and each decimals source
--           carry in the headline column, and what share of rows is unpriced under each
--           price policy?
-- Grain:    one row per (price_source, decimals_source) present (3), after a total row.
-- Definition applied:
--   - price_source: 'provided' when prices.csv prices the row's (chain, token, hour),
--     'coingecko' when only the CoinGecko snapshot does, '(none)' when neither does.
--   - decimals_source: 'provided' from prices.csv for the (chain, token) pair, 'lifi' from
--     LI.FI's token list for the source chain's id.
--   - usd: amount_usd, the headline; usd_provided: amount_usd_provided.
--   - pct_rows_unpriced_*: rows with NULL USD over all 124,858 rows, per policy (total row).
-- Inputs:   transfers_priced (reference data: the CoinGecko snapshot and LI.FI's token list).
-- The rows the provided feed does not price, pair by pair: 33_rows_not_priced_by_provided_feed.

WITH per_source AS (
    SELECT coalesce(price_source, '(none)')       AS price_source,
           coalesce(decimals_source, '(none)')    AS decimals_source,
           0                                      AS is_total,
           count(*)                               AS n_rows,
           count(DISTINCT (chain, sending_asset_id)) AS token_pairs,
           sum(amount_usd)                        AS usd,
           sum(amount_usd_provided)               AS usd_provided,
           count(*) FILTER (WHERE amount_usd IS NULL)          AS rows_unpriced_headline,
           count(*) FILTER (WHERE amount_usd_provided IS NULL) AS rows_unpriced_provided
    FROM transfers_priced
    GROUP BY 1, 2
),
total AS (
    SELECT '(all)', '(all)', 1, sum(n_rows), NULL, sum(usd), sum(usd_provided),
           sum(rows_unpriced_headline), sum(rows_unpriced_provided)
    FROM per_source
)
SELECT price_source,
       decimals_source,
       n_rows,
       round(100.0 * n_rows / (SELECT count(*) FROM transfers_priced), 3)                 AS pct_rows,
       token_pairs,
       round(usd, 2)                                                                       AS usd,
       round(usd_provided, 2)                                                              AS usd_provided,
       rows_unpriced_headline,
       round(100.0 * rows_unpriced_headline / (SELECT count(*) FROM transfers_priced), 3) AS pct_rows_unpriced_headline,
       rows_unpriced_provided,
       round(100.0 * rows_unpriced_provided / (SELECT count(*) FROM transfers_priced), 3) AS pct_rows_unpriced_provided
FROM (SELECT * FROM per_source UNION ALL SELECT * FROM total)
ORDER BY is_total DESC, n_rows DESC
