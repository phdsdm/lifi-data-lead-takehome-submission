-- 91_partner_fee_tier_gaps
-- Question: Among partners whose LI.FI rate the sample measures, which carry a lower rate than
--           partners of similar volume, and what would LI.FI earn per week if each paid its
--           volume band's median rate, or the 25 bps that unattributed lifi-api traffic pays?
-- Grain:    one row per rate-measurable partner (class 'partner', at least 10 sampled transfers
--           with hasSourceSwaps; 16), grouped by volume band, largest bridge volume first; then a
--           total row over them (sizes summed from the rounded rows).
-- Definition applied:
--   - Partner, class, bridge volume, swap_usd, the sampled rates and the threshold: from
--     the uniform 2,000.
--   - Volume band on the partner's bridge volume: '$1M and above', '$100k to $1M', 'under $100k'
--     (a judgement; "similar volume" means the same band).
--   - swap_lifi_bps: the partner's LI.FI fee over its sampled swap transfers' amount_usd.
--     modal_lifi_bps: its commonest per-transfer rate there. line_names: the LIFI-named line
--     names its sampled transfers carry (Fixed or Shared; none when no line).
--   - band_median_bps: the median swap_lifi_bps of the rate-measurable partners in the band,
--     zeros included. gap_to_band_median_bps = band_median_bps - swap_lifi_bps when positive.
--   - Sizes, on the partner's swap volume only (its bridge-only volume carries no fee in any
--     sampled transfer, and a tier change alone would not add one), × completion 98.20%
--     (44_status_completion_rates), volume held fixed (no price elasticity):
--       weekly_uplift_to_band_median_usd = gap / 10,000 × swap_usd × completion;
--       weekly_uplift_to_25bps_usd = max(0, 25 - swap_lifi_bps) / 10,000 × swap_usd × completion,
--         25 bps being the LI.FI rate on every sampled lifi-api transfer
--         (76_status_lifi_fee_rate_distribution) and on 67 integrator strings;
--       annual = × 52; weekly_per_1bps_usd = 1 bp on the swap volume.
--   - bridge_only_usd: the partner's volume without hasSourceSwaps, which no tier change reaches.
-- Inputs:   transfers_priced; ref_integrator_map; ref_lifi_api_transfer_status_sample_2600
--           (reference data: LI.FI /v1/status, fetched 2026-10-28).

WITH source_ids(chain, source_chain_id) AS (
    VALUES ('ethereum', 1), ('optimism', 10), ('bnb', 56), ('polygon', 137), ('base', 8453), ('arbitrum', 42161)
),
completion AS (
    SELECT avg(CASE WHEN substatus = 'COMPLETED' THEN 1.0 ELSE 0.0 END) AS c
    FROM ref_lifi_api_transfer_status_sample_2600
    WHERE sample_design = 'uniform_2000'
),
bv AS (
    SELECT t.chain, t.tx_hash, t.log_index, t.amount_usd, t.has_source_swaps, m.partner
    FROM transfers_priced t
    JOIN source_ids s USING (chain)
    JOIN ref_integrator_map m ON coalesce(m.integrator, '') = t.integrator
    WHERE t.destination_chain_id <> s.source_chain_id
      AND m.class = 'partner'
),
file_p AS (
    SELECT partner,
           coalesce(sum(amount_usd), 0)                                         AS bridge_usd,
           coalesce(sum(amount_usd) FILTER (WHERE has_source_swaps), 0)         AS swap_usd,
           coalesce(sum(amount_usd) FILTER (WHERE NOT has_source_swaps), 0)     AS bridge_only_usd
    FROM bv GROUP BY partner
),
smp AS (
    SELECT b.partner, b.amount_usd AS x,
           coalesce(st.fee_split_lifi_usd, 0)                                   AS lifi,
           CASE WHEN coalesce(st.quote_fee_lifi_usd, 0) > 0
                THEN round(1e4 * st.quote_fee_lifi_percentages * st.fee_split_lifi_usd / st.quote_fee_lifi_usd, 2) ELSE 0 END       AS lifi_rate,
           CASE WHEN coalesce(st.quote_fee_lifi_usd, 0) > 0
                THEN round(1e4 * st.quote_fee_lifi_percentages * st.fee_split_integrator_usd / st.quote_fee_lifi_usd, 2) ELSE 0 END AS integ_rate,
           CASE WHEN coalesce(st.quote_fee_lifi_usd, 0) = 0 THEN 'none'
                WHEN st.quote_fee_names LIKE '%LIFI Shared Fee%' THEN 'Shared' ELSE 'Fixed' END AS line_name
    FROM ref_lifi_api_transfer_status_sample_2600 st
    JOIN bv b USING (chain, tx_hash, log_index)
    WHERE st.sample_design = 'uniform_2000' AND b.has_source_swaps
),
modal AS (
    SELECT partner, lifi_rate, integ_rate, count(*) AS n,
           row_number() OVER (PARTITION BY partner ORDER BY count(*) DESC, lifi_rate) AS k
    FROM smp GROUP BY partner, lifi_rate, integ_rate
),
measured AS (
    SELECT s.partner,
           count(*)                                            AS sampled_swap,
           sum(s.lifi) / sum(s.x)                              AS r,
           string_agg(DISTINCT s.line_name, ', ' ORDER BY s.line_name) AS line_names
    FROM smp s GROUP BY s.partner HAVING count(*) >= 10
),
banded AS (
    SELECT m.*, f.bridge_usd, f.swap_usd, f.bridge_only_usd,
           md.lifi_rate AS modal_lifi_bps, md.integ_rate AS modal_integrator_bps,
           CASE WHEN f.bridge_usd >= 1000000 THEN 1 WHEN f.bridge_usd >= 100000 THEN 2 ELSE 3 END AS band_ord
    FROM measured m
    JOIN file_p f USING (partner)
    JOIN modal md ON md.partner = m.partner AND md.k = 1
),
band_median AS (
    SELECT band_ord, median(r) AS r_med, count(*) AS partners_in_band FROM banded GROUP BY band_ord
),
rows_ AS (
SELECT b.band_ord,
       CASE b.band_ord WHEN 1 THEN '$1M and above' WHEN 2 THEN '$100k to $1M' ELSE 'under $100k' END AS volume_band,
       bm.partners_in_band,
       b.partner,
       round(b.bridge_usd, 2)                                                    AS bridge_usd,
       round(b.swap_usd, 2)                                                      AS swap_usd,
       round(b.bridge_only_usd, 2)                                               AS bridge_only_usd,
       b.sampled_swap,
       b.line_names,
       b.modal_lifi_bps,
       b.modal_integrator_bps,
       round(1e4 * b.r, 3)                                                       AS swap_lifi_bps,
       round(1e4 * bm.r_med, 3)                                                  AS band_median_bps,
       round(greatest(0, 1e4 * (bm.r_med - b.r)), 3)                             AS gap_to_band_median_bps,
       round(greatest(0, bm.r_med - b.r) * b.swap_usd * c.c, 2)                  AS weekly_uplift_to_band_median_usd,
       round(52 * greatest(0, bm.r_med - b.r) * b.swap_usd * c.c, 0)             AS annual_uplift_to_band_median_usd,
       round(greatest(0, 25e-4 - b.r) * b.swap_usd * c.c, 2)                     AS weekly_uplift_to_25bps_usd,
       round(52 * greatest(0, 25e-4 - b.r) * b.swap_usd * c.c, 0)                AS annual_uplift_to_25bps_usd,
       round(1e-4 * b.swap_usd * c.c, 2)                                         AS weekly_per_1bps_usd
FROM banded b
JOIN band_median bm USING (band_ord)
CROSS JOIN completion c
)
SELECT * EXCLUDE (band_ord) FROM (
    SELECT * FROM rows_
    UNION ALL
    SELECT 9, '(all measured partners)', count(*), NULL, sum(bridge_usd), sum(swap_usd), sum(bridge_only_usd), sum(sampled_swap),
           NULL, NULL, NULL, NULL, NULL, NULL,
           sum(weekly_uplift_to_band_median_usd), sum(annual_uplift_to_band_median_usd),
           sum(weekly_uplift_to_25bps_usd), sum(annual_uplift_to_25bps_usd), sum(weekly_per_1bps_usd)
    FROM rows_
)
ORDER BY band_ord, bridge_usd DESC, partner
