-- 68_partner_concentration
-- Question: How concentrated is the week's partner volume: what share of partner USD and rows
--           do the top 1, 5, 10 and 20 normalised partners carry?
-- Grain:    one row per cut (top 1, 5, 10, 20, then all 562 partners).
-- Definition applied, the ranking of 67_started_volume_by_partner:
--   - Partner: the normalised name of ref_integrator_map, class = 'partner' only (LI.FI's own
--     products, unattributed API traffic and test or dev strings are not ranked); underscore
--     partners are partners. Map joined on coalesce(m.integrator, '').
--   - Ranked by started USD (amount_usd, the headline, every row); ties by rows,
--     then name.
--   - pct_partner_usd / pct_partner_rows: the top N's share of all partners' USD and rows;
--     pct_started_usd: the same USD over the started-volume total (every class).
--   - underscore_partners: how many of the top N start with '_'; ranks_added: the partners
--     ranked after the previous cut up to this one, with their share of partner USD.
-- Inputs:   transfers_priced, ref_integrator_map. Depends on reference data for the
--           CoinGecko-priced rows. 24_integrator_usd_without_rows_above_1m shows how the
--           raw-string ranking moves without the 22 rows above $1M.

WITH t AS (
    SELECT p.amount_usd, m.partner, m.class, m.underscore
    FROM transfers_priced p
    LEFT JOIN ref_integrator_map m ON coalesce(m.integrator, '') = p.integrator
),
per_partner AS (
    SELECT partner,
           bool_or(underscore)            AS underscore,
           count(*)                       AS n_rows,
           coalesce(sum(amount_usd), 0)   AS usd
    FROM t
    WHERE class = 'partner'
    GROUP BY partner
),
ranked AS (
    SELECT *, row_number() OVER (ORDER BY usd DESC, n_rows DESC, partner) AS rank
    FROM per_partner
),
totals AS (
    SELECT (SELECT sum(usd) FROM per_partner)       AS partner_usd,
           (SELECT sum(n_rows) FROM per_partner)    AS partner_rows,
           (SELECT count(*) FROM per_partner)       AS partners,
           (SELECT sum(amount_usd) FROM t)          AS started_usd
),
cuts AS (
    SELECT cut_order, top_n, lag(top_n, 1, 0) OVER (ORDER BY cut_order) AS previous_n
    FROM (
        SELECT * FROM (VALUES (1, 1), (2, 5), (3, 10), (4, 20)) v(cut_order, top_n)
        UNION ALL
        SELECT 5, partners FROM totals
    )
)
SELECT CASE WHEN c.cut_order = 5 THEN 'all partners' ELSE 'top ' || c.top_n END     AS cut,
       c.top_n                                                                       AS partners,
       round(sum(r.usd), 2)                                                          AS usd,
       round(100.0 * sum(r.usd) / totals.partner_usd, 2)                             AS pct_partner_usd,
       round(100.0 * sum(r.usd) / totals.started_usd, 2)                             AS pct_started_usd,
       sum(r.n_rows)                                                                 AS n_rows,
       round(100.0 * sum(r.n_rows) / totals.partner_rows, 2)                         AS pct_partner_rows,
       count(*) FILTER (WHERE r.underscore)                                          AS underscore_partners,
       CASE WHEN c.cut_order < 5 THEN
           string_agg(r.partner || ' ' || CAST(round(100.0 * r.usd / totals.partner_usd, 2) AS VARCHAR) || '%', ', '
                      ORDER BY r.rank) FILTER (WHERE r.rank > c.previous_n)
       END                                                                           AS ranks_added
FROM cuts c
CROSS JOIN totals
JOIN ranked r ON r.rank <= c.top_n
GROUP BY c.cut_order, c.top_n, totals.partner_usd, totals.partner_rows, totals.started_usd
ORDER BY c.cut_order
