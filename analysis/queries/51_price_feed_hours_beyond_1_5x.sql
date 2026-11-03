-- 51_price_feed_hours_beyond_1_5x
-- Question: In which token-hours does the provided price stand at least 1.5 times above or
--           below CoinGecko's, for the tokens where this happens in some hours but not all?
-- Grain:    one row per token-hour beyond the 1.5x band (32: GEAR ethereum 23, kBTC optimism
--           8, PUFFER bnb 1), in time order per token.
-- Definition applied:
--   - ratio = provided price / CoinGecko price for the same (chain, token_address, hour);
--     beyond the band: ratio >= 1.5 or ratio <= 1/1.5.
--   - Episodic tokens only: pairs with at least one compared hour inside the band. Pairs
--     beyond it in every compared hour (SWEAT ethereum and ISLAND base, 168 of 168) are a
--     constant offset.
--   - ratio_2dp: the ratio rounded to two decimals. at_or_above_2_55: ratio >= 2.55 exactly;
--     at_or_above_2_55_rounded: ratio_2dp >= 2.55. The two give different counts.
--   - run_start: the first hour of the run of consecutive beyond-band hours the row is in.
-- Inputs:   prices, ref_coingecko_hourly_prices_2026_10_13_to_2026_10_19 (reference data).

WITH cg AS (
    SELECT chain, token_address, strptime(hour, '%Y-%m-%d %H:%M:%S+00:00') AS hour, price_usd
    FROM ref_coingecko_hourly_prices_2026_10_13_to_2026_10_19
),
cmp AS (
    SELECT p.chain, p.token_address, p.symbol, p.hour,
           p.price_usd                  AS price_provided,
           c.price_usd                  AS price_coingecko,
           p.price_usd / c.price_usd    AS ratio
    FROM prices p
    JOIN cg c USING (chain, token_address, hour)
),
flagged AS (
    SELECT *, ratio >= 1.5 OR ratio <= 1 / 1.5 AS beyond
    FROM cmp
),
episodic AS (
    SELECT chain, token_address
    FROM flagged
    GROUP BY chain, token_address
    HAVING count(*) FILTER (WHERE beyond) > 0 AND count(*) FILTER (WHERE NOT beyond) > 0
),
beyond_hours AS (
    SELECT f.*,
           f.hour - INTERVAL 1 HOUR * row_number() OVER (PARTITION BY f.chain, f.token_address ORDER BY f.hour) AS run_key
    FROM flagged f
    JOIN episodic USING (chain, token_address)
    WHERE f.beyond
)
SELECT chain,
       symbol,
       hour,
       round(price_provided, 8)                                                  AS price_provided,
       round(price_coingecko, 8)                                                 AS price_coingecko,
       round(ratio, 4)                                                           AS ratio,
       round(ratio, 2)                                                           AS ratio_2dp,
       ratio >= 2.55                                                             AS at_or_above_2_55,
       round(ratio, 2) >= 2.55                                                   AS at_or_above_2_55_rounded,
       min(hour) OVER (PARTITION BY chain, token_address, run_key)               AS run_start,
       count(*) OVER (PARTITION BY chain, token_address)                         AS hours_beyond_band_for_token,
       count(*) FILTER (WHERE ratio >= 2.55) OVER (PARTITION BY chain, token_address) AS hours_at_or_above_2_55,
       count(*) FILTER (WHERE round(ratio, 2) >= 2.55) OVER (PARTITION BY chain, token_address) AS hours_at_or_above_2_55_rounded,
       token_address
FROM beyond_hours
ORDER BY chain, symbol, hour
