-- 160_token_class_review
-- Question: How much weighted volume does each token symbol carry under the token class table, and
--           which of the largest symbols would a reader judge misclassified?
-- Grain:    one row per symbol seen on either side of a frame row, largest first, plus one row per
--           class. judged_misclassified lists symbols judged misclassified, reported and not applied: the
--           table keeps its classes. Bridge volume counted once per pair; a pair counts for
--           both its symbols, so symbol rows do not add to the total.
-- Definitions applied (the same in every query of this family):
--   - Bridge volume: started rows in headline amount_usd, without the 295 same-chain
--     *Dex rows; the 4 unpriced rows carry no USD and fall out. Reference data: every fee, route
--     kind and token below comes from LI.FI /v1/status snapshots; amount_usd may be CoinGecko-filled.
--   - Paying LI.FI: fee_split_lifi_usd above 0 on the quote. Quote fee as fee charged. Weekly "completed" and annual: × completion 98.20% (query 44) and × 52; volume
--     held fixed. "Quoted" means before completion.
--   - Route kind: no source step = hasSourceSwaps false; fee step only = sending_included_tools
--     exactly 'feeCollection'; DEX step = anything else with the flag true. The fee step itself
--     sets hasSourceSwaps, so the flag does not mean "swap".
--   - Same token: sending and receiving symbols match after merging USDC with USDC.e, USDCe, USDbC,
--     axlUSDC; USDT with USD₮0, USDT0; ETH with WETH; BNB with WBNB; POL with WPOL, MATIC, WMATIC.
--     Bridge-only = same token, cross-chain, no DEX step. Cross-chain is read from the event's
--     destinationChainId, never from the receiving leg: a refund on the source chain stays
--     in bridge volume, and its receiving symbol is compared as recorded, so a refund in the token
--     sent counts as same token. A missing receiving symbol (2 refunded strata rows) is not same
--     token, and its pair class comes from the sending symbol alone.
--   - Token class: ref_token_class (data/reference/token_class.csv); a symbol not in it is alt. A
--     pair is alt if either side is alt, else major if either side is major, else stable.
--   - Estimator, one weight w per observed row, so a sum over rows of w × value is the
--     file-level figure. Source-step rows: at $10k and above, the census (in_census), w = 1, exact;
--     under $10k, the raw integrator string's in_strata rows under $10k, w = the string's under-$10k
--     volume in the file / the same rows' USD, the ratio estimate. No-source-step rows are zero (0 of
--     627, query 75; 0 of 309, query 150): at $100k and above the census (w = 1, exact); under
--     $100k the uniform 2,000's no-step rows, w = the file's no-step volume in the size band / the
--     sampled rows' USD in it, bands under $10k and $10k to $100k (621 rows, 29 in the upper band).
--     Rate mixtures stay as observed, row by row, in proportion to their USD among the sampled rows;
--     no rate is merged or modelled. moby's integrator fee is a fixed amount:
--     where the integrator fee is summed, its strata rows take rows in file / rows sampled. The 27
--     strata rows on bridge volume without a quote count as paying nothing (query 159 sizes it).
--   - Increase, not level: a size is the increase on today's LI.FI fee. A floor is max(floor × amount
--     - LI.FI fee, 0) row by row on the sampled rows, then weighted, so rates above the floor stay.
-- Inputs:   transfers_priced; ref_integrator_map; ref_token_class; ref_lifi_api_transfer_status_extension,
--           ref_lifi_api_transfer_status_bridge_census and ref_lifi_api_transfer_status_sample_2600 (reference
--           data: LI.FI /v1/status, fetched 2026-10-28 and 2026-11-01). Quoted fee, not fee collected.

WITH source_ids(chain, source_chain_id) AS (
    VALUES ('ethereum', 1), ('optimism', 10), ('bnb', 56), ('polygon', 137), ('base', 8453), ('arbitrum', 42161)
),
completion AS (
    SELECT avg(CASE WHEN substatus = 'COMPLETED' THEN 1.0 ELSE 0.0 END) AS c
    FROM ref_lifi_api_transfer_status_sample_2600
    WHERE sample_design = 'uniform_2000'
),
bridge_rows AS (
    SELECT t.chain, t.tx_hash, t.log_index, t.integrator, t.bridge, t.tx_from, t.symbol AS file_symbol,
           t.amount_usd AS x, t.has_source_swaps AS flag,
           CASE WHEN t.amount_usd < 10000 THEN 'under $10k'
                WHEN t.amount_usd < 100000 THEN '$10k to $100k'
                ELSE '$100k and above' END AS size_band
    FROM transfers_priced t
    JOIN source_ids s USING (chain)
    WHERE t.destination_chain_id <> s.source_chain_id AND t.amount_usd IS NOT NULL
),
status_rows AS (
    SELECT chain, tx_hash, log_index,
           CASE WHEN in_census THEN 'source_census' ELSE 'source_strata' END AS design,
           sending_included_tools, sending_token_symbol, receiving_token_symbol, substatus, quote_tool,
           sending_amountUSD, receiving_amountUSD, quote_toAmountUSD, quote_fee_usd,
           coalesce(quote_fee_lifi_usd, 0) > 0 AS has_line,
           coalesce(fee_split_lifi_usd, 0) AS lifi, coalesce(fee_split_integrator_usd, 0) AS integ
    FROM ref_lifi_api_transfer_status_extension
    UNION ALL
    SELECT chain, tx_hash, log_index, 'no_step_census', sending_included_tools, sending_token_symbol,
           receiving_token_symbol, substatus, quote_tool, sending_amountUSD, receiving_amountUSD, quote_toAmountUSD,
           quote_fee_usd, coalesce(quote_fee_lifi_usd, 0) > 0, coalesce(fee_split_lifi_usd, 0), coalesce(fee_split_integrator_usd, 0)
    FROM ref_lifi_api_transfer_status_bridge_census
    UNION ALL
    SELECT chain, tx_hash, log_index, 'no_step_uniform', sending_included_tools, sending_token_symbol,
           receiving_token_symbol, substatus, quote_tool, sending_amountUSD, receiving_amountUSD, quote_toAmountUSD,
           quote_fee_usd, coalesce(quote_fee_lifi_usd, 0) > 0, coalesce(fee_split_lifi_usd, 0), coalesce(fee_split_integrator_usd, 0)
    FROM ref_lifi_api_transfer_status_sample_2600
    WHERE sample_design = 'uniform_2000' AND NOT event_hasSourceSwaps
),
observed AS (
    SELECT b.*, s.* EXCLUDE (chain, tx_hash, log_index)
    FROM status_rows s
    JOIN bridge_rows b USING (chain, tx_hash, log_index)
    WHERE s.design <> 'no_step_uniform' OR b.x < 100000
),
strata_weight AS (
    SELECT f.integrator, f.v / o.xs AS w, f.n * 1.0 / o.n AS w_rows
    FROM (SELECT integrator, sum(x) AS v, count(*) AS n FROM bridge_rows WHERE flag AND x < 10000 GROUP BY integrator) f
    JOIN (SELECT integrator, sum(x) AS xs, count(*) AS n FROM observed WHERE design = 'source_strata' GROUP BY integrator) o USING (integrator)
),
uniform_weight AS (
    SELECT f.size_band, f.v / o.xs AS w
    FROM (SELECT size_band, sum(x) AS v FROM bridge_rows WHERE NOT flag AND x < 100000 GROUP BY size_band) f
    JOIN (SELECT size_band, sum(x) AS xs FROM observed WHERE design = 'no_step_uniform' GROUP BY size_band) o USING (size_band)
),
frame AS (
    SELECT o.*, m.partner, m.class AS integrator_class,
           CASE o.design WHEN 'source_strata' THEN sw.w WHEN 'no_step_uniform' THEN uw.w ELSE 1.0 END AS w,
           CASE o.design WHEN 'source_strata' THEN sw.w_rows WHEN 'no_step_uniform' THEN uw.w ELSE 1.0 END AS w_rows,
           CASE WHEN NOT o.flag THEN 'no_source_step'
                WHEN o.sending_included_tools = 'feeCollection' THEN 'fee_step_only'
                ELSE 'dex_step' END AS route_kind,
           CASE WHEN o.sending_token_symbol IN ('USDC', 'USDC.e', 'USDCe', 'USDbC', 'axlUSDC') THEN 'USDC'
                WHEN o.sending_token_symbol IN ('USDT', 'USD₮0', 'USDT0') THEN 'USDT'
                WHEN o.sending_token_symbol IN ('ETH', 'WETH') THEN 'ETH'
                WHEN o.sending_token_symbol IN ('BNB', 'WBNB') THEN 'BNB'
                WHEN o.sending_token_symbol IN ('POL', 'WPOL', 'MATIC', 'WMATIC') THEN 'POL'
                ELSE o.sending_token_symbol END AS sent_family,
           CASE WHEN o.receiving_token_symbol IN ('USDC', 'USDC.e', 'USDCe', 'USDbC', 'axlUSDC') THEN 'USDC'
                WHEN o.receiving_token_symbol IN ('USDT', 'USD₮0', 'USDT0') THEN 'USDT'
                WHEN o.receiving_token_symbol IN ('ETH', 'WETH') THEN 'ETH'
                WHEN o.receiving_token_symbol IN ('BNB', 'WBNB') THEN 'BNB'
                WHEN o.receiving_token_symbol IN ('POL', 'WPOL', 'MATIC', 'WMATIC') THEN 'POL'
                ELSE o.receiving_token_symbol END AS received_family,
           coalesce(ts.class, 'alt') AS sent_class,
           CASE WHEN o.receiving_token_symbol IS NULL THEN coalesce(ts.class, 'alt') ELSE coalesce(tr.class, 'alt') END AS received_class
    FROM observed o
    LEFT JOIN strata_weight sw ON sw.integrator = o.integrator
    LEFT JOIN uniform_weight uw ON uw.size_band = o.size_band
    LEFT JOIN ref_integrator_map m ON coalesce(m.integrator, '') = o.integrator
    LEFT JOIN ref_token_class ts ON ts.symbol = o.sending_token_symbol
    LEFT JOIN ref_token_class tr ON tr.symbol = o.receiving_token_symbol
),
weighted AS (
    SELECT *,
           sent_family IS NOT DISTINCT FROM received_family AS same_token,
           CASE WHEN route_kind = 'dex_step' THEN 'dex_step'
                WHEN sent_family IS NOT DISTINCT FROM received_family THEN 'bridge_only'
                ELSE 'token_change' END AS segment,
           CASE WHEN sent_class = 'alt' OR received_class = 'alt' THEN 'alt'
                WHEN sent_class = 'major' OR received_class = 'major' THEN 'major'
                ELSE 'stable' END AS pair_class,
           lifi > 0 AS paying
    FROM frame
),
sides AS (
    SELECT sending_token_symbol AS symbol, x, w, pair_class, flag FROM weighted
    UNION ALL
    SELECT receiving_token_symbol, x, w, pair_class, flag FROM weighted WHERE receiving_token_symbol IS DISTINCT FROM sending_token_symbol
),
judged(symbol, note) AS (
    VALUES ('PYUSD0', 'stable by intent: PYUSD on another chain; also splits same-token from PYUSD'),
           ('EURC', 'fiat stablecoin in euro; alt here because the list is USD and majors'),
           ('EURe', 'fiat stablecoin in euro'),
           ('XAUt', 'gold-backed token, not an altcoin in volatility'),
           ('PAXG', 'gold-backed token, not an altcoin in volatility'),
           ('USDt', 'USDT under another casing; alt here and outside the USDT merge'),
           ('BTCB', 'BTC on BNB Chain; major by intent'),
           ('cirBTC', 'wrapped BTC; major by intent'),
           ('HBTC', 'wrapped BTC; major by intent'),
           ('UBTC', 'wrapped BTC; major by intent'),
           ('UETH', 'wrapped ETH; major by intent'),
           ('WAVAX', 'AVAX is major, its wrapped form is not in the list'),
           ('JPYC', 'fiat stablecoin in yen'),
           ('BRZ', 'fiat stablecoin in Brazilian real'),
           ('mUSD', 'USD stablecoin not in the list'),
           ('USD3', 'USD stablecoin not in the list'),
           ('sUSDe', 'staked USDe; sUSDai is listed stable, this is not')
),
per AS (
    SELECT symbol, sum(w * x) AS weighted_usd, sum(w * x) FILTER (WHERE pair_class = 'alt') AS alt_pair_usd,
           sum(w * x) FILTER (WHERE flag) AS source_step_usd, count(*) AS observed_rows
    FROM sides WHERE symbol IS NOT NULL GROUP BY symbol
),
class_totals AS (SELECT pair_class, sum(w * x) AS weighted_usd, sum(w * x) FILTER (WHERE flag) AS source_step_usd, count(*) AS observed_rows FROM weighted GROUP BY pair_class)
SELECT 'symbol' AS level, p.symbol AS name, coalesce(t.class, 'alt') AS class,
       round(p.weighted_usd, 2) AS weighted_usd, round(p.source_step_usd, 2) AS source_step_usd, round(p.alt_pair_usd, 2) AS alt_pair_usd,
       p.observed_rows, j.note AS judged_misclassified
FROM per p LEFT JOIN ref_token_class t USING (symbol) LEFT JOIN judged j USING (symbol)
UNION ALL
SELECT 'pair class', pair_class, pair_class, round(weighted_usd, 2), round(source_step_usd, 2), NULL, observed_rows, NULL FROM class_totals
ORDER BY level, weighted_usd DESC
