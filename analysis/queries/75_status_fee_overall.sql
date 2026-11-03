-- 75_status_fee_overall
-- Question: In the quotes behind the uniform 2,000, what share of transfers carries a LI.FI fee
--           and an integrator fee, and what are the two fees as a share of the transfer's USD,
--           overall, on bridge-volume rows, with and without a source swap, and on same-chain
--           rows?
-- Grain:    one row per group (5): all 2,000 sampled events; the 1,990 bridge-volume rows; those
--           with hasSourceSwaps and those without; the 10 same-chain *Dex rows.
-- Definition applied:
--   - Sample: sample_design = 'uniform_2000' (a uniform random draw from the file),
--     every status. The edge cases are not a random sample and are left out.
--   - Fee lines (as 43_status_fee_lines_by_integrator): the quote's fee lines whose name starts
--     with "LIFI" (one per transfer at most). LI.FI fee: their feeSplit.lifiFee
--     (fee_split_lifi_usd); integrator fee: feeSplit.integratorFee (fee_split_integrator_usd);
--     both in USD at the line's own amountUSD / amount. A transfer without such a line has
--     both fees 0. Other lines (bridge, relayer, gas): quote_fee_other_usd. The quote is what
--     was offered at request time, not what was collected.
--   - Denominator: the sampled event's amount_usd (headline, from transfers_priced), the
--     column file volume is measured in, so a rate here applies to file volume. The *_api_bps
--     columns use the API's sending_amountUSD instead, as query 43 does.
--   - bps = 10,000 × sum(fee) / sum(amount_usd) over the group: a ratio estimate. low/high: its
--     95% interval, ratio ± 1.96 × SE, SE = sqrt(n / (n - 1) × sum((fee - ratio × amount_usd)²))
--     / sum(amount_usd) (linearisation; normal approximation, which a sample this skewed strains). Floored at 0.
--   - Shares of transfers: of sampled events, with the Wilson 95% interval (z = 1.96).
--   - mean_lifi_rate_bps: the unweighted mean over transfers of the LI.FI rate the line
--     configures (percentage × lifiFee / line amount; 0 without a line).
--   - Bridge-volume rows and same-chain rows as in 65_started_volume.
-- Inputs:   ref_lifi_api_transfer_status_sample_2600 (reference data: LI.FI /v1/status,
--           fetched 2026-10-28); transfers_priced (amount_usd).

WITH source_ids(chain, source_chain_id) AS (
    VALUES ('ethereum', 1), ('optimism', 10), ('bnb', 56), ('polygon', 137), ('base', 8453), ('arbitrum', 42161)
),
s AS (
    SELECT p.amount_usd                                                         AS x,
           st.sending_amountUSD                                                 AS x_api,
           coalesce(st.fee_split_lifi_usd, 0)                                   AS lifi,
           coalesce(st.fee_split_integrator_usd, 0)                             AS integ,
           coalesce(st.quote_fee_other_usd, 0)                                  AS other,
           st.quote_tool IS NOT NULL                                            AS has_quote,
           coalesce(st.quote_fee_lifi_usd, 0) > 0                               AS has_line,
           CASE WHEN coalesce(st.quote_fee_lifi_usd, 0) > 0
                THEN 1e4 * st.quote_fee_lifi_percentages * st.fee_split_lifi_usd / st.quote_fee_lifi_usd
                ELSE 0 END                                                      AS lifi_rate_bps,
           p.destination_chain_id = si.source_chain_id                          AS same_chain,
           st.event_hasSourceSwaps                                              AS source_swap
    FROM ref_lifi_api_transfer_status_sample_2600 st
    JOIN transfers_priced p USING (chain, tx_hash, log_index)
    JOIN source_ids si ON si.chain = st.chain
    WHERE st.sample_design = 'uniform_2000'
),
labelled AS (
    SELECT 1 AS ord, 'all sampled (uniform 2,000)' AS grp, * FROM s
    UNION ALL SELECT 2, 'bridge-volume rows', * FROM s WHERE NOT same_chain
    UNION ALL SELECT 3, 'bridge-volume rows with hasSourceSwaps', * FROM s WHERE NOT same_chain AND source_swap
    UNION ALL SELECT 4, 'bridge-volume rows without hasSourceSwaps', * FROM s WHERE NOT same_chain AND NOT source_swap
    UNION ALL SELECT 5, 'same-chain *Dex rows', * FROM s WHERE same_chain
),
ratios AS (
    SELECT ord, grp, sum(lifi) / sum(x) AS r_lifi, sum(integ) / sum(x) AS r_integ
    FROM labelled GROUP BY ord, grp
),
agg AS (
    SELECT l.ord, l.grp,
           count(*)                                          AS n,
           count(*) FILTER (WHERE l.has_quote)               AS with_quote,
           count(*) FILTER (WHERE l.has_line)                AS with_line,
           count(*) FILTER (WHERE l.lifi > 0)                AS with_lifi_fee,
           count(*) FILTER (WHERE l.integ > 0)               AS with_integ_fee,
           sum(l.x)                                          AS sx,
           sum(l.x_api)                                      AS sx_api,
           sum(l.lifi)                                       AS s_lifi,
           sum(l.integ)                                      AS s_integ,
           sum(l.other)                                      AS s_other,
           avg(l.lifi_rate_bps)                              AS mean_rate,
           any_value(r.r_lifi)                               AS r_lifi,
           any_value(r.r_integ)                              AS r_integ,
           sum(power(l.lifi - r.r_lifi * l.x, 2))            AS e2_lifi,
           sum(power(l.integ - r.r_integ * l.x, 2))          AS e2_integ
    FROM labelled l
    JOIN ratios r USING (ord, grp)
    GROUP BY l.ord, l.grp
),
k AS (
    SELECT *,
           1.96 AS z,
           with_line * 1.0 / n       AS p_line,
           with_lifi_fee * 1.0 / n   AS p_lifi,
           with_integ_fee * 1.0 / n  AS p_integ,
           CASE WHEN n > 1 THEN sqrt(n / (n - 1.0) * e2_lifi) / sx END  AS se_lifi,
           CASE WHEN n > 1 THEN sqrt(n / (n - 1.0) * e2_integ) / sx END AS se_integ
    FROM agg
)
SELECT grp,
       n                                                                                                AS sampled,
       with_quote,
       with_line                                                                                        AS with_lifi_named_line,
       round(100 * p_line, 2)                                                                           AS pct_with_line,
       round(100 * ((p_line + z*z/(2*n)) - z * sqrt(p_line*(1-p_line)/n + z*z/(4*n*n))) / (1 + z*z/n), 2) AS pct_with_line_low,
       round(100 * ((p_line + z*z/(2*n)) + z * sqrt(p_line*(1-p_line)/n + z*z/(4*n*n))) / (1 + z*z/n), 2) AS pct_with_line_high,
       with_lifi_fee,
       round(100 * p_lifi, 2)                                                                           AS pct_with_lifi_fee,
       round(100 * ((p_lifi + z*z/(2*n)) - z * sqrt(p_lifi*(1-p_lifi)/n + z*z/(4*n*n))) / (1 + z*z/n), 2) AS pct_with_lifi_fee_low,
       round(100 * ((p_lifi + z*z/(2*n)) + z * sqrt(p_lifi*(1-p_lifi)/n + z*z/(4*n*n))) / (1 + z*z/n), 2) AS pct_with_lifi_fee_high,
       with_integ_fee                                                                                   AS with_integrator_fee,
       n - with_integ_fee                                                                               AS without_integrator_fee,
       round(100 * p_integ, 2)                                                                          AS pct_with_integrator_fee,
       round(100 * ((p_integ + z*z/(2*n)) - z * sqrt(p_integ*(1-p_integ)/n + z*z/(4*n*n))) / (1 + z*z/n), 2) AS pct_with_integrator_fee_low,
       round(100 * ((p_integ + z*z/(2*n)) + z * sqrt(p_integ*(1-p_integ)/n + z*z/(4*n*n))) / (1 + z*z/n), 2) AS pct_with_integrator_fee_high,
       round(sx, 2)                                                                                     AS sample_usd,
       round(s_lifi, 2)                                                                                 AS lifi_fee_usd,
       round(s_integ, 2)                                                                                AS integrator_fee_usd,
       round(s_other, 2)                                                                                AS other_lines_usd,
       round(1e4 * r_lifi, 3)                                                                           AS lifi_bps,
       round(greatest(0, 1e4 * (r_lifi - 1.96 * se_lifi)), 3)                                           AS lifi_bps_low,
       round(1e4 * (r_lifi + 1.96 * se_lifi), 3)                                                        AS lifi_bps_high,
       round(1e4 * r_integ, 3)                                                                          AS integrator_bps,
       round(greatest(0, 1e4 * (r_integ - 1.96 * se_integ)), 3)                                         AS integrator_bps_low,
       round(1e4 * (r_integ + 1.96 * se_integ), 3)                                                      AS integrator_bps_high,
       round(1e4 * s_lifi / sx_api, 3)                                                                  AS lifi_api_bps,
       round(1e4 * s_integ / sx_api, 3)                                                                 AS integrator_api_bps,
       round(1e4 * s_other / sx_api, 3)                                                                 AS other_lines_api_bps,
       round(mean_rate, 3)                                                                              AS mean_lifi_rate_bps
FROM k
ORDER BY ord
