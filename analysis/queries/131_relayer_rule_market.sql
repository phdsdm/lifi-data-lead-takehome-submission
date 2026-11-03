-- 131_relayer_rule_market
-- Question: How many signing addresses sign for many
--           integrators, how many rows do they sign, and do they ever receive what they send?
-- Grain:    one row per bucket of distinct integrator strings per tx_from (1, 2 to 4, 5 or more),
--           then one row for the relayer variant that never self-receives, then a total row.
-- Definition applied (the relayer rule):
--   - Relayer: a tx_from that signs rows for at least 5 distinct integrator strings in the week
--     (raw strings, not the map's partner: a relayer serving several integrators of one partner
--     would still count by strings). The bucket '5 or more (relayer)' is the rule.
--   - pct_rows_self_receive: rows whose receiver equals tx_from, over the bucket's rows.
--   - rows_to_placeholder_receiver: rows whose receiver is LI.FI's non-EVM placeholder
--     0x11f111f111f111f111f111f111f111f111f111f1 (46_receiver_sentinel_by_destination), where the
--     real receiver is only in the status record's toAddress.
--   - 'relayer, never self-receiving': a per-partner variant (at least 5 strings
--     and no row with receiver = tx_from), for reconciliation.
-- Inputs:   transfers (provided data only).

WITH a AS (
    SELECT tx_from,
           count(DISTINCT integrator)                                                        AS n_int,
           count(*)                                                                          AS n,
           count(*) FILTER (WHERE receiver = tx_from)                                        AS self_rows,
           count(*) FILTER (WHERE receiver = '0x11f111f111f111f111f111f111f111f111f111f1')   AS placeholder_rows
    FROM transfers
    GROUP BY tx_from
),
labelled AS (
    SELECT CASE WHEN n_int >= 5 THEN '5 or more (relayer)' WHEN n_int >= 2 THEN '2 to 4' ELSE '1' END AS bucket,
           CASE WHEN n_int >= 5 THEN 3 WHEN n_int >= 2 THEN 2 ELSE 1 END AS ord, * FROM a
    UNION ALL SELECT 'relayer, never self-receiving', 4, * FROM a WHERE n_int >= 5 AND self_rows = 0
    UNION ALL SELECT '(all addresses)', 5, * FROM a
)
SELECT bucket                                                          AS integrators_per_address,
       count(*)                                                        AS addresses,
       sum(n)                                                          AS n_rows,
       round(100.0 * sum(n) / (SELECT count(*) FROM transfers), 2)     AS pct_all_rows,
       round(100.0 * sum(self_rows) / sum(n), 1)                       AS pct_rows_self_receive,
       sum(placeholder_rows)                                           AS rows_to_placeholder_receiver,
       round(100.0 * sum(placeholder_rows) / sum(n), 1)                AS pct_rows_to_placeholder,
       max(n_int)                                                      AS max_integrators_one_address,
       max(n)                                                          AS max_rows_one_address
FROM labelled
GROUP BY ord, bucket
ORDER BY ord
