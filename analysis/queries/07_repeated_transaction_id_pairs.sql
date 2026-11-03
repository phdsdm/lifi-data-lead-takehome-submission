-- 07_repeated_transaction_id_pairs
-- Question: For each transactionId carried by two rows, what do the two rows share and
--           how far apart are they?
-- Grain:    one row per repeated transactionId (6), first and second row side by side,
--           ordered by block_time then log_index.
-- Definition applied:
--   - A repeated transactionId is a value carried by more than one row (06_key_uniqueness:
--     every repeated value has exactly two rows).
--   - Token amount: min_amount / 10^decimals with decimals from prices.csv for
--     (chain, sending_asset_id); symbol from prices.csv. No USD figure here.
--   - seconds_apart: difference of the two block times.
--   - first_substatus / second_substatus come from the LI.FI status lookup by tx_hash
--     (reference data, ref_lifi_api_transfer_status_edge_cases, lookup = 'tx_hash').
-- Inputs:   transfers, prices (provided data); ref_lifi_api_transfer_status_edge_cases
--           (reference data, the two substatus columns only).
-- Counts: 06_key_uniqueness.

WITH repeated AS (
    SELECT transaction_id FROM transfers GROUP BY transaction_id HAVING count(*) > 1
),
tokens AS (
    SELECT DISTINCT chain, token_address, symbol, decimals FROM prices
),
legs AS (
    SELECT t.*,
           k.symbol,
           t.min_amount / power(10, k.decimals)                                   AS amount_token,
           row_number() OVER (PARTITION BY t.transaction_id ORDER BY t.block_time, t.log_index) AS leg
    FROM transfers t
    JOIN repeated USING (transaction_id)
    LEFT JOIN tokens k ON k.chain = t.chain AND k.token_address = t.sending_asset_id
),
status AS (
    SELECT tx_hash, any_value(substatus) AS substatus
    FROM ref_lifi_api_transfer_status_edge_cases
    WHERE lookup = 'tx_hash'
    GROUP BY tx_hash
)
SELECT a.transaction_id,
       a.chain,
       a.bridge,
       a.integrator,
       a.symbol,
       a.destination_chain_id,
       a.block_time                                           AS first_block_time,
       epoch(b.block_time) - epoch(a.block_time)              AS seconds_apart,
       a.amount_token                                         AS first_amount_token,
       b.amount_token                                         AS second_amount_token,
       a.min_amount                                           AS first_min_amount,
       b.min_amount                                           AS second_min_amount,
       a.chain = b.chain                                      AS same_chain,
       a.bridge = b.bridge                                    AS same_bridge,
       a.integrator = b.integrator                            AS same_integrator,
       a.sending_asset_id = b.sending_asset_id                AS same_token,
       a.min_amount = b.min_amount                            AS same_amount,
       a.destination_chain_id = b.destination_chain_id        AS same_destination,
       a.tx_from = b.tx_from                                  AS same_sender,
       a.receiver = b.receiver                                AS same_receiver,
       a.tx_from = a.receiver AND b.tx_from = b.receiver      AS sender_is_receiver,
       a.tx_hash <> b.tx_hash                                 AS different_transactions,
       a.has_source_swaps AND b.has_source_swaps              AS both_source_swaps,
       a.tx_hash                                              AS first_tx_hash,
       b.tx_hash                                              AS second_tx_hash,
       sa.substatus                                           AS first_substatus,
       sb.substatus                                           AS second_substatus
FROM legs a
JOIN legs b ON b.transaction_id = a.transaction_id AND a.leg = 1 AND b.leg = 2
LEFT JOIN status sa ON sa.tx_hash = a.tx_hash
LEFT JOIN status sb ON sb.tx_hash = b.tx_hash
ORDER BY seconds_apart, a.transaction_id
