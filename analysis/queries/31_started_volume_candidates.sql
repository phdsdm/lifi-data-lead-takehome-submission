-- 31_started_volume_candidates
-- Question: What is the week's started volume under each definition choice,
--           each applied alone against a baseline, and under all of them together?
-- Grain:    one row per measure (6); one column per candidate (10). The measures are the
--           USD total, the rows counted, the priced and unpriced rows among them, and the
--           USD difference from the baseline in dollars and in percent.
-- Definition applied (candidates):
--   - baseline: every row, priced with amount_usd, the headline (prices.csv, else the
--     CoinGecko snapshot).
--   - provided_price_only: amount_usd_provided, prices.csv only.
--   - without_same_chain_rows: rows whose destination_chain_id equals the
--     source chain's id (ethereum 1, optimism 10, bnb 56, polygon 137, base 8453,
--     arbitrum 42161) left out: the 295 rows of the three *Dex tools.
--   - repeated_ids_once: of the two rows sharing a transactionId, the later
--     one (by block_time, then log_index) left out; 6 rows.
--   - without_underscore_strings: integrator strings starting with '_' left out.
--   - without_jumper_lifi_strings: strings starting with 'jumper.' or
--     'lifi-' left out (9 strings; 09_integrator_rows_and_senders lists them).
--   - round_trip_one_leg: the return leg of the 9,519,447.993443 USDC round trip
--     (arbitrum to 1, 2026-10-19 17:57:04, `_arbitrum`) left out.
--   - round_trip_netted: both legs left out.
--   - all_choices_headline / all_choices_provided: the five exclusions together
--     (same-chain rows, later repeated row, '_' strings, 'jumper.'/'lifi-' strings, round
--     trip return leg) under each price. The round-trip legs are `_arbitrum` rows, so they
--     are already out with the '_' strings.
--   - Every measure is cast to DECIMAL(18,2) so one column can hold counts and dollars.
-- Inputs:   transfers_priced (headline: reference data for its CoinGecko-priced rows).

WITH source_ids(chain, chain_id) AS (
    VALUES ('ethereum', 1), ('optimism', 10), ('bnb', 56), ('polygon', 137), ('base', 8453), ('arbitrum', 42161)
),
round_trip AS (
    SELECT chain, tx_hash, log_index,
           row_number() OVER (ORDER BY block_time) AS leg
    FROM transfers
    WHERE integrator = '_arbitrum' AND min_amount = 9519447993443
),
r AS (
    SELECT t.amount_usd,
           t.amount_usd_provided,
           t.destination_chain_id = s.chain_id                                                       AS same_chain,
           row_number() OVER (PARTITION BY t.transaction_id ORDER BY t.block_time, t.log_index) > 1   AS later_repeat,
           starts_with(t.integrator, '_')                                                            AS underscore,
           starts_with(t.integrator, 'jumper.') OR starts_with(t.integrator, 'lifi-')                AS jumper_or_lifi,
           coalesce(rt.leg = 2, FALSE)                                                               AS round_trip_return,
           rt.leg IS NOT NULL                                                                        AS round_trip_leg
    FROM transfers_priced t
    JOIN source_ids s USING (chain)
    LEFT JOIN round_trip rt USING (chain, tx_hash, log_index)
),
candidates(col_order, candidate, provided_price, drop_same_chain, drop_later_repeat,
           drop_underscore, drop_jumper_lifi, drop_round_trip_return, drop_round_trip_both) AS (
    VALUES
        ( 1, 'baseline',                     FALSE, FALSE, FALSE, FALSE, FALSE, FALSE, FALSE),
        ( 2, 'provided_price_only',          TRUE,  FALSE, FALSE, FALSE, FALSE, FALSE, FALSE),
        ( 3, 'without_same_chain_rows',      FALSE, TRUE,  FALSE, FALSE, FALSE, FALSE, FALSE),
        ( 4, 'repeated_ids_once',            FALSE, FALSE, TRUE,  FALSE, FALSE, FALSE, FALSE),
        ( 5, 'without_underscore_strings',   FALSE, FALSE, FALSE, TRUE,  FALSE, FALSE, FALSE),
        ( 6, 'without_jumper_lifi_strings',  FALSE, FALSE, FALSE, FALSE, TRUE,  FALSE, FALSE),
        ( 7, 'round_trip_one_leg',           FALSE, FALSE, FALSE, FALSE, FALSE, TRUE,  FALSE),
        ( 8, 'round_trip_netted',            FALSE, FALSE, FALSE, FALSE, FALSE, FALSE, TRUE),
        ( 9, 'all_choices_headline',         FALSE, TRUE,  TRUE,  TRUE,  TRUE,  TRUE,  FALSE),
        (10, 'all_choices_provided',         TRUE,  TRUE,  TRUE,  TRUE,  TRUE,  TRUE,  FALSE)
),
kept AS (
    SELECT c.col_order, c.candidate,
           CASE WHEN c.provided_price THEN r.amount_usd_provided ELSE r.amount_usd END AS usd
    FROM candidates c
    CROSS JOIN r
    WHERE NOT (c.drop_same_chain        AND r.same_chain)
      AND NOT (c.drop_later_repeat      AND r.later_repeat)
      AND NOT (c.drop_underscore        AND r.underscore)
      AND NOT (c.drop_jumper_lifi       AND r.jumper_or_lifi)
      AND NOT (c.drop_round_trip_return AND r.round_trip_return)
      AND NOT (c.drop_round_trip_both   AND r.round_trip_leg)
),
per_candidate AS (
    SELECT col_order, candidate,
           sum(usd)        AS usd_total,
           count(*)        AS rows_counted,
           count(usd)      AS rows_priced,
           count(*) - count(usd) AS rows_unpriced
    FROM kept
    GROUP BY col_order, candidate
),
with_baseline AS (
    SELECT p.*,
           p.usd_total - b.usd_total                       AS usd_minus_baseline,
           100.0 * (p.usd_total / b.usd_total - 1)         AS pct_vs_baseline
    FROM per_candidate p
    CROSS JOIN (SELECT usd_total FROM per_candidate WHERE candidate = 'baseline') b
),
long AS (
    SELECT 1 AS measure_order, 'usd_total' AS measure, candidate, CAST(round(usd_total, 2) AS DECIMAL(18, 2)) AS v FROM with_baseline
    UNION ALL SELECT 2, 'usd_minus_baseline', candidate, CAST(round(usd_minus_baseline, 2) AS DECIMAL(18, 2)) FROM with_baseline
    UNION ALL SELECT 3, 'pct_vs_baseline', candidate, CAST(round(pct_vs_baseline, 4) AS DECIMAL(18, 4)) FROM with_baseline
    UNION ALL SELECT 4, 'rows_counted', candidate, CAST(rows_counted AS DECIMAL(18, 2)) FROM with_baseline
    UNION ALL SELECT 5, 'rows_priced', candidate, CAST(rows_priced AS DECIMAL(18, 2)) FROM with_baseline
    UNION ALL SELECT 6, 'rows_unpriced', candidate, CAST(rows_unpriced AS DECIMAL(18, 2)) FROM with_baseline
)
SELECT measure,
       max(v) FILTER (WHERE candidate = 'baseline')                     AS baseline,
       max(v) FILTER (WHERE candidate = 'provided_price_only')          AS provided_price_only,
       max(v) FILTER (WHERE candidate = 'without_same_chain_rows')      AS without_same_chain_rows,
       max(v) FILTER (WHERE candidate = 'repeated_ids_once')            AS repeated_ids_once,
       max(v) FILTER (WHERE candidate = 'without_underscore_strings')   AS without_underscore_strings,
       max(v) FILTER (WHERE candidate = 'without_jumper_lifi_strings')  AS without_jumper_lifi_strings,
       max(v) FILTER (WHERE candidate = 'round_trip_one_leg')           AS round_trip_one_leg,
       max(v) FILTER (WHERE candidate = 'round_trip_netted')            AS round_trip_netted,
       max(v) FILTER (WHERE candidate = 'all_choices_headline')         AS all_choices_headline,
       max(v) FILTER (WHERE candidate = 'all_choices_provided')         AS all_choices_provided
FROM long
GROUP BY measure_order, measure
ORDER BY measure_order
