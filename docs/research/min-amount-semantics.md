# `minAmount` in `LiFiTransferStarted`: which side, which decimals, what it means on swap rows

AI-assisted investigation of 2026-10-30, prompted by third-party pages that call `minAmount` "the minimum amount to receive". Sources: LI.FI's contract code (`lifinance/contracts`, branch `main`, fetched 2026-10-30), the committed status API snapshots (reference data, fetched 2026-10-28), four transactions read from public RPCs on 2026-10-30, and LI.FI help pages. Labels: **named query** figures are pinned by tests; **one-off check** figures come from one-off scripts and are not pinned. "(inference)" marks what no source states.

## 1. Summary

1. `minAmount` is the amount of `sendingAssetId` the LI.FI Diamond handed to the bridge on the **source** chain, in that token's smallest unit with the **source** chain's decimals. It is not denominated in the destination token or the destination chain's decimals.
2. The receiving-side floor is a different field in each bridge's own struct (Across `outputAmount`, Stargate `minAmountLD`). It is not in `BridgeData` and not in the export.
3. Rows without a source swap: `minAmount` is the exact amount deposited. Calldata, event and the status API's `sending.amount` all carry the same integer.
4. Rows with a source swap: in the **calldata**, `minAmount` is the minimum acceptable output of the source swap, the quote's `toAmountMin` for the swap step at the chosen slippage. The contract reverts if the swap returns less, otherwise overwrites the field with the realised swap output and only then emits the event. The **event**, and so the export, carries the realised amount, not the floor.
5. The "minimum to receive" wording comes from auto-generated docs of the `lifi-contract-types` package and from `SwapperV2.sol`'s own parameter comment, "the minimum amount of the final asset to receive". The final asset there is the output of the source-side swaps on the source chain, not what arrives at the destination.

## 2. The contract path

Files from `lifinance/contracts`, `main`, 2026-10-30. Line numbers are from that fetch.

- `src/Interfaces/ILiFi.sol` lines 10 to 21: `BridgeData` is `transactionId, bridge, integrator, referrer, sendingAssetId, receiver, minAmount (uint256), destinationChainId, hasSourceSwaps, hasDestinationCall`. The struct carries no field for the destination token or a destination amount. Line 25: `event LiFiTransferStarted(ILiFi.BridgeData bridgeData)`.
- `src/Helpers/Validatable.sol` line 18: `minAmount == 0` reverts with `InvalidAmount`.
- No source swap (every facet, for example `AcrossFacetV4.sol` lines 107 to 111 and `RelayDepositoryFacet.sol` lines 67 to 71): `LibAsset.depositAsset(_bridgeData.sendingAssetId, _bridgeData.minAmount)` pulls exactly `minAmount` of the sending token from the caller, then `_startBridge` runs.
- Source swap (`AcrossFacetV4.sol` lines 130 to 135, `RelayDepositoryFacet.sol` 91 to 96, `StargateFacetV2.sol` 85 to 88): `_bridgeData.minAmount = _depositAndSwap(_bridgeData.transactionId, _bridgeData.minAmount, _swapData, payable(msg.sender))`. In `src/Helpers/SwapperV2.sol`: line 85 documents the second parameter as "the minimum amount of the final asset to receive"; lines 101 to 126 take the Diamond's balance of the last swap's `receivingAssetId` before and after the swaps, revert with `CumulativeSlippageTooHigh(_minAmount, newBalance)` if the gain is below the floor, and return the gain. The facet stores that return value in `minAmount`.
- Handoff to the bridge: `AcrossFacetV4.sol` lines 209 to 215 and 228 to 236 call the SpokePool with `_bridgeData.minAmount` as `inputAmount` and `_acrossData.outputAmount` as `outputAmount`. Lines 137 to 146: after a swap the facet rescales `outputAmount` by `outputAmountMultiplier` "to account for the difference in decimals ... from 6 > 18 decimals and vice versa"; the comment states the multiplier is `multiplierPercentage * 1e18 * 10^(outputDecimals - inputDecimals)`. `StargateFacetV2.sol` line 154 sets `sendParams.amountLD = _bridgeData.minAmount` and lines 156 to 160 describe `sendParams.minAmountLD` as "the destination floor".
- The event is emitted after all of this (`AcrossFacetV4.sol` 246, `RelayDepositoryFacet.sol` 143, `StargateFacetV2.sol` 169), so the exported value is the post-swap, pre-bridge amount.

## 3. Evidence

### 3.1 No source swap, decimals differ between the chains (one-off check, on-chain)

Ethereum → BNB, USDT, `across`, `hasSourceSwaps = false`. Export: `minAmount` 609197905, `destinationChainId` 56. USDT has 6 decimals on Ethereum and 18 on BNB.

| Where | Value | Reading |
|---|---|---|
| Ethereum tx `0x01c70d82d1dc85835be1ce82d3892bc84003836e949ddcca07d788d13a26d1a8`, block 26185162: three USDT `Transfer` logs, user → router → Diamond → Across SpokePool | 609197905 each | 609.197905 USDT at 6 decimals |
| Same receipt, `LiFiTransferStarted` data, struct word 6 | 609197905; word 7 = 56 | equals the export |
| Status API `sending.amount` | 609197905 | equals the export |
| BNB tx `0x0baf937573042f14b34c08ef392f06d7cec019a11dbd9a7dd1115cbdf4e69aaa`, block 127445357: USDT `Transfer` to the receiver | 609133329000000000000 | 609.133329 USDT at 18 decimals |

Had the field used the receiving side's unit it would read about 6.09e20, not 6.09e8.

### 3.2 Source swap: calldata floor versus emitted value (one-off check, on-chain plus the stored quote)

BNB, user pays USDT, swapped to ETH (Binance-peg) by `bitget`, bridged by `across`. Tx `0x5e281ecd835e13b365605a5c935c32f98eb0ee561408190d4bfc9e918cddee28`, sent directly to the Diamond. All ETH values at 18 decimals.

| Stage | Value | Source |
|---|---|---|
| User input | 1673 USDT; `feeCollection` step leaves 1667.981 USDT | status response, `sending.includedSteps[0]` |
| Swap step expected output | 664667433092354734 | `quote.includedSteps[1].estimate.toAmount` |
| Swap step minimum | 658020758761431186 (= expected × 0.99; `action.slippage` = 0.01) | `quote.includedSteps[1].estimate.toAmountMin` |
| `BridgeData.minAmount` in the calldata | 658020758761431186 | tx input, struct word 6; `destinationChainId` word = 1, `hasSourceSwaps` = 1 |
| Bridge leg quoted on | 658020758761431186 | `quote.includedSteps[2].estimate.fromAmount` |
| `minAmount` in the emitted event and in the export | 664868023347329352 | receipt, struct word 6; equals `sending.includedSteps[1].toAmount` |

Realised over floor: 1.0104. A second direct call, `0x6fe871a6592e8e275f2687935a71f1d968deaa3e7147eda1f1f8b2bb56196e68` (50 USDT → ETH → chain 4663): `toAmountMin` 19462737473551701 = calldata `minAmount`; emitted 19662288505508209 = `sending.includedSteps[1].toAmount`; ratio 1.0103. Two other sampled swap transactions were sent through another contract rather than to the Diamond, so their calldata nests the struct and was not decoded; their emitted values match the export.

The slippage in both examples is 1%, set by the integrator. LI.FI's default when the quote request names none is 0.5% per step (help centre, see sources). (inference) The floor is "user-defined" only in the sense that the wallet or app chooses the slippage; LI.FI's backend writes the number into the calldata.

### 3.3 Status API sample, rows whose two sides have different decimals (one-off check)

Over the 2,600-event status sample (reference data): 933 events have different token decimals on the sending and receiving legs.

| Set | Rows | `minAmount` = API `sending.amount` | `minAmount` = API `receiving.amount` |
|---|---|---|---|
| Decimals differ, no source swap | 212 | 212 | 0 |
| Of which stablecoin on both sides (USDC, USDT, USDC.e, USDbC; 34 routes, 6 ↔ 18 in both directions) | 155 | 155 | 0 |
| Decimals differ, stablecoin both sides, with source swap (33 routes) | 116 | 0 | 0 |

Swap rows match neither because the API's `sending.amount` is the pre-swap input in the pre-swap token (named query `11_status_min_amount_vs_sending_amount`: on the 831 sampled events without a source step, `sending.amount` equals `minAmount` exactly, in the same token). Received amount over `minAmount`, each shifted by its own chain's decimals, has a median between 0.94 and 1.00 on every stablecoin route and 0.999 on most. The sample includes USDT → USDC routes (BNB USDT to Base USDC, 8 rows), so the token is not always the same on both sides either; `minAmount` is still the USDT sent.

### 3.4 Whole export, BNB routes (one-off check)

USDC and USDT have 18 decimals on BNB and 6 on the other five source chains. Shifting `minAmount` by the **source** (chain, token) decimals from `prices.csv`:

| Rows | Count | Median tokens per route | Raw values on the wrong side of 1e12 |
|---|---|---|---|
| BNB USDT/USDC → the 12 largest destinations (Ethereum, Arbitrum, Base, Polygon, 4663, Solana and others) | 15,052 | 21.56 to 991.48 | 0 below 1e12 |
| 6-decimal USDC/USDT on Base, Ethereum, Arbitrum, Polygon, Optimism → BNB | 7,697 | 3.67 to 142.86 | 2 above 1e12 (the two Ethereum USDT transfers above $1M) |

Under destination decimals these would be off by 10^12 in opposite directions.

## 4. What this means for the analysis

- USD valuation shifts `minAmount` by the source (chain, `sendingAssetId`) decimals, from `prices.csv`, else LI.FI's token list. That is what the view `transfers_priced` does.
- 14,864 rows exceed int64 (named query `47_min_amount_above_int64`), so the integer stays exact until the shift.
- On the 67.8% of rows with `hasSourceSwaps`, the value is the realised swap output: at or above the quote's `toAmountMin`, in the post-swap token. The user's input token and amount are not in the export; the status API's `sending.amount` has them.
- What arrives is not in the export. On completed transfers the API's received USD is a median 0.9965 of sent USD (named query `42_status_received_over_sent_and_gas`).
- The 295 same-chain `*Dex` rows (`lifiIntentsDex`, `m0Dex`, `paxosDex`) are the same event with destination = source; `minAmount` is the amount handed to that tool.

## 5. Limits

- The facets were read from `main` on 2026-10-30. Facets deployed during the export window (13 to 19 October 2026) may be earlier versions; `AcrossFacetV3.sol` and `RelayFacet.sol`, for example, no longer exist on `main`. The pattern "deposit or swap, assign, then emit" is the same in every facet read, and the Across row in §3.1 confirms it for deployed code.
- Calldata was decoded only for transactions sent directly to the Diamond. Bundled or relayed calls nest the struct inside another ABI and need the outer selector to decode.

## 6. How to reproduce the on-chain reads

`eth_getTransactionReceipt` on a public RPC (`https://ethereum-rpc.publicnode.com`, `https://bsc-dataseed.binance.org`; some others returned HTTP 403 or 525 without a browser user agent). In the Diamond's `LiFiTransferStarted` log (topic0 starts `0xcba69f43`), the data is an ABI-encoded struct behind one offset word: 32-byte word 7 is `minAmount`, word 8 `destinationChainId`. In the calldata of a direct call, word 0 after the selector is the offset of the struct; from there word 4 is `sendingAssetId`, 5 `receiver`, 6 `minAmount`, 7 `destinationChainId`, 8 `hasSourceSwaps`. ERC-20 transfers are the logs with topic0 `0xddf252ad…b3ef` on the token address.

## 7. Sources

- `lifinance/contracts` on GitHub, `main`, 2026-10-30: `src/Interfaces/ILiFi.sol`, `src/Helpers/SwapperV2.sol`, `src/Helpers/Validatable.sol`, `src/Facets/AcrossFacetV4.sol`, `src/Facets/RelayDepositoryFacet.sol`, `src/Facets/StargateFacetV2.sol`.
- LI.FI help centre: "Is the difference between toAmount and toAmountMin purely based on the slippage ... which is the default slippage" (https://help.li.fi/hc/en-us/articles/13305089581595), "How does slippage and toMinAmount work in routes with several steps" (https://help.li.fi/hc/en-us/articles/12111462474139); LI.FI docs, slippage and price impact (https://docs.li.fi/faqs/slippage-price-impact). Accessed 2026-10-30.
- The "minimum amount to receive" wording: Mintlify mirror of `lifinance/lifi-contract-types` (https://www.mintlify.com/lifinance/lifi-contract-types/guides/bridge-integration and `/concepts/bridge-data`); both returned HTTP 410 on 2026-10-30, so only search snippets were seen.
- Reference data: `data/reference/lifi_api_transfer_status_sample_2600.csv` (LI.FI `/v1/status`, fetched 2026-10-28).
- Named queries: `11_status_min_amount_vs_sending_amount`, `42_status_received_over_sent_and_gas`, `47_min_amount_above_int64`.
