-- 33_rows_not_priced_by_provided_feed
-- Question: Which (chain, token) pairs have rows that prices.csv does not price, why, and
--           what does the CoinGecko fill do for each?
-- Grain:    one row per (chain, sending_asset_id) with at least one row lacking a
--           prices.csv price for its hour (12), largest headline USD first.
-- Definition applied:
--   - reason: 'pair not in prices.csv' when the pair has no row in prices.csv at all;
--     'hour missing in prices.csv' when the pair is in prices.csv but not for the row's hour.
--   - symbol and decimals as the view carries them (prices.csv, else LI.FI's token list);
--     decimals_source says which.
--   - rows_coingecko_priced / rows_unpriced: the same rows under the headline column; usd is
--     their headline USD (the CoinGecko fill).
-- Inputs:   transfers_priced, prices (reference data: the CoinGecko snapshot and LI.FI's
--           token list).

WITH provided_pairs AS (
    SELECT DISTINCT chain, token_address FROM prices
)
SELECT t.chain,
       t.sending_asset_id,
       any_value(t.symbol)                                                 AS symbol,
       any_value(t.decimals)                                               AS decimals,
       any_value(t.decimals_source)                                        AS decimals_source,
       CASE WHEN p.token_address IS NULL THEN 'pair not in prices.csv'
            ELSE 'hour missing in prices.csv' END                          AS reason,
       count(*)                                                            AS n_rows,
       count(*) FILTER (WHERE t.price_source = 'coingecko')                AS rows_coingecko_priced,
       count(*) FILTER (WHERE t.price_source IS NULL)                      AS rows_unpriced,
       round(sum(t.amount_token), 6)                                       AS amount_token,
       round(sum(t.amount_usd), 2)                                         AS usd,
       round(min(t.price_usd_coingecko), 6)                                AS min_coingecko_price,
       round(max(t.price_usd_coingecko), 6)                                AS max_coingecko_price,
       count(DISTINCT t.hour)                                              AS distinct_hours
FROM transfers_priced t
LEFT JOIN provided_pairs p ON p.chain = t.chain AND p.token_address = t.sending_asset_id
WHERE t.price_usd_provided IS NULL
GROUP BY t.chain, t.sending_asset_id, p.token_address
ORDER BY usd DESC NULLS LAST, n_rows DESC, t.chain, t.sending_asset_id
