-- 145_status_extension_status_and_fee_line_by_design
-- Question: In the status snapshot extension, per design: how the events split by status
--           and substatus, how many carry a quote, a LIFI-named fee line, a LI.FI fee above zero
--           and an integrator fee above zero.
-- Grain:    one row per (design, status, substatus) plus a total row per design; designs are
--           census_swap_10k (in_census), integrator_strata (in_strata) and all (every row).
-- Definition applied:
--   - LIFI-named line: quote_fee_lifi_usd > 0 (a line whose name starts with LIFI, as
--     75_status_fee_overall); lifi_fee_gt_0: fee_split_lifi_usd > 0; integrator_fee_gt_0:
--     fee_split_integrator_usd > 0; with_quote: quote_tool IS NOT NULL.
--   - A row in both designs is counted under each.
--   - pct_of_design: events / the design's total × 100.
-- Inputs:   ref_lifi_api_transfer_status_extension (reference data: LI.FI /v1/status).

WITH ext AS (
    SELECT 'census_swap_10k' AS design, * FROM ref_lifi_api_transfer_status_extension WHERE in_census
    UNION ALL
    SELECT 'integrator_strata', * FROM ref_lifi_api_transfer_status_extension WHERE in_strata
    UNION ALL
    SELECT 'all', * FROM ref_lifi_api_transfer_status_extension
),
agg AS (
    SELECT design, coalesce(status, '(none)') AS status, coalesce(substatus, '(none)') AS substatus,
           count(*)                                                        AS events,
           count(*) FILTER (WHERE http_status = 200)                       AS http_200,
           count(*) FILTER (WHERE quote_tool IS NOT NULL)                  AS with_quote,
           count(*) FILTER (WHERE coalesce(quote_fee_lifi_usd, 0) > 0)     AS with_lifi_line,
           count(*) FILTER (WHERE coalesce(fee_split_lifi_usd, 0) > 0)     AS lifi_fee_gt_0,
           count(*) FILTER (WHERE coalesce(fee_split_integrator_usd, 0) > 0) AS integrator_fee_gt_0,
           count(*) FILTER (WHERE batch_n IS NOT NULL)                     AS with_batch_status,
           round(sum(amount_usd_provided), 2)                              AS amount_usd_provided
    FROM ext
    GROUP BY 1, 2, 3
),
tot AS (
    SELECT design, 'all' AS status, 'all' AS substatus, sum(events), sum(http_200), sum(with_quote), sum(with_lifi_line),
           sum(lifi_fee_gt_0), sum(integrator_fee_gt_0), sum(with_batch_status), sum(amount_usd_provided)
    FROM agg GROUP BY design
),
u AS (SELECT * FROM agg UNION ALL SELECT * FROM tot)
SELECT design, status, substatus, events,
       round(100.0 * events / sum(events) FILTER (WHERE status = 'all') OVER (PARTITION BY design), 2) AS pct_of_design,
       http_200, with_quote, with_lifi_line, lifi_fee_gt_0, integrator_fee_gt_0, with_batch_status, amount_usd_provided
FROM u
ORDER BY CASE design WHEN 'census_swap_10k' THEN 1 WHEN 'integrator_strata' THEN 2 ELSE 3 END,
         CASE WHEN status = 'all' THEN 0 ELSE 1 END, events DESC
