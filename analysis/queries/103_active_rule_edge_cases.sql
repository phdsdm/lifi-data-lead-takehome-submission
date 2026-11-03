-- 103_active_rule_edge_cases
-- Question: Which partners sit at the edges of the active rule: long-tail partners with many
--           transfers but little USD, which a higher USD floor would drop; one-sender partners with
--           real volume, which a sender condition would drop; and partners with few transfers and
--           large volume, which a transfer count would drop?
-- Grain:    one row per (case, partner); a partner can appear under two cases. Three cases:
--           (a) below_1000_usd_with_20plus_transfers: started USD < 1,000 and transfers >= 20;
--           (b) one_sender_at_10000_usd_plus: 1 distinct sender and started USD >= 10,000;
--           (c) under_10_transfers_at_100000_usd_plus: fewer than 10 transfers and USD >= 100,000.
--           Case (a) is ordered by transfers, cases (b) and (c) by USD, descending.
-- Definition applied:
--   - Partner: the organisation, the normalised partner of ref_integrator_map, class = 'partner'
--     (562); rows, senders and USD pool its partner-class strings. Classes lifi_product,
--     unattributed_api and test_or_dev are not candidates.
--   - transfers: started transfers, one LiFiTransferStarted row each, every row; senders:
--     distinct tx_from; usd: the sum of amount_usd, the headline, over the window
--     (2026-10-13 to 2026-10-19 UTC), rows neither feed prices adding nothing.
--   - active_usd_100: usd >= 100, the active rule applied to the window. active_10_transfers_2_senders: transfers >= 10 AND
--     senders >= 2, the 10-transfers-and-2-senders alternative, for the comparison.
--   - A case (a) unit is active under the active rule only when its USD is >= 100 (active_usd_100 says which)
--     and under the 10-transfers-and-2-senders alternative when it has 2 senders. A case (b) unit is active under the active rule and never under
--     the 10-transfers-and-2-senders alternative (one sender); so is a case (c) unit (fewer than 10 transfers).
--   - Map joined on coalesce(m.integrator, ''): its empty-string row loads as NULL.
-- Inputs:   transfers_priced, ref_integrator_map. usd depends on reference data for its
--           CoinGecko-priced rows.

WITH t AS (
    SELECT p.tx_from, p.amount_usd, m.partner
    FROM transfers_priced p
    JOIN ref_integrator_map m ON coalesce(m.integrator, '') = p.integrator
    WHERE m.class = 'partner'
),
partners AS (
    SELECT partner, count(*) AS transfers, count(DISTINCT tx_from) AS senders, coalesce(sum(amount_usd), 0) AS usd
    FROM t GROUP BY partner
),
cases(case_order, "case") AS (
    VALUES (1, 'below_1000_usd_with_20plus_transfers'),
           (2, 'one_sender_at_10000_usd_plus'),
           (3, 'under_10_transfers_at_100000_usd_plus')
),
matched AS (
    SELECT c.case_order, c."case", p.*
    FROM cases c JOIN partners p
      ON (c.case_order = 1 AND p.usd < 1000 AND p.transfers >= 20)
      OR (c.case_order = 2 AND p.senders = 1 AND p.usd >= 10000)
      OR (c.case_order = 3 AND p.transfers < 10 AND p.usd >= 100000)
)
SELECT "case",
       partner,
       transfers,
       senders,
       round(usd, 2)                        AS usd,
       usd >= 100                           AS active_usd_100,
       transfers >= 10 AND senders >= 2     AS active_10_transfers_2_senders
FROM matched
ORDER BY case_order,
         CASE WHEN case_order = 1 THEN transfers ELSE usd END DESC,
         partner
