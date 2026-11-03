-- 144_status_extension_coverage_by_design_and_chain
-- Question: How many events the status snapshot extension holds per design and
--           source chain, how many were reused from the earlier snapshots, how many were fetched,
--           and how large the population each design samples is.
-- Grain:    one row per (design, source chain) plus an 'all chains' row per design; designs are
--           census_swap_10k, integrator_strata, the overlap (in both) and the union (every row of
--           the snapshot).
-- Definition applied:
--   - census_swap_10k: every transfer with has_source_swaps and amount_usd >= 10,000 (headline
--     USD of transfers_priced); population_rows is that set per chain.
--   - integrator_strata: in_strata = true; population_rows is every swap row per chain.
--   - both: in_census AND in_strata; all: every row of the snapshot (one row per event).
--   - reused_*: the response came from the named earlier raw JSONL (reused_from); fetched_new:
--     reused_from IS NULL, a call made by notebook 07 §4.
--   - events_per_1000_rows: events / population_rows × 1,000.
-- Inputs:   ref_lifi_api_transfer_status_extension (reference data: LI.FI /v1/status);
--           transfers_priced.

WITH pop AS (
    SELECT chain,
           count(*)                                        AS swap_rows,
           count(*) FILTER (WHERE amount_usd >= 10000)     AS swap_rows_10k
    FROM transfers_priced
    WHERE has_source_swaps
    GROUP BY chain
),
ext AS (
    SELECT 'census_swap_10k' AS design, * FROM ref_lifi_api_transfer_status_extension WHERE in_census
    UNION ALL
    SELECT 'integrator_strata', * FROM ref_lifi_api_transfer_status_extension WHERE in_strata
    UNION ALL
    SELECT 'both', * FROM ref_lifi_api_transfer_status_extension WHERE in_census AND in_strata
    UNION ALL
    SELECT 'all', * FROM ref_lifi_api_transfer_status_extension
),
agg AS (
    SELECT design, chain,
           count(*)                                                                    AS events,
           count(DISTINCT tx_hash)                                                     AS distinct_hashes,
           count(*) FILTER (WHERE reused_from = 'lifi_api_transfer_status_sample_2600_raw.jsonl') AS reused_from_2600,
           count(*) FILTER (WHERE reused_from = 'lifi_api_transfer_status_edge_cases_raw.jsonl') AS reused_from_edge_cases,
           count(*) FILTER (WHERE reused_from IS NULL)                                 AS fetched_new,
           count(*) FILTER (WHERE http_status = 200)                                   AS http_200,
           count(*) FILTER (WHERE status = 'DONE' AND substatus = 'COMPLETED')         AS completed,
           count(DISTINCT coalesce(event_integrator, ''))                              AS integrators,
           round(sum(amount_usd_provided), 2)                                          AS amount_usd_provided
    FROM ext
    GROUP BY design, chain
),
with_all AS (
    SELECT * FROM agg
    UNION ALL
    SELECT design, 'all chains', sum(events), sum(distinct_hashes), sum(reused_from_2600), sum(reused_from_edge_cases),
           sum(fetched_new), sum(http_200), sum(completed), NULL, sum(amount_usd_provided)
    FROM agg GROUP BY design
),
pop_all AS (
    SELECT chain, swap_rows, swap_rows_10k FROM pop
    UNION ALL
    SELECT 'all chains', sum(swap_rows), sum(swap_rows_10k) FROM pop
)
SELECT w.design, w.chain,
       CASE WHEN w.design = 'census_swap_10k' THEN p.swap_rows_10k ELSE p.swap_rows END AS population_rows,
       w.events,
       round(1000.0 * w.events / CASE WHEN w.design = 'census_swap_10k' THEN p.swap_rows_10k ELSE p.swap_rows END, 1) AS events_per_1000_rows,
       w.distinct_hashes, w.reused_from_2600, w.reused_from_edge_cases, w.fetched_new, w.http_200, w.completed, w.integrators, w.amount_usd_provided
FROM with_all w
JOIN pop_all p USING (chain)
ORDER BY CASE w.design WHEN 'census_swap_10k' THEN 1 WHEN 'integrator_strata' THEN 2 WHEN 'both' THEN 3 ELSE 4 END,
         CASE WHEN w.chain = 'all chains' THEN 0 ELSE 1 END, w.events DESC
