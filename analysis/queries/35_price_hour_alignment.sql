-- 35_price_hour_alignment
-- Question: How much does the total move if each row is priced at the previous or the next
--           hour instead of the hour of its block_time?
-- Grain:    one row per (price policy, hour offset): offsets -1, 0 and +1 hour under the
--           headline policy and under the provided feed alone (6 rows).
-- Definition applied:
--   - Offset 0 is the view's join: the hourly price whose `hour` equals block_time floored
--     to the hour (UTC; `hour` is the start of the hour in both feeds). Offset +1 takes the
--     price of the following hour, -1 of the preceding hour, same (chain, token).
--   - headline: prices.csv at that hour, else the CoinGecko snapshot at that hour;
--     provided: prices.csv only. decimals and amount_token as in transfers_priced.
--   - Rows in the first hour have no price at -1 and rows in the last hour none at +1
--     (both feeds stop at the window), so the comparison that isolates the price is over
--     common_rows: rows priced at all three offsets under that policy.
--   - pct_vs_offset_0 compares usd_on_common_rows with offset 0 under the same policy.
-- Inputs:   transfers_priced, prices, ref_coingecko_hourly_prices_2026_10_13_to_2026_10_19
--           (reference data for the headline rows).

WITH cg AS (
    SELECT chain, token_address, strptime(hour, '%Y-%m-%d %H:%M:%S+00:00') AS hour, price_usd
    FROM ref_coingecko_hourly_prices_2026_10_13_to_2026_10_19
),
offsets(k) AS (VALUES (-1), (0), (1)),
priced AS (
    SELECT t.chain, t.tx_hash, t.log_index, o.k,
           t.amount_token * p.price_usd                         AS usd_provided,
           t.amount_token * coalesce(p.price_usd, c.price_usd)  AS usd_headline
    FROM transfers_priced t
    CROSS JOIN offsets o
    LEFT JOIN prices p
           ON p.chain = t.chain AND p.token_address = t.sending_asset_id
          AND p.hour = t.hour + o.k * INTERVAL 1 HOUR
    LEFT JOIN cg c
           ON c.chain = t.chain AND c.token_address = t.sending_asset_id
          AND c.hour = t.hour + o.k * INTERVAL 1 HOUR
),
long AS (
    SELECT 'headline' AS policy, chain, tx_hash, log_index, k, usd_headline AS usd FROM priced
    UNION ALL
    SELECT 'provided', chain, tx_hash, log_index, k, usd_provided FROM priced
),
common AS (
    SELECT policy, chain, tx_hash, log_index
    FROM long
    GROUP BY policy, chain, tx_hash, log_index
    HAVING count(usd) = 3
),
per_offset AS (
    SELECT l.policy, l.k,
           count(l.usd)                                        AS rows_priced,
           sum(l.usd)                                          AS usd_total,
           count(c.tx_hash)                                    AS common_rows,
           sum(l.usd) FILTER (WHERE c.tx_hash IS NOT NULL)     AS usd_on_common_rows
    FROM long l
    LEFT JOIN common c USING (policy, chain, tx_hash, log_index)
    GROUP BY l.policy, l.k
)
SELECT p.policy,
       p.k                                                                 AS hour_offset,
       p.rows_priced,
       round(p.usd_total, 2)                                               AS usd_total,
       p.common_rows,
       round(p.usd_on_common_rows, 2)                                      AS usd_on_common_rows,
       round(p.usd_on_common_rows - z.usd_on_common_rows, 2)               AS usd_minus_offset_0,
       round(100.0 * (p.usd_on_common_rows / z.usd_on_common_rows - 1), 4) AS pct_vs_offset_0
FROM per_offset p
JOIN per_offset z ON z.policy = p.policy AND z.k = 0
ORDER BY p.policy, p.k
