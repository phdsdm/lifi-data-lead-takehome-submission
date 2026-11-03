-- 150_status_bridge_census_fee_usd_by_integrator
-- Question: On the census of bridge-only transfers at $100,000 or more of headline USD: per integrator and in total, how many events, which bridges, their headline
--           and API USD, how many completed, how many carry a fee line of any kind and a
--           LIFI-named line, whether a batchStatus is present, and the LI.FI, integrator and
--           other fee USD the quotes carry, in basis points of the headline USD.
-- Grain:    one row per raw integrator string with a census event, plus a 'total' row; most
--           headline USD first.
-- Definition applied:
--   - Census: every row of ref_lifi_api_transfer_status_bridge_census (has_source_swaps false and
--     amount_usd >= 100,000, notebook 07 §8.1); every status is counted, so a refund's quoted
--     fee is included.
--   - amount_usd: the headline USD of transfers_priced; sending_usd: the API's
--     sending.amountUSD.
--   - with_any_fee_line: quote_fee_names non-empty (any entry of the quote's feeCosts);
--     with_lifi_line: quote_fee_lifi_usd > 0 (a line whose name starts with LIFI, as
--     75_status_fee_overall); fee USD as 147_status_extension_census_fee_usd (lifi_fee_usd =
--     fee_split_lifi_usd, integrator_fee_usd = fee_split_integrator_usd, other_fee_usd =
--     quote_fee_other_usd); bps = fee USD / amount_usd × 10,000. fee_line_names lists the
--     distinct quote_fee_names seen on the integrator's rows.
--   - A column empty in the CSV loads as DOUBLE, hence the casts.
--   - The census's quoted fee, exhaustive over its rows: not a revenue estimate.
-- Inputs:   ref_lifi_api_transfer_status_bridge_census (reference data: LI.FI /v1/status);
--           transfers_priced (amount_usd, bridge).

WITH c AS (
    SELECT coalesce(e.event_integrator, '') AS integrator, p.bridge, e.status, e.substatus, p.amount_usd, CAST(e.sending_amountUSD AS DOUBLE) AS sending_usd,
           CAST(e.http_status AS BIGINT) AS http_status, CAST(e.quote_tool AS VARCHAR) AS quote_tool, CAST(e.quote_fee_names AS VARCHAR) AS quote_fee_names,
           coalesce(CAST(e.quote_fee_lifi_usd AS DOUBLE), 0) > 0 AS has_line,
           coalesce(CAST(e.fee_split_lifi_usd AS DOUBLE), 0) AS lifi, coalesce(CAST(e.fee_split_integrator_usd AS DOUBLE), 0) AS integ, coalesce(CAST(e.quote_fee_other_usd AS DOUBLE), 0) AS other,
           CAST(e.batch_n AS DOUBLE) AS batch_n, CAST(e.reused_from AS VARCHAR) AS reused_from
    FROM ref_lifi_api_transfer_status_bridge_census e
    JOIN transfers_priced p USING (chain, tx_hash, log_index)
),
agg AS (
    SELECT integrator,
           count(*)                                                           AS events,
           count(DISTINCT bridge)                                             AS bridges,
           string_agg(DISTINCT bridge, ', ' ORDER BY bridge)                  AS bridge_names,
           count(*) FILTER (WHERE http_status = 200)                          AS http_200,
           count(*) FILTER (WHERE reused_from IS NOT NULL)                    AS reused,
           count(*) FILTER (WHERE status = 'DONE' AND substatus = 'COMPLETED') AS completed,
           count(*) FILTER (WHERE quote_tool IS NOT NULL)                     AS with_quote,
           count(*) FILTER (WHERE coalesce(quote_fee_names, '') <> '')        AS with_any_fee_line,
           count(*) FILTER (WHERE has_line)                                   AS with_lifi_line,
           count(*) FILTER (WHERE lifi > 0)                                   AS lifi_fee_gt_0,
           count(*) FILTER (WHERE integ > 0)                                  AS integrator_fee_gt_0,
           count(*) FILTER (WHERE other > 0)                                  AS other_fee_gt_0,
           count(*) FILTER (WHERE batch_n IS NOT NULL)                        AS with_batch_status,
           string_agg(DISTINCT quote_fee_names, ' | ') FILTER (WHERE coalesce(quote_fee_names, '') <> '') AS fee_line_names,
           sum(amount_usd)                                                    AS amount_usd,
           sum(sending_usd)                                                   AS sending_usd,
           sum(lifi)                                                          AS lifi_fee_usd,
           sum(integ)                                                         AS integrator_fee_usd,
           sum(other)                                                         AS other_fee_usd
    FROM c GROUP BY integrator
),
u AS (
    SELECT * FROM agg
    UNION ALL
    SELECT 'total', sum(events), (SELECT count(DISTINCT bridge) FROM c), (SELECT string_agg(DISTINCT bridge, ', ' ORDER BY bridge) FROM c),
           sum(http_200), sum(reused), sum(completed), sum(with_quote), sum(with_any_fee_line), sum(with_lifi_line), sum(lifi_fee_gt_0), sum(integrator_fee_gt_0), sum(other_fee_gt_0),
           sum(with_batch_status), (SELECT string_agg(DISTINCT quote_fee_names, ' | ') FROM c WHERE coalesce(quote_fee_names, '') <> ''),
           sum(amount_usd), sum(sending_usd), sum(lifi_fee_usd), sum(integrator_fee_usd), sum(other_fee_usd)
    FROM agg
)
SELECT CASE WHEN integrator = '' THEN '(empty)' ELSE integrator END AS integrator,
       events, bridges, bridge_names, http_200, reused, completed, with_quote, with_any_fee_line, with_lifi_line, lifi_fee_gt_0, integrator_fee_gt_0, other_fee_gt_0, with_batch_status, fee_line_names,
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
