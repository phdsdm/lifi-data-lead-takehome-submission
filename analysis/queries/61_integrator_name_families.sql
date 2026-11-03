-- 61_integrator_name_families
-- Question: Which raw integrator strings collapse into one name once a leading underscore and
--           environment suffixes are stripped, and how many rows do those families carry?
-- Grain:    one row per family with more than one raw string (7), after a total row.
-- Definition applied (the rule of notebook 00 §4; a judgement rule, not the normalisation map):
--   - stem: lowercase the string, drop leading underscores, then strip, repeatedly, one
--     trailing environment suffix: an optional separator ('-' up to three times, '_' or '.')
--     followed by production, prod, dev, develop, development, testing, testenv, test,
--     staging, stg, local, api, sdk, widget, app or v<digits>; finally drop every character
--     that is not a-z or 0-9. The query strips five times; fixed_point says that a fifth pass
--     changed nothing, so the result equals the notebook's strip-until-stable loop.
--   - A family is a stem shared by more than one raw string.
-- Inputs:   transfers (provided data only).

WITH strings AS (
    SELECT integrator, count(*) AS n_rows FROM transfers GROUP BY integrator
),
passes AS (
    SELECT integrator, n_rows,
           '(?:-{1,3}|_|\.)?(?:production|prod|dev|develop|development|testing|testenv|test|staging|stg|local|api|sdk|widget|app|v\d+)$' AS re,
           ltrim(lower(integrator), '_') AS s0
    FROM strings
),
p1 AS (SELECT *, regexp_replace(s0, re, '') AS s1 FROM passes),
p2 AS (SELECT *, regexp_replace(s1, re, '') AS s2 FROM p1),
p3 AS (SELECT *, regexp_replace(s2, re, '') AS s3 FROM p2),
p4 AS (SELECT *, regexp_replace(s3, re, '') AS s4 FROM p3),
p5 AS (SELECT *, regexp_replace(s4, re, '') AS s5 FROM p4),
stems AS (
    SELECT integrator, n_rows,
           regexp_replace(s5, '[^a-z0-9]', '', 'g') AS stem,
           s4 = s5                                  AS fixed_point
    FROM p5
),
multi AS (
    SELECT stem,
           count(*)                                                   AS strings,
           sum(n_rows)                                                AS n_rows,
           string_agg(integrator || ' (' || CAST(n_rows AS VARCHAR) || ')', ', ' ORDER BY n_rows DESC, integrator) AS raw_strings,
           bool_and(fixed_point)                                      AS fixed_point
    FROM stems
    GROUP BY stem
    HAVING count(*) > 1
)
SELECT stem, strings, n_rows, pct_rows, raw_strings, fixed_point
FROM (
    SELECT 0 AS ord,
           '(all ' || CAST(count(*) AS VARCHAR) || ' families)'               AS stem,
           sum(strings)                                                       AS strings,
           sum(n_rows)                                                        AS n_rows,
           round(100.0 * sum(n_rows) / (SELECT count(*) FROM transfers), 2)   AS pct_rows,
           NULL                                                               AS raw_strings,
           bool_and(fixed_point)                                              AS fixed_point
    FROM multi
    UNION ALL
    SELECT 1, stem, strings, n_rows,
           round(100.0 * n_rows / (SELECT count(*) FROM transfers), 2),
           raw_strings, fixed_point
    FROM multi
)
ORDER BY ord, n_rows DESC, stem
