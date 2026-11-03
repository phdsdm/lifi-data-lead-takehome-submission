-- 36_price_feed_total_provided_vs_coingecko
-- Question: Over the rows both feeds price, how much does the week's total move if every row
--           takes CoinGecko's price instead of the provided one, and which token pairs move it?
-- Grain:    one row per (chain, sending_asset_id) priced by both feeds, after a total row;
--           largest absolute difference first.
-- Definition applied:
--   - Rows priced by both: price_usd_provided and price_usd_coingecko both present for the
--     row's (chain, token, hour of block_time).
--   - usd_provided_price = amount_token × price_usd_provided; usd_coingecko_price =
--     amount_token × price_usd_coingecko; the difference is CoinGecko minus provided.
--   - This is a sensitivity of the total to the feed, not a price policy: neither column is
--     the headline (the headline uses the provided price on all these rows).
-- Inputs:   transfers_priced (reference data: the CoinGecko snapshot).

WITH both_priced AS (
    SELECT chain, sending_asset_id, symbol,
           amount_token * price_usd_provided   AS usd_provided_price,
           amount_token * price_usd_coingecko  AS usd_coingecko_price
    FROM transfers_priced
    WHERE price_usd_provided IS NOT NULL AND price_usd_coingecko IS NOT NULL
),
per_pair AS (
    SELECT chain, sending_asset_id, any_value(symbol) AS symbol, 1 AS is_pair,
           count(*) AS n_rows, sum(usd_provided_price) AS usd_provided_price, sum(usd_coingecko_price) AS usd_coingecko_price
    FROM both_priced
    GROUP BY chain, sending_asset_id
),
total AS (
    SELECT '(all)' AS chain, '(all)' AS sending_asset_id, '(all)' AS symbol, 0 AS is_pair,
           count(*) AS n_rows, sum(usd_provided_price) AS usd_provided_price, sum(usd_coingecko_price) AS usd_coingecko_price
    FROM both_priced
)
SELECT chain,
       sending_asset_id,
       symbol,
       n_rows,
       round(usd_provided_price, 2)                                         AS usd_provided_price,
       round(usd_coingecko_price, 2)                                        AS usd_coingecko_price,
       round(usd_coingecko_price - usd_provided_price, 2)                   AS usd_difference,
       round(100.0 * (usd_coingecko_price / usd_provided_price - 1), 4)     AS pct_difference
FROM (SELECT * FROM total UNION ALL SELECT * FROM per_pair)
ORDER BY is_pair, abs(usd_coingecko_price - usd_provided_price) DESC, chain, sending_asset_id
