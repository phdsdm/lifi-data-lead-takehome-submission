-- 44_status_completion_rates
-- Question: What share of sampled started transfers completed, was refunded or was partial,
--           overall and by source chain, in each sample design?
-- Grain:    one row per (sample design, source chain) and one per sample design for all
--           chains (sample designs: uniform_2000, equal_per_chain_600).
-- Definition applied:
--   - Completed: substatus COMPLETED; refunded: REFUNDED; partial: PARTIAL. status_done
--     counts responses with status DONE.
--   - Rates are of sampled events. wilson_low / wilson_high: the Wilson 95% interval of the
--     completed share, z = 1.96, in percent.
--   - uniform_2000 is a uniform random sample of the file and represents it;
--     equal_per_chain_600 is 100 events per source chain.
-- Inputs:   ref_lifi_api_transfer_status_sample_2600 (reference data: LI.FI /v1/status by
--           tx_hash, fetched 2026-10-28).

WITH counts AS (
    SELECT sample_design,
           coalesce(chain, '(all chains)')                      AS chain,
           grouping(chain)                                      AS is_total,
           count(*)                                             AS sampled,
           count(*) FILTER (WHERE status = 'DONE')              AS status_done,
           count(*) FILTER (WHERE substatus = 'COMPLETED')      AS completed,
           count(*) FILTER (WHERE substatus = 'REFUNDED')       AS refunded,
           count(*) FILTER (WHERE substatus = 'PARTIAL')        AS partial
    FROM ref_lifi_api_transfer_status_sample_2600
    GROUP BY GROUPING SETS ((sample_design, chain), (sample_design))
),
rates AS (
    SELECT *,
           completed * 1.0 / sampled AS p,
           1.96                      AS z
    FROM counts
)
SELECT sample_design,
       chain,
       sampled,
       status_done,
       completed,
       refunded,
       partial,
       round(100.0 * p, 2)                                                        AS pct_completed,
       round(100.0 * refunded / sampled, 2)                                       AS pct_refunded,
       round(100.0 * partial / sampled, 2)                                        AS pct_partial,
       round(100.0 * ((p + z * z / (2 * sampled))
                      - z * sqrt(p * (1 - p) / sampled + z * z / (4 * sampled * sampled)))
                     / (1 + z * z / sampled), 2)                                  AS wilson_low,
       round(100.0 * ((p + z * z / (2 * sampled))
                      + z * sqrt(p * (1 - p) / sampled + z * z / (4 * sampled * sampled)))
                     / (1 + z * z / sampled), 2)                                  AS wilson_high
FROM rates
ORDER BY sample_design DESC, is_total DESC, pct_completed, chain
