-- 153_receiver_rule_shared_and_bulk_checks
-- Question: Under the receiver-default user rule, how often is one receiver shared by many signers
--           (a receiver that may not be one user), and how often does a non-relayer signer send to
--           someone else or to many receivers (bulk senders)?
-- Grain:    one row, whole file.
-- Definition applied (152_partner_users_receiver_default):
--   - Placeholder: receiver = 0x11f111f111f111f111f111f111f111f111f111f1, the non-EVM rows
--     (46_receiver_sentinel_by_destination). Relayer: a tx_from signing rows for at least 5 distinct
--     integrator strings in the week (131_relayer_rule_market). The relayer test is used here only
--     to set the scope of the checks; the rule itself uses no relayer list.
--   - Shared receivers, scope: rows with a non-placeholder receiver, relayer-signed rows included.
--     rows_evm_destination is that scope; receivers_10plus_signers and receivers_100plus_signers
--     are receivers with at least 10 or 100 distinct tx_from on it. pct_rows_receivers_10plus_signers
--     has rows_evm_destination as its denominator.
--   - Differing receiver, scope: rows not signed by a relayer and with a non-placeholder receiver.
--     differing_receiver_rows are those where tx_from differs from receiver.
--     pct_differing_of_rows_not_relayer_signed has as denominator rows_not_relayer_signed: every row
--     of the file not signed by a relayer, the rows to the placeholder included, which cannot differ
--     by this test. pct_differing_of_scope has rows_not_relayer_evm_destination as its denominator:
--     the same rows without those to the placeholder.
--   - Bulk signers, same scope: signers_10plus_receivers are tx_from with at least 10 distinct
--     receivers, their own address counted if it receives. rows_signers_10plus_receivers are all
--     their rows in the scope, those to themselves included.
-- Inputs:   transfers (provided data).

WITH a AS (
    SELECT tx_from, count(DISTINCT integrator) AS n_int
    FROM transfers GROUP BY tx_from
),
t AS (
    SELECT tr.tx_from, tr.receiver,
           a.n_int >= 5                                                AS relayer,
           tr.receiver = '0x11f111f111f111f111f111f111f111f111f111f1'  AS placeholder
    FROM transfers tr
    JOIN a USING (tx_from)
),
per_receiver AS (
    SELECT receiver, count(DISTINCT tx_from) AS signers, count(*) AS n
    FROM t WHERE NOT placeholder GROUP BY receiver
),
per_signer AS (
    SELECT tx_from, count(DISTINCT receiver) AS receivers, count(*) AS n
    FROM t WHERE NOT placeholder AND NOT relayer GROUP BY tx_from
),
shared AS (
    SELECT sum(n)                                              AS rows_evm_destination,
           count(*)                                            AS distinct_receivers,
           count(*) FILTER (WHERE signers >= 10)               AS receivers_10plus_signers,
           coalesce(sum(n) FILTER (WHERE signers >= 10), 0)    AS rows_receivers_10plus_signers,
           round(100.0 * coalesce(sum(n) FILTER (WHERE signers >= 10), 0) / sum(n), 2)
                                                               AS pct_rows_receivers_10plus_signers,
           count(*) FILTER (WHERE signers >= 100)              AS receivers_100plus_signers,
           max(signers)                                        AS max_signers_one_receiver
    FROM per_receiver
),
differing AS (
    SELECT count(*) FILTER (WHERE NOT relayer)                                    AS rows_not_relayer_signed,
           count(*) FILTER (WHERE NOT relayer AND NOT placeholder)                AS rows_not_relayer_evm_destination,
           count(*) FILTER (WHERE NOT relayer AND NOT placeholder AND tx_from <> receiver)
                                                                                  AS differing_receiver_rows
    FROM t
),
bulk AS (
    SELECT count(*) FILTER (WHERE receivers >= 10)             AS signers_10plus_receivers,
           coalesce(sum(n) FILTER (WHERE receivers >= 10), 0)  AS rows_signers_10plus_receivers,
           max(receivers)                                      AS max_receivers_one_signer
    FROM per_signer
)
SELECT shared.*,
       differing.rows_not_relayer_signed,
       differing.rows_not_relayer_evm_destination,
       differing.differing_receiver_rows,
       round(100.0 * differing.differing_receiver_rows / differing.rows_not_relayer_signed, 2)
                                                               AS pct_differing_of_rows_not_relayer_signed,
       round(100.0 * differing.differing_receiver_rows / differing.rows_not_relayer_evm_destination, 2)
                                                               AS pct_differing_of_scope,
       bulk.*
FROM shared, differing, bulk
