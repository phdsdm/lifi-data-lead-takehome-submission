-- 124_partner_time_to_completion
-- Question: How long do each mock-up partner's completed transfers take from the
--           source block to the destination block, overall and by tool, against all sampled
--           transfers?
-- Grain:    section 'partner': one row per (partner, sample) for base-app, phantom,
--           metamask-bridge, rabbykmsv2 and '(all sampled)', samples pooled_2600 and
--           uniform_2000; section 'partner × tool': one row per (partner, tool) with at least
--           one completed transfer, pooled_2600 only.
-- Definition applied (task_2.md metric 3):
--   - Time to completion: receiving_timestamp - sending_timestamp in seconds, the block
--     timestamps of the two legs as /v1/status reports them, on substatus COMPLETED only.
--   - A negative value (the destination block timestamp earlier than the source one, from the
--     two chains' clocks) is floored at 0 before the percentiles and counted in negatives.
--     13_status_time_to_completion_by_bridge gives the market by bridge without the floor; its
--     all_receiving_before_sending is the same count.
--   - Percentiles are quantile_cont. Partner as in 123_partner_completion_rate (the map's
--     partner of the event's integrator string, class partner).
--   - tool: the status response's tool. market_completed / market_median_s / market_p90_s: all
--     sampled completed transfers of that tool, pooled, floored, for the comparison column.
--   - publishable: at least 30 completed transfers in the cell, a reading threshold, not a definition.
-- Inputs:   ref_lifi_api_transfer_status_sample_2600 (reference data: LI.FI /v1/status, fetched
--           2026-10-28), ref_integrator_map.

WITH mock(partner, ord) AS (
    VALUES ('base-app', 1), ('phantom', 2), ('metamask-bridge', 3), ('rabbykmsv2', 4)
),
s AS (
    SELECT st.sample_design, st.tool, m.partner, m.class,
           st.receiving_timestamp - st.sending_timestamp              AS raw_s,
           greatest(0, st.receiving_timestamp - st.sending_timestamp) AS secs
    FROM ref_lifi_api_transfer_status_sample_2600 st
    LEFT JOIN ref_integrator_map m ON coalesce(m.integrator, '') = st.event_integrator
    WHERE st.substatus = 'COMPLETED'
),
labelled AS (
    SELECT mk.ord, mk.partner AS label, 'pooled_2600' AS sample, s.* FROM s JOIN mock mk ON mk.partner = s.partner AND s.class = 'partner'
    UNION ALL
    SELECT mk.ord, mk.partner, 'uniform_2000', s.* FROM s JOIN mock mk ON mk.partner = s.partner AND s.class = 'partner' WHERE s.sample_design = 'uniform_2000'
    UNION ALL SELECT 5, '(all sampled)', 'pooled_2600', * FROM s
    UNION ALL SELECT 5, '(all sampled)', 'uniform_2000', * FROM s WHERE sample_design = 'uniform_2000'
),
by_partner AS (
    SELECT ord, label, sample, '(all tools)' AS tool,
           count(*) AS completed,
           quantile_cont(secs, 0.5) AS median_s, quantile_cont(secs, 0.9) AS p90_s, quantile_cont(secs, 0.99) AS p99_s,
           max(secs) AS max_s, count(*) FILTER (WHERE raw_s < 0) AS negatives, min(raw_s) AS min_raw_s,
           NULL::BIGINT AS market_completed, NULL::DOUBLE AS market_median_s, NULL::DOUBLE AS market_p90_s
    FROM labelled GROUP BY ord, label, sample
),
market_tool AS (
    SELECT tool, count(*) AS n, quantile_cont(secs, 0.5) AS med, quantile_cont(secs, 0.9) AS p90 FROM s GROUP BY tool
),
by_tool AS (
    SELECT l.ord, l.label, 'pooled_2600', l.tool,
           count(*), quantile_cont(l.secs, 0.5), quantile_cont(l.secs, 0.9), quantile_cont(l.secs, 0.99),
           max(l.secs), count(*) FILTER (WHERE l.raw_s < 0), min(l.raw_s),
           any_value(mt.n), any_value(mt.med), any_value(mt.p90)
    FROM labelled l JOIN market_tool mt USING (tool)
    WHERE l.sample = 'pooled_2600' AND l.ord <= 4
    GROUP BY l.ord, l.label, l.tool
)
SELECT CASE WHEN tool = '(all tools)' THEN 'partner' ELSE 'partner × tool' END AS section,
       label                       AS partner,
       sample,
       tool,
       completed,
       completed >= 30             AS publishable,
       round(median_s, 1)          AS median_s,
       round(p90_s, 1)             AS p90_s,
       round(p99_s, 1)             AS p99_s,
       max_s,
       round(max_s / 60.0, 1)      AS max_min,
       negatives,
       min_raw_s,
       market_completed,
       round(market_median_s, 1)   AS market_median_s,
       round(market_p90_s, 1)      AS market_p90_s
FROM (SELECT * FROM by_partner UNION ALL SELECT * FROM by_tool)
ORDER BY tool <> '(all tools)', ord, sample, completed DESC, tool
