-- 13_status_time_to_completion_by_bridge
-- Question: How long do sampled transfers take from the source transaction to the
--           destination transaction, by bridge?
-- Grain:    one row per bridge string in the sample, plus a first row for all bridges.
-- Definition applied:
--   - Time to completion: receiving.timestamp - sending.timestamp in seconds, the block
--     timestamps of the two legs as LI.FI's status API reports them, on transfers with
--     substatus COMPLETED only (refunds and partials excluded).
--   - The uniform_* columns use the 2,000 uniform events (sample_design = 'uniform_2000'),
--     the sample that represents the file; the all_* columns pool them with the 600
--     equal-per-chain events.
--   - Percentiles are quantile_cont (linear interpolation).
--   - receiving_before_sending: completed transfers whose destination block timestamp is
--     earlier than the source block timestamp (the two chains' clocks are compared as given).
-- Inputs:   ref_lifi_api_transfer_status_sample_2600 (reference data: LI.FI /v1/status,
--           fetched 2026-10-28).

WITH c AS (
    SELECT coalesce(event_bridge, '(all bridges)')                         AS bridge,
           grouping(event_bridge)                                          AS is_total,
           count(*) FILTER (WHERE sample_design = 'uniform_2000')          AS uniform_completed,
           quantile_cont(receiving_timestamp - sending_timestamp, 0.5)
               FILTER (WHERE sample_design = 'uniform_2000')               AS uniform_median_s,
           quantile_cont(receiving_timestamp - sending_timestamp, 0.9)
               FILTER (WHERE sample_design = 'uniform_2000')               AS uniform_p90_s,
           max(receiving_timestamp - sending_timestamp)
               FILTER (WHERE sample_design = 'uniform_2000')               AS uniform_max_s,
           count(*)                                                        AS all_completed,
           quantile_cont(receiving_timestamp - sending_timestamp, 0.5)     AS all_median_s,
           quantile_cont(receiving_timestamp - sending_timestamp, 0.9)     AS all_p90_s,
           min(receiving_timestamp - sending_timestamp)                    AS all_min_s,
           max(receiving_timestamp - sending_timestamp)                    AS all_max_s,
           count(*) FILTER (WHERE receiving_timestamp < sending_timestamp) AS all_receiving_before_sending
    FROM ref_lifi_api_transfer_status_sample_2600
    WHERE substatus = 'COMPLETED'
    GROUP BY ROLLUP (event_bridge)
)
SELECT bridge,
       uniform_completed,
       uniform_median_s,
       round(uniform_median_s / 60, 1)  AS uniform_median_min,
       round(uniform_p90_s, 1)          AS uniform_p90_s,
       uniform_max_s,
       all_completed,
       all_median_s,
       round(all_median_s / 60, 1)      AS all_median_min,
       round(all_p90_s, 1)              AS all_p90_s,
       all_min_s,
       all_max_s,
       all_receiving_before_sending
FROM c
ORDER BY is_total DESC, all_completed DESC, bridge
