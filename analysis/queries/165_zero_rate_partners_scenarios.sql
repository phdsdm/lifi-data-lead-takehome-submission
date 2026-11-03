-- 165_zero_rate_partners_scenarios
-- Question: What do rabbykmsv2, bitget, Zerion and kyberswap, whose fee line pays only the integrator, add
--           to LI.FI at 25 bps on all volume, free on stablecoin pairs, or on altcoin pairs only?
-- Grain:    one row per (scenario, integrator, basis); integrator '(all four)' sums the four.
--   - 'all volume': file bridge volume, exact; no sample is involved beyond their LI.FI part being 0.
--     Zerion's $10,888.55 and kyberswap's and rabbykmsv2's cents without a source step are in it.
--   - 'not stablecoin pairs' and 'altcoin pairs only': source-step volume by pair class. Census rows
--     ($10k and above) are exact in every basis. Under $10k the class mix has three readings:
--     basis 'schedule' is the estimator (the string's in_strata rows, 30 each, one row carrying
--     w up to 420 for rabbykmsv2); 'uniform 2,000' takes the same string's uniform rows under
--     $10k (rabbykmsv2 140); 'pooled' takes both, one row per event. The 'schedule' row is the
--     definition; the other two show how far a mix on 30 rows can move it.
--   - sampled_rows_under_10k: rows behind the mix.
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
four(integrator) AS (VALUES ('rabbykmsv2'), ('bitget'), ('Zerion'), ('kyberswap')),
uni AS (
    SELECT b.chain, b.tx_hash, b.log_index, b.integrator, b.x, coalesce(st.fee_split_lifi_usd, 0) AS lifi,
           CASE WHEN coalesce(ts.class, 'alt') = 'alt' OR (st.receiving_token_symbol IS NOT NULL AND coalesce(tr.class, 'alt') = 'alt') THEN 'alt'
                WHEN coalesce(ts.class, 'alt') = 'major' OR (st.receiving_token_symbol IS NOT NULL AND coalesce(tr.class, 'alt') = 'major') THEN 'major'
                ELSE 'stable' END AS pair_class
    FROM ref_lifi_api_transfer_status_sample_2600 st
    JOIN bridge_rows b USING (chain, tx_hash, log_index)
    JOIN four USING (integrator)
    LEFT JOIN ref_token_class ts ON ts.symbol = st.sending_token_symbol
    LEFT JOIN ref_token_class tr ON tr.symbol = st.receiving_token_symbol
    WHERE st.sample_design = 'uniform_2000' AND b.flag AND b.x < 10000
),
sch AS (
    SELECT chain, tx_hash, log_index, integrator, x, lifi, pair_class, design
    FROM weighted JOIN four USING (integrator) WHERE flag
),
under_rows AS (
    SELECT 'schedule' AS basis, integrator, chain, tx_hash, log_index, x, lifi, pair_class FROM sch WHERE design = 'source_strata'
    UNION ALL SELECT 'uniform 2,000', integrator, chain, tx_hash, log_index, x, lifi, pair_class FROM uni
    UNION ALL SELECT 'pooled', integrator, chain, tx_hash, log_index, x, lifi, pair_class FROM sch WHERE design = 'source_strata'
    UNION ALL SELECT 'pooled', u.integrator, u.chain, u.tx_hash, u.log_index, u.x, u.lifi, u.pair_class FROM uni u
              WHERE NOT EXISTS (SELECT 1 FROM sch s WHERE s.design = 'source_strata' AND s.chain = u.chain AND s.tx_hash = u.tx_hash AND s.log_index = u.log_index)
),
under_v AS (SELECT integrator, sum(x) AS v FROM bridge_rows JOIN four USING (integrator) WHERE flag AND x < 10000 GROUP BY integrator),
under_w AS (
    SELECT r.basis, r.integrator, any_value(v.v) / sum(r.x) AS w, count(*) AS n FROM under_rows r JOIN under_v v USING (integrator) GROUP BY r.basis, r.integrator
),
bases(basis) AS (VALUES ('schedule'), ('uniform 2,000'), ('pooled')),
row_w AS (
    SELECT b.basis, s.integrator, s.pair_class, s.x, s.lifi, 1.0 AS w FROM sch s CROSS JOIN bases b WHERE s.design = 'source_census'
    UNION ALL
    SELECT r.basis, r.integrator, r.pair_class, r.x, r.lifi, w.w FROM under_rows r JOIN under_w w USING (basis, integrator)
),
scen AS (
    SELECT 2 AS ord, 'not stablecoin pairs (free on stablecoin pairs)' AS scenario, * FROM row_w WHERE pair_class <> 'stable'
    UNION ALL
    SELECT 3, 'altcoin pairs only', * FROM row_w WHERE pair_class = 'alt'
),
source_v AS (SELECT integrator, sum(x) AS v FROM bridge_rows JOIN four USING (integrator) WHERE flag GROUP BY integrator),
agg AS (
    SELECT ord, scenario, basis, coalesce(integrator, '(all four)') AS integrator,
           sum(w * x) AS v, sum(w * lifi) AS l,
           sum(w * greatest(5e-4 * x - lifi, 0)) AS i5, sum(w * greatest(20e-4 * x - lifi, 0)) AS i20, sum(w * greatest(25e-4 * x - lifi, 0)) AS i25
    FROM scen GROUP BY GROUPING SETS ((ord, scenario, basis), (ord, scenario, basis, integrator))
),
all_vol AS (
    SELECT 1 AS ord, 'all volume' AS scenario, 'file, exact' AS basis, coalesce(b.integrator, '(all four)') AS integrator,
           sum(b.x) AS v, 0.0 AS l, sum(b.x) * 5e-4 AS i5, sum(b.x) * 20e-4 AS i20, sum(b.x) * 25e-4 AS i25
    FROM bridge_rows b JOIN four f USING (integrator)
    GROUP BY GROUPING SETS ((), (b.integrator))
)
SELECT a.scenario, a.integrator, a.basis,
       round(a.v, 2)                            AS weekly_usd,
       CASE WHEN a.basis <> 'file, exact' THEN round(100 * a.v / CASE WHEN a.integrator = '(all four)' THEN (SELECT sum(v) FROM source_v) ELSE (SELECT v FROM source_v s WHERE s.integrator = a.integrator) END, 2) END AS pct_of_source_step_volume,
       CASE WHEN a.basis = 'file, exact' THEN NULL
            WHEN a.integrator = '(all four)' THEN (SELECT sum(n) FROM under_w u WHERE u.basis = a.basis)
            ELSE (SELECT n FROM under_w u WHERE u.basis = a.basis AND u.integrator = a.integrator) END AS sampled_rows_under_10k,
       round(a.v * 1e-4 * c.c * 52, 0)          AS annual_per_1bp_usd,
       round(a.i5 * c.c * 52, 0)                AS annual_at_5bps_usd,
       round(a.i20 * c.c * 52, 0)               AS annual_at_20bps_usd,
       round(a.i25 * c.c * 52, 0)               AS annual_at_25bps_usd
FROM (SELECT * FROM agg UNION ALL SELECT * FROM all_vol) a CROSS JOIN completion c
ORDER BY a.ord, a.basis DESC, CASE a.integrator WHEN '(all four)' THEN 0 ELSE 1 END, a.v DESC
