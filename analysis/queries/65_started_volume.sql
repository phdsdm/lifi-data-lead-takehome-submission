-- 65_started_volume
-- Question: What is the week's started volume under the started-volume definition: the total, the bridge volume without
--           the same-chain *Dex rows, and those rows on their own? How much of each is priced
--           by CoinGecko, and how much of it does each class of the integrator map carry?
-- Grain:    one row per line (5). Lines 1 to 3 are the metric; lines 4 and 5 are the two cases
--           the definition keeps inside started volume.
-- Definition applied:
--   - Started volume: the USD value handed to bridges on the source chain, one
--     LiFiTransferStarted row = one started transfer, every row of the file. Completed
--     volume needs the status source and is not computed here.
--   - USD: amount_usd of transfers_priced, the headline: prices.csv for (chain, token,
--     hour of block_time), else the CoinGecko snapshot; decimals from prices.csv, else LI.FI's
--     token list. Rows neither feed prices count in rows and add nothing to usd.
--   - Same-chain rows: destination_chain_id equals the source chain's id (ethereum 1,
--     optimism 10, bnb 56, polygon 137, base 8453, arbitrum 42161). They are the 295 rows of
--     the three *Dex tools; no other tool has one. Out of bridge volume, reported separately, in total volume.
--   - Repeated transactionId pairs: both rows of each of the 6 pairs stay in.
--   - The round trip: both legs of the 9,519,447.993443 USDC `_arbitrum` round trip stay in.
--     29_rows_above_1m_usd lists them among the rows above $1M.
--   - rows_coingecko / usd_coingecko: rows whose headline price is CoinGecko's
--     (price_source = 'coingecko'); pct_rows_coingecko and pct_usd_coingecko are shares of the
--     line. usd_provided_feed_only: the same rows at prices.csv only, to show the dependency on CoinGecko.
--   - usd_<class>: the line's USD by class of ref_integrator_map: LI.FI's own products
--     stay inside the metric, flagged; test_or_dev stays in total volume. The
--     map's empty-string row loads as NULL, so the join is on coalesce(m.integrator, '');
--     rows_not_in_map counts rows the map misses (0 when the map is complete).
-- Inputs:   transfers_priced, ref_integrator_map. usd depends on reference data for its
--           CoinGecko-priced rows.

WITH source_ids(chain, chain_id) AS (
    VALUES ('ethereum', 1), ('optimism', 10), ('bnb', 56), ('polygon', 137), ('base', 8453), ('arbitrum', 42161)
),
round_trip AS (
    SELECT chain, tx_hash, log_index
    FROM transfers
    WHERE integrator = '_arbitrum' AND min_amount = 9519447993443
),
repeated AS (
    SELECT transaction_id FROM transfers GROUP BY transaction_id HAVING count(*) > 1
),
t AS (
    SELECT p.amount_usd,
           p.amount_usd_provided,
           p.price_source,
           p.destination_chain_id = s.chain_id                         AS same_chain,
           p.transaction_id IN (SELECT transaction_id FROM repeated)   AS repeated_id,
           rt.tx_hash IS NOT NULL                                      AS round_trip_leg,
           m.class
    FROM transfers_priced p
    JOIN source_ids s USING (chain)
    LEFT JOIN round_trip rt USING (chain, tx_hash, log_index)
    LEFT JOIN ref_integrator_map m ON coalesce(m.integrator, '') = p.integrator
),
lines AS (
    SELECT 1 AS line_order, 'started volume: every row' AS line, * FROM t
    UNION ALL
    SELECT 2, 'bridge volume: without the same-chain *Dex rows', * FROM t WHERE NOT same_chain
    UNION ALL
    SELECT 3, 'same-chain *Dex rows, reported separately', * FROM t WHERE same_chain
    UNION ALL
    SELECT 4, 'in started volume, noted: repeated transactionId pairs, both rows', * FROM t WHERE repeated_id
    UNION ALL
    SELECT 5, 'in started volume, noted: the round trip, both legs', * FROM t WHERE round_trip_leg
),
started AS (SELECT sum(amount_usd) AS usd FROM t)
SELECT l.line,
       count(*)                                                                       AS n_rows,
       count(l.amount_usd)                                                            AS rows_priced,
       count(*) - count(l.amount_usd)                                                 AS rows_unpriced,
       round(sum(l.amount_usd), 2)                                                    AS usd,
       round(100.0 * sum(l.amount_usd) / started.usd, 4)                              AS pct_of_started_usd,
       count(*) FILTER (WHERE l.price_source = 'coingecko')                           AS rows_coingecko,
       round(coalesce(sum(l.amount_usd) FILTER (WHERE l.price_source = 'coingecko'), 0), 2) AS usd_coingecko,
       round(100.0 * count(*) FILTER (WHERE l.price_source = 'coingecko') / count(*), 4)    AS pct_rows_coingecko,
       round(100.0 * coalesce(sum(l.amount_usd) FILTER (WHERE l.price_source = 'coingecko'), 0) / sum(l.amount_usd), 4) AS pct_usd_coingecko,
       round(sum(l.amount_usd_provided), 2)                                           AS usd_provided_feed_only,
       round(coalesce(sum(l.amount_usd) FILTER (WHERE l.class = 'partner'), 0), 2)          AS usd_partner,
       round(coalesce(sum(l.amount_usd) FILTER (WHERE l.class = 'lifi_product'), 0), 2)     AS usd_lifi_product,
       round(coalesce(sum(l.amount_usd) FILTER (WHERE l.class = 'unattributed_api'), 0), 2) AS usd_unattributed_api,
       round(coalesce(sum(l.amount_usd) FILTER (WHERE l.class = 'test_or_dev'), 0), 2)      AS usd_test_or_dev,
       count(*) FILTER (WHERE l.class IS NULL)                                        AS rows_not_in_map
FROM lines l
CROSS JOIN started
GROUP BY l.line_order, l.line, started.usd
ORDER BY l.line_order
