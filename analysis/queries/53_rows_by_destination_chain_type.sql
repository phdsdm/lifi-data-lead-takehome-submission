-- 53_rows_by_destination_chain_type
-- Question: What share of rows and USD goes to each destination chain type, to non-EVM
--           chains together, and to ids LI.FI's /v1/chains does not list?
-- Grain:    one row per chain type (6), then a row for all non-EVM types together and a row
--           for the whole file.
-- Definition applied:
--   - Chain type from LI.FI's chain-id registry (reference data). Chains are counted after
--     merging an id into its API id (api_chain_id), so Tron's contract id 1885080386571452
--     and API id 728126428 count as one chain.
--   - Non-EVM: every type other than EVM (SVM, UTXO, TVM, MVM, STL).
--   - rows_to_unlisted_ids: rows whose id /v1/chains, asked with all six chain types, does
--     not list (listed_by_v1_chains = false).
--   - usd: amount_usd (headline); usd_provided: amount_usd_provided. Shares are of the file.
-- Inputs:   transfers_priced; ref_lifi_chain_id_registry (reference data).
-- Per id: 48_usd_by_destination_chain.

WITH t AS (
    SELECT r.chain_type,
           coalesce(r.api_chain_id, t.destination_chain_id)                    AS chain_key,
           t.destination_chain_id,
           t.receiver = '0x11f111f111f111f111f111f111f111f111f111f1'           AS sentinel,
           NOT coalesce(r.listed_by_v1_chains, FALSE)                          AS unlisted,
           t.amount_usd,
           t.amount_usd_provided
    FROM transfers_priced t
    LEFT JOIN ref_lifi_chain_id_registry r ON r.chain_id = t.destination_chain_id
),
labelled AS (
    SELECT chain_type AS label, CASE WHEN chain_type = 'EVM' THEN 0 ELSE 1 END AS ord, * FROM t
    UNION ALL
    SELECT '(non-EVM, all types)', 2, * FROM t WHERE chain_type <> 'EVM'
    UNION ALL
    SELECT '(all)', 3, * FROM t
),
total AS (
    SELECT count(*) AS n_rows, sum(amount_usd) AS usd, sum(amount_usd_provided) AS usd_provided FROM t
)
SELECT l.label                                                        AS chain_type,
       count(DISTINCT l.chain_key)                                    AS chains,
       count(DISTINCT l.destination_chain_id)                         AS ids,
       count(*)                                                       AS n_rows,
       round(100.0 * count(*) / total.n_rows, 2)                      AS pct_rows,
       round(sum(l.amount_usd), 2)                                    AS usd,
       round(100.0 * sum(l.amount_usd) / total.usd, 2)                AS pct_usd,
       round(sum(l.amount_usd_provided), 2)                           AS usd_provided,
       round(100.0 * sum(l.amount_usd_provided) / total.usd_provided, 2) AS pct_usd_provided,
       count(*) FILTER (WHERE l.sentinel)                             AS sentinel_rows,
       count(DISTINCT l.destination_chain_id) FILTER (WHERE l.unlisted) AS unlisted_ids,
       count(*) FILTER (WHERE l.unlisted)                             AS rows_to_unlisted_ids
FROM labelled l
CROSS JOIN total
GROUP BY l.ord, l.label, total.n_rows, total.usd, total.usd_provided
ORDER BY l.ord, n_rows DESC
