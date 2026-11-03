-- 84_revenue_sensitivity_to_fee_rate
-- Question: How much weekly and annual LI.FI fee revenue does each basis point of LI.FI fee
--           earn on the file's completed volume, on all bridge volume and on the volume bases a
--           revenue idea would target?
-- Grain:    one row per volume base (7): all bridge volume; with hasSourceSwaps; without
--           hasSourceSwaps; transfers above $100k; those of them without hasSourceSwaps (the
--           overlap of the two candidate bases); transfers above $1M; the same-chain *Dex rows
--           (outside bridge volume).
-- Definition applied:
--   - Volume: started volume in amount_usd (headline). Bridge volume excludes the 295
--     same-chain *Dex rows, as in 65_started_volume; the 4 unpriced rows add no
--     USD. Above $100k and above $1M are strict (> 100,000, > 1,000,000) and within bridge
--     volume.
--   - completion: the uniform sample's completed share, 1,964 of 2,000 (98.20%), with its Wilson
--     95% interval (97.52% to 98.70%), from 44_status_completion_rates; revenue is recognised on
--     completed transfers only (the brief).
--   - weekly_at_n_bps = n / 10,000 × file_usd × completion. The fee is linear in the rate, so the
--     columns scale; weekly_at_1bps_low/high use the completion interval. annual = weekly × 52,
--     assuming the week repeats. No price elasticity: volume is held fixed whatever the rate,
--     which is the assumption a fee change would test.
--   - For comparison, the LI.FI rate the uniform 2,000 observes on these bases is in
--     75_status_fee_overall (all, with and without source swap); 83_revenue_model_weekly_lifi_fee gives the implied revenue.
-- Inputs:   transfers_priced (reference data for its 377 CoinGecko-priced rows);
--           ref_lifi_api_transfer_status_sample_2600 (reference data: completion only).

WITH source_ids(chain, source_chain_id) AS (
    VALUES ('ethereum', 1), ('optimism', 10), ('bnb', 56), ('polygon', 137), ('base', 8453), ('arbitrum', 42161)
),
rows_ AS (
    SELECT t.amount_usd,
           t.has_source_swaps,
           t.destination_chain_id = s.source_chain_id AS same_chain
    FROM transfers_priced t
    JOIN source_ids s USING (chain)
),
completion AS (
    SELECT count(*) AS n, count(*) FILTER (WHERE substatus = 'COMPLETED') AS k
    FROM ref_lifi_api_transfer_status_sample_2600
    WHERE sample_design = 'uniform_2000'
),
c AS (
    SELECT k * 1.0 / n AS p,
           ((k * 1.0 / n + 1.96*1.96/(2*n)) - 1.96 * sqrt((k * 1.0 / n) * (1 - k * 1.0 / n) / n + 1.96*1.96/(4*n*n))) / (1 + 1.96*1.96/n) AS p_low,
           ((k * 1.0 / n + 1.96*1.96/(2*n)) + 1.96 * sqrt((k * 1.0 / n) * (1 - k * 1.0 / n) / n + 1.96*1.96/(4*n*n))) / (1 + 1.96*1.96/n) AS p_high
    FROM completion
),
bases AS (
    SELECT 1 AS ord, 'all bridge volume' AS base, count(*) AS n_rows, coalesce(sum(amount_usd), 0) AS usd FROM rows_ WHERE NOT same_chain
    UNION ALL SELECT 2, 'bridge volume with hasSourceSwaps', count(*), coalesce(sum(amount_usd), 0) FROM rows_ WHERE NOT same_chain AND has_source_swaps
    UNION ALL SELECT 3, 'bridge volume without hasSourceSwaps', count(*), coalesce(sum(amount_usd), 0) FROM rows_ WHERE NOT same_chain AND NOT has_source_swaps
    UNION ALL SELECT 4, 'bridge volume above $100k', count(*), coalesce(sum(amount_usd), 0) FROM rows_ WHERE NOT same_chain AND amount_usd > 100000
    UNION ALL SELECT 5, 'bridge volume above $100k without hasSourceSwaps', count(*), coalesce(sum(amount_usd), 0) FROM rows_ WHERE NOT same_chain AND amount_usd > 100000 AND NOT has_source_swaps
    UNION ALL SELECT 6, 'bridge volume above $1M', count(*), coalesce(sum(amount_usd), 0) FROM rows_ WHERE NOT same_chain AND amount_usd > 1000000
    UNION ALL SELECT 7, 'same-chain *Dex rows (not bridge volume)', count(*), coalesce(sum(amount_usd), 0) FROM rows_ WHERE same_chain
)
SELECT b.base,
       b.n_rows,
       round(b.usd, 2)                                  AS file_usd,
       round(100.0 * c.p, 2)                            AS completion_pct,
       round(b.usd * c.p, 2)                            AS completed_usd,
       round(1e-4 * b.usd * c.p, 2)                     AS weekly_at_1bps,
       round(1e-4 * b.usd * c.p_low, 2)                 AS weekly_at_1bps_low,
       round(1e-4 * b.usd * c.p_high, 2)                AS weekly_at_1bps_high,
       round(2e-4 * b.usd * c.p, 2)                     AS weekly_at_2bps,
       round(5e-4 * b.usd * c.p, 2)                     AS weekly_at_5bps,
       round(10e-4 * b.usd * c.p, 2)                    AS weekly_at_10bps,
       round(25e-4 * b.usd * c.p, 2)                    AS weekly_at_25bps,
       round(52 * 1e-4 * b.usd * c.p, 0)                AS annual_at_1bps,
       round(52 * 2e-4 * b.usd * c.p, 0)                AS annual_at_2bps,
       round(52 * 5e-4 * b.usd * c.p, 0)                AS annual_at_5bps,
       round(52 * 10e-4 * b.usd * c.p, 0)               AS annual_at_10bps,
       round(52 * 25e-4 * b.usd * c.p, 0)               AS annual_at_25bps
FROM bases b
CROSS JOIN c
ORDER BY b.ord
