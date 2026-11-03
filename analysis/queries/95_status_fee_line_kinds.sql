-- 95_status_fee_line_kinds
-- Question: What kinds of LIFI-named fee line do the quotes behind the uniform 2,000 carry
--           (line name and recipient type), which LI.FI and line rates does each kind carry,
--           does each line split exactly into a LI.FI part and an integrator part, and under
--           which integrator strings?
-- Grain:    one row per (line name, recipient types), most lines first, then a total row.
-- Definition applied:
--   - Fee lines: ref_lifi_api_transfer_status_fee_lines (derived from the raw
--     status JSONLs), snapshot 'sample_2600', sample_design 'uniform_2000', source 'quote' (the
--     quote's estimate.feeCosts), name starting with 'LIFI' (as 43_status_fee_lines_by_integrator).
--   - recipient_types: the distinct `type` of the line's feeSplit recipients (DYNAMIC, FIXED,
--     SHARED), joined by '|'.
--   - LI.FI rate (bps) = 10,000 × percentage × lifi_fee / amount, in token units (exact
--     integers, not USD); integrator rate likewise; line rate = 10,000 × percentage. Rates are
--     rounded to 0.01 bps and listed with their line counts, most first.
--   - split_adds_up: lines whose lifi_fee + integrator_fee equals amount.
--   - transfers_with_more_than_one_line: transfers carrying two or more LIFI-named lines.
--   - integrators: response_integrator (the API's metadata.integrator; raw strings, normalisation not
--     applied) with its line count, most first; the empty string loads as NULL and shows as
--     '(empty)'.
-- Inputs:   ref_lifi_api_transfer_status_fee_lines (reference data: LI.FI /v1/status, fetched
--           2026-10-28; derived offline).

WITH l AS (
    SELECT f.chain, f.tx_hash, f.log_index, f.name, f.percentage, f.amount, f.lifi_fee, f.integrator_fee,
           coalesce(f.response_integrator, '(empty)')                                                         AS integrator,
           array_to_string(list_sort(list_distinct(list_filter([f.lifi_recipient_type, f.integrator_recipient_type], lambda x: x IS NOT NULL))), '|') AS recipient_types,
           round(1e4 * f.percentage * CAST(f.lifi_fee AS DOUBLE) / CAST(f.amount AS DOUBLE), 2)              AS lifi_bps,
           round(1e4 * f.percentage * CAST(f.integrator_fee AS DOUBLE) / CAST(f.amount AS DOUBLE), 2)        AS integ_bps,
           round(1e4 * f.percentage, 2)                                                                       AS line_bps
    FROM ref_lifi_api_transfer_status_fee_lines f
    WHERE f.snapshot = 'sample_2600' AND f.sample_design = 'uniform_2000' AND f.source = 'quote' AND f.name LIKE 'LIFI%'
),
labelled AS (
    SELECT 0 AS is_total, name, recipient_types, * EXCLUDE (name, recipient_types) FROM l
    UNION ALL
    SELECT 1, '(all LIFI-named lines)', '(all)', * EXCLUDE (name, recipient_types) FROM l
),
rate_counts AS (
    SELECT is_total, name, recipient_types, 'lifi' AS what, lifi_bps AS v, count(*) AS n FROM labelled GROUP BY ALL
    UNION ALL SELECT is_total, name, recipient_types, 'integ', integ_bps, count(*) FROM labelled GROUP BY ALL
    UNION ALL SELECT is_total, name, recipient_types, 'line', line_bps, count(*) FROM labelled GROUP BY ALL
),
rate_lists AS (
    SELECT is_total, name, recipient_types,
           string_agg(CAST(v AS VARCHAR) || ' ×' || CAST(n AS VARCHAR), ', ' ORDER BY n DESC, v) FILTER (WHERE what = 'lifi')  AS lifi_bps_seen,
           string_agg(CAST(v AS VARCHAR) || ' ×' || CAST(n AS VARCHAR), ', ' ORDER BY n DESC, v) FILTER (WHERE what = 'integ') AS integrator_bps_seen,
           string_agg(CAST(v AS VARCHAR) || ' ×' || CAST(n AS VARCHAR), ', ' ORDER BY n DESC, v) FILTER (WHERE what = 'line')  AS line_bps_seen
    FROM rate_counts GROUP BY is_total, name, recipient_types
),
integ_lists AS (
    SELECT is_total, name, recipient_types,
           count(*) AS n_integrators,
           string_agg(integrator || ' ' || CAST(n AS VARCHAR), ', ' ORDER BY n DESC, integrator) AS integrators
    FROM (SELECT is_total, name, recipient_types, integrator, count(*) AS n FROM labelled GROUP BY ALL)
    GROUP BY is_total, name, recipient_types
),
per_transfer AS (
    SELECT chain, tx_hash, log_index, count(*) AS n FROM l GROUP BY ALL
),
agg AS (
    SELECT is_total, name, recipient_types,
           count(*)                                                        AS lines,
           count(DISTINCT (chain, tx_hash, log_index))                     AS transfers,
           count(*) FILTER (WHERE lifi_fee + integrator_fee = amount)      AS split_adds_up,
           count(*) FILTER (WHERE lifi_fee > 0)                            AS with_lifi_part,
           count(*) FILTER (WHERE integrator_fee > 0)                      AS with_integrator_part
    FROM labelled GROUP BY is_total, name, recipient_types
)
SELECT a.name                                                              AS line_name,
       a.recipient_types,
       a.lines,
       a.transfers,
       CASE WHEN a.is_total = 1 THEN (SELECT count(*) FROM per_transfer WHERE n > 1) END AS transfers_with_more_than_one_line,
       a.split_adds_up,
       a.with_lifi_part,
       a.with_integrator_part,
       r.lifi_bps_seen,
       r.integrator_bps_seen,
       r.line_bps_seen,
       i.n_integrators,
       i.integrators
FROM agg a
JOIN rate_lists r USING (is_total, name, recipient_types)
JOIN integ_lists i USING (is_total, name, recipient_types)
ORDER BY a.is_total, a.lines DESC, a.name, a.recipient_types
