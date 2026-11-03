-- 55_status_edge_case_checks
-- Question: What do LI.FI's status lookups of the edge cases show, as checks with a count and
--           a denominator?
-- Grain:    one row per check (9), with the keys of the cases that fail it.
-- Definition applied (edge-case snapshot of 2026-10-28):
--   - id lookups: the 6 repeated transactionIds looked up with the id itself as txHash
--     (lookup = 'transaction_id'); a check passes when the returned sending hash is the
--     earlier of the pair's two transactions.
--   - bridge-parameter probes: the 22 two-event rows looked up with the event's bridge
--     (lookup = 'tx_hash_bridge'); a probe passes when its transactionId, tool and substatus
--     equal the plain hash lookup of the same event.
--   - two-event transactions: from the plain lookups (lookup = 'tx_hash'), the top-level
--     record is the first leg (lower log_index) when its transactionId equals the first
--     leg's; the second leg's transactionId appears in batch_call_transactionIds.
--   - Tron: events to 1885080386571452 whose receiving chain is 728126428.
--   - Blast, opBNB, BOB, Lens: events to 81457, 204, 60808 or 232 with substatus COMPLETED.
--   - above $1M: events tagged above_1m_usd with substatus COMPLETED.
--   - batch statuses: two-event transactions whose batch_call_statuses are all COMPLETED
--     (a transaction without batchStatus fails).
--   - failing: the tx_hash (or transactionId for the id lookups) of each failing case.
-- Inputs:   ref_lifi_api_transfer_status_edge_cases (reference data); transfers (provided
--           data, for the pairs' earlier transaction).

WITH e AS (
    SELECT * FROM ref_lifi_api_transfer_status_edge_cases
),
plain AS (
    SELECT * FROM e WHERE lookup = 'tx_hash'
),
pair_first AS (
    SELECT transaction_id, arg_min(tx_hash, (block_time, log_index)) AS first_tx_hash
    FROM transfers
    WHERE transaction_id IN (SELECT transaction_id FROM transfers GROUP BY transaction_id HAVING count(*) > 1)
    GROUP BY transaction_id
),
id_lookups AS (
    SELECT DISTINCT e.lookup_value, lower(e.sending_txHash) = f.first_tx_hash AS returns_first
    FROM e JOIN pair_first f ON f.transaction_id = e.lookup_value
    WHERE e.lookup = 'transaction_id'
),
probes AS (
    SELECT b.chain, b.tx_hash, b.log_index,
           b.api_transactionId IS NOT DISTINCT FROM p.api_transactionId
           AND b.tool IS NOT DISTINCT FROM p.tool
           AND b.substatus IS NOT DISTINCT FROM p.substatus AS identical
    FROM e b
    JOIN plain p USING (chain, tx_hash, log_index)
    WHERE b.lookup = 'tx_hash_bridge'
),
two_event AS (
    SELECT p.*, row_number() OVER (PARTITION BY p.chain, p.tx_hash ORDER BY p.log_index) AS leg
    FROM plain p
    WHERE p.reason_tags LIKE '%two_event_tx%'
),
two_event_tx AS (
    SELECT a.chain || ':' || a.tx_hash                                               AS tx,
           a.event_integrator                                                        AS integrator,
           a.api_transactionId = a.event_transactionId                               AS top_is_first_leg,
           coalesce(contains(a.batch_call_transactionIds, b.event_transactionId), FALSE) AS second_in_batch,
           coalesce(a.batch_call_statuses IS NOT NULL
                    AND len(list_filter(string_split(a.batch_call_statuses, '|'), lambda x: x NOT LIKE '%COMPLETED%')) = 0, FALSE) AS batch_all_completed
    FROM two_event a JOIN two_event b ON b.chain = a.chain AND b.tx_hash = a.tx_hash AND a.leg = 1 AND b.leg = 2
)
SELECT * FROM (
    SELECT 1 AS ord, 'id lookups returning the earlier transaction of the pair' AS checked,
           (SELECT count(*) FILTER (WHERE returns_first) FROM id_lookups) AS passing,
           (SELECT count(*) FROM id_lookups) AS out_of,
           (SELECT string_agg(lookup_value, ', ') FILTER (WHERE NOT returns_first) FROM id_lookups) AS failing
    UNION ALL
    SELECT 2, 'bridge-parameter probes identical to the plain hash lookup',
           (SELECT count(*) FILTER (WHERE identical) FROM probes), (SELECT count(*) FROM probes),
           (SELECT string_agg(chain || ':' || tx_hash, ', ') FILTER (WHERE NOT identical) FROM probes)
    UNION ALL
    SELECT 3, 'two-event transactions whose top-level record is the first leg',
           (SELECT count(*) FILTER (WHERE top_is_first_leg) FROM two_event_tx), (SELECT count(*) FROM two_event_tx),
           (SELECT string_agg(tx || ' (' || integrator || ')', ', ') FILTER (WHERE NOT top_is_first_leg) FROM two_event_tx)
    UNION ALL
    SELECT 4, 'two-event transactions whose batchStatus carries the second leg',
           (SELECT count(*) FILTER (WHERE second_in_batch) FROM two_event_tx), (SELECT count(*) FROM two_event_tx),
           (SELECT string_agg(tx || ' (' || integrator || ')', ', ') FILTER (WHERE NOT second_in_batch) FROM two_event_tx)
    UNION ALL
    SELECT 5, 'two-event transactions whose batch calls are all COMPLETED',
           (SELECT count(*) FILTER (WHERE batch_all_completed) FROM two_event_tx), (SELECT count(*) FROM two_event_tx),
           (SELECT string_agg(tx || ' (' || integrator || ')', ', ') FILTER (WHERE NOT batch_all_completed) FROM two_event_tx)
    UNION ALL
    SELECT 6, 'events to 1885080386571452 received on 728126428 (Tron)',
           (SELECT count(*) FILTER (WHERE receiving_chainId = 728126428) FROM plain WHERE event_destinationChainId = 1885080386571452),
           (SELECT count(*) FROM plain WHERE event_destinationChainId = 1885080386571452),
           (SELECT string_agg(chain || ':' || tx_hash, ', ') FILTER (WHERE receiving_chainId IS DISTINCT FROM 728126428) FROM plain WHERE event_destinationChainId = 1885080386571452)
    UNION ALL
    SELECT 7, 'events to Blast, opBNB, BOB or Lens completed',
           (SELECT count(*) FILTER (WHERE substatus = 'COMPLETED') FROM plain WHERE event_destinationChainId IN (81457, 204, 60808, 232)),
           (SELECT count(*) FROM plain WHERE event_destinationChainId IN (81457, 204, 60808, 232)),
           (SELECT string_agg(chain || ':' || tx_hash, ', ') FILTER (WHERE substatus IS DISTINCT FROM 'COMPLETED') FROM plain WHERE event_destinationChainId IN (81457, 204, 60808, 232))
    UNION ALL
    SELECT 8, 'events above $1M completed',
           (SELECT count(*) FILTER (WHERE substatus = 'COMPLETED') FROM plain WHERE reason_tags LIKE '%above_1m_usd%'),
           (SELECT count(*) FROM plain WHERE reason_tags LIKE '%above_1m_usd%'),
           (SELECT string_agg(chain || ':' || tx_hash, ', ') FILTER (WHERE substatus IS DISTINCT FROM 'COMPLETED') FROM plain WHERE reason_tags LIKE '%above_1m_usd%')
    UNION ALL
    SELECT 9, 'edge-case hash lookups with status DONE',
           (SELECT count(*) FILTER (WHERE status = 'DONE') FROM plain), (SELECT count(*) FROM plain),
           (SELECT string_agg(chain || ':' || tx_hash, ', ') FILTER (WHERE status IS DISTINCT FROM 'DONE') FROM plain)
)
ORDER BY ord
