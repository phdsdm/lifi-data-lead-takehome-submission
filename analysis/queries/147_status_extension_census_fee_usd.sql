-- 147_status_extension_census_fee_usd
-- Question: On the census of swap rows at $10,000 or more of headline USD: per
--           integrator and in total, how many events, their headline and API USD, how many carry
--           a LIFI-named line, and the LI.FI, integrator and other fee USD the quotes carry, in
--           basis points of the headline USD.
-- Grain:    one row per raw integrator string with a census event, plus a 'total' row; most
--           headline USD first.
-- Definition applied:
--   - Census: in_census = true (every transfer with has_source_swaps and amount_usd >= 10,000);
--     every status is counted, so a refund's quoted fee is included.
--   - amount_usd: the headline USD of transfers_priced; sending_usd: the API's
--     sending.amountUSD (the pre-swap input).
--   - Fee USD as 75_status_fee_overall: lifi_fee_usd = fee_split_lifi_usd, integrator_fee_usd =
--     fee_split_integrator_usd (the LIFI-named line's feeSplit at the line's own price),
--     other_fee_usd = quote_fee_other_usd. bps = fee USD / amount_usd × 10,000.
--   - This is the census's quoted fee, not a revenue estimate: no weighting, no schedule.
-- Inputs:   ref_lifi_api_transfer_status_extension (reference data: LI.FI /v1/status);
--           transfers_priced (amount_usd).

WITH c AS (
    SELECT coalesce(e.event_integrator, '') AS integrator, e.status, e.substatus, p.amount_usd, e.sending_amountUSD,
           coalesce(e.quote_fee_lifi_usd, 0) > 0 AS has_line,
           coalesce(e.fee_split_lifi_usd, 0) AS lifi, coalesce(e.fee_split_integrator_usd, 0) AS integ, coalesce(e.quote_fee_other_usd, 0) AS other
    FROM ref_lifi_api_transfer_status_extension e
    JOIN transfers_priced p USING (chain, tx_hash, log_index)
    WHERE e.in_census
),
agg AS (
    SELECT integrator,
           count(*)                                                           AS events,
           count(*) FILTER (WHERE status = 'DONE' AND substatus = 'COMPLETED') AS completed,
           count(*) FILTER (WHERE has_line)                                   AS with_lifi_line,
           count(*) FILTER (WHERE lifi > 0)                                   AS lifi_fee_gt_0,
           count(*) FILTER (WHERE integ > 0)                                  AS integrator_fee_gt_0,
           sum(amount_usd)                                                    AS amount_usd,
           sum(sending_amountUSD)                                             AS sending_usd,
           sum(lifi)                                                          AS lifi_fee_usd,
           sum(integ)                                                         AS integrator_fee_usd,
           sum(other)                                                         AS other_fee_usd
    FROM c GROUP BY integrator
),
u AS (
    SELECT * FROM agg
    UNION ALL
    SELECT 'total', sum(events), sum(completed), sum(with_lifi_line), sum(lifi_fee_gt_0), sum(integrator_fee_gt_0),
           sum(amount_usd), sum(sending_usd), sum(lifi_fee_usd), sum(integrator_fee_usd), sum(other_fee_usd)
    FROM agg
)
SELECT CASE WHEN integrator = '' THEN '(empty)' ELSE integrator END AS integrator,
       events, completed, with_lifi_line, lifi_fee_gt_0, integrator_fee_gt_0,
       round(amount_usd, 2)                              AS amount_usd,
       round(sending_usd, 2)                             AS sending_usd,
       round(lifi_fee_usd, 2)                            AS lifi_fee_usd,
       round(integrator_fee_usd, 2)                      AS integrator_fee_usd,
       round(other_fee_usd, 2)                           AS other_fee_usd,
       round(1e4 * lifi_fee_usd / amount_usd, 3)         AS lifi_bps,
       round(1e4 * integrator_fee_usd / amount_usd, 3)   AS integrator_bps,
       round(1e4 * other_fee_usd / amount_usd, 3)        AS other_bps
FROM u
ORDER BY CASE WHEN integrator = 'total' THEN 0 ELSE 1 END, amount_usd DESC
