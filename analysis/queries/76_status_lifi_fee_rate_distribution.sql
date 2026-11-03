-- 76_status_lifi_fee_rate_distribution
-- Question: Which LI.FI fee rates do the quotes behind the uniform 2,000 configure, how many
--           transfers carry each, with or without an integrator fee beside it, and under which
--           integrator strings?
-- Grain:    one row per LI.FI rate in basis points, rounded to 0.01 bps, plus one row for the
--           transfers without a LIFI-named line; most transfers first.
-- Definition applied:
--   - Sample: sample_design = 'uniform_2000', every status, all 2,000 events.
--   - LIFI-named line: as 75_status_fee_overall (one per transfer at most). Its `percentage` is
--     the whole line's rate (LI.FI and integrator together); its feeSplit divides it.
--   - LI.FI rate (bps) = 10,000 × percentage × lifiFee / line amount, the latter ratio taken
--     as fee_split_lifi_usd / quote_fee_lifi_usd (both converted at the line's own price, so
--     their ratio is lifiFee / amount). Integrator rate likewise with integratorFee. Rounding
--     to 0.01 bps merges the integer-rounding artefacts of the split (24.997 to 25.00) and keeps
--     4.25 apart from 4.24.
--   - line_rates_bps: the distinct line percentages, in bps, at this LI.FI rate; line_names:
--     the line name with its count; integrators: the raw integrator strings with their count,
--     most first (no normalisation).
--   - pct_of_sampled: of the 2,000, with the Wilson 95% interval (z = 1.96).
--   - sample_usd: the events' amount_usd (headline); fees in USD as in 75_status_fee_overall.
--   - No row here says which rate is a default or a tier: the line names and the integrator
--     strings are the evidence.
-- Inputs:   ref_lifi_api_transfer_status_sample_2600 (reference data: LI.FI /v1/status,
--           fetched 2026-10-28); transfers_priced (amount_usd).

WITH s AS (
    SELECT st.event_integrator,
           coalesce(st.quote_fee_lifi_usd, 0) > 0                                   AS has_line,
           st.quote_fee_names,
           st.quote_fee_lifi_percentages                                            AS line_pct,
           p.amount_usd,
           coalesce(st.fee_split_lifi_usd, 0)                                       AS lifi,
           coalesce(st.fee_split_integrator_usd, 0)                                 AS integ,
           CASE WHEN coalesce(st.quote_fee_lifi_usd, 0) > 0
                THEN round(1e4 * st.quote_fee_lifi_percentages * st.fee_split_lifi_usd / st.quote_fee_lifi_usd, 2) END       AS lifi_rate_bps,
           CASE WHEN coalesce(st.quote_fee_lifi_usd, 0) > 0
                THEN round(1e4 * st.quote_fee_lifi_percentages * st.fee_split_integrator_usd / st.quote_fee_lifi_usd, 2) END AS integ_rate_bps
    FROM ref_lifi_api_transfer_status_sample_2600 st
    JOIN transfers_priced p USING (chain, tx_hash, log_index)
    WHERE st.sample_design = 'uniform_2000'
),
named AS (
    SELECT *,
           CASE WHEN NOT has_line THEN NULL
                WHEN quote_fee_names LIKE '%LIFI Shared Fee%' THEN 'LIFI Shared Fee'
                ELSE 'LIFI Fixed Fee' END AS line_name
    FROM s
),
per_integrator AS (
    SELECT lifi_rate_bps, coalesce(event_integrator, '(empty)') AS integrator, count(*) AS n
    FROM named GROUP BY lifi_rate_bps, integrator
),
integrator_list AS (
    SELECT lifi_rate_bps, string_agg(integrator || ' ' || CAST(n AS VARCHAR), ', ' ORDER BY n DESC, integrator) AS integrators,
           count(*) AS n_integrators
    FROM per_integrator GROUP BY lifi_rate_bps
),
per_name AS (
    SELECT lifi_rate_bps, line_name, count(*) AS n FROM named WHERE has_line GROUP BY lifi_rate_bps, line_name
),
name_list AS (
    SELECT lifi_rate_bps, string_agg(line_name || ' ' || CAST(n AS VARCHAR), ', ' ORDER BY n DESC, line_name) AS line_names
    FROM per_name GROUP BY lifi_rate_bps
),
agg AS (
    SELECT lifi_rate_bps,
           count(*)                                                                    AS transfers,
           count(*) FILTER (WHERE integ > 0)                                            AS with_integrator_fee,
           string_agg(DISTINCT CAST(round(1e4 * line_pct, 2) AS VARCHAR), ', ' ORDER BY CAST(round(1e4 * line_pct, 2) AS VARCHAR)) AS line_rates_bps,
           string_agg(DISTINCT CAST(integ_rate_bps AS VARCHAR), ', ')                   AS integrator_rates_bps,
           sum(amount_usd)                                                             AS sample_usd,
           sum(lifi)                                                                   AS lifi_fee_usd,
           sum(integ)                                                                  AS integrator_fee_usd
    FROM named
    GROUP BY lifi_rate_bps
),
k AS (
    SELECT a.*, transfers * 1.0 / sum(transfers) OVER () AS p, sum(transfers) OVER () AS n, 1.96 AS z
    FROM agg a
)
SELECT CASE WHEN k.lifi_rate_bps IS NULL THEN 'no LIFI-named line' ELSE 'LIFI-named line' END                 AS line,
       k.lifi_rate_bps,
       k.transfers,
       round(100 * k.p, 2)                                                                                    AS pct_of_sampled,
       round(100 * ((k.p + k.z*k.z/(2*k.n)) - k.z * sqrt(k.p*(1-k.p)/k.n + k.z*k.z/(4*k.n*k.n))) / (1 + k.z*k.z/k.n), 2) AS pct_low,
       round(100 * ((k.p + k.z*k.z/(2*k.n)) + k.z * sqrt(k.p*(1-k.p)/k.n + k.z*k.z/(4*k.n*k.n))) / (1 + k.z*k.z/k.n), 2) AS pct_high,
       k.with_integrator_fee,
       k.line_rates_bps,
       k.integrator_rates_bps,
       nl.line_names,
       il.n_integrators,
       round(k.sample_usd, 2)                                                                                 AS sample_usd,
       round(k.lifi_fee_usd, 2)                                                                               AS lifi_fee_usd,
       round(k.integrator_fee_usd, 2)                                                                         AS integrator_fee_usd,
       il.integrators
FROM k
LEFT JOIN name_list nl ON nl.lifi_rate_bps IS NOT DISTINCT FROM k.lifi_rate_bps
LEFT JOIN integrator_list il ON il.lifi_rate_bps IS NOT DISTINCT FROM k.lifi_rate_bps
ORDER BY k.transfers DESC, k.lifi_rate_bps
