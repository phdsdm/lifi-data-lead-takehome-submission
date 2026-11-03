-- 125_partner_net_cost_to_user
-- Question: Net cost to the user. On each mock-up partner's completed sampled transfers, how much of
--           the USD sent arrived, what did the user lose net of the partner's own fee, and how
--           large is that fee beside it?
-- Grain:    one row per (partner, sample): base-app, phantom, metamask-bridge, rabbykmsv2 and
--           '(all sampled)'; samples pooled_2600 and uniform_2000.
-- Definition applied (`task_2.md`, net cost to the user):
--   - Completed: substatus COMPLETED. sent_usd / received_usd: the API's sending_amountUSD and
--     receiving_amountUSD, each leg at LI.FI's own price.
--   - Trim: transfers whose received-to-sent ratio lies outside 0.5 to 2 are excluded from every
--     ratio and counted in excluded (a mispriced token is the usual cause).
--   - integrator_fee_usd: the partner's own fee, the integratorFee part of the quote's LIFI-named
--     fee lines (name starting 'LIFI', source 'quote') in ref_lifi_api_transfer_status_fee_lines,
--     in USD at each line's amount_usd / amount; lifi_fee_usd the lifiFee part; other_fee_usd the
--     other quote lines (bridge, relayer, gas). These equal the sample table's fee_split_* columns.
--   - gross_loss_bps = 10,000 × (sent − received) / sent over the kept transfers, aggregate;
--     net_cost_bps = 10,000 × (sent − received − integrator fee) / sent: the metric;
--     partner_fee_bps = 10,000 × integrator fee / sent, shown as its own line. median_net_cost_bps
--     is the per-transfer median. net_cost_bps + partner_fee_bps = gross_loss_bps.
--   - median_received_over_sent, p10, p90: per-transfer ratio over the kept transfers.
--   - median_sending_gas_usd: the sending leg's gas, the user's cost outside the amount.
--   - Partner as in 123_partner_completion_rate.
-- Inputs:   ref_lifi_api_transfer_status_sample_2600 and ref_lifi_api_transfer_status_fee_lines
--           (reference data: LI.FI /v1/status, fetched 2026-10-28; the fee lines derived offline
--           from the status responses), ref_integrator_map.

WITH mock(partner, ord) AS (
    VALUES ('base-app', 1), ('phantom', 2), ('metamask-bridge', 3), ('rabbykmsv2', 4)
),
fees AS (
    SELECT chain, tx_hash, log_index,
           coalesce(sum(amount_usd * CAST(integrator_fee AS DOUBLE) / nullif(CAST(amount AS DOUBLE), 0)) FILTER (WHERE name LIKE 'LIFI%'), 0) AS integrator_fee_usd,
           coalesce(sum(amount_usd * CAST(lifi_fee AS DOUBLE) / nullif(CAST(amount AS DOUBLE), 0)) FILTER (WHERE name LIKE 'LIFI%'), 0)       AS lifi_fee_usd,
           coalesce(sum(amount_usd) FILTER (WHERE name NOT LIKE 'LIFI%'), 0)                                                                  AS other_fee_usd
    FROM ref_lifi_api_transfer_status_fee_lines
    WHERE snapshot = 'sample_2600' AND source = 'quote'
    GROUP BY chain, tx_hash, log_index
),
s AS (
    SELECT st.sample_design, m.partner, m.class,
           st.sending_amountUSD AS sent, st.receiving_amountUSD AS recv, st.sending_gasAmountUSD AS gas,
           st.receiving_amountUSD / nullif(st.sending_amountUSD, 0) AS ratio,
           coalesce(f.integrator_fee_usd, 0) AS ifee, coalesce(f.lifi_fee_usd, 0) AS lfee, coalesce(f.other_fee_usd, 0) AS ofee
    FROM ref_lifi_api_transfer_status_sample_2600 st
    LEFT JOIN ref_integrator_map m ON coalesce(m.integrator, '') = st.event_integrator
    LEFT JOIN fees f USING (chain, tx_hash, log_index)
    WHERE st.substatus = 'COMPLETED'
),
labelled AS (
    SELECT mk.ord, mk.partner AS label, 'pooled_2600' AS sample, s.* FROM s JOIN mock mk ON mk.partner = s.partner AND s.class = 'partner'
    UNION ALL
    SELECT mk.ord, mk.partner, 'uniform_2000', s.* FROM s JOIN mock mk ON mk.partner = s.partner AND s.class = 'partner' WHERE s.sample_design = 'uniform_2000'
    UNION ALL SELECT 5, '(all sampled)', 'pooled_2600', * FROM s
    UNION ALL SELECT 5, '(all sampled)', 'uniform_2000', * FROM s WHERE sample_design = 'uniform_2000'
),
kept AS (
    SELECT * FROM labelled WHERE ratio BETWEEN 0.5 AND 2
)
SELECT l.label                                                                          AS partner,
       l.sample,
       count(*)                                                                         AS completed,
       count(*) FILTER (WHERE l.ratio BETWEEN 0.5 AND 2)                                AS kept,
       count(*) FILTER (WHERE l.ratio IS NULL OR l.ratio < 0.5 OR l.ratio > 2)          AS excluded,
       round(k.sent_usd, 2)                                                             AS sent_usd,
       round(k.recv_usd, 2)                                                             AS received_usd,
       round(k.med_ratio, 4)                                                            AS median_received_over_sent,
       round(k.p10_ratio, 4)                                                            AS p10_received_over_sent,
       round(k.p90_ratio, 4)                                                            AS p90_received_over_sent,
       round(1e4 * (k.sent_usd - k.recv_usd) / k.sent_usd, 1)                           AS gross_loss_bps,
       round(1e4 * k.ifee / k.sent_usd, 1)                                              AS partner_fee_bps,
       round(1e4 * (k.sent_usd - k.recv_usd - k.ifee) / k.sent_usd, 1)                  AS net_cost_bps,
       round(k.med_net_bps, 1)                                                          AS median_net_cost_bps,
       round(k.med_gross_bps, 1)                                                        AS median_gross_loss_bps,
       round(1e4 * k.lfee / k.sent_usd, 1)                                              AS lifi_fee_bps,
       round(1e4 * k.ofee / k.sent_usd, 1)                                              AS other_lines_bps,
       k.with_partner_fee                                                               AS kept_with_partner_fee,
       round(k.med_gas, 4)                                                              AS median_sending_gas_usd
FROM labelled l
JOIN (
    SELECT ord, label, sample,
           sum(sent) AS sent_usd, sum(recv) AS recv_usd, sum(ifee) AS ifee, sum(lfee) AS lfee, sum(ofee) AS ofee,
           median(ratio) AS med_ratio, quantile_cont(ratio, 0.1) AS p10_ratio, quantile_cont(ratio, 0.9) AS p90_ratio,
           median(1e4 * (sent - recv - ifee) / sent) AS med_net_bps,
           median(1e4 * (sent - recv) / sent) AS med_gross_bps,
           count(*) FILTER (WHERE ifee > 0) AS with_partner_fee,
           median(gas) AS med_gas
    FROM kept GROUP BY ord, label, sample
) k USING (ord, label, sample)
GROUP BY l.ord, l.label, l.sample, k.sent_usd, k.recv_usd, k.ifee, k.lfee, k.ofee, k.med_ratio, k.p10_ratio, k.p90_ratio,
         k.med_net_bps, k.med_gross_bps, k.with_partner_fee, k.med_gas
ORDER BY l.ord, l.sample
