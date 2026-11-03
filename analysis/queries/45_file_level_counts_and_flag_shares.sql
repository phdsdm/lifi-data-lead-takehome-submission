-- 45_file_level_counts_and_flag_shares
-- Question: What share of rows carries each flag or row property Task 1 uses:
--           a source-side step, a destination call, the sender as receiver, the native
--           asset, a same-chain destination; and how many emitting contracts are there?
-- Grain:    one row for the whole file.
-- Definition applied:
--   - hasSourceSwaps / hasDestinationCall: the bridge_data flags.
--   - sender_is_receiver: tx_from = receiver.
--   - native_asset: sending_asset_id = the zero address (ETH on four chains, BNB on bnb,
--     POL on polygon).
--   - same_chain: destination_chain_id = the source chain's id (ethereum 1, optimism 10,
--     bnb 56, polygon 137, base 8453, arbitrum 42161).
--   - native_symbol_by_chain: the symbol transfers_priced gives the zero address on each
--     chain (prices.csv, else LI.FI's token list: polygon's POL comes from the latter).
--   - Shares are of all 124,858 rows, in percent.
-- Inputs:   transfers (provided data); transfers_priced (the native symbols only; POL is
--           reference data).

WITH source_ids(chain, chain_id) AS (
    VALUES ('ethereum', 1), ('optimism', 10), ('bnb', 56), ('polygon', 137), ('base', 8453), ('arbitrum', 42161)
),
t AS (
    SELECT t.*, t.destination_chain_id = s.chain_id AS same_chain
    FROM transfers t JOIN source_ids s USING (chain)
)
SELECT count(*)                                                                               AS n_rows,
       count(DISTINCT chain)                                                                  AS source_chains,
       count(DISTINCT contract_address)                                                       AS contract_addresses,
       count(DISTINCT (chain, contract_address))                                              AS chain_contract_pairs,
       count(*) FILTER (WHERE has_source_swaps)                                               AS has_source_swaps_rows,
       round(100.0 * count(*) FILTER (WHERE has_source_swaps) / count(*), 2)                  AS pct_has_source_swaps,
       count(*) FILTER (WHERE has_destination_call)                                           AS has_destination_call_rows,
       round(100.0 * count(*) FILTER (WHERE has_destination_call) / count(*), 2)              AS pct_has_destination_call,
       count(*) FILTER (WHERE tx_from = receiver)                                             AS sender_is_receiver_rows,
       round(100.0 * count(*) FILTER (WHERE tx_from = receiver) / count(*), 2)                AS pct_sender_is_receiver,
       count(*) FILTER (WHERE sending_asset_id = '0x0000000000000000000000000000000000000000') AS native_asset_rows,
       round(100.0 * count(*) FILTER (WHERE sending_asset_id = '0x0000000000000000000000000000000000000000') / count(*), 2) AS pct_native_asset,
       count(*) FILTER (WHERE same_chain)                                                     AS same_chain_rows,
       round(100.0 * count(*) FILTER (WHERE same_chain) / count(*), 2)                        AS pct_same_chain,
       (SELECT string_agg(DISTINCT chain || ' ' || symbol, ', ' ORDER BY chain || ' ' || symbol)
          FROM transfers_priced
         WHERE sending_asset_id = '0x0000000000000000000000000000000000000000')                AS native_symbol_by_chain
FROM t
