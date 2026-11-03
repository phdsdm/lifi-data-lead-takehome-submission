-- 01_referrer_summary
-- Question: How is `referrer` filled, how do referrer addresses map to integrator
--           strings, and do referrer addresses act as senders or receivers in the file?
-- Grain:    one row for the whole file (124,858 events).
-- Definition applied:
--   - A row is one LiFiTransferStarted event; integrator is the raw string, no normalisation.
--   - Zero referrer: referrer = 0x0000000000000000000000000000000000000000.
--   - A referrer address is a distinct non-zero referrer value.
--   - "Seen as tx_from" / "seen as receiver": rows anywhere in the file whose tx_from /
--     receiver equals a referrer address. "On its own referrer row" means the same row
--     carries that address as referrer; "on other rows" means it does not.
-- Inputs:   transfers (provided data only).

WITH t AS (
    SELECT *, referrer <> '0x0000000000000000000000000000000000000000' AS has_referrer
    FROM transfers
),
refs AS (
    SELECT referrer, count(DISTINCT integrator) AS integrators
    FROM t
    WHERE has_referrer
    GROUP BY referrer
),
as_sender AS (
    SELECT t.referrer = r.referrer AS own_row, t.tx_from AS address
    FROM t JOIN refs r ON t.tx_from = r.referrer
),
as_receiver AS (
    SELECT t.referrer = r.referrer AS own_row, t.receiver AS address
    FROM t JOIN refs r ON t.receiver = r.referrer
)
SELECT
    (SELECT count(*) FROM t)                                                   AS n_rows,
    (SELECT count(*) FROM t WHERE NOT has_referrer)                            AS zero_referrer_rows,
    round(100.0 * (SELECT count(*) FROM t WHERE NOT has_referrer)
                / (SELECT count(*) FROM t), 2)                                 AS zero_referrer_pct,
    (SELECT count(*) FROM t WHERE has_referrer)                                AS nonzero_referrer_rows,
    (SELECT count(*) FROM refs)                                                AS referrer_addresses,
    (SELECT count(*) FROM refs WHERE integrators = 1)                          AS referrers_under_one_integrator,
    (SELECT max(integrators) FROM refs)                                        AS max_integrators_per_referrer,
    (SELECT count(DISTINCT integrator) FROM t WHERE has_referrer)              AS integrators_using_a_referrer,
    (SELECT count(DISTINCT integrator) FROM t)                                 AS integrators_in_file,
    (SELECT count(DISTINCT address) FROM as_sender)                            AS referrers_seen_as_tx_from,
    (SELECT count(*) FROM as_sender WHERE own_row)                             AS tx_from_rows_on_own_referrer_row,
    (SELECT count(*) FROM as_sender WHERE NOT own_row)                         AS tx_from_rows_on_other_rows,
    (SELECT count(DISTINCT address) FROM as_receiver)                          AS referrers_seen_as_receiver,
    (SELECT count(*) FROM as_receiver WHERE own_row)                           AS receiver_rows_on_own_referrer_row,
    (SELECT count(*) FROM as_receiver WHERE NOT own_row)                       AS receiver_rows_on_other_rows
