-- 152_partner_users_receiver_default
-- Question: For each mock-up partner, how many users does the receiver-default rule give, against
--           distinct signers and against the relayer rule, and how far does the rule's known limit
--           reach (non-EVM transfers signed by a relayer, which count the relayer as the user)?
-- Grain:    one row per partner (base-app, phantom, metamask-bridge, rabbykmsv2) and one for the
--           whole file. Partner pooling as 132_partner_users_under_relayer_rule: a partner's rows
--           are its integrators of class partner in the map.
-- Definition applied (a variant of the relayer rule):
--   - users_receiver_default: count(DISTINCT CASE WHEN placeholder THEN tx_from ELSE receiver END).
--     A user is the transfer's receiver, or tx_from when the destination is non-EVM, meaning the
--     receiver is LI.FI's placeholder 0x11f111f111f111f111f111f111f111f111f111f1
--     (46_receiver_sentinel_by_destination: the placeholder marks exactly the non-EVM rows). One
--     address list, so an address that signs non-EVM rows and receives EVM rows counts once. The
--     rule uses no relayer list.
--   - distinct_receivers_evm_destination: distinct receivers on rows whose receiver is not the
--     placeholder.
--   - users_under_relayer_rule: the relayer rule, logic of query 132, kept beside the new rule; it
--     reproduces 132's users_under_rule. Relayer: a tx_from signing rows for at least 5 distinct
--     integrator strings in the week (131_relayer_rule_market, 132).
--   - relayer_signed_rows_to_placeholder, relayers_on_placeholder_rows: rows to the placeholder
--     signed by a relayer, and the distinct relayers on them. The relayer list is used only here,
--     to measure the limit: under the rule each of these relayers counts as a user.
--   - distinct_tx_from: the count a "unique users = distinct senders" tile would show.
-- Inputs:   transfers (provided data), ref_integrator_map.

WITH mock(partner, ord) AS (
    VALUES ('base-app', 1), ('phantom', 2), ('metamask-bridge', 3), ('rabbykmsv2', 4)
),
a AS (
    SELECT tx_from, count(DISTINCT integrator) AS n_int
    FROM transfers GROUP BY tx_from
),
t AS (
    SELECT tr.tx_from, tr.receiver, m.partner, m.class,
           a.n_int >= 5                                                AS relayer,
           tr.receiver = '0x11f111f111f111f111f111f111f111f111f111f1'  AS placeholder
    FROM transfers tr
    JOIN a USING (tx_from)
    LEFT JOIN ref_integrator_map m ON coalesce(m.integrator, '') = tr.integrator
),
groups AS (
    SELECT mk.ord, mk.partner AS label, t.* FROM t JOIN mock mk ON mk.partner = t.partner AND t.class = 'partner'
    UNION ALL SELECT 5, '(whole file)', * FROM t
)
SELECT label                                                              AS partner,
       count(*)                                                           AS n_rows,
       count(DISTINCT tx_from)                                            AS distinct_tx_from,
       count(DISTINCT CASE WHEN relayer THEN receiver ELSE tx_from END)   AS users_under_relayer_rule,
       count(DISTINCT CASE WHEN placeholder THEN tx_from ELSE receiver END) AS users_receiver_default,
       count(DISTINCT receiver) FILTER (WHERE NOT placeholder)            AS distinct_receivers_evm_destination,
       count(*) FILTER (WHERE placeholder)                                AS rows_to_placeholder,
       count(*) FILTER (WHERE placeholder AND relayer)                    AS relayer_signed_rows_to_placeholder,
       count(DISTINCT tx_from) FILTER (WHERE placeholder AND relayer)     AS relayers_on_placeholder_rows
FROM groups
GROUP BY ord, label
ORDER BY ord
