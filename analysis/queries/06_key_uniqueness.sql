-- 06_key_uniqueness
-- Question: Which keys are unique: the physical event key (chain, tx_hash, log_index), the
--           business key transactionId, and the transaction (chain, tx_hash)? How many
--           repeats are there of each?
-- Grain:    one row for the whole file.
-- Definition applied:
--   - A row is one LiFiTransferStarted event.
--   - A repeated transactionId is a value carried by more than one row; a multi-event
--     transaction is a (chain, tx_hash) carrying more than one row.
--   - identical_rows compares every column, bridge_data keys included.
-- Inputs:   transfers (provided data only).
-- Detail: 07_repeated_transaction_id_pairs.

WITH id_counts AS (
    SELECT transaction_id, count(*) AS n FROM transfers GROUP BY transaction_id
),
tx_counts AS (
    SELECT chain, tx_hash, count(*) AS n FROM transfers GROUP BY chain, tx_hash
),
hash_chains AS (
    SELECT tx_hash, count(DISTINCT chain) AS chains FROM transfers GROUP BY tx_hash
)
SELECT
    (SELECT count(*) FROM transfers)                                            AS n_rows,
    (SELECT count(*) FROM (SELECT DISTINCT chain, tx_hash, log_index FROM transfers)) AS distinct_event_keys,
    (SELECT count(*) FROM transfers) - (SELECT count(*) FROM (SELECT DISTINCT * FROM transfers)) AS identical_rows,
    (SELECT count(*) FROM id_counts)                                            AS distinct_transaction_ids,
    (SELECT count(*) FROM id_counts WHERE n > 1)                                AS repeated_transaction_ids,
    (SELECT max(n) FROM id_counts)                                              AS max_rows_per_transaction_id,
    (SELECT sum(n) FROM id_counts WHERE n > 1)                                  AS rows_with_repeated_transaction_id,
    (SELECT count(*) FROM tx_counts)                                            AS distinct_transactions,
    (SELECT count(*) FROM tx_counts WHERE n > 1)                                AS multi_event_transactions,
    (SELECT max(n) FROM tx_counts)                                              AS max_events_per_transaction,
    (SELECT sum(n) FROM tx_counts WHERE n > 1)                                  AS rows_in_multi_event_transactions,
    (SELECT count(*) FROM hash_chains WHERE chains > 1)                         AS tx_hashes_on_more_than_one_chain
