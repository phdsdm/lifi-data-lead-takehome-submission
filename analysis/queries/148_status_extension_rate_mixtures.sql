-- 148_status_extension_rate_mixtures
-- Question: For the integrators whose quotes in the status snapshot extension carry more
--           than one LI.FI rate or more than one integrator rate: how the events split by rate,
--           and over which destination chains, sending tokens, days and sizes each rate appears.
-- Grain:    one row per (integrator, LI.FI rate, integrator rate, line kind) for integrators with
--           two or more distinct LI.FI rates or two or more distinct integrator rates on their
--           LIFI-named lines; 'none' is the events without a line. Most swap rows in the data
--           first, then most events.
-- Definition applied:
--   - Rates as 146_status_extension_rates_by_integrator (line percentage × feeSplit part / line
--     amount, in bps, rounded to 0.01); rows with more than one LIFI-named line carry no rate
--     and are excluded here.
--   - destination_chains, sending_tokens, days: distinct event_destinationChainId,
--     event_sendingAssetId and dates of block_time among the events at that rate; amount_usd_min
--     and _max: the provided-feed USD range (amount_usd_provided, NULL when unpriced).
-- Inputs:   ref_lifi_api_transfer_status_extension (reference data: LI.FI /v1/status); transfers.

WITH base AS (
    SELECT coalesce(event_integrator, '') AS integrator,
           coalesce(quote_fee_lifi_usd, 0) > 0                                    AS has_line,
           try_cast(CAST(quote_fee_lifi_percentages AS VARCHAR) AS DOUBLE)         AS pct,
           quote_fee_lifi_usd, fee_split_lifi_usd, fee_split_integrator_usd, quote_fee_names,
           event_destinationChainId, event_sendingAssetId, CAST(block_time AS DATE) AS day, amount_usd_provided, in_census
    FROM ref_lifi_api_transfer_status_extension
),
rated AS (
    SELECT *,
           CASE WHEN has_line AND pct IS NOT NULL THEN round(1e4 * pct * fee_split_lifi_usd / quote_fee_lifi_usd, 2) END       AS lifi_rate_bps,
           CASE WHEN has_line AND pct IS NOT NULL THEN round(1e4 * pct * fee_split_integrator_usd / quote_fee_lifi_usd, 2) END AS integ_rate_bps,
           CASE WHEN NOT has_line THEN 'none' WHEN quote_fee_names LIKE '%LIFI Shared Fee%' THEN 'Shared' ELSE 'Fixed' END     AS line_kind
    FROM base
    WHERE NOT has_line OR pct IS NOT NULL
),
mixed AS (
    SELECT integrator
    FROM rated
    GROUP BY integrator
    HAVING count(DISTINCT lifi_rate_bps) >= 2 OR count(DISTINCT integ_rate_bps) >= 2
),
rows_in_data AS (SELECT coalesce(integrator, '') AS integrator, count(*) AS rows_in_data FROM transfers WHERE has_source_swaps GROUP BY 1)
SELECT CASE WHEN r.integrator = '' THEN '(empty)' ELSE r.integrator END AS integrator,
       d.rows_in_data,
       r.lifi_rate_bps,
       r.integ_rate_bps                                   AS integrator_rate_bps,
       r.line_kind,
       count(*)                                           AS events,
       count(*) FILTER (WHERE r.in_census)                AS in_census,
       count(DISTINCT r.event_destinationChainId)         AS destination_chains,
       count(DISTINCT r.event_sendingAssetId)             AS sending_tokens,
       count(DISTINCT r.day)                              AS days,
       round(min(r.amount_usd_provided), 2)               AS amount_usd_min,
       round(max(r.amount_usd_provided), 2)               AS amount_usd_max
FROM rated r
JOIN mixed m USING (integrator)
LEFT JOIN rows_in_data d USING (integrator)
GROUP BY 1, 2, 3, 4, 5
ORDER BY d.rows_in_data DESC NULLS LAST, 1, events DESC, r.lifi_rate_bps NULLS LAST, r.integ_rate_bps NULLS LAST
