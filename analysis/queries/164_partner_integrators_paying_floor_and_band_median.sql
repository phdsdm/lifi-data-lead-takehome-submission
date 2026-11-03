-- 164_partner_integrators_paying_floor_and_band_median
-- Question: For each integrator of class partner paying above zero, what does moving that paying volume to
--           25 bps, or to the median rate of integrators of similar volume, add?
-- Grain:    one row per raw integrator string of class partner with paying rows, largest increase to 25
--           bps first; then a total per volume band and overall. Used for sizing instead of
--           91_partner_fee_tier_gaps: 91 reads 16 partners' rate from the uniform 2,000
--           and applies it to their swap volume, zero-rate partners included; this query takes every
--           partner string paying above zero, row by row, from the schedule.
--   - paying_rate_bps: the string's LI.FI fee / its paying volume (weighted rows).
--   - Volume band on the string's whole bridge volume in the file: $1M and above, $100k to $1M, under
--     $100k (query 91's bands, on the string). band_median_bps: the median of paying_rate_bps over
--     the strings of the band, unweighted. Increase to the band median: the floor rule with that
--     median as the floor, row by row.
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
partner_paying AS (SELECT * FROM weighted WHERE paying AND integrator_class = 'partner'),
per AS (
    SELECT integrator, sum(w * x) AS paying_usd, sum(w * lifi) AS l, count(*) AS rows_observed,
           count(*) FILTER (WHERE design = 'source_census') AS census_rows,
           sum(w * x) FILTER (WHERE design = 'source_census') AS census_usd,
           sum(w * greatest(25e-4 * x - lifi, 0)) AS inc_25
    FROM partner_paying GROUP BY integrator
),
banded AS (
    SELECT p.*, f.bridge_usd,
           CASE WHEN f.bridge_usd >= 1000000 THEN 1 WHEN f.bridge_usd >= 100000 THEN 2 ELSE 3 END AS band_ord,
           p.l / p.paying_usd AS r
    FROM per p
    JOIN (SELECT integrator, sum(x) AS bridge_usd FROM bridge_rows GROUP BY integrator) f USING (integrator)
),
med AS (SELECT band_ord, median(r) AS r_med, count(*) AS strings FROM banded GROUP BY band_ord),
inc_med AS (
    SELECT z.integrator, sum(z.w * greatest(m.r_med * z.x - z.lifi, 0)) AS inc_med
    FROM partner_paying z JOIN banded b USING (integrator) JOIN med m USING (band_ord)
    GROUP BY z.integrator
),
rows_ AS (
    SELECT b.band_ord, b.integrator, 1 AS strings, b.bridge_usd, b.paying_usd, b.census_usd, b.l, b.inc_25, i.inc_med, b.rows_observed, b.census_rows, m.r_med, b.r
    FROM banded b JOIN inc_med i USING (integrator) JOIN med m USING (band_ord)
),
rolled AS (
    SELECT 2 AS ord, band_ord, integrator AS name, strings, bridge_usd, paying_usd, census_usd, l, inc_25, inc_med, rows_observed, census_rows, r_med, r FROM rows_
    UNION ALL
    SELECT 1, band_ord, '(band total)', count(*), sum(bridge_usd), sum(paying_usd), sum(census_usd), sum(l), sum(inc_25), sum(inc_med), sum(rows_observed), sum(census_rows), any_value(r_med), NULL FROM rows_ GROUP BY band_ord
    UNION ALL
    SELECT 0, 0, '(all partner strings paying above zero)', count(*), sum(bridge_usd), sum(paying_usd), sum(census_usd), sum(l), sum(inc_25), sum(inc_med), sum(rows_observed), sum(census_rows), NULL, NULL FROM rows_
)
SELECT name,
       CASE band_ord WHEN 0 THEN 'all' WHEN 1 THEN '$1M and above' WHEN 2 THEN '$100k to $1M' ELSE 'under $100k' END AS volume_band,
       strings, rows_observed, census_rows,
       round(bridge_usd, 2)            AS bridge_usd,
       round(paying_usd, 2)            AS weekly_paying_usd,
       round(coalesce(census_usd, 0), 2) AS weekly_paying_usd_exact,
       round(l * c.c * 52, 0)          AS annual_fee_today_usd,
       round(1e4 * r, 3)               AS paying_rate_bps,
       round(1e4 * r_med, 3)           AS band_median_bps,
       round(inc_25 * c.c * 52, 0)     AS annual_increase_to_25bps_usd,
       round(inc_med * c.c * 52, 0)    AS annual_increase_to_band_median_usd
FROM rolled CROSS JOIN completion c
ORDER BY ord, band_ord, inc_25 DESC, name
