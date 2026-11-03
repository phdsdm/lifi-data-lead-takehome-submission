-- 64_integrator_map_proposal
-- Question: What does the normalisation map look like when its rules are applied to every
--           raw integrator string, and where does the reviewed map in
--           data/reference/integrator_map.csv depart from that proposal?
-- Grain:    one row per raw integrator string (598, the empty string included), departures
--           from the reviewed map first, then by rows.
-- Definition applied (the proposal, not the reviewed map):
--   - class, in this order of precedence:
--       1. unattributed_api: the empty string (no integrator at all; partner '(empty string)').
--       2. test_or_dev: the string contains test, dev, local, staging or stg, compared
--          case-insensitively; out of partner counts, kept in total volume.
--       3. unattributed_api: lifi-api (the API writes it when a caller passes no
--          integrator), and the other members of its family (lifi-sdk).
--       4. lifi_product: LI.FI's own named products, kept as
--          products: jumper.exchange, jumperadvanced, li.fi-playground.
--       5. lifi_product: LI.FI's brand at the start of the string, case-insensitive: 'jumper',
--          'li.fi' or 'lifi' (a proposal rule; the hand edits below depart where it misfires).
--       6. partner: everything else, the underscore strings included.
--   - partner (the normalised name):
--       - the seven variant families merge. A family is a stem shared by more than one
--         string under the stem rule of 61_integrator_name_families (lowercase, leading '_'
--         dropped, environment suffixes stripped, non-alphanumerics dropped). Its name is the
--         member with the most rows among those that are not test_or_dev;
--       - tangem and tangem-pay-prod merge into tangem;
--       - every other string is its own partner: other prefix pairs stay separate.
--     A test_or_dev string keeps its family's name, so a partner's test traffic stays linked.
--   - underscore: the string starts with '_' (counted as a partner, flagged).
--   - rule: the reasons that applied, class first, then the merge; 'raw string' when none.
--   - map_*: the row of ref_integrator_map, the reviewed file. Its empty-string row
--     loads as NULL (pandas reads an empty field as missing), so the join is on
--     coalesce(m.integrator, ''). departs: partner, class or underscore differ, or the string
--     is missing on one side. departs_on names what differs ('partner', 'class', 'underscore',
--     'missing from the map', 'not in the data'). A reviewed row's rule starts with 'reviewed:'.
--   - The hand-checked departures:
--       LIFI-BUMI-PROD-API: class (partner, not a LI.FI product);
--       whitewallet-qa: class (test_or_dev by hand; the substring list not extended);
--       hashport-wallet-e2e: class and partner (test_or_dev by hand, under
--         HashPort-Wallet-Prod);
--       dev.jumper.exchange, stg.jumper.exchange: partner (under jumper.exchange);
--       Reah-STG: partner (under Reah-PRD).
--     These partner links are departures because partner is compared: the proposal's stem
--     rule leaves these strings their own name.
--   - n_rows, senders (distinct tx_from), usd (amount_usd, the headline): aids for checking.
-- Inputs:   transfers_priced, ref_integrator_map (data/reference/integrator_map.csv, maintained
--           by hand). usd depends on reference data for its CoinGecko-priced rows.

WITH strings AS (
    SELECT integrator,
           count(*)                 AS n_rows,
           count(DISTINCT tx_from)  AS senders,
           sum(amount_usd)          AS usd
    FROM transfers_priced
    GROUP BY integrator
),
-- the stem rule of 61_integrator_name_families, five passes
passes AS (
    SELECT integrator,
           '(?:-{1,3}|_|\.)?(?:production|prod|dev|develop|development|testing|testenv|test|staging|stg|local|api|sdk|widget|app|v\d+)$' AS re,
           ltrim(lower(integrator), '_') AS s0
    FROM strings
),
p1 AS (SELECT *, regexp_replace(s0, re, '') AS s1 FROM passes),
p2 AS (SELECT *, regexp_replace(s1, re, '') AS s2 FROM p1),
p3 AS (SELECT *, regexp_replace(s2, re, '') AS s3 FROM p2),
p4 AS (SELECT *, regexp_replace(s3, re, '') AS s4 FROM p3),
p5 AS (SELECT *, regexp_replace(s4, re, '') AS s5 FROM p4),
s AS (
    SELECT st.*,
           regexp_replace(p5.s5, '[^a-z0-9]', '', 'g')                                 AS stem,
           regexp_extract(lower(st.integrator), '(test|dev|local|staging|stg)', 1)     AS test_hit,
           regexp_extract(lower(st.integrator), '^(jumper|li\.fi|lifi)', 1)            AS brand_hit
    FROM strings st JOIN p5 USING (integrator)
),
families AS (
    SELECT stem,
           arg_max(integrator, n_rows) FILTER (WHERE test_hit = '') AS family_name
    FROM s
    WHERE integrator <> ''
    GROUP BY stem
    HAVING count(*) > 1
),
proposed AS (
    SELECT s.integrator, s.n_rows, s.senders, s.usd, s.test_hit, s.brand_hit,
           f.family_name,
           s.integrator IN ('tangem', 'tangem-pay-prod') AS tangem_pair
    FROM s LEFT JOIN families f USING (stem)
),
classed AS (
    SELECT *,
           CASE
               WHEN integrator = ''                         THEN 'unattributed_api'
               WHEN test_hit <> ''                          THEN 'test_or_dev'
               WHEN integrator = 'lifi-api'
                 OR family_name = 'lifi-api'                THEN 'unattributed_api'
               WHEN integrator IN ('jumper.exchange', 'jumperadvanced', 'li.fi-playground')
                                                            THEN 'lifi_product'
               WHEN brand_hit <> ''                         THEN 'lifi_product'
               ELSE 'partner'
           END AS class,
           CASE
               WHEN integrator = ''                         THEN 'empty string'
               WHEN test_hit <> ''                          THEN 'contains ' || test_hit
               WHEN integrator = 'lifi-api'                 THEN 'lifi-api'
               WHEN integrator IN ('jumper.exchange', 'jumperadvanced', 'li.fi-playground')
                                                            THEN 'named product'
               WHEN family_name = 'lifi-api'                THEN NULL
               WHEN brand_hit <> ''                         THEN 'brand prefix ' || brand_hit
               WHEN starts_with(integrator, '_')            THEN 'underscore'
           END AS class_reason,
           CASE
               WHEN family_name IS NOT NULL                 THEN 'family:' || family_name
               WHEN tangem_pair                             THEN 'tangem merge'
           END AS merge_reason
    FROM proposed
),
proposal AS (
    SELECT integrator,
           CASE
               WHEN integrator = ''          THEN '(empty string)'
               WHEN family_name IS NOT NULL  THEN family_name
               WHEN tangem_pair              THEN 'tangem'
               ELSE integrator
           END                                                      AS partner,
           class,
           starts_with(integrator, '_')                             AS underscore,
           coalesce(nullif(concat_ws('; ', class_reason, merge_reason), ''), 'raw string') AS rule,
           n_rows, senders, usd
    FROM classed
)
SELECT p.integrator,
       p.partner,
       p.class,
       p.underscore,
       p.rule,
       m.partner                                                    AS map_partner,
       m.class                                                      AS map_class,
       m.underscore                                                 AS map_underscore,
       m.rule                                                       AS map_rule,
       (p.integrator IS NULL OR m.class IS NULL
        OR p.partner    IS DISTINCT FROM m.partner
        OR p.class      IS DISTINCT FROM m.class
        OR p.underscore IS DISTINCT FROM m.underscore)              AS departs,
       CASE
           WHEN p.integrator IS NULL THEN 'not in the data'
           WHEN m.class IS NULL      THEN 'missing from the map'
           ELSE nullif(concat_ws(', ',
                    CASE WHEN p.class      IS DISTINCT FROM m.class      THEN 'class' END,
                    CASE WHEN p.partner    IS DISTINCT FROM m.partner    THEN 'partner' END,
                    CASE WHEN p.underscore IS DISTINCT FROM m.underscore THEN 'underscore' END), '')
       END                                                          AS departs_on,
       p.n_rows,
       p.senders,
       round(p.usd, 2)                                              AS usd
FROM proposal p
FULL OUTER JOIN ref_integrator_map m ON coalesce(m.integrator, '') = p.integrator
ORDER BY departs DESC, p.n_rows DESC NULLS FIRST, lower(p.integrator), p.integrator
