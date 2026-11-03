-- 97_status_fee_batch_vs_quote
-- Question: For the status responses that carry batchStatus, does the fee line of the quoted
--           transfer's own batch call, which may be the fee as settled, equal the quote's
--           LIFI-named line, field by field?
-- Grain:    one row per status design (3): uniform_2000, equal_per_chain_600, the edge cases'
--           hash lookups; then a row over all three.
-- Definition applied:
--   - Responses: rows of the flattened snapshots with batchStatus (batch_n not NULL): the
--     sample's events by (chain, tx_hash, log_index); the edge cases' 'tx_hash' lookups by
--     (chain, tx_hash), one per call, since a two-event transaction's two rows share a response.
--     quote_present: the response carries a quote (quote_tool not NULL).
--   - The quoted transfer's call: the batchStatus call whose transactionId equals the response's
--     transactionId (batch_call_transactionIds of the flattened snapshot; in the fee-line table
--     call_is_response_transfer). top_call_in_batch counts responses that list it.
--   - Quote line: the response's quote line named 'LIFI…' (source 'quote'); batch line: a fee line
--     of the quoted transfer's call (source 'batch', call_is_response_transfer), from
--     ref_lifi_api_transfer_status_fee_lines. Each has at most one.
--   - Field comparisons on responses with both lines: percentage, amount (token units, exact),
--     token address (lowercased), included, lifi_fee, integrator_fee, amount_usd. batch_wallets:
--     batch lines whose every recipient carries a walletAddress; integrator_named_integrator:
--     batch lines whose non-LI.FI recipient is named 'integrator' (of those with one).
--   - usd_ratio_*: batch amount_usd / quote amount_usd, quantile_cont.
--   - other_calls_with_line: batch fee lines on calls that are not the quoted transfer (other
--     transfers in the bundle). lifi_wallets: distinct walletAddress values of the 'lifi'
--     recipient over every batch line of the design, and lifi_recipients the lines carrying one.
-- Inputs:   ref_lifi_api_transfer_status_fee_lines, ref_lifi_api_transfer_status_sample_2600,
--           ref_lifi_api_transfer_status_edge_cases (reference data: LI.FI /v1/status, fetched
--           2026-10-28).

WITH resp AS (
    SELECT sample_design AS design, chain, tx_hash, log_index, api_transactionId, batch_call_transactionIds,
           quote_tool IS NOT NULL AS quote_present
    FROM ref_lifi_api_transfer_status_sample_2600
    WHERE batch_n IS NOT NULL
    UNION ALL
    SELECT DISTINCT 'edge cases (hash lookups)', chain, tx_hash, NULL::BIGINT, api_transactionId, batch_call_transactionIds,
           quote_tool IS NOT NULL
    FROM ref_lifi_api_transfer_status_edge_cases
    WHERE batch_n IS NOT NULL AND lookup = 'tx_hash'
),
lines AS (
    SELECT coalesce(sample_design, 'edge cases (hash lookups)') AS design, *
    FROM ref_lifi_api_transfer_status_fee_lines
    WHERE snapshot = 'sample_2600' OR (snapshot = 'edge_cases' AND lookup = 'tx_hash')
),
q AS (SELECT * FROM lines WHERE source = 'quote' AND name LIKE 'LIFI%'),
b AS (SELECT * FROM lines WHERE source = 'batch' AND call_is_response_transfer),
j AS (
    SELECT r.design, r.quote_present,
           list_contains(string_split(lower(coalesce(r.batch_call_transactionIds, '')), '|'), lower(r.api_transactionId)) AS top_in_batch,
           q.name IS NOT NULL AS has_q, b.name IS NOT NULL AS has_b,
           q.percentage = b.percentage                         AS same_pct,
           q.amount = b.amount                                 AS same_amount,
           lower(q.token_address) = lower(b.token_address)     AS same_token,
           q.included = b.included                             AS same_included,
           q.lifi_fee = b.lifi_fee                             AS same_lifi,
           q.integrator_fee = b.integrator_fee                 AS same_integ,
           q.amount_usd = b.amount_usd                         AS same_usd,
           b.amount_usd / nullif(q.amount_usd, 0)              AS usd_ratio,
           (b.lifi_recipient_type IS NULL OR b.lifi_recipient_wallet IS NOT NULL) AND
           (b.integrator_recipient_name IS NULL OR b.integrator_recipient_wallet IS NOT NULL) AS wallets_given,
           b.integrator_recipient_name IS NOT NULL             AS b_has_integ_recipient,
           b.integrator_recipient_name = 'integrator'          AS b_integ_named_integrator,
           b.name AS b_name, b.description AS b_description
    FROM resp r
    LEFT JOIN q ON q.design = r.design AND q.chain = r.chain AND q.tx_hash = r.tx_hash AND q.log_index IS NOT DISTINCT FROM r.log_index
    LEFT JOIN b ON b.design = r.design AND b.chain = r.chain AND b.tx_hash = r.tx_hash AND b.log_index IS NOT DISTINCT FROM r.log_index
),
batch_all AS (
    SELECT design,
           count(*) FILTER (WHERE NOT call_is_response_transfer) AS other_calls_with_line,
           count(DISTINCT lower(lifi_recipient_wallet))           AS lifi_wallets,
           count(lifi_recipient_wallet)                            AS lifi_recipients,
           max(line_position) + 1                                  AS max_lines_per_call
    FROM lines WHERE source = 'batch' GROUP BY design
),
labelled AS (
    SELECT CASE design WHEN 'uniform_2000' THEN 1 WHEN 'equal_per_chain_600' THEN 2 ELSE 3 END AS ord, * FROM j
    UNION ALL
    SELECT 4, '(all three)', * EXCLUDE (design) FROM j
),
agg AS (
    SELECT ord, design,
           count(*)                                                       AS responses_with_batch_status,
           count(*) FILTER (WHERE top_in_batch)                           AS top_call_in_batch,
           count(*) FILTER (WHERE has_q AND has_b)                        AS compared,
           count(*) FILTER (WHERE NOT has_q AND NOT has_b)                AS neither_line,
           count(*) FILTER (WHERE has_b AND NOT has_q AND NOT quote_present) AS batch_line_no_quote,
           count(*) FILTER (WHERE has_b AND NOT has_q AND quote_present)  AS batch_line_quote_without_line,
           count(*) FILTER (WHERE has_q AND NOT has_b)                    AS quote_line_no_batch_line,
           count(*) FILTER (WHERE same_pct)                               AS same_percentage,
           count(*) FILTER (WHERE same_amount)                            AS same_amount,
           count(*) FILTER (WHERE same_token)                             AS same_token,
           count(*) FILTER (WHERE same_included)                          AS same_included,
           count(*) FILTER (WHERE same_lifi)                              AS same_lifi_fee,
           count(*) FILTER (WHERE same_integ)                             AS same_integrator_fee,
           count(*) FILTER (WHERE same_usd)                               AS same_amount_usd,
           count(*) FILTER (WHERE has_q AND has_b AND wallets_given)      AS batch_wallets_given,
           count(*) FILTER (WHERE has_q AND has_b AND b_has_integ_recipient) AS batch_with_integrator_recipient,
           count(*) FILTER (WHERE has_q AND has_b AND b_integ_named_integrator) AS integrator_named_integrator,
           round(quantile_cont(usd_ratio, 0.5), 4)                        AS usd_ratio_median,
           round(quantile_cont(usd_ratio, 0.05), 4)                       AS usd_ratio_p5,
           round(quantile_cont(usd_ratio, 0.95), 4)                       AS usd_ratio_p95,
           round(min(usd_ratio), 4)                                       AS usd_ratio_min,
           round(max(usd_ratio), 4)                                       AS usd_ratio_max,
           string_agg(DISTINCT b_name || ' / ' || b_description, '; ')    AS batch_line_names
    FROM labelled GROUP BY ord, design
)
SELECT a.design,
       a.* EXCLUDE (ord, design),
       CASE WHEN a.ord < 4 THEN ba.other_calls_with_line ELSE (SELECT sum(other_calls_with_line) FROM batch_all) END AS other_calls_with_line,
       CASE WHEN a.ord < 4 THEN ba.max_lines_per_call ELSE (SELECT max(max_lines_per_call) FROM batch_all) END       AS max_lines_per_call,
       CASE WHEN a.ord < 4 THEN ba.lifi_recipients ELSE (SELECT sum(lifi_recipients) FROM batch_all) END             AS lifi_recipients,
       CASE WHEN a.ord < 4 THEN ba.lifi_wallets
            ELSE (SELECT count(DISTINCT lower(lifi_recipient_wallet)) FROM lines WHERE source = 'batch') END       AS lifi_wallets
FROM agg a
LEFT JOIN batch_all ba USING (design)
ORDER BY a.ord
