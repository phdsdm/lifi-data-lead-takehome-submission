-- 83_revenue_model_weekly_lifi_fee
-- Question: What weekly and annual LI.FI fee revenue do the fee rates observed in the uniform
--           2,000 imply on the file's completed bridge volume, under each way of weighting the
--           sample to the file?
-- Grain:    one row per estimator (9), A to I.
-- Definition applied (the brief's fee model plus the assumptions below):
--   - LI.FI fee: feeSplit.lifiFee of the quote's LIFI-named line, as in 75_status_fee_overall.
--     The integrator's share of the line is the integrator's revenue and is not counted. Other
--     quote lines (bridge, relayer, gas) are not LI.FI's and are not counted.
--   - Revenue is recognised on completed transfers only (the brief): weekly = sum over strata
--     of rate_h × file_usd_h × completion, completion = the uniform sample's completed share,
--     1,964 of 2,000 (98.20%, 44_status_completion_rates), one value for every stratum.
--   - rate_h = sum(LI.FI fee) / sum(amount_usd) over the stratum's observed events (a ratio
--     estimate); file_usd_h = the stratum's bridge volume in the file (headline
--     amount_usd, same-chain *Dex rows out; the 4 rows no feed prices add no USD and are left
--     out). volume_without_rate_usd: file volume in a stratum with no observed event (0 here).
--   - Estimators (strata):
--       A overall ratio: one stratum, the 1,990 bridge-volume rows of the uniform 2,000.
--       B by source swap: hasSourceSwaps true / false.
--       C by size band: seven size bands; the band above $1M takes
--         the edge-case census of the 22 rows above $1M (the uniform sample draws none).
--       D by source swap × size band: 14 strata, the two above-$1M strata from the census.
--       E by bridge, F by route, G by token symbol, H by (route, token)
--         (segments under 30 sampled events pooled).
--       I by measured partner, else source swap × size band: rows without hasSourceSwaps one
--         stratum; rows with it, of a partner (any class of ref_integrator_map, joined on
--         coalesce(m.integrator, '')) with at least 10 sampled swap transfers, that partner's
--         own stratum; every other swap row its
--         size band's stratum, the band above $1M from the census. 93_partner_revenue_concentration
--         allocates this estimator to partners.
--   - Interval: weekly ± 1.96 × sqrt(sum((file_usd_h × completion × SE_h)²)), SE_h the
--     linearised ratio SE of 75_status_fee_overall (0 for census strata); strata treated as
--     independent; floored at 0. It covers sampling error in the rates only, not the
--     assumptions.
--   - annual = weekly × 52: assumes the week of 2026-10-13 to 2026-10-19 repeats. The file
--     covers six EVM source chains and is itself a sample of LI.FI's events (data README), so
--     the figure is for the file's coverage, not LI.FI's whole business.
--   - implied_bps: weekly / (bridge volume × completion), the LI.FI fee per completed USD.
--   - Further assumptions: the quoted fee is the fee charged; USD-weighted completion equals the count share; a stratum's sampled
--     events carry the rate of all its volume.
-- Inputs:   ref_lifi_api_transfer_status_sample_2600 and ref_lifi_api_transfer_status_edge_cases
--           (reference data: LI.FI /v1/status, fetched 2026-10-28); transfers_priced (reference
--           data for its 377 CoinGecko-priced rows); ref_lifi_chain_id_registry (names only).

WITH source_ids(chain, source_chain_id) AS (
    VALUES ('ethereum', 1), ('optimism', 10), ('bnb', 56), ('polygon', 137), ('base', 8453), ('arbitrum', 42161)
),
bands(band_ord, band, lo, hi) AS (
    VALUES (1, 'under $10', 0.0, 10.0), (2, '$10 to <$100', 10.0, 100.0), (3, '$100 to <$1k', 100.0, 1000.0),
           (4, '$1k to <$10k', 1000.0, 10000.0), (5, '$10k to $100k', 10000.0, 100000.0),
           (6, '>$100k to $1M', 100000.0, 1000000.0), (7, '>$1M', 1000000.0, 1e18)
),
completion AS (
    SELECT avg(CASE WHEN substatus = 'COMPLETED' THEN 1.0 ELSE 0.0 END) AS c
    FROM ref_lifi_api_transfer_status_sample_2600
    WHERE sample_design = 'uniform_2000'
),
bv AS (
    SELECT t.chain, t.tx_hash, t.log_index, t.amount_usd,
           t.has_source_swaps,
           m.class || ' · ' || m.partner                                                            AS partner_key,
           t.bridge,
           rs.name || ' → ' || rd.name                                                              AS route,
           coalesce(t.symbol, '(no symbol) ' || t.sending_asset_id)                                 AS token_symbol,
           rs.name || ' → ' || rd.name || ' · ' || coalesce(t.symbol, '?') || ' ' || t.sending_asset_id AS route_token,
           b.band_ord, b.band
    FROM transfers_priced t
    JOIN source_ids s USING (chain)
    LEFT JOIN ref_lifi_chain_id_registry rs ON rs.chain_id = s.source_chain_id
    LEFT JOIN ref_lifi_chain_id_registry rd ON rd.chain_id = t.destination_chain_id
    LEFT JOIN ref_integrator_map m ON coalesce(m.integrator, '') = t.integrator
    LEFT JOIN bands b ON (b.band_ord <= 4 AND t.amount_usd >= b.lo AND t.amount_usd < b.hi)
                      OR (b.band_ord = 5  AND t.amount_usd >= b.lo AND t.amount_usd <= b.hi)
                      OR (b.band_ord >= 6 AND t.amount_usd > b.lo AND t.amount_usd <= b.hi)
    WHERE t.destination_chain_id <> s.source_chain_id
      AND t.amount_usd IS NOT NULL
),
smp AS (
    SELECT bv.*, FALSE AS census,
           coalesce(st.fee_split_lifi_usd, 0) AS lifi
    FROM ref_lifi_api_transfer_status_sample_2600 st
    JOIN bv USING (chain, tx_hash, log_index)
    WHERE st.sample_design = 'uniform_2000'
),
cen AS (
    SELECT bv.*, TRUE AS census,
           coalesce(e.fee_split_lifi_usd, 0) AS lifi
    FROM ref_lifi_api_transfer_status_edge_cases e
    JOIN bv USING (chain, tx_hash, log_index)
    WHERE e.lookup = 'tx_hash' AND e.reason_tags LIKE '%above_1m_usd%' AND bv.band_ord = 7
),
measured_partners AS (
    SELECT partner_key FROM smp WHERE has_source_swaps GROUP BY partner_key HAVING count(*) >= 10
),
strat_i AS (   -- estimator I's stratum for every bridge-volume row
    SELECT bv.chain, bv.tx_hash, bv.log_index,
           CASE WHEN NOT bv.has_source_swaps THEN 'no source swap'
                WHEN mp.partner_key IS NOT NULL THEN 'partner · ' || bv.partner_key
                ELSE 'swap · ' || bv.band END AS stratum
    FROM bv LEFT JOIN measured_partners mp USING (partner_key)
),
estimators(est, min_n) AS (
    VALUES ('A overall ratio', 1), ('B by source swap', 1), ('C by size band', 1), ('D by source swap x size band', 1),
           ('E by bridge', 30), ('F by route', 30), ('G by token symbol', 30), ('H by route and token', 30),
           ('I by measured partner, else source swap x size band', 1)
),
obs AS (   -- observed units with their stratum under each estimator
    SELECT 'A overall ratio' AS est, 'all' AS stratum, amount_usd AS x, lifi, census FROM smp
    UNION ALL SELECT 'B by source swap', CAST(has_source_swaps AS VARCHAR), amount_usd, lifi, census FROM smp
    UNION ALL SELECT 'C by size band', band, amount_usd, lifi, census FROM smp WHERE band_ord < 7
    UNION ALL SELECT 'C by size band', band, amount_usd, lifi, census FROM cen
    UNION ALL SELECT 'D by source swap x size band', CAST(has_source_swaps AS VARCHAR) || ' · ' || band, amount_usd, lifi, census FROM smp WHERE band_ord < 7
    UNION ALL SELECT 'D by source swap x size band', CAST(has_source_swaps AS VARCHAR) || ' · ' || band, amount_usd, lifi, census FROM cen
    UNION ALL SELECT 'E by bridge', bridge, amount_usd, lifi, census FROM smp
    UNION ALL SELECT 'F by route', route, amount_usd, lifi, census FROM smp
    UNION ALL SELECT 'G by token symbol', token_symbol, amount_usd, lifi, census FROM smp
    UNION ALL SELECT 'H by route and token', route_token, amount_usd, lifi, census FROM smp
    UNION ALL SELECT 'I by measured partner, else source swap x size band', si.stratum, x.amount_usd, x.lifi, x.census
              FROM smp x JOIN strat_i si USING (chain, tx_hash, log_index)
    UNION ALL SELECT 'I by measured partner, else source swap x size band', si.stratum, x.amount_usd, x.lifi, x.census
              FROM cen x JOIN strat_i si USING (chain, tx_hash, log_index) WHERE si.stratum = 'swap · >$1M'
),
fil AS (   -- file units with their stratum under each estimator
    SELECT 'A overall ratio' AS est, 'all' AS stratum, amount_usd FROM bv
    UNION ALL SELECT 'B by source swap', CAST(has_source_swaps AS VARCHAR), amount_usd FROM bv
    UNION ALL SELECT 'C by size band', band, amount_usd FROM bv
    UNION ALL SELECT 'D by source swap x size band', CAST(has_source_swaps AS VARCHAR) || ' · ' || band, amount_usd FROM bv
    UNION ALL SELECT 'E by bridge', bridge, amount_usd FROM bv
    UNION ALL SELECT 'F by route', route, amount_usd FROM bv
    UNION ALL SELECT 'G by token symbol', token_symbol, amount_usd FROM bv
    UNION ALL SELECT 'H by route and token', route_token, amount_usd FROM bv
    UNION ALL SELECT 'I by measured partner, else source swap x size band', si.stratum, bv.amount_usd
              FROM bv JOIN strat_i si USING (chain, tx_hash, log_index)
),
kept AS (
    SELECT o.est, o.stratum
    FROM obs o JOIN estimators e USING (est)
    GROUP BY o.est, o.stratum, e.min_n
    HAVING count(*) >= e.min_n
),
obs_l AS (
    SELECT o.est, coalesce(k.stratum, '(other)') AS label, o.x, o.lifi, o.census
    FROM obs o LEFT JOIN kept k ON k.est = o.est AND k.stratum IS NOT DISTINCT FROM o.stratum
),
fil_l AS (
    SELECT f.est, coalesce(k.stratum, '(other)') AS label, f.amount_usd
    FROM fil f LEFT JOIN kept k ON k.est = f.est AND k.stratum IS NOT DISTINCT FROM f.stratum
),
ratios AS (
    SELECT est, label, sum(lifi) / sum(x) AS r FROM obs_l GROUP BY est, label
),
o_agg AS (
    SELECT o.est, o.label,
           count(*)                AS n,
           bool_and(o.census)      AS census,
           any_value(r.r)          AS r,
           CASE WHEN bool_and(o.census) THEN 0
                WHEN count(*) > 1 THEN sqrt(count(*) / (count(*) - 1.0) * sum(power(o.lifi - r.r * o.x, 2))) / sum(o.x)
                ELSE 0 END         AS se
    FROM obs_l o JOIN ratios r USING (est, label)
    GROUP BY o.est, o.label
),
f_agg AS (
    SELECT est, label, coalesce(sum(amount_usd), 0) AS file_usd FROM fil_l GROUP BY est, label
),
strata AS (
    SELECT f.est, f.label, f.file_usd, a.n, a.census, a.r, a.se, c.c
    FROM f_agg f
    LEFT JOIN o_agg a USING (est, label)
    CROSS JOIN completion c
)
SELECT est                                                                         AS estimator,
       count(*)                                                                    AS strata,
       sum(n) FILTER (WHERE NOT census)                                            AS sampled_events_used,
       coalesce(sum(n) FILTER (WHERE census), 0)                                   AS census_events_used,
       round(sum(file_usd), 2)                                                     AS bridge_volume_usd,
       round(coalesce(sum(file_usd) FILTER (WHERE r IS NULL), 0), 2)               AS volume_without_rate_usd,
       round(100.0 * any_value(c), 2)                                              AS completion_pct,
       round(1e4 * sum(r * file_usd * c) / (sum(file_usd) * any_value(c)), 3)      AS implied_bps,
       round(sum(r * file_usd * c), 2)                                             AS weekly_lifi_fee_usd,
       round(greatest(0, sum(r * file_usd * c) - 1.96 * sqrt(sum(power(file_usd * c * se, 2)))), 2) AS weekly_low,
       round(sum(r * file_usd * c) + 1.96 * sqrt(sum(power(file_usd * c * se, 2))), 2)               AS weekly_high,
       round(52 * sum(r * file_usd * c), 0)                                        AS annual_lifi_fee_usd,
       round(52 * greatest(0, sum(r * file_usd * c) - 1.96 * sqrt(sum(power(file_usd * c * se, 2)))), 0) AS annual_low,
       round(52 * (sum(r * file_usd * c) + 1.96 * sqrt(sum(power(file_usd * c * se, 2)))), 0)        AS annual_high
FROM strata
GROUP BY est
ORDER BY est
