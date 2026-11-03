-- 154_partner_weekly_users_by_volume_band
-- Question: How are a partner's active users of the week spread over USD volume bands, and how much
--           of the partner's bridge volume does each band carry? This is a one-week stand-in: the
--           core metric is monthly active users, which the sample cannot measure.
-- Grain:    one row per (partner, band): base-app, phantom, metamask-bridge, rabbykmsv2 and the
--           whole file, each with the five volume bands and the 'no priced rows' line (30 rows).
--           Partner pooling as 132_partner_users_under_relayer_rule: a partner's rows are its
--           integrators of class partner in the map, so base-app excludes base-app-testing.
--           The whole file is every class. A user is counted within the group: an address active
--           with two partners counts once in each, and its USD is summed across them only in the
--           whole-file rows, so the partner rows do not add up to the whole file.
-- Definition applied (the sample's proxy for weekly users by volume band; bridge_volume_usd in
-- task_1.md):
--   - Scope: bridge rows only, destination_chain_id differs from the source chain's id, so
--     the 295 same-chain *Dex rows are out. An address active only on same-chain rows is not a user
--     here, which is the difference from 152_partner_users_receiver_default (every row).
--   - User, THE SAMPLE'S PROXY: receiver, or the signing address tx_from when receiver is the
--     non-EVM placeholder 0x11f111f111f111f111f111f111f111f111f111f1. The proposed rule takes
--     the real receiver from the status record on non-EVM rows and the signing address only where
--     that is unavailable. The status record is not available for every row, so the sample's
--     figures keep the signing address on every non-EVM row.
--   - usd: sum of amount_usd of transfers_priced over the user's bridge rows in the seven days.
--   - Bands: lower bound included, upper bound excluded, so a user at exactly $100 is in
--     $100–$500 and a user at exactly $10,000 is in 'above $10k'. A user at $0 is in $0–$100.
--     users_on_lower_bound counts the users of a band whose sum equals the band's lower bound.
--   - Unpriced rows (amount_usd NULL, neither feed prices them): a user with only such rows has
--     no USD, is not placed in $0–$100 and is counted in the band 'no priced rows' with usd 0. A
--     user with at least one priced row is banded on the priced rows; its unpriced rows add
--     nothing to usd (users_with_unpriced_rows counts those users, unpriced_rows the rows).
--   - pct_users: of users_total, every user of the group, 'no priced rows' included.
--     pct_usd: of usd_total, the group's bridge USD. Both are shares of the group, not of the file.
--   - largest_user_usd: the band's largest single user.
--   - A limit of the sample's figures, measured in the band: under the proxy, a non-EVM transfer
--     signed by a relayer counts the relayer as its user, so such a "user" sums many people's
--     transfers and lands in a high band. relayer_placeholder_users: users of the band with at
--     least one such row; relayer_placeholder_rows, relayer_placeholder_usd: those rows and their
--     USD. Relayer: a tx_from signing rows for at least 5 distinct integrator strings in the week,
--     over every row of the file, as 152_partner_users_receiver_default. The relayer test is used
--     only here, to measure the limit; neither the proxy nor the proposed rule uses a relayer list.
-- Inputs:   transfers_priced, ref_integrator_map. usd depends on reference data for its
--           CoinGecko-priced rows: coingecko_rows, coingecko_usd.

WITH source_ids(chain, chain_id) AS (
    VALUES ('ethereum', 1), ('optimism', 10), ('bnb', 56), ('polygon', 137), ('base', 8453), ('arbitrum', 42161)
),
mock(partner, ord) AS (
    VALUES ('base-app', 1), ('phantom', 2), ('metamask-bridge', 3), ('rabbykmsv2', 4), ('(whole file)', 5)
),
bands(band, band_ord, lower_usd, upper_usd) AS (
    VALUES ('$0–$100',        1, 0.0,     100.0),
           ('$100–$500',      2, 100.0,   500.0),
           ('$500–$2,000',    3, 500.0,   2000.0),
           ('$2,000–$10k',    4, 2000.0,  10000.0),
           ('above $10k',     5, 10000.0, NULL),
           ('no priced rows', 6, NULL,    NULL)
),
a AS (
    SELECT tx_from, count(DISTINCT integrator) AS n_int
    FROM transfers GROUP BY tx_from
),
t AS (
    SELECT CASE WHEN p.receiver = '0x11f111f111f111f111f111f111f111f111f111f1' THEN p.tx_from ELSE p.receiver END AS user_address,
           p.amount_usd, p.price_source, m.partner, m.class,
           p.receiver = '0x11f111f111f111f111f111f111f111f111f111f1' AND a.n_int >= 5 AS relayer_placeholder
    FROM transfers_priced p
    JOIN source_ids s USING (chain)
    JOIN a ON a.tx_from = p.tx_from
    LEFT JOIN ref_integrator_map m ON coalesce(m.integrator, '') = p.integrator
    WHERE p.destination_chain_id <> s.chain_id
),
groups AS (
    SELECT t.partner AS label, t.user_address, t.amount_usd, t.price_source, t.relayer_placeholder
    FROM t JOIN mock mk ON mk.partner = t.partner AND t.class = 'partner'
    UNION ALL
    SELECT '(whole file)', user_address, amount_usd, price_source, relayer_placeholder FROM t
),
per_user AS (
    SELECT label, user_address,
           sum(amount_usd)                                                        AS usd,
           count(*)                                                               AS n_rows,
           count(*) FILTER (WHERE amount_usd IS NULL)                             AS unpriced_rows,
           count(*) FILTER (WHERE price_source = 'coingecko')                     AS coingecko_rows,
           coalesce(sum(amount_usd) FILTER (WHERE price_source = 'coingecko'), 0) AS coingecko_usd,
           count(*) FILTER (WHERE relayer_placeholder)                            AS relayer_placeholder_rows,
           coalesce(sum(amount_usd) FILTER (WHERE relayer_placeholder), 0)        AS relayer_placeholder_usd
    FROM groups
    GROUP BY label, user_address
),
banded AS (
    SELECT u.*, b.band_ord, b.lower_usd
    FROM per_user u
    JOIN bands b
      ON (u.usd IS NULL AND b.band_ord = 6)
      OR (u.usd >= b.lower_usd AND (b.upper_usd IS NULL OR u.usd < b.upper_usd))
),
totals AS (
    SELECT label, count(*) AS users_total, coalesce(sum(usd), 0) AS usd_total
    FROM per_user GROUP BY label
),
agg AS (
    SELECT label, band_ord,
           count(*)                                  AS users,
           coalesce(sum(usd), 0)                     AS usd,
           sum(n_rows)                               AS n_rows,
           count(*) FILTER (WHERE usd = lower_usd)   AS users_on_lower_bound,
           count(*) FILTER (WHERE unpriced_rows > 0) AS users_with_unpriced_rows,
           sum(unpriced_rows)                        AS unpriced_rows,
           sum(coingecko_rows)                       AS coingecko_rows,
           sum(coingecko_usd)                        AS coingecko_usd,
           max(usd)                                  AS largest_user_usd,
           count(*) FILTER (WHERE relayer_placeholder_rows > 0) AS relayer_placeholder_users,
           sum(relayer_placeholder_rows)             AS relayer_placeholder_rows,
           sum(relayer_placeholder_usd)              AS relayer_placeholder_usd
    FROM banded
    GROUP BY label, band_ord
)
SELECT mk.partner,
       b.band,
       coalesce(a.users, 0)                                     AS users,
       round(100.0 * coalesce(a.users, 0) / tot.users_total, 2) AS pct_users,
       round(coalesce(a.usd, 0), 2)                             AS usd,
       round(100.0 * coalesce(a.usd, 0) / tot.usd_total, 2)     AS pct_usd,
       coalesce(a.n_rows, 0)                                    AS n_rows,
       coalesce(a.users_on_lower_bound, 0)                      AS users_on_lower_bound,
       coalesce(a.users_with_unpriced_rows, 0)                  AS users_with_unpriced_rows,
       coalesce(a.unpriced_rows, 0)                             AS unpriced_rows,
       coalesce(a.coingecko_rows, 0)                            AS coingecko_rows,
       round(coalesce(a.coingecko_usd, 0), 2)                   AS coingecko_usd,
       round(a.largest_user_usd, 2)                             AS largest_user_usd,
       coalesce(a.relayer_placeholder_users, 0)                 AS relayer_placeholder_users,
       coalesce(a.relayer_placeholder_rows, 0)                  AS relayer_placeholder_rows,
       round(coalesce(a.relayer_placeholder_usd, 0), 2)         AS relayer_placeholder_usd,
       tot.users_total,
       round(tot.usd_total, 2)                                  AS usd_total
FROM mock mk
CROSS JOIN bands b
JOIN totals tot ON tot.label = mk.partner
LEFT JOIN agg a ON a.label = mk.partner AND a.band_ord = b.band_ord
ORDER BY mk.ord, b.band_ord
