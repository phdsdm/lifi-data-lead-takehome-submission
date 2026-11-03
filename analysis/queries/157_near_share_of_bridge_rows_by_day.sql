-- 157_near_share_of_bridge_rows_by_day
-- Question: On each day of the week, how many bridge rows did LI.FI start in total, how many went
--           through near, and what share is that, around near's 18-hour silence on 2026-10-15?
-- Grain:    one row per UTC day (7).
-- Definition applied (bridge_volume_usd in task_1.md for the scope):
--   - Scope: bridge rows only, destination_chain_id differs from the source chain's id.
--     near has no same-chain row.
--     bridge_rows + same_chain_rows equals all_rows there, which counts every row of the file.
--   - near: bridge = 'near' in the event. Day: block_time truncated to the UTC day.
--   - The gap itself (05:00 to 22:59 UTC on 2026-10-15): 15_bridge_activity_span.
-- Inputs:   transfers (provided data only).

WITH source_ids(chain, chain_id) AS (
    VALUES ('ethereum', 1), ('optimism', 10), ('bnb', 56), ('polygon', 137), ('base', 8453), ('arbitrum', 42161)
),
days AS (
    SELECT CAST(range AS DATE) AS day FROM range(DATE '2026-10-13', DATE '2026-10-20', INTERVAL 1 DAY)
),
t AS (
    SELECT CAST(date_trunc('day', p.block_time) AS DATE) AS day,
           p.bridge,
           p.destination_chain_id <> s.chain_id AS is_bridge_row
    FROM transfers p
    JOIN source_ids s USING (chain)
)
SELECT d.day,
       count(*) FILTER (WHERE t.is_bridge_row)                        AS bridge_rows,
       count(*) FILTER (WHERE t.is_bridge_row AND t.bridge = 'near')  AS near_rows,
       round(100.0 * count(*) FILTER (WHERE t.is_bridge_row AND t.bridge = 'near')
             / nullif(count(*) FILTER (WHERE t.is_bridge_row), 0), 2) AS near_share_pct,
       count(*) FILTER (WHERE NOT t.is_bridge_row)                    AS same_chain_rows
FROM days d
LEFT JOIN t USING (day)
GROUP BY d.day
ORDER BY d.day
