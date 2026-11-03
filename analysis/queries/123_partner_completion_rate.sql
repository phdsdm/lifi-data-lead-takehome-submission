-- 123_partner_completion_rate
-- Question: In the status samples, what share of each mock-up partner's started
--           transfers completed within 24 hours, was refunded, was partial or is still pending,
--           what completed volume does that imply for the week, and how long did the slowest
--           completion and the latest refund take?
-- Grain:    one row per (partner, sample): partners base-app, phantom, metamask-bridge,
--           rabbykmsv2 and '(all sampled)'; samples pooled_2600 (both designs together) and
--           uniform_2000 (the design that represents the file).
-- Definition applied (task_1.md "Completed volume"):
--   - Completed: status DONE and substatus COMPLETED with the destination block timestamp at
--     most 24 hours after the source block timestamp (receiving_timestamp - sending_timestamp
--     <= 86,400 s). completed_any_time counts COMPLETED without the 24-hour condition; the two
--     are equal here (longest completion 48 minutes). Refunded: substatus REFUNDED; partial:
--     PARTIAL; pending_beyond_24h: status other than DONE (none: every sampled response is DONE,
--     the samples were fetched 9 to 15 days after the events, so the pending and stuck rates of
--     a live product are not observable here).
--   - Rate = completed / sampled, with the Wilson 95% interval (z = 1.96).
--   - Partner: ref_integrator_map's partner for the event's integrator string (class partner;
--     joined on coalesce(m.integrator, '')). The sample's integrator is the event's string.
--   - started_rows / started_usd: the partner's week;
--     implied_completed_usd = started_usd × rate, with the Wilson bounds: completed volume at
--     the started amount (task_1.md), assuming completion does not depend on size.
--     sampled_usd / pct_sampled_usd_completed: the sampled rows' headline USD and the completed
--     share of it, the size-weighted check on that assumption.
--   - longest_completion_min: max(receiving - sending) over COMPLETED, in minutes;
--     median_refund_min / latest_refund_min: over REFUNDED (the refund's receiving leg is on the
--     source chain).
-- Inputs:   ref_lifi_api_transfer_status_sample_2600 (reference data: LI.FI /v1/status, fetched
--           2026-10-28), ref_integrator_map, transfers_priced (reference data for its
--           CoinGecko-priced rows).

WITH mock(partner, ord) AS (
    VALUES ('base-app', 1), ('phantom', 2), ('metamask-bridge', 3), ('rabbykmsv2', 4)
),
s AS (
    SELECT st.*, m.partner, m.class, p.amount_usd,
           st.receiving_timestamp - st.sending_timestamp AS secs
    FROM ref_lifi_api_transfer_status_sample_2600 st
    LEFT JOIN ref_integrator_map m ON coalesce(m.integrator, '') = st.event_integrator
    JOIN transfers_priced p USING (chain, tx_hash, log_index)
),
labelled AS (
    SELECT mk.ord, mk.partner AS label, 'pooled_2600' AS sample, s.* FROM s JOIN mock mk ON mk.partner = s.partner AND s.class = 'partner'
    UNION ALL
    SELECT mk.ord, mk.partner, 'uniform_2000', s.* FROM s JOIN mock mk ON mk.partner = s.partner AND s.class = 'partner' WHERE s.sample_design = 'uniform_2000'
    UNION ALL SELECT 5, '(all sampled)', 'pooled_2600', * FROM s
    UNION ALL SELECT 5, '(all sampled)', 'uniform_2000', * FROM s WHERE sample_design = 'uniform_2000'
),
week AS (
    SELECT mk.ord, count(*) AS started_rows, sum(p.amount_usd) AS started_usd
    FROM transfers_priced p
    JOIN ref_integrator_map m ON coalesce(m.integrator, '') = p.integrator AND m.class = 'partner'
    JOIN mock mk ON mk.partner = m.partner
    GROUP BY mk.ord
    UNION ALL
    SELECT 5, count(*), sum(amount_usd) FROM transfers_priced
),
counts AS (
    SELECT ord, label, sample,
           count(*)                                                                        AS sampled,
           count(*) FILTER (WHERE status = 'DONE')                                         AS status_done,
           count(*) FILTER (WHERE substatus = 'COMPLETED' AND secs <= 86400)               AS completed,
           count(*) FILTER (WHERE substatus = 'COMPLETED')                                 AS completed_any_time,
           count(*) FILTER (WHERE substatus = 'REFUNDED')                                  AS refunded,
           count(*) FILTER (WHERE substatus = 'PARTIAL')                                   AS partial,
           count(*) FILTER (WHERE status <> 'DONE')                                        AS pending_beyond_24h,
           sum(amount_usd)                                                                 AS sampled_usd,
           sum(amount_usd) FILTER (WHERE substatus = 'COMPLETED' AND secs <= 86400)        AS completed_usd,
           max(secs) FILTER (WHERE substatus = 'COMPLETED')                                AS longest_completion_s,
           median(secs) FILTER (WHERE substatus = 'REFUNDED')                              AS median_refund_s,
           max(secs) FILTER (WHERE substatus = 'REFUNDED')                                 AS latest_refund_s
    FROM labelled
    GROUP BY ord, label, sample
),
rates AS (
    SELECT *, completed * 1.0 / sampled AS p, 1.96 AS z FROM counts
),
wilson AS (
    SELECT *,
           ((p + z * z / (2 * sampled)) - z * sqrt(p * (1 - p) / sampled + z * z / (4 * sampled * sampled))) / (1 + z * z / sampled) AS w_low,
           ((p + z * z / (2 * sampled)) + z * sqrt(p * (1 - p) / sampled + z * z / (4 * sampled * sampled))) / (1 + z * z / sampled) AS w_high
    FROM rates
)
SELECT w.label                                                  AS partner,
       w.sample,
       w.sampled,
       w.status_done,
       w.completed,
       w.completed_any_time,
       w.refunded,
       w.partial,
       w.pending_beyond_24h,
       round(100.0 * w.p, 2)                                    AS pct_completed,
       round(100.0 * w.w_low, 2)                                AS wilson_low,
       round(100.0 * w.w_high, 2)                               AS wilson_high,
       round(100.0 * w.refunded / w.sampled, 2)                 AS pct_refunded,
       round(100.0 * w.partial / w.sampled, 2)                  AS pct_partial,
       round(w.sampled_usd, 2)                                  AS sampled_usd,
       round(100.0 * w.completed_usd / w.sampled_usd, 2)        AS pct_sampled_usd_completed,
       wk.started_rows,
       round(wk.started_usd, 2)                                 AS started_usd,
       round(wk.started_usd * w.p, 2)                           AS implied_completed_usd,
       round(wk.started_usd * w.w_low, 2)                       AS implied_completed_usd_low,
       round(wk.started_usd * w.w_high, 2)                      AS implied_completed_usd_high,
       round(wk.started_rows * (1 - w.p), 0)                    AS implied_not_completed_rows,
       round(w.longest_completion_s / 60.0, 1)                  AS longest_completion_min,
       round(w.median_refund_s / 60.0, 1)                       AS median_refund_min,
       round(w.latest_refund_s / 60.0, 1)                       AS latest_refund_min
FROM wilson w
JOIN week wk USING (ord)
ORDER BY w.ord, w.sample
