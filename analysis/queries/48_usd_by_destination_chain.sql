-- 48_usd_by_destination_chain
-- Question: How many rows and how much USD go to each destination chain id, what is each id
--           in LI.FI's published sources, and through which bridges is it reached?
-- Grain:    one row per destination_chain_id (69), most rows first.
-- Definition applied:
--   - Destination: destination_chain_id as the event carries it (LI.FI's contract-side id).
--     Tron appears twice: 1885080386571452 (contract id) and 728126428 (API id);
--     53_rows_by_destination_chain_type merges them.
--   - Name, key, chain_type, namespace, api_chain_id, listed_by_v1_chains (with all six chain
--     types), types_chainid_member (the @lifi/types ChainId enum), connections_http_status
--     (LI.FI's /v1/connections validation on 2026-10-28) and
--     quote_onchain_destination_chain_id (the id a quote's calldata carried) come from
--     LI.FI's chain-id registry (reference data).
--   - usd: amount_usd (headline); usd_provided: amount_usd_provided. Shares are of the
--     whole file.
--   - above_2_53: the id exceeds 9,007,199,254,740,991, beyond float64's exact integers.
--   - bridges: each bridge with its rows to the id, most rows first.
-- Inputs:   transfers_priced (headline: reference data for its CoinGecko-priced rows);
--           ref_lifi_chain_id_registry (reference data).

WITH per_bridge AS (
    SELECT destination_chain_id, bridge, count(*) AS n
    FROM transfers
    GROUP BY destination_chain_id, bridge
),
bridge_list AS (
    SELECT destination_chain_id, string_agg(bridge || ' ' || CAST(n AS VARCHAR), ', ' ORDER BY n DESC, bridge) AS bridges
    FROM per_bridge
    GROUP BY destination_chain_id
),
per_id AS (
    SELECT destination_chain_id,
           count(*)                                                                      AS n_rows,
           count(*) FILTER (WHERE receiver = '0x11f111f111f111f111f111f111f111f111f111f1') AS sentinel_rows,
           sum(amount_usd)                                                               AS usd,
           sum(amount_usd_provided)                                                      AS usd_provided
    FROM transfers_priced
    GROUP BY destination_chain_id
),
total AS (
    SELECT sum(n_rows) AS n_rows, sum(usd) AS usd, sum(usd_provided) AS usd_provided FROM per_id
)
SELECT p.destination_chain_id,
       r.name,
       r.key,
       r.chain_type,
       r.namespace,
       r.api_chain_id,
       r.listed_by_v1_chains,
       p.n_rows,
       round(100.0 * p.n_rows / total.n_rows, 2)              AS pct_rows,
       p.sentinel_rows,
       round(p.usd, 2)                                        AS usd,
       round(100.0 * p.usd / total.usd, 2)                    AS pct_usd,
       round(p.usd_provided, 2)                               AS usd_provided,
       round(100.0 * p.usd_provided / total.usd_provided, 2)  AS pct_usd_provided,
       p.destination_chain_id > 9007199254740991              AS above_2_53,
       r.types_chainid_member,
       r.connections_http_status,
       r.quote_onchain_destination_chain_id,
       b.bridges
FROM per_id p
CROSS JOIN total
LEFT JOIN ref_lifi_chain_id_registry r ON r.chain_id = p.destination_chain_id
LEFT JOIN bridge_list b USING (destination_chain_id)
ORDER BY p.n_rows DESC, p.destination_chain_id
