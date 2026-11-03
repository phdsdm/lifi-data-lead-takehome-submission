-- 105_price_feed_integrity
-- Question: Is prices.csv a sound hourly feed: one row per (chain, token_address, hour), no
--           duplicate keys, no missing or non-positive prices, hours on the hour and inside the
--           export window, one symbol and one decimals per token; and what are its extremes and
--           its coverage of the transfers file?
-- Grain:    one row per check (15): what is checked, the count it finds (count), what the count
--           is out of (out_of), the value where the check is a price (value), and a detail.
-- Definition applied (data/README_data_final.md; notebook 02):
--   - Key: (chain, token_address, hour), the key the headline price join uses.
--     duplicate keys = keys with more than one row; a feed with none has rows = distinct keys.
--   - Window: 2026-10-13 00:00 to 2026-10-19 23:00 UTC, 168 hourly prices per token when
--     complete. An hour is "on the hour" when
--     its minute, second and fraction are zero.
--   - Token: a distinct (chain, token_address) pair. A pair with more than one symbol or more
--     than one decimals over its rows would break the per-token decimals of the view.
--   - value: price_usd for the minimum and maximum rows; detail names the chain, symbol, token
--     and hour of that row (the first by hour if several tie).
--   - Coverage (lines 14, 15): tokens short of 168 hours; distinct (chain, sending_asset_id)
--     pairs of the transfers file without any row in prices.csv. 33_rows_not_priced_by_provided_feed
--     lists 12 pairs with unpriced rows: these 11 plus strUSD on ethereum, which is in the feed
--     but short of hours (line 14).
-- Inputs:   prices, transfers (provided data only).

WITH keys AS (
    SELECT chain, token_address, hour, count(*) AS n FROM prices GROUP BY chain, token_address, hour
),
tokens AS (
    SELECT chain, token_address,
           count(*) AS hours_present,
           count(DISTINCT symbol) AS symbols,
           count(DISTINCT decimals) AS decimals_values
    FROM prices GROUP BY chain, token_address
),
extremes AS (
    SELECT min(price_usd) AS min_price, max(price_usd) AS max_price FROM prices
),
min_row AS (
    SELECT p.* FROM prices p, extremes e WHERE p.price_usd = e.min_price ORDER BY p.hour, p.chain, p.token_address LIMIT 1
),
max_row AS (
    SELECT p.* FROM prices p, extremes e WHERE p.price_usd = e.max_price ORDER BY p.hour, p.chain, p.token_address LIMIT 1
),
transfer_pairs AS (
    SELECT DISTINCT chain, sending_asset_id AS token_address FROM transfers
)
SELECT * FROM (
    SELECT 1 AS ord, 'rows' AS check,
           (SELECT count(*) FROM prices) AS count, (SELECT count(*) FROM prices) AS out_of,
           NULL::DOUBLE AS value, NULL::VARCHAR AS detail
    UNION ALL
    SELECT 2, 'distinct (chain, token_address, hour) keys',
           (SELECT count(*) FROM keys), (SELECT count(*) FROM prices), NULL, NULL
    UNION ALL
    SELECT 3, 'duplicate keys (keys with more than one row)',
           (SELECT count(*) FROM keys WHERE n > 1), (SELECT count(*) FROM keys), NULL, NULL
    UNION ALL
    SELECT 4, 'rows with a NULL price_usd',
           (SELECT count(*) FROM prices WHERE price_usd IS NULL), (SELECT count(*) FROM prices), NULL, NULL
    UNION ALL
    SELECT 5, 'rows with price_usd <= 0',
           (SELECT count(*) FROM prices WHERE price_usd <= 0), (SELECT count(*) FROM prices), NULL, NULL
    UNION ALL
    SELECT 6, 'minimum price_usd', NULL, NULL, (SELECT min_price FROM extremes),
           (SELECT chain || ' ' || symbol || ' ' || token_address || ' at ' || CAST(hour AS VARCHAR) FROM min_row)
    UNION ALL
    SELECT 7, 'maximum price_usd', NULL, NULL, (SELECT max_price FROM extremes),
           (SELECT chain || ' ' || symbol || ' ' || token_address || ' at ' || CAST(hour AS VARCHAR) FROM max_row)
    UNION ALL
    SELECT 8, 'tokens: distinct (chain, token_address) pairs',
           (SELECT count(*) FROM tokens), (SELECT count(*) FROM tokens), NULL, NULL
    UNION ALL
    SELECT 9, 'chains',
           (SELECT count(DISTINCT chain) FROM prices), (SELECT count(DISTINCT chain) FROM transfers), NULL,
           (SELECT string_agg(chain, ', ' ORDER BY chain) FROM (SELECT DISTINCT chain FROM prices))
    UNION ALL
    SELECT 10, 'distinct symbols',
           (SELECT count(DISTINCT symbol) FROM prices), (SELECT count(*) FROM tokens), NULL, NULL
    UNION ALL
    SELECT 11, 'tokens with more than one symbol or more than one decimals',
           (SELECT count(*) FROM tokens WHERE symbols > 1 OR decimals_values > 1), (SELECT count(*) FROM tokens), NULL, NULL
    UNION ALL
    SELECT 12, 'rows with hour outside 2026-10-13 00:00 to 2026-10-19 23:00 UTC',
           (SELECT count(*) FROM prices WHERE hour < TIMESTAMP '2026-10-13 00:00:00' OR hour > TIMESTAMP '2026-10-19 23:00:00'),
           (SELECT count(*) FROM prices), NULL,
           (SELECT 'first ' || CAST(min(hour) AS VARCHAR) || ', last ' || CAST(max(hour) AS VARCHAR) FROM prices)
    UNION ALL
    SELECT 13, 'rows with hour not on the hour',
           (SELECT count(*) FROM prices WHERE hour <> date_trunc('hour', hour)), (SELECT count(*) FROM prices), NULL, NULL
    UNION ALL
    SELECT 14, 'tokens with fewer than 168 hours',
           (SELECT count(*) FROM tokens WHERE hours_present < 168), (SELECT count(*) FROM tokens), NULL,
           (SELECT string_agg(chain || ' ' || token_address || ' (' || CAST(hours_present AS VARCHAR) || ' h)', ', ' ORDER BY hours_present, chain)
              FROM tokens WHERE hours_present < 168)
    UNION ALL
    SELECT 15, 'transfer (chain, sending_asset_id) pairs with no row in prices.csv (11 of the 12 pairs of 33_rows_not_priced_by_provided_feed)',
           (SELECT count(*) FROM transfer_pairs tp WHERE NOT EXISTS (SELECT 1 FROM tokens k WHERE k.chain = tp.chain AND k.token_address = tp.token_address)),
           (SELECT count(*) FROM transfer_pairs), NULL, NULL
)
ORDER BY ord
