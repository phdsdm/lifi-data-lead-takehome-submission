-- 127_benchmark_routes
-- Question: Benchmarks, feasibility market-wide. On how many routes, carrying what share of
--           the week's rows and USD, could a partner's figures be set against other partners'
--           under the peer and dominance rules, and which routes fail because one partner
--           dominates them?
-- Grain:    first summary rows (row_kind 'summary'), one per rule variant; then one row per route
--           (row_kind 'route', 334 routes), largest by rows first.
-- Definition applied (the benchmark rules):
--   - Route: source chain → destination chain, named through ref_lifi_chain_id_registry, Tron's
--     two ids one destination; every row of the file, same-chain *Dex routes flagged same_chain.
--   - Partner: ref_integrator_map's partner, class partner only. LI.FI's own products,
--     unattributed API traffic and test or dev connections are excluded by class, not by name
--     pattern (a stricter cut excludes the 19 strings matching jumper / lifi / li.fi, which
--     drops lifi-api as LI.FI's own and keeps test strings as peers).
--   - partners: distinct partners with a row on the route. top_partner_rows / top_rows_share_pct:
--     the partner with the most rows (ties by name) and its share of the route's class-partner rows;
--     top_partner_usd / top_usd_share_pct likewise for USD (amount_usd, headline).
--   - publishable_rows_rule: at least 5 partners and no partner above 50% of the route's
--     class-partner rows (the benchmark rule, "transfers"). publishable_usd_rule: the same with USD,
--     reported because the routes failing the rule were USD-dominated.
--     fails_on_dominance_rows: at least 5 partners but one above 50% of rows.
--   - Summary rows: pct_partner_rows / pct_partner_usd are the qualifying routes' share of all
--     class-partner rows and USD (the population a benchmark is computed over); pct_all_rows /
--     pct_all_usd the share of the whole file.
-- Inputs:   transfers_priced (reference data for its CoinGecko-priced rows), ref_integrator_map,
--           ref_lifi_chain_id_registry (names).

WITH source_ids(chain, source_chain_id) AS (
    VALUES ('ethereum', 1), ('optimism', 10), ('bnb', 56), ('polygon', 137), ('base', 8453), ('arbitrum', 42161)
),
t AS (
    SELECT rs.name || ' → ' || rd.name AS route,
           p.destination_chain_id = s.source_chain_id AS same_chain,
           p.amount_usd, m.partner, m.class
    FROM transfers_priced p
    JOIN source_ids s USING (chain)
    LEFT JOIN ref_lifi_chain_id_registry rs ON rs.chain_id = s.source_chain_id
    LEFT JOIN ref_lifi_chain_id_registry rd ON rd.chain_id = p.destination_chain_id
    LEFT JOIN ref_integrator_map m ON coalesce(m.integrator, '') = p.integrator
),
pr AS (
    SELECT route, partner, count(*) AS n, coalesce(sum(amount_usd), 0) AS usd
    FROM t WHERE class = 'partner' GROUP BY route, partner
),
per_route_partner AS (
    SELECT route,
           count(*)                              AS partners,
           sum(n)                                AS partner_rows,
           sum(usd)                              AS partner_usd,
           first(partner ORDER BY n DESC, partner) AS top_partner_rows,
           max(n) * 1.0 / sum(n)                 AS top_rows_share,
           first(partner ORDER BY usd DESC, partner) AS top_partner_usd,
           max(usd) / nullif(sum(usd), 0)        AS top_usd_share
    FROM pr GROUP BY route
),
routes AS (
    SELECT a.route, a.all_rows, a.all_usd, a.same_chain,
           coalesce(p.partners, 0) AS partners, coalesce(p.partner_rows, 0) AS partner_rows, coalesce(p.partner_usd, 0) AS partner_usd,
           p.top_partner_rows, p.top_rows_share, p.top_partner_usd, p.top_usd_share,
           coalesce(p.partners >= 5 AND p.top_rows_share <= 0.5, FALSE)  AS pub_rows,
           coalesce(p.partners >= 5 AND p.top_usd_share <= 0.5, FALSE)   AS pub_usd,
           coalesce(p.partners >= 5 AND p.top_rows_share > 0.5, FALSE)   AS fail_dom_rows
    FROM (SELECT route, count(*) AS all_rows, coalesce(sum(amount_usd), 0) AS all_usd, bool_or(same_chain) AS same_chain FROM t GROUP BY route) a
    LEFT JOIN per_route_partner p USING (route)
),
tot AS (
    SELECT sum(all_rows) AS all_rows, sum(all_usd) AS all_usd, sum(partner_rows) AS partner_rows, sum(partner_usd) AS partner_usd FROM routes
),
variants(v_ord, label, min_partners, dom_rows, dom_usd) AS (
    VALUES (1, 'all routes', 0, FALSE, FALSE),
           (2, 'at least 3 partners', 3, FALSE, FALSE),
           (3, 'at least 5 partners', 5, FALSE, FALSE),
           (4, 'at least 10 partners', 10, FALSE, FALSE),
           (5, 'at least 5 partners, none above 50% of rows (the rule)', 5, TRUE, FALSE),
           (6, 'at least 5 partners, none above 50% of USD', 5, FALSE, TRUE),
           (7, 'at least 5 partners, none above 50% of rows or of USD', 5, TRUE, TRUE),
           (8, 'at least 5 partners, one above 50% of rows (fails on dominance)', -1, FALSE, FALSE)
),
summary AS (
    SELECT v.v_ord, v.label,
           count(r.route)                                          AS routes,
           coalesce(sum(r.all_rows), 0)                            AS all_rows,
           coalesce(sum(r.all_usd), 0)                             AS all_usd,
           coalesce(sum(r.partner_rows), 0)                        AS partner_rows,
           coalesce(sum(r.partner_usd), 0)                         AS partner_usd
    FROM variants v
    LEFT JOIN routes r
           ON (v.min_partners >= 0 AND r.partners >= v.min_partners
               AND (NOT v.dom_rows OR coalesce(r.top_rows_share, 0) <= 0.5)
               AND (NOT v.dom_usd OR coalesce(r.top_usd_share, 0) <= 0.5))
           OR (v.min_partners = -1 AND r.fail_dom_rows)
    GROUP BY v.v_ord, v.label
)
SELECT 'summary'                                            AS row_kind,
       s.label                                              AS route,
       s.routes,
       NULL::BIGINT                                         AS partners,
       s.all_rows,
       round(100.0 * s.all_rows / tot.all_rows, 2)          AS pct_all_rows,
       round(s.all_usd, 2)                                  AS all_usd,
       round(100.0 * s.all_usd / tot.all_usd, 2)            AS pct_all_usd,
       s.partner_rows,
       round(100.0 * s.partner_rows / tot.partner_rows, 2)  AS pct_partner_rows,
       round(s.partner_usd, 2)                              AS partner_usd,
       round(100.0 * s.partner_usd / tot.partner_usd, 2)    AS pct_partner_usd,
       NULL::VARCHAR AS top_partner_rows, NULL::DOUBLE AS top_rows_share_pct,
       NULL::VARCHAR AS top_partner_usd, NULL::DOUBLE AS top_usd_share_pct,
       NULL::BOOLEAN AS publishable_rows_rule, NULL::BOOLEAN AS publishable_usd_rule, NULL::BOOLEAN AS fails_on_dominance_rows,
       NULL::BOOLEAN AS same_chain,
       s.v_ord AS ord_a, 0::BIGINT AS ord_b
FROM summary s CROSS JOIN tot
UNION ALL
SELECT 'route', r.route, 1, r.partners,
       r.all_rows, round(100.0 * r.all_rows / tot.all_rows, 3),
       round(r.all_usd, 2), round(100.0 * r.all_usd / tot.all_usd, 3),
       r.partner_rows, round(100.0 * r.partner_rows / tot.partner_rows, 3),
       round(r.partner_usd, 2), round(100.0 * r.partner_usd / tot.partner_usd, 3),
       r.top_partner_rows, round(100.0 * r.top_rows_share, 1),
       r.top_partner_usd, round(100.0 * r.top_usd_share, 1),
       r.pub_rows, r.pub_usd, r.fail_dom_rows, r.same_chain,
       9, -r.all_rows
FROM routes r CROSS JOIN tot
ORDER BY ord_a, ord_b, route
