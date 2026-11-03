-- 132_partner_users_under_relayer_rule
-- Question: For each mock-up partner, how many of its rows
--           are signed by relayers, and how many users does it have under the rule (the receiver
--           on relayer-signed rows, the signer otherwise) against distinct signers?
-- Grain:    one row per partner (base-app, phantom, metamask-bridge, rabbykmsv2) and one for the
--           whole file.
-- Definition applied (the relayer rule):
--   - Relayer: a tx_from signing rows for at least 5 distinct integrator strings in the week
--     (131_relayer_rule_market). Partner rows pool its class-partner integrators (the map).
--   - users_under_rule: count(DISTINCT CASE WHEN relayer THEN receiver ELSE tx_from END): one
--     address list, so an address that both signs its own rows and receives relayed ones counts
--     once. users_research_variant: an alternative arithmetic, distinct non-relayer signers
--     plus distinct receivers on rows signed by relayers that never self-receive, which can count
--     an address twice and uses the stricter relayer test.
--   - relayer_rows_to_placeholder: relayer-signed rows whose receiver is the non-EVM placeholder
--     0x11f1…11f1; those rows contribute one "user" here and need the status record's toAddress
--     for the real one. users_under_rule_excl_placeholder leaves them out.
--   - distinct_tx_from: the count a "unique users = distinct senders" tile would show.
-- Inputs:   transfers (provided data), ref_integrator_map.

WITH mock(partner, ord) AS (
    VALUES ('base-app', 1), ('phantom', 2), ('metamask-bridge', 3), ('rabbykmsv2', 4)
),
a AS (
    SELECT tx_from, count(DISTINCT integrator) AS n_int, count(*) FILTER (WHERE receiver = tx_from) AS self_rows
    FROM transfers GROUP BY tx_from
),
t AS (
    SELECT tr.tx_from, tr.receiver, m.partner, m.class,
           a.n_int >= 5                                              AS relayer,
           a.n_int >= 5 AND a.self_rows = 0                          AS relayer_strict,
           tr.receiver = '0x11f111f111f111f111f111f111f111f111f111f1'  AS placeholder
    FROM transfers tr
    JOIN a USING (tx_from)
    LEFT JOIN ref_integrator_map m ON coalesce(m.integrator, '') = tr.integrator
),
groups AS (
    SELECT mk.ord, mk.partner AS label, t.* FROM t JOIN mock mk ON mk.partner = t.partner AND t.class = 'partner'
    UNION ALL SELECT 5, '(whole file)', * FROM t
)
SELECT label                                                                          AS partner,
       count(*)                                                                       AS n_rows,
       count(*) FILTER (WHERE relayer)                                                AS relayer_signed_rows,
       round(100.0 * count(*) FILTER (WHERE relayer) / count(*), 1)                   AS pct_relayer_signed,
       count(DISTINCT tx_from) FILTER (WHERE relayer)                                 AS relayers,
       count(DISTINCT tx_from)                                                        AS distinct_tx_from,
       count(DISTINCT CASE WHEN relayer THEN receiver ELSE tx_from END)               AS users_under_rule,
       count(DISTINCT CASE WHEN relayer AND NOT placeholder THEN receiver
                           WHEN NOT relayer THEN tx_from END)                         AS users_under_rule_excl_placeholder,
       count(DISTINCT tx_from) FILTER (WHERE NOT relayer_strict)
         + count(DISTINCT receiver) FILTER (WHERE relayer_strict)                     AS users_research_variant,
       count(*) FILTER (WHERE relayer AND placeholder)                                AS relayer_rows_to_placeholder,
       count(*) FILTER (WHERE placeholder)                                            AS rows_to_placeholder,
       round(100.0 * count(*) FILTER (WHERE receiver = tx_from) / count(*), 1)        AS pct_tx_from_eq_receiver
FROM groups
GROUP BY ord, label
ORDER BY ord
