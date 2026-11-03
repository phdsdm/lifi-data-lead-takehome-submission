-- 140_persona_shares
-- Question: What share of the
--           week's rows and USD do the example partners of each partner type (persona) carry, with LI.FI's
--           own products, unattributed traffic, test or dev connections and the remaining partners
--           beside them?
-- Grain:    one row per persona (P1 to P4), then one per remaining group, then a total row.
-- Definition applied (partner types assigned by name):
--   - THE ASSIGNMENT IS A JUDGEMENT, not a fact in the data: the strings below were placed in a
--     persona by name and by what is publicly known of the product. P1
--     multi-provider wallet: phantom, metamask-bridge. P2 single-provider wallet or dApp:
--     rabbykmsv2, _binancewallet, bitget, tangem, trezor-suite, onekey, Cow, derive-v3, oku.trade.
--     P3 own-funds execution and custody platform: Fireblocks, safe-app, USDai, mbridge-stable,
--     definitive-prod, metrika-capital. P4 chain bridge portal: _arbitrum, Pharos-Bridge,
--     HashPort-Wallet-Prod.
--   - A listed string is widened to its partner through ref_integrator_map (class partner), so a
--     partner's other integrators are included (tangem adds tangem-pay-prod); integrators_included
--     lists them. Shares are of the whole file; USD is amount_usd (headline).
--   - Remaining groups: lifi_product, unattributed_api and test_or_dev by class, and 'other
--     partners': class partner outside every persona.
-- Inputs:   transfers_priced (reference data for its CoinGecko-priced rows), ref_integrator_map.

WITH assignment(persona, ord, integrator) AS (
    VALUES ('P1 multi-provider wallet', 1, 'phantom'), ('P1 multi-provider wallet', 1, 'metamask-bridge'),
           ('P2 single-provider wallet or dApp', 2, 'rabbykmsv2'), ('P2 single-provider wallet or dApp', 2, '_binancewallet'),
           ('P2 single-provider wallet or dApp', 2, 'bitget'), ('P2 single-provider wallet or dApp', 2, 'tangem'),
           ('P2 single-provider wallet or dApp', 2, 'trezor-suite'), ('P2 single-provider wallet or dApp', 2, 'onekey'),
           ('P2 single-provider wallet or dApp', 2, 'Cow'), ('P2 single-provider wallet or dApp', 2, 'derive-v3'),
           ('P2 single-provider wallet or dApp', 2, 'oku.trade'),
           ('P3 own-funds execution and custody platform', 3, 'Fireblocks'), ('P3 own-funds execution and custody platform', 3, 'safe-app'),
           ('P3 own-funds execution and custody platform', 3, 'USDai'), ('P3 own-funds execution and custody platform', 3, 'mbridge-stable'),
           ('P3 own-funds execution and custody platform', 3, 'definitive-prod'), ('P3 own-funds execution and custody platform', 3, 'metrika-capital'),
           ('P4 chain bridge portal', 4, '_arbitrum'), ('P4 chain bridge portal', 4, 'Pharos-Bridge'), ('P4 chain bridge portal', 4, 'HashPort-Wallet-Prod')
),
persona_partners AS (
    SELECT DISTINCT a.persona, a.ord, m.partner
    FROM assignment a JOIN ref_integrator_map m ON m.integrator = a.integrator
),
t AS (
    SELECT p.integrator, p.amount_usd, m.partner, m.class,
           pp.persona, pp.ord
    FROM transfers_priced p
    LEFT JOIN ref_integrator_map m ON coalesce(m.integrator, '') = p.integrator
    LEFT JOIN persona_partners pp ON pp.partner = m.partner AND m.class = 'partner'
),
labelled AS (
    SELECT coalesce(persona,
                    CASE class WHEN 'partner' THEN 'other partners (class partner, no persona)'
                               WHEN 'lifi_product' THEN 'LI.FI products (lifi_product)'
                               WHEN 'unattributed_api' THEN 'unattributed API traffic'
                               ELSE 'test or dev connections' END) AS label,
           coalesce(ord, CASE class WHEN 'partner' THEN 5 WHEN 'lifi_product' THEN 6 WHEN 'unattributed_api' THEN 7 ELSE 8 END) AS ord,
           *
    FROM t
    UNION ALL SELECT '(whole file)', 9, * FROM t
)
SELECT label                                                                   AS persona,
       count(DISTINCT partner)                                                 AS partners,
       count(DISTINCT integrator)                                              AS integrators,
       CASE WHEN ord <= 4 THEN string_agg(DISTINCT integrator, ', ' ORDER BY integrator) END AS integrators_included,
       count(*)                                                                AS n_rows,
       round(100.0 * count(*) / (SELECT count(*) FROM t), 1)                   AS pct_rows,
       round(coalesce(sum(amount_usd), 0), 2)                                  AS usd,
       round(100.0 * sum(amount_usd) / (SELECT sum(amount_usd) FROM t), 1)     AS pct_usd,
       round(quantile_cont(amount_usd, 0.5), 2)                                AS median_row_usd,
       count(DISTINCT integrator) FILTER (WHERE integrator IN (SELECT integrator FROM assignment)) AS integrators_listed
FROM labelled
GROUP BY ord, label
ORDER BY ord
