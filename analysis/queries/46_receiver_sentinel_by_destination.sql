-- 46_receiver_sentinel_by_destination
-- Question: On which rows is the receiver LI.FI's non-EVM placeholder, and is it on exactly
--           the rows to non-EVM destinations?
-- Grain:    one row per destination_chain_id that carries the sentinel or is non-EVM (7),
--           after a total row.
-- Definition applied:
--   - Sentinel: receiver = 0x11f111f111f111f111f111f111f111f111f111f1, `NON_EVM_ADDRESS` in
--     LI.FI's LiFiData.sol.
--   - Chain type and name from LI.FI's chain-id registry (reference data): non-EVM = any type
--     other than EVM. Tron appears under two ids (contract id and API id).
--   - sentinel_rows_to_evm and non_evm_rows_without_sentinel on the total row are 0 when the
--     sentinel marks exactly the non-EVM rows.
-- Inputs:   transfers (provided data); ref_lifi_chain_id_registry (reference data, chain type
--           and names).

WITH t AS (
    SELECT t.destination_chain_id,
           t.receiver = '0x11f111f111f111f111f111f111f111f111f111f1' AS sentinel,
           r.name, r.chain_type,
           coalesce(r.chain_type <> 'EVM', FALSE)                     AS non_evm
    FROM transfers t
    LEFT JOIN ref_lifi_chain_id_registry r ON r.chain_id = t.destination_chain_id
),
per_id AS (
    SELECT CAST(destination_chain_id AS VARCHAR) AS destination_chain_id,
           any_value(name) AS name, any_value(chain_type) AS chain_type, 1 AS is_id,
           count(*) AS n_rows,
           count(*) FILTER (WHERE sentinel) AS sentinel_rows,
           NULL::BIGINT AS sentinel_rows_to_evm,
           NULL::BIGINT AS non_evm_rows_without_sentinel
    FROM t
    WHERE sentinel OR non_evm
    GROUP BY destination_chain_id
),
total AS (
    SELECT '(all)' AS destination_chain_id, NULL AS name, NULL AS chain_type, 0 AS is_id,
           count(*) AS n_rows,
           count(*) FILTER (WHERE sentinel) AS sentinel_rows,
           count(*) FILTER (WHERE sentinel AND NOT non_evm) AS sentinel_rows_to_evm,
           count(*) FILTER (WHERE non_evm AND NOT sentinel) AS non_evm_rows_without_sentinel
    FROM t
)
SELECT destination_chain_id,
       name,
       chain_type,
       n_rows,
       sentinel_rows,
       round(100.0 * sentinel_rows / (SELECT count(*) FROM transfers), 2) AS pct_of_all_rows,
       sentinel_rows_to_evm,
       non_evm_rows_without_sentinel
FROM (SELECT * FROM total UNION ALL SELECT * FROM per_id)
ORDER BY is_id, sentinel_rows DESC
