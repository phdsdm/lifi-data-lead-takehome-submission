-- 93_partner_revenue_concentration
-- Question: How concentrated are bridge volume and the implied LI.FI fee across partners, how
--           much of the fee would leave with the largest partners, and how do the partners that
--           carry the volume compare with those that carry the fee?
-- Grain:    row_kind 'class': one row per map class (4) and the total; row_kind 'top_by_volume'
--           and 'top_by_fee': the top 1, 3, 5, 10 and 20 partners by bridge volume and by implied
--           fee; row_kind 'partner': one row per partner of class 'partner' with bridge volume
--           (558), largest volume first.
-- Definition applied:
--   - Partner and class: ref_integrator_map, joined on coalesce(m.integrator, ''); ranking over class 'partner' only. A class row's `partners` counts the
--     distinct names in the class that carry bridge volume, so test strings that the map puts
--     under one partner's name count once. Bridge volume: headline amount_usd, the 4
--     unpriced rows add no USD, as in 65_started_volume.
--   - Implied LI.FI fee: estimator I of 83_revenue_model_weekly_lifi_fee, allocated to the rows
--     it covers. A row without hasSourceSwaps pays 0 (as every sampled one does); a swap row of
--     a partner with at least 10 sampled swap transfers pays that partner's own rate (its LI.FI
--     fee over its sampled swap transfers' amount_usd); every other
--     swap row pays the rate of its size band over the sampled swap transfers of such partners
--     (the band above $1M from the edge-case census of its rows). weekly = rate × amount_usd ×
--     completion (98.20%, 44_status_completion_rates), summed per partner; the total equals
--     estimator I. rate_source: 'own sample' or 'size band'. sampled_swap and
--     sampled_swap_with_lifi_fee show, for every partner, its own sampled swap transfers and how
--     many pay LI.FI, so a 'size band' allocation can be read against the partner's own few
--     transfers (the census rows above $1M are not counted here).
--   - The assumptions of 83 apply: the quoted fee is charged, a stratum's sampled transfers carry
--     the rate of all its volume, volume is held fixed. A partner's implied fee is a model
--     allocation, not an observation: for 'size band' partners it is their swap volume at the
--     band's rate.
--   - Revenue at risk: the implied weekly LI.FI fee of the partners in a top-N group, the fee
--     that would stop if they stopped routing through LI.FI (no substitution assumed).
--   - Shares: pct_partner_usd of class-'partner' bridge volume; pct_partner_fee of the partners'
--     implied fee; pct_total_fee of the implied fee of every class.
-- Inputs:   transfers_priced; ref_integrator_map; ref_lifi_api_transfer_status_sample_2600 and
--           ref_lifi_api_transfer_status_edge_cases (reference data: LI.FI /v1/status, fetched
--           2026-10-28).

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
    SELECT t.chain, t.tx_hash, t.log_index, t.amount_usd, t.has_source_swaps,
           m.class, m.partner, m.class || ' · ' || m.partner AS partner_key, b.band
    FROM transfers_priced t
    JOIN source_ids s USING (chain)
    LEFT JOIN ref_integrator_map m ON coalesce(m.integrator, '') = t.integrator
    LEFT JOIN bands b ON (b.band_ord <= 4 AND t.amount_usd >= b.lo AND t.amount_usd < b.hi)
                      OR (b.band_ord = 5  AND t.amount_usd >= b.lo AND t.amount_usd <= b.hi)
                      OR (b.band_ord >= 6 AND t.amount_usd > b.lo AND t.amount_usd <= b.hi)
    WHERE t.destination_chain_id <> s.source_chain_id
      AND t.amount_usd IS NOT NULL
),
smp AS (
    SELECT bv.*, coalesce(st.fee_split_lifi_usd, 0) AS lifi
    FROM ref_lifi_api_transfer_status_sample_2600 st
    JOIN bv USING (chain, tx_hash, log_index)
    WHERE st.sample_design = 'uniform_2000'
),
cen AS (
    SELECT bv.*, coalesce(e.fee_split_lifi_usd, 0) AS lifi
    FROM ref_lifi_api_transfer_status_edge_cases e
    JOIN bv USING (chain, tx_hash, log_index)
    WHERE e.lookup = 'tx_hash' AND e.reason_tags LIKE '%above_1m_usd%' AND bv.band = '>$1M'
),
measured_partners AS (
    SELECT partner_key FROM smp WHERE has_source_swaps GROUP BY partner_key HAVING count(*) >= 10
),
strat AS (
    SELECT bv.*,
           CASE WHEN NOT bv.has_source_swaps THEN 'no source swap'
                WHEN mp.partner_key IS NOT NULL THEN 'partner · ' || bv.partner_key
                ELSE 'swap · ' || bv.band END                                  AS stratum,
           mp.partner_key IS NOT NULL                                          AS measured
    FROM bv LEFT JOIN measured_partners mp USING (partner_key)
),
obs AS (
    SELECT s.stratum, x.amount_usd, x.lifi FROM smp x JOIN strat s USING (chain, tx_hash, log_index)
    UNION ALL
    SELECT s.stratum, x.amount_usd, x.lifi FROM cen x JOIN strat s USING (chain, tx_hash, log_index) WHERE s.stratum = 'swap · >$1M'
),
rates AS (
    SELECT stratum, sum(lifi) / sum(amount_usd) AS r FROM obs GROUP BY stratum
),
per_partner AS (
    SELECT s.class, s.partner,
           bool_or(s.measured)                                          AS measured,
           sum(s.amount_usd)                                            AS usd,
           coalesce(sum(s.amount_usd) FILTER (WHERE NOT s.has_source_swaps), 0) AS bridge_only_usd,
           sum(r.r * s.amount_usd) * any_value(c.c)                     AS weekly
    FROM strat s
    JOIN rates r USING (stratum)
    CROSS JOIN completion c
    GROUP BY s.class, s.partner
),
samp_counts AS (
    SELECT class, partner,
           count(*) FILTER (WHERE has_source_swaps)               AS sampled_swap,
           count(*) FILTER (WHERE has_source_swaps AND lifi > 0)  AS sampled_swap_with_lifi_fee
    FROM smp GROUP BY class, partner
),
ranked AS (
    SELECT p.*, coalesce(sc.sampled_swap, 0) AS sampled_swap, coalesce(sc.sampled_swap_with_lifi_fee, 0) AS sampled_swap_with_lifi_fee,
           row_number() OVER (ORDER BY usd DESC, partner)                AS rank_volume,
           row_number() OVER (ORDER BY weekly DESC, usd DESC, partner)   AS rank_fee
    FROM per_partner p LEFT JOIN samp_counts sc USING (class, partner)
    WHERE p.class = 'partner'
),
tot AS (
    SELECT (SELECT sum(usd) FROM ranked)            AS partner_usd,
           (SELECT sum(weekly) FROM ranked)         AS partner_fee,
           (SELECT sum(usd) FROM per_partner)       AS all_usd,
           (SELECT sum(weekly) FROM per_partner)    AS all_fee
),
cuts(n) AS (VALUES (1), (3), (5), (10), (20)),
out AS (
    SELECT 1 AS ord_a, 0 AS ord_b, 'class' AS row_kind, p.class AS name, count(*) AS partners,
           sum(p.usd) AS usd, sum(p.bridge_only_usd) AS bridge_only_usd, sum(p.weekly) AS weekly, NULL::VARCHAR AS rate_source,
           NULL::BIGINT AS rank_volume, NULL::BIGINT AS rank_fee, NULL::BIGINT AS sampled_swap, NULL::BIGINT AS sampled_swap_with_lifi_fee
    FROM per_partner p GROUP BY p.class
    UNION ALL
    SELECT 1, 9, 'class', '(all classes)', count(*), sum(usd), sum(bridge_only_usd), sum(weekly), NULL, NULL, NULL, NULL, NULL FROM per_partner
    UNION ALL
    SELECT 2, k.n, 'top_by_volume', 'top ' || CAST(k.n AS VARCHAR) || ' partners by bridge volume', k.n,
           sum(r.usd), sum(r.bridge_only_usd), sum(r.weekly),
           string_agg(r.partner, ', ' ORDER BY r.rank_volume), NULL, NULL, NULL, NULL
    FROM cuts k JOIN ranked r ON r.rank_volume <= k.n GROUP BY k.n
    UNION ALL
    SELECT 3, k.n, 'top_by_fee', 'top ' || CAST(k.n AS VARCHAR) || ' partners by implied LI.FI fee', k.n,
           sum(r.usd), sum(r.bridge_only_usd), sum(r.weekly),
           string_agg(r.partner, ', ' ORDER BY r.rank_fee), NULL, NULL, NULL, NULL
    FROM cuts k JOIN ranked r ON r.rank_fee <= k.n GROUP BY k.n
    UNION ALL
    SELECT 4, r.rank_volume, 'partner', r.partner, 1, r.usd, r.bridge_only_usd, r.weekly,
           CASE WHEN r.measured THEN 'own sample' ELSE 'size band' END, r.rank_volume, r.rank_fee,
           r.sampled_swap, r.sampled_swap_with_lifi_fee
    FROM ranked r
)
SELECT o.row_kind,
       o.name,
       o.partners,
       round(o.usd, 2)                                                                  AS bridge_usd,
       CASE WHEN o.row_kind <> 'class' THEN round(100.0 * o.usd / t.partner_usd, 3) END AS pct_partner_usd,
       round(100.0 * o.usd / t.all_usd, 3)                                              AS pct_bridge_volume,
       round(100.0 * o.bridge_only_usd / nullif(o.usd, 0), 2)                           AS pct_bridge_only,
       round(o.weekly, 2)                                                               AS weekly_lifi_fee_usd,
       round(52 * o.weekly, 0)                                                          AS annual_lifi_fee_usd,
       CASE WHEN o.row_kind <> 'class' THEN round(100.0 * o.weekly / t.partner_fee, 2) END AS pct_partner_fee,
       round(100.0 * o.weekly / t.all_fee, 2)                                           AS pct_total_fee,
       round(1e4 * o.weekly / nullif(o.usd * c.c, 0), 3)                                AS implied_lifi_bps,
       o.rank_volume,
       o.rank_fee,
       o.sampled_swap,
       o.sampled_swap_with_lifi_fee,
       o.rate_source                                                                    AS rate_source_or_partners
FROM out o CROSS JOIN tot t CROSS JOIN completion c
ORDER BY o.ord_a, o.ord_b, o.name
