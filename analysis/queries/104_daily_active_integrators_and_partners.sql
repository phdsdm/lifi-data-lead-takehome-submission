-- 104_daily_active_integrators_and_partners
-- Question: How many partners and how many integrators are active on each UTC day of the window
--           under the active rule's daily form (at least one started transfer in the day), and what is the
--           seven-day average? For the record, how many would pass $100 of started USD in the
--           day, and how many a 10-transfers-and-2-senders rule applied to the day?
-- Grain:    one row per UTC day (7, Tuesday 2026-10-13 to Monday 2026-10-19) and one
--           seven-day average row (day_utc NULL, weekday '(seven-day average)').
-- Definition applied:
--   - Daily active: a unit with at least one started transfer in the UTC day of
--     block_time. The average of the daily count over the month is the operational
--     companion; the window holds seven days, so the average row is over the seven.
--   - Partner: the organisation, the normalised partner of ref_integrator_map, class =
--     'partner', its partner-class strings pooled; integrator: the raw string of class 'partner'.
--     Classes lifi_product, unattributed_api and test_or_dev are not counted.
--   - partner_rows, partner_usd: the day's partner-class rows and their headline amount_usd, every row
--     as in the started-volume definition.
--   - *_any_transfer: units with at least one started transfer that day, the active rule's daily form.
--     *_usd_100_in_day: units whose started USD that day is >= 100, for the record (the active rule sets
--     the $100 floor on the month, not the day). *_10_transfers_2_senders_in_day: units with
--     >= 10 transfers from >= 2 distinct tx_from that day, that rule applied to the day, for
--     the record.
--   - The average row: the arithmetic mean of the seven daily values, 1 decimal for counts,
--     2 for USD.
--   - Map joined on coalesce(m.integrator, ''): its empty-string row loads as NULL.
-- Inputs:   transfers_priced, ref_integrator_map. partner_usd and the *_usd_100_in_day columns
--           depend on reference data for the CoinGecko-priced rows; the other counts use
--           provided data and the map only.

WITH t AS (
    SELECT CAST(p.block_time AS DATE) AS day_utc, p.integrator, p.tx_from, p.amount_usd, m.partner
    FROM transfers_priced p
    JOIN ref_integrator_map m ON coalesce(m.integrator, '') = p.integrator
    WHERE m.class = 'partner'
),
per_partner_day AS (
    SELECT day_utc, partner, count(*) AS transfers, count(DISTINCT tx_from) AS senders, coalesce(sum(amount_usd), 0) AS usd
    FROM t GROUP BY day_utc, partner
),
per_integrator_day AS (
    SELECT day_utc, integrator, count(*) AS transfers, count(DISTINCT tx_from) AS senders, coalesce(sum(amount_usd), 0) AS usd
    FROM t GROUP BY day_utc, integrator
),
days AS (
    SELECT day_utc,
           sum(transfers)                                               AS partner_rows,
           sum(usd)                                                     AS partner_usd,
           count(*)                                                     AS partners_any_transfer,
           count(*) FILTER (WHERE usd >= 100)                           AS partners_usd_100_in_day,
           count(*) FILTER (WHERE transfers >= 10 AND senders >= 2)     AS partners_10_transfers_2_senders_in_day
    FROM per_partner_day GROUP BY day_utc
),
days_integrators AS (
    SELECT day_utc,
           count(*)                                                     AS integrators_any_transfer,
           count(*) FILTER (WHERE usd >= 100)                           AS integrators_usd_100_in_day,
           count(*) FILTER (WHERE transfers >= 10 AND senders >= 2)     AS integrators_10_transfers_2_senders_in_day
    FROM per_integrator_day GROUP BY day_utc
),
daily AS (
    SELECT d.day_utc, dayname(d.day_utc) AS weekday,
           d.partner_rows, d.partner_usd,
           d.partners_any_transfer, d.partners_usd_100_in_day, d.partners_10_transfers_2_senders_in_day,
           i.integrators_any_transfer, i.integrators_usd_100_in_day, i.integrators_10_transfers_2_senders_in_day
    FROM days d JOIN days_integrators i USING (day_utc)
)
SELECT day_utc, weekday,
       partner_rows, round(partner_usd, 2) AS partner_usd,
       partners_any_transfer, partners_usd_100_in_day, partners_10_transfers_2_senders_in_day,
       integrators_any_transfer, integrators_usd_100_in_day, integrators_10_transfers_2_senders_in_day
FROM daily
UNION ALL
SELECT NULL, '(seven-day average)',
       round(avg(partner_rows), 1), round(avg(partner_usd), 2),
       round(avg(partners_any_transfer), 1), round(avg(partners_usd_100_in_day), 1), round(avg(partners_10_transfers_2_senders_in_day), 1),
       round(avg(integrators_any_transfer), 1), round(avg(integrators_usd_100_in_day), 1), round(avg(integrators_10_transfers_2_senders_in_day), 1)
FROM daily
ORDER BY day_utc NULLS LAST
