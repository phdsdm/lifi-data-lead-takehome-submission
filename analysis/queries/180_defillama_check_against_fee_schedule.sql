-- 180_defillama_check_against_fee_schedule
-- Question: Do DefiLlama's on-chain figures for LI.FI agree with the fee schedule of query 158 on the
--           same scope (13 to 19 October 2026, six source chains, bridges), how much wider is LI.FI's
--           fee on wider scopes that week, and what are its fees and revenue by calendar year?
--           A check and a statement of scope: no idea is sized on it.
-- Grain:    one row per (section, item, measure).
--   1. Same scope: DefiLlama against ours; difference = DefiLlama - ours, in % of ours.
--   2. Scope ladder: the week in defillama_usd, × 52 in annual_usd; three rows of the six chains' share.
--   3. Calendar years, total series: 2025; 2026 to the snapshot's last date; 2026 × 365 / days; the same
--      without the largest revenue day and without the last day; those two days; 2026 by month. Then
--      what bears on those figures: 2026-09-30 by series, the
--      days from it on which bridge and dex are equal on every chain, the annualised figures with
--      that day counted once, the 54 days from 2026-08-07, and the bridge series' mean a day either
--      side of 2026-09-30. Mean rows are a day's mean, not a sum.
--   4. Same scope by day and by chain, and the correlation over the 42 chain-days of ours against
--      DefiLlama's label shifted by -1, 0 and +1 day, which tests what a label covers. The schedule's
--      weights are per string and not per day or chain, so its rows here are noisier than its total.
-- Definitions applied:
--   - Ours, fees: query 158's schedule and frame on the quoted basis, before
--     completion and before × 52. Its CTEs are repeated below down to the weights, with the event's
--     day added. Its total is $28,219.12 of LI.FI fee and $106,832.61 of integrator fee. Reference
--     data: LI.FI /v1/status.
--   - Ours, volume: started volume (task_1.md, query 65, $307,969,358.59), since DefiLlama's bridge
--     volume on these six chains counts every LiFiTransferStarted event, same-chain rows included.
--     Bridge volume ($307,741,849.38) is the row 'volume, bridge volume', for reference.
--   - LI.FI fee without Jumper: 158's LI.FI fee less class lifi_product. Integrators' fees with Jumper:
--     158's integrator fee plus class lifi_product's LI.FI fee. DefiLlama moves four Jumper tags; class
--     lifi_product holds eight strings, $0.26 of LI.FI fee apart (query 158).
--   - DefiLlama: ref_defillama_lifi_daily (data/reference/defillama_lifi_daily.csv, reference data,
--     fetched 2026-11-03 by notebook 08; DefiLlama can revise past days). dailyFees = fees,
--     dailyRevenue = LI.FI's part, dailySupplySideRevenue = integrators', dailyBridgeVolume = bridge
--     volume. Its prices and token blacklist are its own. The adapter counts Jumper as integrators'
--     since 2026-08-07; that is not established for the stored days 2026-08-07 to 2026-09-29, and the
--     week is after them.
--   - Week: DefiLlama's labels 2026-10-13 to 2026-10-19. Six chains: Ethereum, Arbitrum, Base,
--     OP Mainnet, Polygon, BSC. The bridge and same-chain split starts on 2026-09-30: before it the dex
--     series has no rows and the bridge series equals the total. On 2026-09-30 itself bridge and dex
--     are identical and the total sums them; rows above the 'counted once' ones keep that day as served.
-- Inputs:   ref_defillama_lifi_daily; transfers_priced; ref_integrator_map; the status snapshots of query 158.

WITH source_ids(chain, source_chain_id, llama_chain) AS (
    VALUES ('ethereum', 1, 'Ethereum'), ('optimism', 10, 'OP Mainnet'), ('bnb', 56, 'BSC'),
           ('polygon', 137, 'Polygon'), ('base', 8453, 'Base'), ('arbitrum', 42161, 'Arbitrum')
),
bridge_rows AS (
    SELECT t.chain, t.tx_hash, t.log_index, t.integrator, s.llama_chain, CAST(t.block_time AS DATE) AS day,
           t.amount_usd AS x, t.has_source_swaps AS flag,
           CASE WHEN t.amount_usd < 10000 THEN 'under $10k'
                WHEN t.amount_usd < 100000 THEN '$10k to $100k'
                ELSE '$100k and above' END AS size_band
    FROM transfers_priced t
    JOIN source_ids s USING (chain)
    WHERE t.destination_chain_id <> s.source_chain_id AND t.amount_usd IS NOT NULL
),
status_rows AS (
    SELECT chain, tx_hash, log_index,
           CASE WHEN in_census THEN 'source_census' ELSE 'source_strata' END AS design,
           coalesce(fee_split_lifi_usd, 0) AS lifi, coalesce(fee_split_integrator_usd, 0) AS integ
    FROM ref_lifi_api_transfer_status_extension
    UNION ALL
    SELECT chain, tx_hash, log_index, 'no_step_census', coalesce(fee_split_lifi_usd, 0), coalesce(fee_split_integrator_usd, 0)
    FROM ref_lifi_api_transfer_status_bridge_census
    UNION ALL
    SELECT chain, tx_hash, log_index, 'no_step_uniform', coalesce(fee_split_lifi_usd, 0), coalesce(fee_split_integrator_usd, 0)
    FROM ref_lifi_api_transfer_status_sample_2600
    WHERE sample_design = 'uniform_2000' AND NOT event_hasSourceSwaps
),
observed AS (
    SELECT b.*, s.* EXCLUDE (chain, tx_hash, log_index)
    FROM status_rows s
    JOIN bridge_rows b USING (chain, tx_hash, log_index)
    WHERE s.design <> 'no_step_uniform' OR b.x < 100000
),
strata_weight AS (
    SELECT f.integrator, f.v / o.xs AS w, f.n * 1.0 / o.n AS w_rows
    FROM (SELECT integrator, sum(x) AS v, count(*) AS n FROM bridge_rows WHERE flag AND x < 10000 GROUP BY integrator) f
    JOIN (SELECT integrator, sum(x) AS xs, count(*) AS n FROM observed WHERE design = 'source_strata' GROUP BY integrator) o USING (integrator)
),
uniform_weight AS (
    SELECT f.size_band, f.v / o.xs AS w
    FROM (SELECT size_band, sum(x) AS v FROM bridge_rows WHERE NOT flag AND x < 100000 GROUP BY size_band) f
    JOIN (SELECT size_band, sum(x) AS xs FROM observed WHERE design = 'no_step_uniform' GROUP BY size_band) o USING (size_band)
),
frame AS (
    SELECT o.llama_chain, o.day, o.flag, o.integrator, o.lifi, o.integ, m.class AS integrator_class,
           CASE o.design WHEN 'source_strata' THEN sw.w WHEN 'no_step_uniform' THEN uw.w ELSE 1.0 END AS w,
           CASE o.design WHEN 'source_strata' THEN sw.w_rows WHEN 'no_step_uniform' THEN uw.w ELSE 1.0 END AS w_rows
    FROM observed o
    LEFT JOIN strata_weight sw ON sw.integrator = o.integrator
    LEFT JOIN uniform_weight uw ON uw.size_band = o.size_band
    LEFT JOIN ref_integrator_map m ON coalesce(m.integrator, '') = o.integrator
),
fees_by_chain_day AS (
    SELECT llama_chain AS chain, day,
           sum(w * lifi) AS lifi,
           coalesce(sum(w * lifi) FILTER (WHERE integrator_class = 'lifi_product'), 0) AS lifi_product,
           sum(CASE WHEN integrator = 'moby' THEN w_rows ELSE w END * integ) AS integ
    FROM frame WHERE flag GROUP BY 1, 2
),
started_by_chain_day AS (
    SELECT s.llama_chain AS chain, CAST(t.block_time AS DATE) AS day, sum(t.amount_usd) AS started
    FROM transfers_priced t JOIN source_ids s USING (chain) GROUP BY 1, 2
),
ours_chain_day(measure, chain, day, ours) AS (
    SELECT 'volume', chain, day, started FROM started_by_chain_day
    UNION ALL SELECT 'fees', chain, day, lifi + integ FROM fees_by_chain_day
    UNION ALL SELECT 'revenue', chain, day, lifi - lifi_product FROM fees_by_chain_day
    UNION ALL SELECT 'supply-side revenue', chain, day, integ + lifi_product FROM fees_by_chain_day
),
llama AS (
    SELECT CAST(date AS DATE) AS day, series, chain, value_usd,
           CASE metric WHEN 'dailyBridgeVolume' THEN 'volume' WHEN 'dailyFees' THEN 'fees'
                       WHEN 'dailyRevenue' THEN 'revenue' WHEN 'dailySupplySideRevenue' THEN 'supply-side revenue' END AS measure,
           chain IN (SELECT llama_chain FROM source_ids) AS six
    FROM ref_defillama_lifi_daily
),
week AS (
    SELECT series, measure, sum(value_usd) AS all_chains, sum(value_usd) FILTER (WHERE six) AS six_chains
    FROM llama WHERE day BETWEEN DATE '2026-10-13' AND DATE '2026-10-19'
    GROUP BY series, measure
),
same_scope_totals AS (
    SELECT w.measure, w.six_chains AS llama_usd, o.ours AS ours_usd
    FROM week w JOIN (SELECT measure, sum(ours) AS ours FROM ours_chain_day GROUP BY measure) o USING (measure)
    WHERE w.series = 'bridge'
),
same_scope(ord, item, measure, llama_usd, ours_usd) AS (
    SELECT 1, 'volume, started', measure, llama_usd, ours_usd FROM same_scope_totals WHERE measure = 'volume'
    UNION ALL
    SELECT 2, 'volume, bridge volume', measure, llama_usd, (SELECT sum(x) FROM bridge_rows) FROM same_scope_totals WHERE measure = 'volume'
    UNION ALL SELECT 3, 'all fees', measure, llama_usd, ours_usd FROM same_scope_totals WHERE measure = 'fees'
    UNION ALL SELECT 4, 'LI.FI fee without Jumper', measure, llama_usd, ours_usd FROM same_scope_totals WHERE measure = 'revenue'
    UNION ALL SELECT 5, 'integrators'' fees with Jumper', measure, llama_usd, ours_usd FROM same_scope_totals WHERE measure = 'supply-side revenue'
),
ladder(ord, item, measure, weekly) AS (
    SELECT 1, 'bridges, six chains', 'revenue', six_chains FROM week WHERE series = 'bridge' AND measure = 'revenue'
    UNION ALL SELECT 2, 'bridges, six chains', 'fees', six_chains FROM week WHERE series = 'bridge' AND measure = 'fees'
    UNION ALL SELECT 3, 'bridges, all chains', 'revenue', all_chains FROM week WHERE series = 'bridge' AND measure = 'revenue'
    UNION ALL SELECT 4, 'bridges, all chains', 'fees', all_chains FROM week WHERE series = 'bridge' AND measure = 'fees'
    UNION ALL SELECT 5, 'bridges plus same-chain swaps, all chains', 'revenue', all_chains FROM week WHERE series = 'total' AND measure = 'revenue'
    UNION ALL SELECT 6, 'bridges plus same-chain swaps, all chains', 'fees', all_chains FROM week WHERE series = 'total' AND measure = 'fees'
),
shares(ord, measure, share_pct) AS (
    SELECT 7, 'bridge volume', 100 * six_chains / all_chains FROM week WHERE series = 'bridge' AND measure = 'volume'
    UNION ALL SELECT 8, 'LI.FI fee', 100 * six_chains / all_chains FROM week WHERE series = 'bridge' AND measure = 'revenue'
    UNION ALL SELECT 9, 'all fees', 100 * six_chains / all_chains FROM week WHERE series = 'bridge' AND measure = 'fees'
),
total_days AS (
    SELECT day,
           sum(value_usd) FILTER (WHERE measure = 'fees') AS fees,
           sum(value_usd) FILTER (WHERE measure = 'revenue') AS revenue
    FROM llama WHERE series = 'total' AND year(day) IN (2025, 2026) GROUP BY day
),
marks AS (
    SELECT max(day) AS last_day, arg_max(day, revenue) FILTER (WHERE year(day) = 2026) AS top_day FROM total_days
),
periods(ord, item, annualise, day_from, day_to, excluded) AS (
    SELECT 1, '2025', false, DATE '2025-01-01', DATE '2025-12-31', NULL::DATE
    UNION ALL SELECT 3, '2026 to the snapshot date', false, DATE '2026-01-01', (SELECT last_day FROM marks), NULL
    UNION ALL SELECT 5, '2026 annualised by days', true, DATE '2026-01-01', (SELECT last_day FROM marks), NULL
    UNION ALL SELECT 7, '2026 annualised by days, without the largest revenue day', true, DATE '2026-01-01', (SELECT last_day FROM marks), (SELECT top_day FROM marks)
    UNION ALL SELECT 9, '2026 annualised by days, without the snapshot''s last day', true, DATE '2026-01-01', (SELECT last_day FROM marks), (SELECT last_day FROM marks)
    UNION ALL SELECT 11, 'largest revenue day of 2026', false, (SELECT top_day FROM marks), (SELECT top_day FROM marks), NULL
    UNION ALL SELECT 13, 'the snapshot''s last day', false, (SELECT last_day FROM marks), (SELECT last_day FROM marks), NULL
    UNION ALL
    SELECT 100 + 2 * month(m), strftime(m, '2026-%m'), false, m, least(last_day(m), (SELECT last_day FROM marks)), NULL
    FROM (SELECT DISTINCT date_trunc('month', day)::DATE AS m FROM total_days WHERE year(day) = 2026)
),
period_sums AS (
    SELECT p.ord, p.item, p.annualise, count(*) AS days, max(t.day) AS last_day, sum(t.fees) AS fees, sum(t.revenue) AS revenue
    FROM periods p JOIN total_days t ON t.day BETWEEN p.day_from AND p.day_to AND t.day IS DISTINCT FROM p.excluded
    GROUP BY p.ord, p.item, p.annualise
),
series_days AS (
    SELECT day, series, measure, sum(value_usd) AS usd
    FROM llama WHERE measure IN ('fees', 'revenue') GROUP BY day, series, measure
),
split_day AS (
    SELECT sum(usd) FILTER (WHERE measure = 'fees') AS fees, sum(usd) FILTER (WHERE measure = 'revenue') AS revenue
    FROM series_days WHERE series = 'dex' AND day = DATE '2026-09-30'
),
equal_days AS (
    SELECT measure, day
    FROM (
        SELECT coalesce(b.measure, d.measure) AS measure, coalesce(b.day, d.day) AS day,
               bool_and(b.value_usd IS NOT DISTINCT FROM d.value_usd) AS all_equal
        FROM (SELECT * FROM llama WHERE series = 'bridge' AND measure IN ('fees', 'revenue') AND day >= DATE '2026-09-30') b
        FULL JOIN (SELECT * FROM llama WHERE series = 'dex' AND measure IN ('fees', 'revenue')) d
          ON d.measure = b.measure AND d.chain = b.chain AND d.day = b.day
        GROUP BY 1, 2
    )
    WHERE all_equal
),
bearing(ord, item, measure, days, last_day, usd) AS (
    SELECT CASE series WHEN 'bridge' THEN 200 WHEN 'dex' THEN 202 ELSE 204 END + CASE measure WHEN 'fees' THEN 0 ELSE 1 END,
           '2026-09-30, ' || series || ' series', measure, 1, day, usd
    FROM series_days WHERE day = DATE '2026-09-30'
    UNION ALL
    SELECT CASE m.measure WHEN 'fees' THEN 206 ELSE 207 END, 'days from 2026-09-30 with bridge equal to dex on every chain', m.measure,
           (SELECT count(*) FROM equal_days e WHERE e.measure = m.measure), (SELECT max(day) FROM equal_days e WHERE e.measure = m.measure), NULL
    FROM (VALUES ('fees'), ('revenue')) m(measure)
    UNION ALL
    SELECT 208, '2026 annualised by days, with 2026-09-30 counted once', 'fees', p.days, p.last_day, (p.fees - s.fees) * 365.0 / p.days
    FROM period_sums p, split_day s WHERE p.item = '2026 annualised by days'
    UNION ALL
    SELECT 209, '2026 annualised by days, with 2026-09-30 counted once', 'revenue', p.days, p.last_day, (p.revenue - s.revenue) * 365.0 / p.days
    FROM period_sums p, split_day s WHERE p.item = '2026 annualised by days'
    UNION ALL
    SELECT 210, '2026 annualised by days, without the largest revenue day, with 2026-09-30 counted once', 'fees', p.days, p.last_day, (p.fees - s.fees) * 365.0 / p.days
    FROM period_sums p, split_day s WHERE p.item = '2026 annualised by days, without the largest revenue day'
    UNION ALL
    SELECT 211, '2026 annualised by days, without the largest revenue day, with 2026-09-30 counted once', 'revenue', p.days, p.last_day, (p.revenue - s.revenue) * 365.0 / p.days
    FROM period_sums p, split_day s WHERE p.item = '2026 annualised by days, without the largest revenue day'
    UNION ALL
    SELECT CASE measure WHEN 'fees' THEN 212 ELSE 213 END, 'total series, 2026-08-07 to 2026-09-29', measure, count(*), max(day), sum(usd)
    FROM series_days WHERE series = 'total' AND day BETWEEN DATE '2026-08-07' AND DATE '2026-09-29' GROUP BY measure
    UNION ALL
    SELECT CASE measure WHEN 'fees' THEN 214 ELSE 215 END, 'bridge series, mean a day, 2026-09-17 to 2026-09-29', measure, count(*), max(day), avg(usd)
    FROM series_days WHERE series = 'bridge' AND day BETWEEN DATE '2026-09-17' AND DATE '2026-09-29' GROUP BY measure
    UNION ALL
    SELECT CASE measure WHEN 'fees' THEN 216 ELSE 217 END, 'bridge series, mean a day, 2026-09-30 to 2026-10-13', measure, count(*), max(day), avg(usd)
    FROM series_days WHERE series = 'bridge' AND day BETWEEN DATE '2026-09-30' AND DATE '2026-10-13' GROUP BY measure
),
years(ord, item, measure, days, last_day, usd) AS (
    SELECT ord, item, 'fees', days, last_day, CASE WHEN annualise THEN fees * 365.0 / days ELSE fees END FROM period_sums
    UNION ALL
    SELECT ord + 1, item, 'revenue', days, last_day, CASE WHEN annualise THEN revenue * 365.0 / days ELSE revenue END FROM period_sums
    UNION ALL
    SELECT CASE measure WHEN 'fees' THEN 15 ELSE 16 END, 'largest revenue day of 2026, dex series, Ethereum', measure, 1, day, value_usd
    FROM llama
    WHERE series = 'dex' AND chain = 'Ethereum' AND measure IN ('fees', 'revenue') AND day = (SELECT top_day FROM marks)
    UNION ALL
    SELECT ord, item, measure, days, last_day, usd FROM bearing
),
bridge_llama AS (
    SELECT day, chain, measure, value_usd FROM llama WHERE series = 'bridge' AND six AND measure IN ('volume', 'fees', 'revenue')
),
matched AS (
    SELECT o.measure, o.chain, o.day, o.ours, l.value_usd AS llama
    FROM ours_chain_day o JOIN bridge_llama l ON l.measure = o.measure AND l.chain = o.chain AND l.day = o.day
),
by_day_or_chain(ord, item, measure, llama_usd, ours_usd) AS (
    SELECT CAST(strftime(day, '%d') AS INT), strftime(day, '%Y-%m-%d'), measure, sum(llama), sum(ours) FROM matched GROUP BY day, measure
    UNION ALL
    SELECT 100, chain, measure, sum(llama), sum(ours) FROM matched GROUP BY chain, measure
),
shifted AS (
    SELECT lag, o.measure, o.ours, l.value_usd AS llama
    FROM ours_chain_day o
    CROSS JOIN (VALUES (-1), (0), (1)) lags(lag)
    JOIN bridge_llama l ON l.measure = o.measure AND l.chain = o.chain AND l.day = o.day + lag
),
alignment AS (
    SELECT lag, measure, count(*) AS chain_days, sum(llama) AS llama_usd, sum(ours) AS ours_usd,
           corr(ours, llama) AS correlation, sum(abs(ours - llama)) AS abs_gap
    FROM shifted GROUP BY lag, measure
),
out AS (
    SELECT 1 AS s, ord, '1. Same scope' AS section, item, measure, 7 AS days, DATE '2026-10-19' AS last_day,
           llama_usd AS defillama_usd, ours_usd, llama_usd - ours_usd AS difference_usd,
           100 * (llama_usd - ours_usd) / ours_usd AS difference_pct, CAST(NULL AS DOUBLE) AS annual_usd, CAST(NULL AS DOUBLE) AS share_pct,
           CAST(NULL AS DOUBLE) AS correlation, CAST(NULL AS DOUBLE) AS chain_day_abs_gap_usd
    FROM same_scope
    UNION ALL
    SELECT 2, ord, '2. Scope ladder', item, measure, 7, DATE '2026-10-19', weekly, NULL, NULL, NULL, weekly * 52, NULL, NULL, NULL
    FROM ladder
    UNION ALL
    SELECT 2, ord, '2. Scope ladder', 'six chains'' share of bridges on all chains', measure, 7, DATE '2026-10-19', NULL, NULL, NULL, NULL, NULL, share_pct, NULL, NULL
    FROM shares
    UNION ALL
    SELECT 3, ord, '3. Calendar years', item, measure, days, last_day, usd, NULL, NULL, NULL, NULL, NULL, NULL, NULL
    FROM years
    UNION ALL
    SELECT 4, ord, '4. By day and chain', item, measure, CASE WHEN ord = 100 THEN 7 ELSE 1 END, NULL,
           llama_usd, ours_usd, llama_usd - ours_usd, 100 * (llama_usd - ours_usd) / ours_usd, NULL, NULL, NULL, NULL
    FROM by_day_or_chain
    UNION ALL
    SELECT 5, lag, '4. By day and chain', 'label = event day ' || CASE WHEN lag = 0 THEN '' WHEN lag > 0 THEN '+ 1' ELSE '- 1' END, measure, 7, NULL,
           llama_usd, ours_usd, NULL, NULL, NULL, NULL, correlation, abs_gap
    FROM alignment
)
SELECT section, trim(item) AS item, measure, days, last_day,
       round(defillama_usd, 2)  AS defillama_usd,
       round(ours_usd, 2)       AS ours_usd,
       round(difference_usd, 2) AS difference_usd,
       round(difference_pct, 2) AS difference_pct,
       round(annual_usd, 0)     AS annual_usd,
       round(share_pct, 2)      AS share_pct,
       round(correlation, 4)    AS chain_day_correlation,
       round(chain_day_abs_gap_usd, 0) AS chain_day_abs_gap_usd
FROM out
ORDER BY s, ord, item, measure
