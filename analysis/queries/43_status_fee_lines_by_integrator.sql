-- 43_status_fee_lines_by_integrator
-- Question: In the quotes behind the uniform sample, what fee do the LIFI-named lines carry
--           in basis points of sending USD, how much of it goes to LI.FI and how much to the
--           integrator, overall and per integrator string?
-- Grain:    a total row, then one row per raw integrator string with at least 30 sampled
--           events in the uniform 2,000 (13), largest sending USD first.
-- Definition applied:
--   - Sample: sample_design = 'uniform_2000', every status.
--   - Sending USD: the API's sending_amountUSD.
--   - LIFI-named lines: the quote's fee lines whose name starts with "LIFI" (quote_fee_lifi_usd);
--     their feeSplit gives lifiFee (fee_split_lifi_usd) and integratorFee
--     (fee_split_integrator_usd); other lines: quote_fee_other_usd.
--   - bps = 10,000 × fee USD / sending USD over the group.
--   - pct_lifi_named_to_integrator: integratorFee over LIFI-named USD.
--   - percentages_quoted: the distinct `percentage` values on the LIFI-named lines.
--   - The quote is what was offered at request time, not what was collected.
-- Inputs:   ref_lifi_api_transfer_status_sample_2600 (reference data: LI.FI /v1/status,
--           fetched 2026-10-28).

WITH s AS (
    SELECT * FROM ref_lifi_api_transfer_status_sample_2600 WHERE sample_design = 'uniform_2000'
),
labelled AS (
    SELECT '(uniform 2,000)' AS integrator, 0 AS is_string, * EXCLUDE (event_integrator) FROM s
    UNION ALL
    SELECT event_integrator, 1, * EXCLUDE (event_integrator) FROM s
    WHERE event_integrator IN (SELECT event_integrator FROM s GROUP BY event_integrator HAVING count(*) >= 30)
)
SELECT integrator,
       count(*)                                                                         AS sampled,
       count(*) FILTER (WHERE quote_fee_lifi_usd > 0)                                    AS with_lifi_named_line,
       round(sum(sending_amountUSD), 2)                                                  AS sending_usd,
       round(sum(quote_fee_lifi_usd), 2)                                                 AS lifi_named_usd,
       round(1e4 * coalesce(sum(quote_fee_lifi_usd), 0) / sum(sending_amountUSD), 1)     AS lifi_named_bps,
       round(1e4 * coalesce(sum(fee_split_lifi_usd), 0) / sum(sending_amountUSD), 1)     AS lifi_fee_bps,
       round(1e4 * coalesce(sum(fee_split_integrator_usd), 0) / sum(sending_amountUSD), 1) AS integrator_fee_bps,
       round(1e4 * coalesce(sum(quote_fee_other_usd), 0) / sum(sending_amountUSD), 1)    AS other_lines_bps,
       round(100.0 * sum(fee_split_integrator_usd) / nullif(sum(quote_fee_lifi_usd), 0), 1) AS pct_lifi_named_to_integrator,
       string_agg(DISTINCT CAST(round(100 * quote_fee_lifi_percentages, 2) AS VARCHAR) || '%', ', ')
           FILTER (WHERE is_string = 1)                                                  AS percentages_quoted
FROM labelled
GROUP BY is_string, integrator
ORDER BY is_string, sum(sending_amountUSD) DESC, integrator
