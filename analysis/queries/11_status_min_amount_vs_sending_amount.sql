-- 11_status_min_amount_vs_sending_amount
-- Question: Does the event's minAmount equal the amount LI.FI's status API reports as sent
--           (sending.amount), and in the same token? How does that differ between rows
--           with and without a source-side step (hasSourceSwaps)?
-- Grain:    one row per (sample design, hasSourceSwaps), the same over both designs
--           (sample = 'all_2600'), and an overall total (has_source_swaps = 'all').
-- Definition applied:
--   - Compared per sampled event: the event's min_amount (exact HUGEINT) with the API's
--     sending_amount (exact HUGEINT), and the event's sendingAssetId with the API's
--     sending token address, both lowercased.
--   - same token, API amount greater: the API reports more of the same token than the
--     event (a source-side step that keeps the token, such as fee collection, ran first).
--   - different token, same amount: a 1:1 conversion before bridging (ETH wrapped to
--     WETH, an Aave aToken redeemed to USDC).
-- Inputs:   ref_lifi_api_transfer_status_sample_2600 (reference data: LI.FI /v1/status by
--           tx_hash, fetched 2026-10-28; 2,000 uniform events and 600 equal-per-chain events).

SELECT CASE WHEN grouping(sample_design) = 1 THEN 'all_2600' ELSE sample_design END          AS sample,
       CASE WHEN grouping(event_hasSourceSwaps) = 1 THEN 'all'
            ELSE CAST(event_hasSourceSwaps AS VARCHAR) END                                    AS has_source_swaps,
       count(*)                                                                               AS events,
       count(sending_amount)                                                                  AS with_api_sending_amount,
       count(*) FILTER (WHERE sending_amount = event_minAmount)                               AS amount_equal,
       count(*) FILTER (WHERE lower(sending_token_address) = event_sendingAssetId)            AS token_equal,
       count(*) FILTER (WHERE sending_amount = event_minAmount
                          AND lower(sending_token_address) = event_sendingAssetId)            AS amount_and_token_equal,
       count(*) FILTER (WHERE lower(sending_token_address) = event_sendingAssetId
                          AND sending_amount > event_minAmount)                               AS same_token_api_amount_greater,
       count(*) FILTER (WHERE lower(sending_token_address) = event_sendingAssetId
                          AND sending_amount < event_minAmount)                               AS same_token_api_amount_smaller,
       count(*) FILTER (WHERE lower(sending_token_address) <> event_sendingAssetId
                          AND sending_amount = event_minAmount)                               AS different_token_same_amount,
       count(*) FILTER (WHERE lower(sending_token_address) <> event_sendingAssetId)           AS token_different
FROM ref_lifi_api_transfer_status_sample_2600
GROUP BY GROUPING SETS ((sample_design, event_hasSourceSwaps), (event_hasSourceSwaps), ())
ORDER BY grouping(sample_design), sample_design, grouping(event_hasSourceSwaps), event_hasSourceSwaps
