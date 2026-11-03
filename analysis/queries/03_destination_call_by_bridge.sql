-- 03_destination_call_by_bridge
-- Question: What share of rows sets hasDestinationCall, overall and by bridge, and which
--           bridges carry the flagged rows?
-- Grain:    one row per bridge string (31), plus a first row for all bridges together.
-- Definition applied:
--   - A row is one LiFiTransferStarted event; bridge is the raw tool key.
--   - pct_of_bridge_rows: flagged rows over the bridge's rows.
--   - pct_of_all_flagged_rows: the bridge's flagged rows over all flagged rows in the file.
-- Inputs:   transfers (provided data only).

WITH by_bridge AS (
    SELECT coalesce(bridge, '(all bridges)')                        AS bridge,
           grouping(bridge)                                         AS is_total,
           count(*)                                                 AS n_rows,
           count(*) FILTER (WHERE has_destination_call)             AS destination_call_rows
    FROM transfers
    GROUP BY ROLLUP (bridge)
)
SELECT bridge,
       n_rows,
       destination_call_rows,
       round(100.0 * destination_call_rows / n_rows, 2)                                       AS pct_of_bridge_rows,
       round(100.0 * destination_call_rows
             / (SELECT count(*) FROM transfers WHERE has_destination_call), 2)                AS pct_of_all_flagged_rows
FROM by_bridge
ORDER BY is_total DESC, n_rows DESC, bridge
