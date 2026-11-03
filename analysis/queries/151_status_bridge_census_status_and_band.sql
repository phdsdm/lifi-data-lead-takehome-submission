-- 151_status_bridge_census_status_and_band
-- Question: On the census of bridge-only transfers at $100,000 or more of headline USD: how the events split by status and substatus, how many fall in each USD band,
--           how many carry a quote, a fee line of any kind, a LIFI-named line and a batchStatus,
--           and how many reuse an earlier snapshot's record.
-- Grain:    one row per (status, substatus) plus a total row; by events.
-- Definition applied:
--   - Census: every row of ref_lifi_api_transfer_status_bridge_census (has_source_swaps false and
--     amount_usd >= 100,000, notebook 07 §8.1).
--   - Bands on the headline USD of transfers_priced: $100k-250k, $250k-1M, $1M+.
--   - with_any_fee_line: quote_fee_names non-empty; with_lifi_line: quote_fee_lifi_usd > 0 (a
--     line whose name starts with LIFI, as 75_status_fee_overall); lifi_fee_gt_0 /
--     integrator_fee_gt_0: the feeSplit USD > 0; with_quote: quote_tool IS NOT NULL.
--   - pct_of_census: events / the census total × 100. A column empty in the CSV loads as
--     DOUBLE, hence the casts.
-- Inputs:   ref_lifi_api_transfer_status_bridge_census (reference data: LI.FI /v1/status);
--           transfers_priced (amount_usd).

WITH c AS (
    SELECT coalesce(e.status, '(none)') AS status, coalesce(e.substatus, '(none)') AS substatus, p.amount_usd,
           CAST(e.http_status AS BIGINT) AS http_status, CAST(e.quote_tool AS VARCHAR) AS quote_tool, CAST(e.quote_fee_names AS VARCHAR) AS quote_fee_names,
           CAST(e.quote_fee_lifi_usd AS DOUBLE) AS quote_fee_lifi_usd, CAST(e.fee_split_lifi_usd AS DOUBLE) AS fee_split_lifi_usd,
           CAST(e.fee_split_integrator_usd AS DOUBLE) AS fee_split_integrator_usd, CAST(e.batch_n AS DOUBLE) AS batch_n, CAST(e.reused_from AS VARCHAR) AS reused_from
    FROM ref_lifi_api_transfer_status_bridge_census e
    JOIN transfers_priced p USING (chain, tx_hash, log_index)
),
agg AS (
    SELECT status, substatus,
           count(*)                                                          AS events,
           count(*) FILTER (WHERE amount_usd < 250000)                       AS band_100k_250k,
           count(*) FILTER (WHERE amount_usd >= 250000 AND amount_usd < 1000000) AS band_250k_1m,
           count(*) FILTER (WHERE amount_usd >= 1000000)                     AS band_1m_plus,
           count(*) FILTER (WHERE http_status = 200)                         AS http_200,
           count(*) FILTER (WHERE reused_from IS NOT NULL)                   AS reused,
           count(*) FILTER (WHERE quote_tool IS NOT NULL)                    AS with_quote,
           count(*) FILTER (WHERE coalesce(quote_fee_names, '') <> '')       AS with_any_fee_line,
           count(*) FILTER (WHERE coalesce(quote_fee_lifi_usd, 0) > 0)       AS with_lifi_line,
           count(*) FILTER (WHERE coalesce(fee_split_lifi_usd, 0) > 0)       AS lifi_fee_gt_0,
           count(*) FILTER (WHERE coalesce(fee_split_integrator_usd, 0) > 0) AS integrator_fee_gt_0,
           count(*) FILTER (WHERE batch_n IS NOT NULL)                       AS with_batch_status,
           round(sum(amount_usd), 2)                                         AS amount_usd
    FROM c GROUP BY 1, 2
),
u AS (
    SELECT * FROM agg
    UNION ALL
    SELECT 'all', 'all', sum(events), sum(band_100k_250k), sum(band_250k_1m), sum(band_1m_plus), sum(http_200), sum(reused), sum(with_quote),
           sum(with_any_fee_line), sum(with_lifi_line), sum(lifi_fee_gt_0), sum(integrator_fee_gt_0), sum(with_batch_status), sum(amount_usd)
    FROM agg
)
SELECT status, substatus, events,
       round(100.0 * events / sum(events) FILTER (WHERE status = 'all') OVER (), 2) AS pct_of_census,
       band_100k_250k, band_250k_1m, band_1m_plus, http_200, reused, with_quote, with_any_fee_line, with_lifi_line, lifi_fee_gt_0, integrator_fee_gt_0, with_batch_status, amount_usd
FROM u
ORDER BY CASE WHEN status = 'all' THEN 0 ELSE 1 END, events DESC
