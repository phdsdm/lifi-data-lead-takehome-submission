-- 96_status_fee_line_lifi_share_by_kind
-- Question: Within each kind of LIFI-named line, what share of the line goes to LI.FI, at which
--           LI.FI rates, and for which integrator strings: which lines pay LI.FI alone, which pay
--           it nothing, and which split?
-- Grain:    one row per (recipient types, LI.FI share of the line rounded to 0.001), within a
--           kind most lines first.
-- Definition applied:
--   - Lines: the uniform 2,000's quote lines named 'LIFI…', as 95_status_fee_line_kinds.
--   - lifi_share_of_line = lifi_fee / amount, in token units (exact integers), rounded to 0.001:
--     1 means the line pays LI.FI alone, 0 the integrator alone.
--   - lifi_bps_seen and line_bps_seen: the LI.FI rate (10,000 × percentage × share) and the
--     line's rate (10,000 × percentage), rounded to 0.01 bps, with their line counts.
--   - integrators: response_integrator with its line count (raw strings; '(empty)' for the
--     empty string, which loads as NULL).
-- Inputs:   ref_lifi_api_transfer_status_fee_lines (reference data: LI.FI /v1/status, fetched
--           2026-10-28; derived offline).

WITH l AS (
    SELECT coalesce(f.response_integrator, '(empty)')                                                         AS integrator,
           array_to_string(list_sort(list_distinct(list_filter([f.lifi_recipient_type, f.integrator_recipient_type], lambda x: x IS NOT NULL))), '|') AS recipient_types,
           round(CAST(f.lifi_fee AS DOUBLE) / CAST(f.amount AS DOUBLE), 3)                                    AS lifi_share,
           round(1e4 * f.percentage * CAST(f.lifi_fee AS DOUBLE) / CAST(f.amount AS DOUBLE), 2)              AS lifi_bps,
           round(1e4 * f.percentage, 2)                                                                       AS line_bps
    FROM ref_lifi_api_transfer_status_fee_lines f
    WHERE f.snapshot = 'sample_2600' AND f.sample_design = 'uniform_2000' AND f.source = 'quote' AND f.name LIKE 'LIFI%'
),
rate_counts AS (
    SELECT recipient_types, lifi_share, 'lifi' AS what, lifi_bps AS v, count(*) AS n FROM l GROUP BY ALL
    UNION ALL SELECT recipient_types, lifi_share, 'line', line_bps, count(*) FROM l GROUP BY ALL
),
rate_lists AS (
    SELECT recipient_types, lifi_share,
           string_agg(CAST(v AS VARCHAR) || ' ×' || CAST(n AS VARCHAR), ', ' ORDER BY n DESC, v) FILTER (WHERE what = 'lifi') AS lifi_bps_seen,
           string_agg(CAST(v AS VARCHAR) || ' ×' || CAST(n AS VARCHAR), ', ' ORDER BY n DESC, v) FILTER (WHERE what = 'line') AS line_bps_seen
    FROM rate_counts GROUP BY recipient_types, lifi_share
),
integ_lists AS (
    SELECT recipient_types, lifi_share,
           string_agg(integrator || ' ' || CAST(n AS VARCHAR), ', ' ORDER BY n DESC, integrator) AS integrators
    FROM (SELECT recipient_types, lifi_share, integrator, count(*) AS n FROM l GROUP BY ALL)
    GROUP BY recipient_types, lifi_share
)
SELECT l.recipient_types,
       l.lifi_share                AS lifi_share_of_line,
       count(*)                    AS lines,
       any_value(r.lifi_bps_seen)  AS lifi_bps_seen,
       any_value(r.line_bps_seen)  AS line_bps_seen,
       any_value(i.integrators)    AS integrators
FROM l
JOIN rate_lists r USING (recipient_types, lifi_share)
JOIN integ_lists i USING (recipient_types, lifi_share)
GROUP BY l.recipient_types, l.lifi_share
ORDER BY l.recipient_types, count(*) DESC, l.lifi_share
