-- 09_integrator_rows_and_senders
-- Question: For each raw integrator string, how many rows and how many distinct senders
--           does it have, how often does the sender also receive, and on how many days
--           is it active? Which strings have many rows and one sender?
-- Grain:    one row per raw integrator string (598, the empty string included).
-- Definition applied:
--   - Integrator is the raw string, no normalisation map; the flag columns mark the
--     strings the definition choices concern, they do not filter anything:
--       starts_with_underscore: first character '_';
--       starts_with_jumper_dot: starts with 'jumper.' (jumper.exchange and its variants);
--       starts_with_lifi_dash:  starts with 'lifi-' (lifi-api, lifi-develop-api, ...);
--       is_empty_string:        integrator = ''.
--   - Sender = tx_from, the address that signed the transaction (not necessarily the user).
--   - pct_sender_is_receiver: share of the string's rows with receiver = tx_from.
--   - active_days: distinct UTC dates of block_time (7 at most).
--   - same_chain_rows: rows whose destination_chain_id equals the source chain's id
--     (ethereum 1, optimism 10, bnb 56, polygon 137, base 8453, arbitrum 42161; ids from
--     LI.FI's /v1/chains). These are the 295 rows of the three *Dex tools.
--   - distinct_transaction_ids below n_rows marks a repeated transactionId.
-- Inputs:   transfers (provided data only).

WITH source_ids(chain, chain_id) AS (
    VALUES ('ethereum', 1), ('optimism', 10), ('bnb', 56), ('polygon', 137), ('base', 8453), ('arbitrum', 42161)
),
t AS (
    SELECT t.*, t.destination_chain_id = s.chain_id AS same_chain
    FROM transfers t JOIN source_ids s USING (chain)
)
SELECT integrator,
       count(*)                                                        AS n_rows,
       count(DISTINCT tx_from)                                         AS senders,
       round(count(*) / count(DISTINCT tx_from), 1)                    AS rows_per_sender,
       count(DISTINCT receiver)                                        AS receivers,
       round(100.0 * count(*) FILTER (WHERE tx_from = receiver) / count(*), 2) AS pct_sender_is_receiver,
       count(DISTINCT CAST(block_time AS DATE))                        AS active_days,
       count(DISTINCT chain)                                           AS source_chains,
       count(DISTINCT bridge)                                          AS bridges,
       count(DISTINCT transaction_id)                                  AS distinct_transaction_ids,
       count(*) FILTER (WHERE same_chain)                              AS same_chain_rows,
       min(block_time)                                                 AS first_row,
       max(block_time)                                                 AS last_row,
       starts_with(integrator, '_')                                    AS starts_with_underscore,
       starts_with(integrator, 'jumper.')                              AS starts_with_jumper_dot,
       starts_with(integrator, 'lifi-')                                AS starts_with_lifi_dash,
       integrator = ''                                                 AS is_empty_string
FROM t
GROUP BY integrator
ORDER BY n_rows DESC, integrator
