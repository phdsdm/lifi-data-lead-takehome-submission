-- 42_status_received_over_sent_and_gas
-- Question: On completed sampled transfers, how much USD arrives for each USD sent, and
--           what does the sending leg's gas cost?
-- Grain:    one row per sample design (2) and one for both together.
-- Definition applied:
--   - Completed: substatus COMPLETED. received_over_sent = receiving_amountUSD /
--     sending_amountUSD, both the API's own USD on each leg; no trimming.
--   - Percentiles are quantile_cont. The shares losing more than 1% / 5% are of completed
--     transfers with both USD amounts.
--   - Gas: sending_gasAmountUSD over every sampled transfer of the design, all statuses
--     NULLs excluded.
--   - The uniform_2000 row represents the file; equal_per_chain_600 samples 100 per chain.
-- Inputs:   ref_lifi_api_transfer_status_sample_2600 (reference data: LI.FI /v1/status,
--           fetched 2026-10-28).

WITH s AS (
    SELECT sample_design AS sample, * FROM ref_lifi_api_transfer_status_sample_2600
    UNION ALL
    SELECT 'all_2600', * FROM ref_lifi_api_transfer_status_sample_2600
),
ratio AS (
    SELECT sample, receiving_amountUSD / sending_amountUSD AS r
    FROM s
    WHERE substatus = 'COMPLETED' AND sending_amountUSD > 0 AND receiving_amountUSD IS NOT NULL
),
r_stats AS (
    SELECT sample,
           count(*)                               AS completed_with_both_usd,
           median(r)                              AS median_received_over_sent,
           quantile_cont(r, 0.05)                 AS p05,
           quantile_cont(r, 0.95)                 AS p95,
           avg((r < 0.99)::INT)                   AS share_losing_over_1pct,
           avg((r < 0.95)::INT)                   AS share_losing_over_5pct,
           avg((r > 1)::INT)                      AS share_receiving_more
    FROM ratio
    GROUP BY sample
),
g_stats AS (
    SELECT sample,
           count(*)                                    AS events,
           count(sending_gasAmountUSD)                 AS events_with_gas,
           median(sending_gasAmountUSD)                AS median_sending_gas_usd,
           avg(sending_gasAmountUSD)                   AS mean_sending_gas_usd,
           quantile_cont(sending_gasAmountUSD, 0.9)    AS p90_sending_gas_usd,
           max(sending_gasAmountUSD)                   AS max_sending_gas_usd,
           median(receiving_gasAmountUSD)              AS median_receiving_gas_usd
    FROM s
    GROUP BY sample
)
SELECT g.sample,
       g.events,
       r.completed_with_both_usd,
       round(r.median_received_over_sent, 4)          AS median_received_over_sent,
       round(r.p05, 4)                                AS p05_received_over_sent,
       round(r.p95, 4)                                AS p95_received_over_sent,
       round(100.0 * r.share_losing_over_1pct, 1)     AS pct_losing_over_1pct,
       round(100.0 * r.share_losing_over_5pct, 1)     AS pct_losing_over_5pct,
       round(100.0 * r.share_receiving_more, 1)       AS pct_receiving_more,
       g.events_with_gas,
       round(g.median_sending_gas_usd, 4)             AS median_sending_gas_usd,
       round(g.mean_sending_gas_usd, 4)               AS mean_sending_gas_usd,
       round(g.p90_sending_gas_usd, 4)                AS p90_sending_gas_usd,
       round(g.max_sending_gas_usd, 2)                AS max_sending_gas_usd,
       round(g.median_receiving_gas_usd, 4)           AS median_receiving_gas_usd
FROM g_stats g
JOIN r_stats r USING (sample)
ORDER BY g.sample = 'all_2600', g.sample DESC
