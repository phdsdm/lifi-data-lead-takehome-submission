-- 85_under_monetised_segments
-- Question: Which high-volume bridges, routes, tokens, (route, token) pairs, size bands and
--           source-swap groups carry a LI.FI fee rate below the overall rate in the quotes, and
--           what would closing the gap to the overall rate be worth per week and per year?
-- Grain:    one row per (dimension, segment) holding at least 1% of bridge volume and at least
--           30 observed events (sampled, or the census above $1M); within a dimension, largest
--           file volume first.
-- Definition applied:
--   - Segments: bridge, route, token symbol, (route, token), source
--     swap (hasSourceSwaps of bridge_data, 75_status_fee_overall), size band
--     (the band above $1M from the edge-case census of its 22 rows,
--     whose count of 22 is below 30 but is the whole band, so it is kept).
--   - lifi_bps with its 95% interval: (ratio estimate over the uniform 2,000's
--     bridge-volume rows; linearised SE; 0 for the census).
--   - overall_lifi_bps: the same ratio over all 1,990 bridge-volume rows of the uniform 2,000
--     (75_status_fee_overall, row 'bridge-volume rows'; estimator A of
--     83_revenue_model_weekly_lifi_fee).
--   - below_overall: lifi_bps < overall_lifi_bps. interval_below_overall: the segment's whole
--     interval is below it (lifi_bps_high < overall_lifi_bps).
--   - weekly_gap_to_overall_usd = (overall_lifi_bps - lifi_bps) / 10,000 × file_usd ×
--     completion when positive, else 0: the LI.FI fee the segment would add per week if its
--     completed volume paid the overall rate with no volume lost (no price elasticity, an
--     assumption). completion = 98.20% (44_status_completion_rates). annual = × 52.
--   - weekly_per_1bps_usd: one basis point on the segment's completed volume; annual = × 52.
--   - Segments overlap across dimensions; gaps of different dimensions do not add up.
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
           CASE WHEN t.has_source_swaps THEN 'with hasSourceSwaps' ELSE 'without hasSourceSwaps' END AS source_swap,
           t.bridge,
           rs.name || ' → ' || rd.name                                                              AS route,
           coalesce(t.symbol, '(no symbol) ' || t.sending_asset_id)                                 AS token_symbol,
           rs.name || ' → ' || rd.name || ' · ' || coalesce(t.symbol, '?') || ' ' || t.sending_asset_id AS route_token,
           b.band_ord, b.band
    FROM transfers_priced t
    JOIN source_ids s USING (chain)
    LEFT JOIN ref_lifi_chain_id_registry rs ON rs.chain_id = s.source_chain_id
    LEFT JOIN ref_lifi_chain_id_registry rd ON rd.chain_id = t.destination_chain_id
    LEFT JOIN bands b ON (b.band_ord <= 4 AND t.amount_usd >= b.lo AND t.amount_usd < b.hi)
                      OR (b.band_ord = 5  AND t.amount_usd >= b.lo AND t.amount_usd <= b.hi)
                      OR (b.band_ord >= 6 AND t.amount_usd > b.lo AND t.amount_usd <= b.hi)
    WHERE t.destination_chain_id <> s.source_chain_id
      AND t.amount_usd IS NOT NULL
),
smp AS (
    SELECT bv.*, FALSE AS census, coalesce(st.fee_split_lifi_usd, 0) AS lifi
    FROM ref_lifi_api_transfer_status_sample_2600 st
    JOIN bv USING (chain, tx_hash, log_index)
    WHERE st.sample_design = 'uniform_2000'
),
cen AS (
    SELECT bv.*, TRUE AS census, coalesce(e.fee_split_lifi_usd, 0) AS lifi
    FROM ref_lifi_api_transfer_status_edge_cases e
    JOIN bv USING (chain, tx_hash, log_index)
    WHERE e.lookup = 'tx_hash' AND e.reason_tags LIKE '%above_1m_usd%' AND bv.band_ord = 7
),
overall AS (
    SELECT sum(lifi) / sum(amount_usd) AS r_all FROM smp
),
obs AS (
    SELECT 1 AS dim_ord, 'bridge' AS dimension, bridge AS segment, amount_usd AS x, lifi, census FROM smp
    UNION ALL SELECT 2, 'route', route, amount_usd, lifi, census FROM smp
    UNION ALL SELECT 3, 'token_symbol', token_symbol, amount_usd, lifi, census FROM smp
    UNION ALL SELECT 4, 'route_and_token', route_token, amount_usd, lifi, census FROM smp
    UNION ALL SELECT 5, 'source_swap', source_swap, amount_usd, lifi, census FROM smp
    UNION ALL SELECT 6, 'size_band', band, amount_usd, lifi, census FROM smp WHERE band_ord < 7
    UNION ALL SELECT 6, 'size_band', band, amount_usd, lifi, census FROM cen
),
fil AS (
    SELECT 1 AS dim_ord, bridge AS segment, amount_usd FROM bv
    UNION ALL SELECT 2, route, amount_usd FROM bv
    UNION ALL SELECT 3, token_symbol, amount_usd FROM bv
    UNION ALL SELECT 4, route_token, amount_usd FROM bv
    UNION ALL SELECT 5, source_swap, amount_usd FROM bv
    UNION ALL SELECT 6, band, amount_usd FROM bv
),
ratios AS (
    SELECT dim_ord, segment, sum(lifi) / sum(x) AS r FROM obs GROUP BY dim_ord, segment
),
o_agg AS (
    SELECT o.dim_ord, any_value(o.dimension) AS dimension, o.segment,
           count(*)            AS n,
           bool_and(o.census)  AS census,
           any_value(r.r)      AS r,
           CASE WHEN bool_and(o.census) THEN 0
                ELSE sqrt(count(*) / (count(*) - 1.0) * sum(power(o.lifi - r.r * o.x, 2))) / sum(o.x) END AS se
    FROM obs o JOIN ratios r USING (dim_ord, segment)
    GROUP BY o.dim_ord, o.segment
    HAVING count(*) >= 30 OR bool_and(o.census)
),
f_agg AS (
    SELECT dim_ord, segment, sum(amount_usd) AS file_usd,
           sum(amount_usd) / sum(sum(amount_usd)) OVER (PARTITION BY dim_ord) AS share
    FROM fil GROUP BY dim_ord, segment
)
SELECT a.dimension,
       a.segment,
       CASE WHEN a.census THEN 'edge-case census (all rows above $1M)' ELSE 'uniform 2,000' END        AS rate_source,
       a.n                                                                                            AS observed,
       round(1e4 * a.r, 3)                                                                            AS lifi_bps,
       round(greatest(0, 1e4 * (a.r - 1.96 * a.se)), 3)                                               AS lifi_bps_low,
       round(1e4 * (a.r + 1.96 * a.se), 3)                                                            AS lifi_bps_high,
       round(1e4 * o.r_all, 3)                                                                        AS overall_lifi_bps,
       a.r < o.r_all                                                                                  AS below_overall,
       a.r + 1.96 * a.se < o.r_all                                                                    AS interval_below_overall,
       round(f.file_usd, 2)                                                                           AS file_usd,
       round(100.0 * f.share, 3)                                                                      AS pct_bridge_volume,
       round(a.r * f.file_usd * c.c, 2)                                                               AS weekly_lifi_fee_at_observed_usd,
       round(greatest(0, o.r_all - a.r) * f.file_usd * c.c, 2)                                        AS weekly_gap_to_overall_usd,
       round(52 * greatest(0, o.r_all - a.r) * f.file_usd * c.c, 0)                                   AS annual_gap_to_overall_usd,
       round(1e-4 * f.file_usd * c.c, 2)                                                              AS weekly_per_1bps_usd,
       round(52 * 1e-4 * f.file_usd * c.c, 0)                                                         AS annual_per_1bps_usd
FROM o_agg a
JOIN f_agg f USING (dim_ord, segment)
CROSS JOIN overall o
CROSS JOIN completion c
WHERE f.share >= 0.01
ORDER BY a.dim_ord, f.file_usd DESC, a.segment
