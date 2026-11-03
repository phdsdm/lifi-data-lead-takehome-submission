-- 57_token_symbols_addresses_decimals
-- Question: Where is a token symbol not a key: one symbol on several addresses of a chain,
--           one symbol with different decimals across chains, and a symbol that differs
--           between prices.csv and LI.FI's token list?
-- Grain:    a summary row, then one row per prices.csv (chain, token_address) pair that falls
--           under at least one of the three cases, by symbol and chain.
-- Definition applied:
--   - Pairs and symbols are those of prices.csv (244 pairs). shares_symbol_on_chain: another
--     address on the same chain carries the same symbol. decimals_vary_for_symbol: the symbol
--     carries more than one decimals value across chains. symbol_differs_from_lifi: LI.FI's
--     token list (source chain id, lowercased address) gives another symbol.
--   - lifi_name / lifi_coin_key: LI.FI's name and coinKey for the pair, which tell native
--     USDC from bridged USDC.e.
-- Inputs:   prices (provided data); ref_lifi_api_tokens_by_chain (reference data).

WITH source_ids(chain, chain_id) AS (
    VALUES ('ethereum', 1), ('optimism', 10), ('bnb', 56), ('polygon', 137), ('base', 8453), ('arbitrum', 42161)
),
pairs AS (
    SELECT DISTINCT p.chain, p.token_address, p.symbol, p.decimals, s.chain_id
    FROM prices p JOIN source_ids s USING (chain)
),
lifi AS (
    SELECT chainId AS chain_id, lower(address) AS address,
           any_value(symbol) AS symbol, any_value(name) AS name, any_value(coinKey) AS coin_key
    FROM ref_lifi_api_tokens_by_chain
    GROUP BY chainId, lower(address)
),
flagged AS (
    SELECT p.*,
           l.symbol AS lifi_symbol, l.name AS lifi_name, l.coin_key AS lifi_coin_key,
           count(*) OVER (PARTITION BY p.chain, p.symbol) > 1                  AS shares_symbol_on_chain,
           count(DISTINCT p.decimals) OVER (PARTITION BY p.symbol) > 1         AS decimals_vary_for_symbol,
           l.symbol IS DISTINCT FROM p.symbol                                  AS symbol_differs_from_lifi
    FROM pairs p
    LEFT JOIN lifi l ON l.chain_id = p.chain_id AND l.address = p.token_address
)
SELECT * FROM (
    SELECT 0 AS ord,
           '(summary)' AS symbol,
           NULL AS chain,
           NULL AS token_address,
           NULL::BIGINT AS decimals,
           'pairs ' || CAST(count(*) AS VARCHAR)
             || '; symbols ' || CAST(count(DISTINCT symbol) AS VARCHAR)
             || '; pairs sharing a symbol on a chain ' || CAST(count(*) FILTER (WHERE shares_symbol_on_chain) AS VARCHAR)
             || '; symbols with varying decimals ' || CAST(count(DISTINCT symbol) FILTER (WHERE decimals_vary_for_symbol) AS VARCHAR)
             || '; pairs whose symbol agrees with LI.FI ' || CAST(count(*) FILTER (WHERE NOT symbol_differs_from_lifi) AS VARCHAR)
                                                                  AS lifi_symbol,
           NULL AS lifi_name, NULL AS lifi_coin_key,
           NULL::BOOLEAN AS shares_symbol_on_chain, NULL::BOOLEAN AS decimals_vary_for_symbol, NULL::BOOLEAN AS symbol_differs_from_lifi
    FROM flagged
    UNION ALL
    SELECT 1, symbol, chain, token_address, decimals, lifi_symbol, lifi_name, lifi_coin_key,
           shares_symbol_on_chain, decimals_vary_for_symbol, symbol_differs_from_lifi
    FROM flagged
    WHERE shares_symbol_on_chain OR decimals_vary_for_symbol OR symbol_differs_from_lifi
)
ORDER BY ord, symbol, chain, token_address
