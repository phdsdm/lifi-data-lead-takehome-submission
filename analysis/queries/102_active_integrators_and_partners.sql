-- 102_active_integrators_and_partners
-- Question: How many integrators and how many partners are active under the active rule (started volume of
--           at least $100 in the period), how many of them are underscore strings, how do the two
--           levels reconcile, and, for context only, how many strings of the classes the active rule does
--           not count would pass the same floor?
-- Grain:    one row per line (10). Line 1 is the active-partner figure and line 3 the
--           active-integrator figure; lines 2 and 4 are parts of them; lines 5 to 7 are context
--           and are not counted; lines 8 and 9 reconcile line 1 with line 3; line 10 is every
--           raw string of every class.
-- Definition applied:
--   - Period: The active rule defines active on a calendar month. The sample holds seven days
--     (2026-10-13 to 2026-10-19 UTC), so the figures are the monthly rule applied to the window,
--     an illustration and not a month. Daily active is 104_daily_active_integrators_and_partners.
--   - Rule: started USD >= 100. No transfer-count and no sender condition. Started USD is
--     the sum of amount_usd over the unit's rows, the headline (prices.csv, else the
--     CoinGecko snapshot), every row as in the started-volume definition. Rows neither feed prices add nothing.
--   - Integrator (lines 3, 4): one connection, the raw integrator string, class = 'partner' of
--     ref_integrator_map (563 strings). Partner (lines 1, 2): the organisation, the map's
--     partner name, class = 'partner' (562); its USD pools its partner-class strings (tangem with
--     tangem-pay-prod). A family's test_or_dev member does not count toward its partner.
--     Underscore strings are integrators and partners, flagged (lines 2 and 4).
--   - Context lines 5 to 7, per raw string, as the active rule does not count them: lifi_product (LI.FI's
--     own products), unattributed_api (lifi-api, lifi-sdk and the empty string),
--     test_or_dev (whitewallet-qa and hashport-wallet-e2e by hand).
--   - Line 8: partners with more than one integrator, passing = those with more than one active
--     integrator. Line 9: all partners, passing = partners active only by pooling, with no
--     integrator of their own at or above $100 alone. Active partners = active integrators -
--     (active integrators beyond the first in line 8's passing partners) + line 9's passing.
--   - candidates: units in the line; passing / failing: units meeting / missing the line's
--     condition; rows_passing, usd_passing and their shares are over the line's own rows and USD
--     (pct_usd_passing to 4 decimals: at $100 the excluded share is 0.0032%).
--     passing_units lists the passing units of lines 2, 4 to 9 with rows, senders and USD.
--   - Map joined on coalesce(m.integrator, ''): its empty-string row loads as NULL.
-- Inputs:   transfers_priced, ref_integrator_map. USD depends on reference data for its
--           CoinGecko-priced rows; the counts of rows and senders use provided data and
--           the map only.

WITH t AS (
    SELECT p.integrator, p.tx_from, p.amount_usd, m.partner, m.class, m.underscore
    FROM transfers_priced p
    LEFT JOIN ref_integrator_map m ON coalesce(m.integrator, '') = p.integrator
),
strings AS (
    SELECT class, partner, coalesce(nullif(integrator, ''), '(empty string)') AS integrator,
           bool_or(underscore) AS underscore,
           count(*) AS transfers, count(DISTINCT tx_from) AS senders, coalesce(sum(amount_usd), 0) AS usd
    FROM t GROUP BY class, partner, integrator
),
partners AS (
    SELECT partner, bool_or(underscore) AS underscore,
           count(*) AS transfers, count(DISTINCT tx_from) AS senders, coalesce(sum(amount_usd), 0) AS usd,
           (SELECT count(*) FROM strings s WHERE s.class = 'partner' AND s.partner = t.partner) AS integrators,
           (SELECT count(*) FROM strings s WHERE s.class = 'partner' AND s.partner = t.partner AND s.usd >= 100) AS active_integrators,
           (SELECT string_agg(s.integrator || ' $' || printf('%.2f', s.usd), ', ' ORDER BY s.usd DESC)
              FROM strings s WHERE s.class = 'partner' AND s.partner = t.partner AND s.usd >= 100) AS active_integrator_list
    FROM t WHERE class = 'partner' GROUP BY partner
),
units AS (
    SELECT 1 AS line_order, partner AS unit, underscore, transfers, senders, usd, usd >= 100 AS passes, NULL AS detail
    FROM partners
    UNION ALL
    SELECT 2, partner, underscore, transfers, senders, usd, usd >= 100, NULL
    FROM partners WHERE underscore
    UNION ALL
    SELECT 3, integrator, underscore, transfers, senders, usd, usd >= 100, NULL
    FROM strings WHERE class = 'partner'
    UNION ALL
    SELECT 4, integrator, underscore, transfers, senders, usd, usd >= 100, NULL
    FROM strings WHERE class = 'partner' AND underscore
    UNION ALL
    SELECT CASE class WHEN 'lifi_product' THEN 5 WHEN 'unattributed_api' THEN 6 WHEN 'test_or_dev' THEN 7 END,
           integrator, underscore, transfers, senders, usd, usd >= 100, NULL
    FROM strings WHERE class IN ('lifi_product', 'unattributed_api', 'test_or_dev')
    UNION ALL
    SELECT 8, partner, underscore, transfers, senders, usd, active_integrators > 1, active_integrator_list
    FROM partners WHERE integrators > 1
    UNION ALL
    SELECT 9, partner, underscore, transfers, senders, usd, usd >= 100 AND active_integrators = 0, NULL
    FROM partners
    UNION ALL
    SELECT 10, integrator, underscore, transfers, senders, usd, usd >= 100, NULL
    FROM strings
),
labels(line_order, line, unit_kind) AS (
    VALUES
        (1,  'active partners: started USD >= 100, pooled over the partner''s integrators', 'partner (merged)'),
        (2,  'of which underscore partners',                                                     'partner (merged)'),
        (3,  'active integrators: started USD >= 100, partner-class strings',              'integrator (raw string)'),
        (4,  'of which underscore integrators',                                                   'integrator (raw string)'),
        (5,  'context, not counted: lifi_product strings',                                        'raw string'),
        (6,  'context, not counted: unattributed_api strings',                                    'raw string'),
        (7,  'context, not counted: test_or_dev strings',                                         'raw string'),
        (8,  'reconciliation: partners with more than one integrator; passing = more than one active', 'partner (merged)'),
        (9,  'reconciliation: partners active only by pooling, no integrator at $100 alone',      'partner (merged)'),
        (10, 'reconciliation: every raw string, every class',                          'raw string')
)
SELECT l.line,
       l.unit_kind,
       100                                                                      AS min_usd,
       count(*)                                                                 AS candidates,
       count(*) FILTER (WHERE u.passes)                                         AS passing,
       count(*) FILTER (WHERE NOT u.passes)                                     AS failing,
       coalesce(sum(u.transfers) FILTER (WHERE u.passes), 0)                    AS rows_passing,
       round(100.0 * coalesce(sum(u.transfers) FILTER (WHERE u.passes), 0) / sum(u.transfers), 3) AS pct_rows_passing,
       round(coalesce(sum(u.usd) FILTER (WHERE u.passes), 0), 2)                AS usd_passing,
       round(100.0 * coalesce(sum(u.usd) FILTER (WHERE u.passes), 0) / sum(u.usd), 4) AS pct_usd_passing,
       CASE WHEN l.line_order IN (2, 4, 5, 6, 7, 8, 9) THEN
           string_agg(u.unit || ' (' || CAST(u.transfers AS VARCHAR) || ' rows, ' || CAST(u.senders AS VARCHAR)
                      || ' senders, $' || printf('%.2f', u.usd)
                      || coalesce(': ' || u.detail, '') || ')', ', '
                      ORDER BY u.usd DESC, u.unit) FILTER (WHERE u.passes)
       END                                                                      AS passing_units
FROM units u
JOIN labels l USING (line_order)
GROUP BY l.line_order, l.line, l.unit_kind
ORDER BY l.line_order
