-- 67_started_volume_by_partner
-- Question: Which normalised partners carry the week's started volume, ranked over partners only,
--           and what do LI.FI's own products, unattributed API traffic and test or dev traffic
--           carry beside them?
-- Grain:    section 1: one row per normalised partner of class partner (562), ranked by USD;
--           section 2: one line per group (all partners, of which underscore partners,
--           lifi_product, unattributed_api, test_or_dev); section 3: the started-volume total.
-- Definition applied:
--   - Partner: the normalised name of ref_integrator_map (data/reference/integrator_map.csv):
--     the seven variant families and tangem / tangem-pay-prod merged, every other string
--     its own partner. Ranked over class = 'partner' only (LI.FI's own products are
--     excluded when partners are ranked; lifi-api is unattributed API traffic, and
--     test_or_dev strings are out of partner counts; the map adds whitewallet-qa and
--     hashport-wallet-e2e to them by hand). Underscore strings are partners, flagged in
--     `underscore`.
--   - A partner's rows, senders and USD pool the rows of its partner-class strings only; a
--     test_or_dev string under a partner's name (base-app-testing, tria-dev, and by hand
--     dev.jumper.exchange, Reah-STG, ...) is in the test_or_dev line. That line's `partners`
--     counts distinct names, so the hand-made links can move it.
--   - Started volume, every row; same-chain *Dex rows included (65_started_volume gives
--     the split). USD: amount_usd, the headline. Senders: distinct tx_from.
--   - pct_partner_usd: share of the partner total (section 2's 'all partners' line);
--     cum_pct_partner_usd: running share down the ranking; pct_started_usd: share of the
--     started-volume total. Ties in USD rank by rows, then name.
--   - Map joined on coalesce(m.integrator, ''): its empty-string row loads as NULL.
-- Inputs:   transfers_priced, ref_integrator_map. usd depends on reference data for its
--           CoinGecko-priced rows. Concentration of the ranking: 68_partner_concentration.

WITH t AS (
    SELECT p.integrator, p.tx_from, p.amount_usd, p.price_source,
           m.partner, m.class, m.underscore
    FROM transfers_priced p
    LEFT JOIN ref_integrator_map m ON coalesce(m.integrator, '') = p.integrator
),
totals AS (
    SELECT sum(amount_usd)                                  AS started_usd,
           sum(amount_usd) FILTER (WHERE class = 'partner') AS partner_usd
    FROM t
),
per_partner AS (
    SELECT partner,
           bool_or(underscore)                                                AS underscore,
           count(DISTINCT integrator)                                         AS strings,
           string_agg(DISTINCT integrator, ', ' ORDER BY integrator)          AS raw_strings,
           count(*)                                                           AS n_rows,
           count(DISTINCT tx_from)                                            AS senders,
           coalesce(sum(amount_usd), 0)                                       AS usd,
           count(*) FILTER (WHERE price_source = 'coingecko')                 AS rows_coingecko,
           count(*) - count(amount_usd)                                       AS rows_unpriced
    FROM t
    WHERE class = 'partner'
    GROUP BY partner
),
ranked AS (
    SELECT *,
           row_number() OVER (ORDER BY usd DESC, n_rows DESC, partner) AS rank
    FROM per_partner
),
groups AS (
    SELECT 1 AS grp, '(all partners)' AS label, 'partner' AS class, * FROM t WHERE class = 'partner'
    UNION ALL
    SELECT 2, '(of which underscore partners)', 'partner', * FROM t WHERE class = 'partner' AND underscore
    UNION ALL
    SELECT 3, '(lifi_product)', 'lifi_product', * FROM t WHERE class = 'lifi_product'
    UNION ALL
    SELECT 4, '(unattributed_api)', 'unattributed_api', * FROM t WHERE class = 'unattributed_api'
    UNION ALL
    SELECT 5, '(test_or_dev)', 'test_or_dev', * FROM t WHERE class = 'test_or_dev'
    UNION ALL
    SELECT 6, '(started volume: every row)', NULL, * FROM t
),
group_lines AS (
    SELECT grp,
           label,
           class,
           count(DISTINCT partner)                                            AS partners,
           count(DISTINCT integrator)                                         AS strings,
           CASE WHEN grp IN (2, 3, 4, 5)
                THEN string_agg(DISTINCT coalesce(nullif(integrator, ''), '(empty string)'), ', '
                                ORDER BY coalesce(nullif(integrator, ''), '(empty string)'))
           END                                                                AS raw_strings,
           count(*)                                                           AS n_rows,
           count(DISTINCT tx_from)                                            AS senders,
           coalesce(sum(amount_usd), 0)                                       AS usd,
           count(*) FILTER (WHERE price_source = 'coingecko')                 AS rows_coingecko,
           count(*) - count(amount_usd)                                       AS rows_unpriced
    FROM groups
    GROUP BY grp, label, class
)
SELECT section, rank, partner, class, underscore, partners, strings, raw_strings,
       n_rows, senders, usd, pct_partner_usd, cum_pct_partner_usd, pct_started_usd,
       rows_coingecko, rows_unpriced
FROM (
    SELECT 1                                                              AS section,
           r.rank,
           r.partner,
           'partner'                                                      AS class,
           r.underscore,
           1                                                              AS partners,
           r.strings,
           r.raw_strings,
           r.n_rows,
           r.senders,
           round(r.usd, 2)                                                AS usd,
           round(100.0 * r.usd / totals.partner_usd, 4)                   AS pct_partner_usd,
           round(100.0 * sum(r.usd) OVER (ORDER BY r.rank) / totals.partner_usd, 4) AS cum_pct_partner_usd,
           round(100.0 * r.usd / totals.started_usd, 4)                   AS pct_started_usd,
           r.rows_coingecko,
           r.rows_unpriced,
           r.rank                                                         AS ord
    FROM ranked r CROSS JOIN totals
    UNION ALL
    SELECT CASE WHEN g.grp = 6 THEN 3 ELSE 2 END,
           NULL,
           g.label,
           g.class,
           CASE WHEN g.grp = 2 THEN TRUE END,
           g.partners,
           g.strings,
           g.raw_strings,
           g.n_rows,
           g.senders,
           round(g.usd, 2),
           CASE WHEN g.grp IN (1, 2) THEN round(100.0 * g.usd / totals.partner_usd, 4) END,
           NULL,
           round(100.0 * g.usd / totals.started_usd, 4),
           g.rows_coingecko,
           g.rows_unpriced,
           g.grp
    FROM group_lines g CROSS JOIN totals
)
ORDER BY section, ord
