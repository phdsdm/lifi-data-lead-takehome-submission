-- 101_active_threshold_sensitivity
-- Question: How many partners and how many integrators would count as active over the seven-day
--           window under each USD floor on started volume, from "any transfer" to $1M, and what
--           do the units below each floor carry: USD, rows, and units with many transfers?
-- Grain:    one row per (level, threshold): 2 levels x 7 thresholds = 14 rows. Thresholds on a
--           log scale: 0 (any started transfer), 10, 100, 1,000, 10,000, 100,000, 1,000,000 USD.
-- Definition applied:
--   - Level 'partner': the organisation, the normalised partner of ref_integrator_map, class =
--     'partner' (562); its rows, senders and USD pool its partner-class strings (tangem with
--     tangem-pay-prod). Level 'integrator': one connection, the raw integrator string of class
--     'partner' (563), unmerged. Classes lifi_product, unattributed_api and test_or_dev
--     are not counted at either level.
--   - Started volume of a unit: the sum of amount_usd over its rows, the headline (prices.csv,
--     else the CoinGecko snapshot), every row as in the started-volume definition (both rows of a repeated transactionId,
--     the same-chain *Dex rows included). Rows neither feed prices add nothing to the sum.
--   - A unit is active at a threshold when its started USD >= threshold. At threshold 0 every
--     unit with at least one started transfer is active, a unit whose rows are all unpriced
--     included (its USD is 0). The active rule is the $100 row; the other rows are the sensitivity.
--   - Period: The active rule defines active on a calendar month. The sample holds seven days
--     (2026-10-13 to 2026-10-19 UTC), so every row is the monthly rule applied to the window.
--   - active: units at or above the threshold; total: units of the level; usd_excluded and
--     rows_excluded: the USD and rows of the units below the threshold; pct_usd_excluded and
--     pct_rows_excluded: their share of the level's USD and rows (the partner-class total,
--     the same at both levels); excluded_units_with_10plus_transfers: units below the threshold
--     with at least 10 started transfers; max_transfers_of_an_excluded_unit: the most transfers
--     any unit below the threshold has; active_with_2_senders: active units with at least 2
--     distinct tx_from, for context (the active rule has no sender condition).
--   - Map joined on coalesce(m.integrator, ''): its empty-string row loads as NULL.
-- Inputs:   transfers_priced, ref_integrator_map. USD depends on reference data for its
--           CoinGecko-priced rows; the counts of rows and senders use provided data and
--           the map only.

WITH t AS (
    SELECT p.integrator, p.tx_from, p.amount_usd, m.partner, m.class
    FROM transfers_priced p
    LEFT JOIN ref_integrator_map m ON coalesce(m.integrator, '') = p.integrator
    WHERE m.class = 'partner'
),
units AS (
    SELECT 1 AS level_order, 'partner' AS level, partner AS unit,
           count(*) AS transfers, count(DISTINCT tx_from) AS senders, coalesce(sum(amount_usd), 0) AS usd
    FROM t GROUP BY partner
    UNION ALL
    SELECT 2, 'integrator', integrator,
           count(*), count(DISTINCT tx_from), coalesce(sum(amount_usd), 0)
    FROM t GROUP BY integrator
),
thresholds(threshold_usd) AS (
    VALUES (0), (10), (100), (1000), (10000), (100000), (1000000)
),
judged AS (
    SELECT u.*, th.threshold_usd, u.usd >= th.threshold_usd AS active
    FROM units u CROSS JOIN thresholds th
)
SELECT level,
       threshold_usd,
       count(*) FILTER (WHERE active)                                                  AS active,
       count(*)                                                                        AS total,
       round(coalesce(sum(usd) FILTER (WHERE NOT active), 0), 2)                       AS usd_excluded,
       round(100.0 * coalesce(sum(usd) FILTER (WHERE NOT active), 0) / sum(usd), 4)    AS pct_usd_excluded,
       coalesce(sum(transfers) FILTER (WHERE NOT active), 0)                           AS rows_excluded,
       round(100.0 * coalesce(sum(transfers) FILTER (WHERE NOT active), 0) / sum(transfers), 3) AS pct_rows_excluded,
       count(*) FILTER (WHERE NOT active AND transfers >= 10)                          AS excluded_units_with_10plus_transfers,
       coalesce(max(transfers) FILTER (WHERE NOT active), 0)                           AS max_transfers_of_an_excluded_unit,
       count(*) FILTER (WHERE active AND senders >= 2)                                 AS active_with_2_senders
FROM judged
GROUP BY level_order, level, threshold_usd
ORDER BY level_order, threshold_usd
