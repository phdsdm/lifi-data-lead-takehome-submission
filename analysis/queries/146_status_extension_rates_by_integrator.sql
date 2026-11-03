-- 146_status_extension_rates_by_integrator
-- Question: Per integrator, which LI.FI rates and which integrator rates the quotes in the status
--           snapshot extension carry, how many events carry each, and whether the
--           uniform 2,000 showed the same LI.FI rates.
-- Grain:    one row per raw integrator string in the extension snapshot (census and strata rows
--           together, one row per event), the empty string shown as '(empty)'; most swap rows in
--           the data first.
-- Definition applied:
--   - LIFI-named line: quote_fee_lifi_usd > 0 (as 75_status_fee_overall), at most one per quote
--     in the earlier snapshots; rows whose quote_fee_lifi_percentages holds more than one value
--     (a '|') are counted in multi_line_rows and carry no rate.
--   - LI.FI rate (bps) = 10,000 × line percentage × fee_split_lifi_usd / quote_fee_lifi_usd,
--     rounded to 0.01 bps, as 76_status_lifi_fee_rate_distribution; integrator rate likewise with fee_split_integrator_usd.
--   - lifi_rates_bps / integrator_rates_bps: 'rate:events' pairs, most events first; 'none' for
--     events without a LIFI-named line. n_lifi_rates counts the distinct rates on lines only.
--   - uniform_2000_lifi_rates: the same list for the integrator's events in the uniform 2,000
--     of lifi_api_transfer_status_sample_2600.csv (sample_design = 'uniform_2000').
--   - rows_in_data: the integrator's swap rows (has_source_swaps) in transfers.
-- Inputs:   ref_lifi_api_transfer_status_extension, ref_lifi_api_transfer_status_sample_2600
--           (reference data: LI.FI /v1/status); transfers.

WITH base AS (
    SELECT coalesce(event_integrator, '') AS integrator,
           coalesce(quote_fee_lifi_usd, 0) > 0                                    AS has_line,
           CAST(quote_fee_lifi_percentages AS VARCHAR)                             AS pct_text,
           try_cast(CAST(quote_fee_lifi_percentages AS VARCHAR) AS DOUBLE)         AS pct,
           quote_fee_lifi_usd, fee_split_lifi_usd, fee_split_integrator_usd, quote_fee_names, amount_usd_provided
    FROM ref_lifi_api_transfer_status_extension
),
rated AS (
    SELECT *,
           CASE WHEN has_line AND pct IS NOT NULL THEN round(1e4 * pct * fee_split_lifi_usd / quote_fee_lifi_usd, 2) END       AS lifi_rate_bps,
           CASE WHEN has_line AND pct IS NOT NULL THEN round(1e4 * pct * fee_split_integrator_usd / quote_fee_lifi_usd, 2) END AS integ_rate_bps,
           CASE WHEN NOT has_line THEN 'none' WHEN quote_fee_names LIKE '%LIFI Shared Fee%' THEN 'Shared' ELSE 'Fixed' END     AS line_kind
    FROM base
),
lifi_counts AS (
    SELECT integrator, coalesce(CAST(lifi_rate_bps AS VARCHAR), 'none') AS rate, count(*) AS n FROM rated GROUP BY 1, 2
),
integ_counts AS (
    SELECT integrator, coalesce(CAST(integ_rate_bps AS VARCHAR), 'none') AS rate, count(*) AS n FROM rated GROUP BY 1, 2
),
kind_counts AS (
    SELECT integrator, line_kind, count(*) AS n FROM rated GROUP BY 1, 2
),
per_integrator AS (
    SELECT integrator,
           count(*)                                                     AS events,
           count(*) FILTER (WHERE has_line)                             AS with_lifi_line,
           count(*) FILTER (WHERE has_line AND pct_text LIKE '%|%')     AS multi_line_rows,
           count(DISTINCT lifi_rate_bps)                                AS n_lifi_rates,
           count(DISTINCT integ_rate_bps)                               AS n_integrator_rates,
           round(sum(amount_usd_provided), 2)                           AS amount_usd_provided,
           round(sum(fee_split_lifi_usd), 2)                            AS lifi_fee_usd,
           round(sum(fee_split_integrator_usd), 2)                      AS integrator_fee_usd
    FROM rated GROUP BY 1
),
uniform AS (
    SELECT coalesce(event_integrator, '') AS integrator,
           CASE WHEN coalesce(quote_fee_lifi_usd, 0) > 0
                THEN CAST(round(1e4 * try_cast(CAST(quote_fee_lifi_percentages AS VARCHAR) AS DOUBLE) * fee_split_lifi_usd / quote_fee_lifi_usd, 2) AS VARCHAR)
                ELSE 'none' END AS rate
    FROM ref_lifi_api_transfer_status_sample_2600
    WHERE sample_design = 'uniform_2000'
),
uniform_counts AS (SELECT integrator, rate, count(*) AS n FROM uniform GROUP BY 1, 2),
rows_in_data AS (SELECT coalesce(integrator, '') AS integrator, count(*) AS rows_in_data FROM transfers WHERE has_source_swaps GROUP BY 1)
SELECT CASE WHEN p.integrator = '' THEN '(empty)' ELSE p.integrator END AS integrator,
       d.rows_in_data,
       p.events, p.with_lifi_line, p.multi_line_rows,
       p.n_lifi_rates,
       (SELECT string_agg(rate || ':' || CAST(n AS VARCHAR), ', ' ORDER BY n DESC, rate) FROM lifi_counts c WHERE c.integrator = p.integrator)   AS lifi_rates_bps,
       p.n_integrator_rates,
       (SELECT string_agg(rate || ':' || CAST(n AS VARCHAR), ', ' ORDER BY n DESC, rate) FROM integ_counts c WHERE c.integrator = p.integrator)  AS integrator_rates_bps,
       (SELECT string_agg(line_kind || ':' || CAST(n AS VARCHAR), ', ' ORDER BY n DESC, line_kind) FROM kind_counts c WHERE c.integrator = p.integrator) AS line_kinds,
       (SELECT string_agg(rate || ':' || CAST(n AS VARCHAR), ', ' ORDER BY n DESC, rate) FROM uniform_counts c WHERE c.integrator = p.integrator) AS uniform_2000_lifi_rates,
       p.amount_usd_provided, p.lifi_fee_usd, p.integrator_fee_usd
FROM per_integrator p
LEFT JOIN rows_in_data d USING (integrator)
ORDER BY d.rows_in_data DESC NULLS LAST, p.integrator
