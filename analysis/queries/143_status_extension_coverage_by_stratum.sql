-- 143_status_extension_coverage_by_stratum
-- Question: For each integrator stratum of the status snapshot extension: how many
--           swap rows the data holds, how many events were planned, how many the snapshot holds,
--           how many of those were reused from the earlier snapshots rather than fetched, how
--           many are also in the $10k census, and their HTTP statuses.
-- Grain:    one row per raw integrator string with at least one swap row (has_source_swaps), the
--           empty string shown as '(empty)'; largest strata first.
-- Definition applied:
--   - Stratum: the integrator's swap rows (transfers.has_source_swaps = true), the raw string
--     (no normalisation). Planned events: 30 when the integrator has 100 or more swap rows,
--     10 when 10 to 99, every row under 10, drawn systematically over the rows sorted by
--     (destination_chain_id, sending_asset_id, block_time) with seed 20261029 (notebook 07 §3).
--   - events_in_snapshot: rows of ref_lifi_api_transfer_status_extension with in_strata = true
--     for the integrator; in_census_too: those also in the census (in_census = true).
--   - reused_*: rows whose response was taken from lifi_api_transfer_status_sample_2600_raw.jsonl
--     or lifi_api_transfer_status_edge_cases_raw.jsonl (reused_from), not refetched.
--   - lifi_line: quote_fee_lifi_usd > 0, as 75_status_fee_overall.
-- Inputs:   ref_lifi_api_transfer_status_extension (reference data: LI.FI /v1/status, fetched
--           2026-11-01 plus reused 2026-10-28 responses); transfers.

WITH strata AS (
    SELECT coalesce(integrator, '') AS integrator, count(*) AS rows_in_data
    FROM transfers
    WHERE has_source_swaps
    GROUP BY 1
),
snap AS (
    SELECT coalesce(stratum_integrator, '') AS integrator,
           max(stratum_planned)                                                        AS planned,
           count(*)                                                                    AS events_in_snapshot,
           count(*) FILTER (WHERE in_census)                                           AS in_census_too,
           count(*) FILTER (WHERE reused_from = 'lifi_api_transfer_status_sample_2600_raw.jsonl') AS reused_from_2600,
           count(*) FILTER (WHERE reused_from = 'lifi_api_transfer_status_edge_cases_raw.jsonl') AS reused_from_edge_cases,
           count(*) FILTER (WHERE reused_from IS NULL)                                 AS fetched_new,
           count(*) FILTER (WHERE http_status = 200)                                   AS http_200,
           count(*) FILTER (WHERE status = 'DONE' AND substatus = 'COMPLETED')         AS completed,
           count(*) FILTER (WHERE coalesce(quote_fee_lifi_usd, 0) > 0)                 AS with_lifi_line,
           count(DISTINCT event_destinationChainId)                                    AS destination_chains,
           count(DISTINCT event_sendingAssetId)                                        AS sending_tokens,
           count(DISTINCT CAST(block_time AS DATE))                                    AS days
    FROM ref_lifi_api_transfer_status_extension
    WHERE in_strata
    GROUP BY 1
)
SELECT CASE WHEN s.integrator = '' THEN '(empty)' ELSE s.integrator END AS integrator,
       CASE WHEN s.rows_in_data >= 100 THEN '30 of 100+' WHEN s.rows_in_data >= 10 THEN '10 of 10-99' ELSE 'all under 10' END AS tier,
       s.rows_in_data,
       n.planned,
       n.events_in_snapshot,
       n.in_census_too,
       n.reused_from_2600,
       n.reused_from_edge_cases,
       n.fetched_new,
       n.http_200,
       n.completed,
       n.with_lifi_line,
       n.destination_chains,
       n.sending_tokens,
       n.days
FROM strata s
LEFT JOIN snap n USING (integrator)
ORDER BY s.rows_in_data DESC, s.integrator
