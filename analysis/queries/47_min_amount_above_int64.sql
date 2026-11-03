-- 47_min_amount_above_int64
-- Question: How many rows carry a minAmount too large for a signed 64-bit integer, and how
--           large is the largest?
-- Grain:    one row for the whole file.
-- Definition applied:
--   - Above int64: min_amount > 9,223,372,036,854,775,807 (2^63 − 1). min_amount is stored
--     exact as HUGEINT, never as a float.
--   - above_2_53: min_amount > 9,007,199,254,740,991, the largest integer a float64 holds
--     exactly; such amounts lose digits when read as float.
-- Inputs:   transfers (provided data only).

SELECT count(*)                                                                       AS n_rows,
       count(*) FILTER (WHERE min_amount > 9223372036854775807)                       AS rows_above_int64,
       round(100.0 * count(*) FILTER (WHERE min_amount > 9223372036854775807) / count(*), 2) AS pct_above_int64,
       count(*) FILTER (WHERE min_amount > 9007199254740991)                          AS rows_above_2_53,
       round(100.0 * count(*) FILTER (WHERE min_amount > 9007199254740991) / count(*), 2) AS pct_above_2_53,
       CAST(max(min_amount) AS VARCHAR)                                               AS largest_min_amount,
       count(*) FILTER (WHERE min_amount <= 0)                                        AS rows_zero_or_negative
FROM transfers
