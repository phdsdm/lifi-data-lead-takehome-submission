-- 54_reference_coverage_counts
-- Question: How well do LI.FI's published lists cover what the file contains: chains, source
--           chains and their contract, bridge strings, tokens and destination ids?
-- Grain:    one row per check (10): what is counted, the count, and what it is out of.
-- Definition applied (reference data snapshots of 2026-10-28):
--   - /v1/chains (first fetch): lifi_api_chains.csv, chain types EVM, SVM, UTXO, MVM, TVM;
--     /v1/chains (all six types): lifi_api_chains_with_stl_2026-10-28.csv, STL added.
--   - Source chain ids: ethereum 1, optimism 10, bnb 56, polygon 137, base 8453,
--     arbitrum 42161. A source chain checks out when /v1/chains lists the id and its
--     diamondAddress equals the file's one contract_address.
--   - Bridge strings against the tool list's keys (exact match), split by the tool's kind.
--   - Token pairs: distinct (chain, sending_asset_id) against LI.FI's token list on the
--     source chain id and the lowercased address; verified = verificationStatus 'verified'.
--   - Destination ids against LI.FI's chain-id registry: named, and listed by /v1/chains with
--     all six chain types.
-- Inputs:   transfers (provided data); ref_lifi_api_chains,
--           ref_lifi_api_chains_with_stl_2026_10_28, ref_lifi_api_tools_bridges_and_exchanges,
--           ref_lifi_api_tokens_by_chain, ref_lifi_chain_id_registry (reference data).

WITH source_ids(chain, chain_id) AS (
    VALUES ('ethereum', 1), ('optimism', 10), ('bnb', 56), ('polygon', 137), ('base', 8453), ('arbitrum', 42161)
),
contract AS (
    SELECT any_value(contract_address) AS address, count(DISTINCT contract_address) AS n FROM transfers
),
bridges AS (
    SELECT DISTINCT t.bridge, k.kind
    FROM transfers t
    LEFT JOIN ref_lifi_api_tools_bridges_and_exchanges k ON k.key = t.bridge
),
pairs AS (
    SELECT DISTINCT t.chain, t.sending_asset_id, s.chain_id
    FROM transfers t JOIN source_ids s USING (chain)
),
tokens AS (
    SELECT chainId AS chain_id, lower(address) AS address, any_value(verificationStatus) AS verification
    FROM ref_lifi_api_tokens_by_chain
    GROUP BY chainId, lower(address)
),
pair_check AS (
    SELECT p.*, k.verification FROM pairs p
    LEFT JOIN tokens k ON k.chain_id = p.chain_id AND k.address = p.sending_asset_id
),
dest AS (
    SELECT DISTINCT t.destination_chain_id, r.name, r.listed_by_v1_chains
    FROM transfers t
    LEFT JOIN ref_lifi_chain_id_registry r ON r.chain_id = t.destination_chain_id
)
SELECT * FROM (
    SELECT 1 AS ord, 'EVM chains in /v1/chains (first fetch, five chain types)' AS checked,
           (SELECT count(*) FROM ref_lifi_api_chains WHERE chainType = 'EVM') AS value,
           (SELECT count(*) FROM ref_lifi_api_chains) AS out_of
    UNION ALL
    SELECT 2, 'chains in /v1/chains with all six chain types (Stellar added under STL)',
           (SELECT count(*) FROM ref_lifi_api_chains_with_stl_2026_10_28),
           (SELECT count(*) FROM ref_lifi_api_chains_with_stl_2026_10_28)
    UNION ALL
    SELECT 3, 'emitting contract addresses in the file',
           (SELECT n FROM contract), (SELECT n FROM contract)
    UNION ALL
    SELECT 4, 'source chain ids listed by /v1/chains with the file''s contract as diamondAddress',
           (SELECT count(*) FROM source_ids s JOIN ref_lifi_api_chains c ON c.id = s.chain_id
             WHERE lower(c.diamondAddress) = (SELECT address FROM contract)),
           (SELECT count(*) FROM source_ids)
    UNION ALL
    SELECT 5, 'bridge strings matching a tool key, kind bridge',
           (SELECT count(*) FROM bridges WHERE kind = 'bridge'), (SELECT count(*) FROM bridges)
    UNION ALL
    SELECT 6, 'bridge strings matching a tool key, kind exchange',
           (SELECT count(*) FROM bridges WHERE kind = 'exchange'), (SELECT count(*) FROM bridges)
    UNION ALL
    SELECT 7, 'token pairs known to LI.FI''s token list',
           (SELECT count(*) FROM pair_check WHERE verification IS NOT NULL), (SELECT count(*) FROM pair_check)
    UNION ALL
    SELECT 8, 'token pairs verified in LI.FI''s token list',
           (SELECT count(*) FROM pair_check WHERE verification = 'verified'), (SELECT count(*) FROM pair_check)
    UNION ALL
    SELECT 9, 'destination ids named in LI.FI''s chain-id registry',
           (SELECT count(*) FROM dest WHERE name IS NOT NULL), (SELECT count(*) FROM dest)
    UNION ALL
    SELECT 10, 'destination ids listed by /v1/chains with all six chain types',
           (SELECT count(*) FROM dest WHERE listed_by_v1_chains), (SELECT count(*) FROM dest)
)
ORDER BY ord
