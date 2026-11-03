-- 58_status_source_steps
-- Question: What source-side steps does LI.FI's status record show for sampled events with
--           and without hasSourceSwaps: none, fee collection only, or a swap or wrap?
-- Grain:    one row per (sample design, hasSourceSwaps), plus the same over both designs
--           (sample = 'all_2600').
-- Definition applied:
--   - Steps: the tools in the API's sending.includedSteps (sending_included_tools, joined by
--     '|'). with_steps: at least one step.
--   - fee_collection_only: every step is 'feeCollection'. with_swap_or_other_step: at least
--     one step that is not 'feeCollection' (a DEX, 'wrapper', 'custom').
--   - pct_fee_collection_only: of the events with steps.
-- Inputs:   ref_lifi_api_transfer_status_sample_2600 (reference data: LI.FI /v1/status,
--           fetched 2026-10-28).

WITH s AS (
    SELECT sample_design, event_hasSourceSwaps,
           CASE WHEN sending_included_tools IS NULL OR sending_included_tools = '' THEN []
                ELSE string_split(sending_included_tools, '|') END AS steps
    FROM ref_lifi_api_transfer_status_sample_2600
),
k AS (
    SELECT *, len(steps) > 0 AS with_steps,
           len(steps) > 0 AND len(list_filter(steps, lambda x: x <> 'feeCollection')) = 0 AS fee_only
    FROM s
)
SELECT CASE WHEN grouping(sample_design) = 1 THEN 'all_2600' ELSE sample_design END        AS sample,
       event_hasSourceSwaps                                                               AS has_source_swaps,
       count(*)                                                                           AS events,
       count(*) FILTER (WHERE with_steps)                                                 AS with_steps,
       count(*) FILTER (WHERE fee_only)                                                   AS fee_collection_only,
       count(*) FILTER (WHERE with_steps AND NOT fee_only)                                AS with_swap_or_other_step,
       round(100.0 * count(*) FILTER (WHERE fee_only) / nullif(count(*) FILTER (WHERE with_steps), 0), 1) AS pct_fee_collection_only
FROM k
GROUP BY GROUPING SETS ((sample_design, event_hasSourceSwaps), (event_hasSourceSwaps))
ORDER BY grouping(sample_design), sample_design DESC, event_hasSourceSwaps
