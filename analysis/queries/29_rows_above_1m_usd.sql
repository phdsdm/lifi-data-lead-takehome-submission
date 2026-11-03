-- 29_rows_above_1m_usd
-- Question: Which rows carry more than $1M each, so a human can read them before a weekly
--           number is sent?
-- Grain:    one row per transfer with amount_usd > 1,000,000 (22), largest first.
-- Definition applied:
--   - USD: amount_usd, the headline; every one of these rows is priced by prices.csv
--     (price_source = 'provided'), so the provided column gives the same rows and values.
--   - rows_with_same_amount: how many of the 22 rows carry the same symbol and token amount.
--     3 marks the three transfers of exactly 10,000,000 USDC; 2 marks the two legs of the
--     9,519,447.993443 USDC round trip (ethereum to 42161 on 2026-10-18, arbitrum to 1 on
--     2026-10-19, one sender) and, separately, two unrelated transfers of
--     exactly 1,000,000 USDC by different integrators and senders.
--   - Integrator: the raw string.
-- Inputs:   transfers_priced (provided data for these rows).

WITH big AS (
    SELECT * FROM transfers_priced WHERE amount_usd > 1000000
)
SELECT block_time,
       chain,
       destination_chain_id,
       bridge,
       integrator,
       symbol,
       amount_token,
       round(amount_usd, 2)                                                     AS usd,
       round(amount_usd_provided, 2)                                            AS usd_provided,
       price_source,
       count(*) OVER (PARTITION BY symbol, amount_token)                        AS rows_with_same_amount,
       round(100.0 * amount_usd / (SELECT sum(amount_usd) FROM transfers_priced), 2) AS pct_of_week_usd,
       tx_from,
       tx_hash
FROM big
ORDER BY amount_usd DESC, block_time
