-- 149_status_100k_all_transfers_fee_line_by_band
-- Question: For every transfer in the file at $100,000 or more of headline USD, swap-route and
--           bridge-only alike: how many there are, how many have a status record in
--           the committed snapshots and from which, their status, how many carry a fee line of any
--           kind and a LIFI-named line, and the quoted LI.FI, integrator and other fee USD, by route
--           kind and USD band and in total.
-- Grain:    one row per (route_kind, usd_band) plus an 'all' band per route kind; route_kind is
--           'swap' (has_source_swaps), 'bridge_only' (not has_source_swaps) and 'all'. Bands on the
--           headline USD: $100k-250k, $250k-1M, $1M+, 'all'. Every row at $100k+ is in the
--           population whether or not it has a record (with_record / without_record say).
-- Definition applied:
--   - Population: transfers_priced WHERE amount_usd >= 100000 (headline USD: the provided
--     feed else CoinGecko). Every status is counted, so a refund's quoted fee is included.
--   - Record, one per event, joined on (chain, tx_hash, log_index), the first that holds the row:
--     ref_lifi_api_transfer_status_extension WHERE in_census (the $10k census of swap rows,
--     notebook 07 §3, covers every swap row at $100k+), else
--     ref_lifi_api_transfer_status_bridge_census (the bridge-only census at $100k+, notebook 07
--     §8), else ref_lifi_api_transfer_status_edge_cases WHERE lookup = 'tx_hash' (notebook 03;
--     a fallback so that nothing is missing: record_from_edge_cases is 0 when the two censuses
--     cover the population). Columns of each table are cast to one schema (a column that is
--     empty in a CSV loads as DOUBLE).
--   - with_any_fee_line: quote_fee_names non-empty (any entry of the quote's feeCosts);
--     with_lifi_line: quote_fee_lifi_usd > 0 (a line whose name starts with LIFI, as
--     75_status_fee_overall); lifi_fee_gt_0 / integrator_fee_gt_0: the feeSplit USD > 0.
--   - Fee USD as 147_status_extension_census_fee_usd: lifi_fee_usd = fee_split_lifi_usd,
--     integrator_fee_usd = fee_split_integrator_usd, other_fee_usd = quote_fee_other_usd;
--     bps = fee USD / amount_usd × 10,000; pct_of_file_usd = amount_usd / the file's headline USD.
--   - The quoted fee on the observed rows, exhaustive over the population: not a revenue estimate.
-- Inputs:   transfers_priced; ref_lifi_api_transfer_status_extension,
--           ref_lifi_api_transfer_status_bridge_census, ref_lifi_api_transfer_status_edge_cases
--           (reference data: LI.FI /v1/status).

WITH rec AS (
    SELECT chain, tx_hash, log_index, 1 AS prio, 'extension' AS record_from,
           CAST(http_status AS BIGINT) AS http_status, CAST(status AS VARCHAR) AS status, CAST(substatus AS VARCHAR) AS substatus,
           CAST(quote_tool AS VARCHAR) AS quote_tool, CAST(quote_fee_names AS VARCHAR) AS quote_fee_names,
           CAST(quote_fee_lifi_usd AS DOUBLE) AS quote_fee_lifi_usd, CAST(fee_split_lifi_usd AS DOUBLE) AS fee_split_lifi_usd,
           CAST(fee_split_integrator_usd AS DOUBLE) AS fee_split_integrator_usd, CAST(quote_fee_other_usd AS DOUBLE) AS quote_fee_other_usd,
           CAST(sending_amountUSD AS DOUBLE) AS sending_amountUSD, CAST(batch_n AS DOUBLE) AS batch_n
    FROM ref_lifi_api_transfer_status_extension WHERE in_census
    UNION ALL
    SELECT chain, tx_hash, log_index, 2, 'bridge_census',
           CAST(http_status AS BIGINT), CAST(status AS VARCHAR), CAST(substatus AS VARCHAR),
           CAST(quote_tool AS VARCHAR), CAST(quote_fee_names AS VARCHAR),
           CAST(quote_fee_lifi_usd AS DOUBLE), CAST(fee_split_lifi_usd AS DOUBLE),
           CAST(fee_split_integrator_usd AS DOUBLE), CAST(quote_fee_other_usd AS DOUBLE),
           CAST(sending_amountUSD AS DOUBLE), CAST(batch_n AS DOUBLE)
    FROM ref_lifi_api_transfer_status_bridge_census
    UNION ALL
    SELECT chain, tx_hash, log_index, 3, 'edge_cases',
           CAST(http_status AS BIGINT), CAST(status AS VARCHAR), CAST(substatus AS VARCHAR),
           CAST(quote_tool AS VARCHAR), CAST(quote_fee_names AS VARCHAR),
           CAST(quote_fee_lifi_usd AS DOUBLE), CAST(fee_split_lifi_usd AS DOUBLE),
           CAST(fee_split_integrator_usd AS DOUBLE), CAST(quote_fee_other_usd AS DOUBLE),
           CAST(sending_amountUSD AS DOUBLE), CAST(batch_n AS DOUBLE)
    FROM ref_lifi_api_transfer_status_edge_cases WHERE lookup = 'tx_hash'
),
one AS (
    SELECT * FROM rec QUALIFY row_number() OVER (PARTITION BY chain, tx_hash, log_index ORDER BY prio) = 1
),
pop AS (
    SELECT p.chain, p.tx_hash, p.log_index, p.amount_usd,
           CASE WHEN p.has_source_swaps THEN 'swap' ELSE 'bridge_only' END AS route_kind,
           CASE WHEN p.amount_usd >= 1000000 THEN '$1M+' WHEN p.amount_usd >= 250000 THEN '$250k-1M' ELSE '$100k-250k' END AS usd_band,
           r.*
    FROM transfers_priced p
    LEFT JOIN one r USING (chain, tx_hash, log_index)
    WHERE p.amount_usd >= 100000
),
grid AS (
    SELECT route_kind, usd_band, * EXCLUDE (route_kind, usd_band) FROM pop
    UNION ALL SELECT route_kind, 'all', * EXCLUDE (route_kind, usd_band) FROM pop
    UNION ALL SELECT 'all', usd_band, * EXCLUDE (route_kind, usd_band) FROM pop
    UNION ALL SELECT 'all', 'all', * EXCLUDE (route_kind, usd_band) FROM pop
),
agg AS (
    SELECT route_kind, usd_band,
           count(*)                                                            AS events,
           count(*) FILTER (WHERE record_from IS NOT NULL)                     AS with_record,
           count(*) FILTER (WHERE record_from = 'extension')                   AS record_from_extension,
           count(*) FILTER (WHERE record_from = 'bridge_census')               AS record_from_bridge_census,
           count(*) FILTER (WHERE record_from = 'edge_cases')                  AS record_from_edge_cases,
           count(*) FILTER (WHERE record_from IS NULL)                         AS without_record,
           count(*) FILTER (WHERE http_status = 200)                           AS http_200,
           count(*) FILTER (WHERE status = 'DONE' AND substatus = 'COMPLETED') AS completed,
           count(*) FILTER (WHERE status = 'DONE' AND substatus <> 'COMPLETED') AS done_not_completed,
           count(*) FILTER (WHERE status IS NOT NULL AND status <> 'DONE')     AS not_done,
           count(*) FILTER (WHERE quote_tool IS NOT NULL)                      AS with_quote,
           count(*) FILTER (WHERE coalesce(quote_fee_names, '') <> '')         AS with_any_fee_line,
           count(*) FILTER (WHERE coalesce(quote_fee_lifi_usd, 0) > 0)         AS with_lifi_line,
           count(*) FILTER (WHERE coalesce(fee_split_lifi_usd, 0) > 0)         AS lifi_fee_gt_0,
           count(*) FILTER (WHERE coalesce(fee_split_integrator_usd, 0) > 0)   AS integrator_fee_gt_0,
           count(*) FILTER (WHERE batch_n IS NOT NULL)                         AS with_batch_status,
           sum(amount_usd)                                                     AS amount_usd,
           sum(sending_amountUSD)                                              AS sending_usd,
           sum(coalesce(fee_split_lifi_usd, 0))                                AS lifi_fee_usd,
           sum(coalesce(fee_split_integrator_usd, 0))                          AS integrator_fee_usd,
           sum(coalesce(quote_fee_other_usd, 0))                               AS other_fee_usd
    FROM grid GROUP BY 1, 2
)
SELECT route_kind, usd_band, events, with_record, record_from_extension, record_from_bridge_census, record_from_edge_cases, without_record,
       http_200, completed, done_not_completed, not_done, with_quote, with_any_fee_line, with_lifi_line,
       round(100.0 * with_lifi_line / events, 2)                    AS pct_with_lifi_line,
       lifi_fee_gt_0, integrator_fee_gt_0, with_batch_status,
       round(amount_usd, 2)                                         AS amount_usd,
       round(100.0 * amount_usd / (SELECT sum(amount_usd) FROM transfers_priced), 2) AS pct_of_file_usd,
       round(sending_usd, 2)                                        AS sending_usd,
       round(lifi_fee_usd, 2)                                       AS lifi_fee_usd,
       round(integrator_fee_usd, 2)                                 AS integrator_fee_usd,
       round(other_fee_usd, 2)                                      AS other_fee_usd,
       round(1e4 * lifi_fee_usd / amount_usd, 3)                    AS lifi_bps,
       round(1e4 * integrator_fee_usd / amount_usd, 3)              AS integrator_bps,
       round(1e4 * other_fee_usd / amount_usd, 3)                   AS other_bps
FROM agg
ORDER BY CASE route_kind WHEN 'all' THEN 0 WHEN 'swap' THEN 1 ELSE 2 END,
         CASE usd_band WHEN 'all' THEN 0 WHEN '$100k-250k' THEN 1 WHEN '$250k-1M' THEN 2 ELSE 3 END
