# LI.FI prices bridges by integrator, not route

LI.FI's documented charge is 0.25% "on each transaction", and neither of two simple readings (a documented 0.25% that is always applied, or a 0%) describes what it does on bridge-only transfers. Its own worked example applies 0.25% to a USDC Ethereum to USDC Arbitrum bridge with no DEX step, and live quotes on 2026-11-02 show the same 25 bps for an unconfigured caller from $1,000 to $1,000,000. No LI.FI text says bridge-only transfers on its API or SDK are charged 0%. The one written 0 is Jumper's "0 bps" on stablecoin bridges, in place since 2026-09-29, with ETH bridges at 2 bps. The same $10,000 USDC quote carries no fee step under five registered integrator strings, so the zero follows the integrator string and the token class, and no public text says why for any partner. 79.07% of bridge volume has no source step (query `84_revenue_sensitivity_to_fee_rate`). That group excludes every same-token bridge that pays through a fee step and includes bridges that change token. A LI.FI bridge-only fee already exists for default callers, so any change is a change to configured rates for named integrators, on a market where direct fast routes cost about 1 bp and CCTP Standard routes cost about 0. No aggregator or bridge protocol checked has a free limit per transfer; token-based tiers are common. Same-token counts in this report are counted over committed snapshots with no named query.

## Evidence labels

AI-assisted research, run on 2026-11-02. Each claim below carries one of these labels.

| Label | Meaning |
|---|---|
| Doc | Read from the raw text of the vendor's own documentation or code |
| Doc (extracted) | Vendor page read through a fetch tool that returns extracted text. |
| Search excerpt | Seen only in a search engine's copy. The live page was not read, or no longer exists. Not confirmed as an exact quotation |
| Secondary | Third party, press or competitor marketing |
| Quote | Live API response on 2026-11-02. An estimate at one moment on one route, nothing signed or sent |
| On-chain | Receipt or contract state read by public RPC |
| Named query | A file in `analysis/queries/` |
| Ad hoc | Counted over committed snapshots with no named query |
| Inference | My reading, not stated by any source |
| Not found / Not tested | Searched and absent / not run. Neither means zero |

Docs.li.fi has no version history, so an undated quotation means live on 2026-11-02. Live quote results are not in the committed snapshots, so no query pins them.

## LI.FI writes 0.25% on each transaction and never writes 0% for its API

**LI.FI's general statement covers bridges and contains no bridge-only exception.** Asked "Does LI.FI charge a fee on every swap or bridge transaction?", the FAQ answers "LI.FI charges a 0.25% service fee on each transaction." ([FAQ](https://docs.li.fi/faqs/fees-monetization), Doc). A full-text search of the docs (46,597 lines) and the OpenAPI spec for "bridge-only", "bridge only", "bridging only", "fee-free", "zero fee", "free of charge", "no additional fee", "minimum fee", "fee waiver" and "waive" found nothing about LI.FI's own fee ([llms-full.txt](https://docs.li.fi/llms-full.txt), Not found). `hasSourceSwaps` does not appear in the docs or the spec; it is a contract field ([ILiFi.sol](https://github.com/lifinance/contracts/blob/main/src/Interfaces/ILiFi.sol), Doc).

| Statement | Source | Label |
|---|---|---|
| Five-call recipe quotes `fromToken=USDC&toToken=USDC`, Ethereum to Arbitrum. Response has `"tool": "across"`, a `feeCollection` step, `"name": "LIFI Fixed Fee"`, `"percentage": "0.0025"`, `"feeSplit": { "integratorFee": "0", "lifiFee": "25000" }` | [Five-call recipe](https://docs.li.fi/agents/quick-start/five-call-recipe) | Doc, implied by example |
| "Integrations without Dynamic Pricing pay the standard fixed LI.FI service fee" | [Dynamic Pricing](https://docs.li.fi/enterprise/dynamic-pricing) | Doc |
| "LI.FI also offers volume-based commercial discounts." and "Custom fee models are available if required." | [FAQ](https://docs.li.fi/faqs/fees-monetization) | Doc, names no integrator or route |
| "Pricing for LI.FI's enterprise features is agreed per integration, not a fixed rate card."; "Same-chain and cross-chain are priced differently."; "Stablecoin-to-stablecoin flows can carry a lower rate than volatile-asset swaps."; "The exact weighting is part of your commercial terms and is not published." | [Dynamic Pricing](https://docs.li.fi/enterprise/dynamic-pricing) | Doc, enterprise only |
| "LI.FI may receive a share of the collected fees depending on the use case and volume." This conflicts with the flat FAQ wording. "will receive" became "may receive" after the 2026-04-16 capture | [Monetizing the integration](https://docs.li.fi/introduction/integrating-lifi/monetizing-integration) | Doc |
| "Main — Stable bridge" "0 bps (0%)", "Main — Major bridge" "2 bps (0.02%)", "Main — Other bridge" "5 bps (0.05%)"; "This page covers the fees charged by **Jumper itself**." | [jumper-fees.mdx](https://github.com/lifinance/jumper-docs/blob/main/jumper-fees.mdx) | Doc (the rendered docs.jumper.xyz returned 403) |
| "Dynamic stablecoin route fees revamped for better pricing." (January 2026); "Added native USDC support on Cronos and a 2 bps Near fee for stable routes." (July 2026) | [Monthly updates](https://docs.li.fi/changelog/monthly-updates) | Doc, no rate or scope given |
| "The contract is meant to be used as part of a batch of transactions run in the swap step of a LIFI bridging transaction." | [FeeCollector.md](https://github.com/lifinance/contracts/blob/main/docs/FeeCollector.md) | Doc, last commit 2022-06-30 |

**The written position has changed twice, and no version separates bridge-only.** "LI.FI does not take any fee by default." appears in the help centre from an article updated March 1, 2023, in captures to 2024-06-25 ([capture](https://web.archive.org/web/20230921192259/https://help.li.fi/hc/en-us/articles/13304987014299-Can-you-share-some-insight-on-the-fees-structure-of-using-LI-FI-for-a-DApp-), Doc). An article updated January 29, 2025 says "LI.FI collects a Monthly Service Fee which is 25bps (0.25%) for each transaction that is executed via LI.FI Smart Contracts & Services." ([capture](https://web.archive.org/web/20251009115737/https://help.li.fi/hc/en-us/articles/13304987014299-Can-you-share-some-insight-on-the-fees-structure-of-using-LI-FI-for-a-DApp), Doc). These dates are "updated" labels and capture dates; no announced effective date was found. The current help centre returned 403.

**Jumper's page has an internal conflict and a short history.** The fee file's first commit, 2026-09-23, had stable bridges at 1 bp, and it reads 0 bps from 2026-09-29 ([bf53a26f](https://github.com/lifinance/jumper-docs/commit/bf53a26f), Doc). The overview page still lists a stable bridge at "1 bp (0.01%)" ([overview](https://github.com/lifinance/jumper-docs/blob/main/products/swap-bridge/overview.mdx), Doc). The data window, 13 to 19 October 2026, falls after the change. The Jumper page does not mention LI.FI's 0.25% or say which tokens are "Stable" or "Major" (Not found).

**Third parties disagree with each other, and the ones that say zero cite no LI.FI text.** "LI.FI charges no protocol fee." ([Stablecoin Insider](https://stablecoininsider.org/synapse-vs-li-fi-which-cross-chain-bridge-should-you-use/), Secondary, extracted) and "Neither LiFi nor Socket charges an explicit aggregator fee on most routes." ([Eco](https://eco.com/support/en/articles/14800727-lifi-vs-socket-which-aggregator-api-to-build-on), Secondary, a competitor, extracted) cite no LI.FI sentence. No staff statement on bridge-only fees was found; Discord and X could not be searched.

## Quotes, contracts and receipts show the zero follows the integrator string

**The same transfer is 25 bps or 0 depending only on the string passed.** Request: `GET https://li.quest/v1/quote`, Ethereum to Arbitrum, no key. Label: Quote.

| Test | Result |
|---|---|
| USDC to USDC, no integrator, $1k, $10k, $100k, $1M | `polymerStandard`, `includedSteps` feeCollection then cross, `LIFI Fixed Fee` 0.0025 at all four, `integratorFee` 0, recipient `lifi` type `FIXED`. `toAmount` exactly 99.75% of `fromAmount` |
| ETH to ETH, no integrator, same four sizes | `arbitrum`, `LIFI Fixed Fee` 0.0025 |
| USDT to USDT0 (by address), no integrator, $10k and $1M | `glacis`, `LIFI Fixed Fee` 0.0025 |
| USDC to USDC $10k, made-up string `zz-madeup-77` | Fee step present, 0.0025, `toAmount` 9975000000 |
| USDC to USDC $10k, `jumper.exchange`, `_arbitrum`, `Pharos-Bridge`, `_binancewallet`, `Cow` | Same bridge, no fee step, empty `feeCosts`, `toAmount` 10000000000, selector `startBridgeTokensViaPolymerCCTP` |
| USDC to ETH $10k on `squid` | `jumper.exchange` 0.0002; `zz-madeup-77` 0.0025 |
| `fee=0` with no integrator | Accepted; `LIFI Fixed Fee` still 0.0025 |
| `fee=0.01&integrator=jumper.exchange` on the stepless route | A fee step appears, line named `LIFI Fixed Fee`, `lifiFee` 0, `integratorFee` 100000000, and `hasSourceSwaps = 1` in calldata |

**The flag cannot be false on a transfer with a LI.FI fee step.** On 32 of 33 facet files scanned, `startBridgeTokensVia…` carries `doesNotContainSourceSwaps` and `swapAndStartBridgeTokensVia…` carries `containsSourceSwaps` ([Validatable.sol](https://github.com/lifinance/contracts/blob/d1b7ca7879284e417e5fc6d8089bf9299af48d1b/src/Helpers/Validatable.sol#L54-L66), Doc; the exception, `AcrossFacetPackedV4`, has no swap entry point). Current quotes run the fee as a `SwapData` call to FeeForwarder `forwardERC20Fees` with `hasSourceSwaps` 1 and no DEX. The scan covers current `main` and function headers, not the bytecode live in October. Task 1 already records that 61.7% of flagged rows are fee collection only (query `58_status_source_steps`, Named query).

**Receipts confirm no in-transaction fee on the flag-false side.** Selection: the four largest completed flag-false same-token rows per bridge, and the ten largest flag-true fee-only rows as a control. The control proves the test detects a fee. On 1,178 of 1,178 flag-false rows `sending_amount` equals `minAmount` (Ad hoc).

| Group | Receipts | USD | `FeesForwarded` | `FeesCollected` | Transfer to a LI.FI fee address |
|---|---|---|---|---|---|
| Flag false, 15 bridges | 52 | $57.1M | 0 | 0 | 0 |
| Control, Ethereum | 10 | $6.7M | 10 | 0 | 9 (the tenth pays in native ETH, which a receipt does not show as a Transfer) |

Example: [0xb2259fe1…87ae](https://etherscan.io/tx/0xb2259fe1302e16a0fcb14284f3fbedfcc15407c48b87ea558801d6d8d2d487ae), `_arbitrum`, `polymerStandard`, 10,000,000,000,000 USDC units sent and the same amount minted on Arbitrum (On-chain). The fee wallet `0xc06ebbef…264b` is identified by inference, from quotes naming recipient `lifi` with the amount calldata sends there.

**Quotes pass the bridge price through at the size tested, with one exception.** At $100,000, LI.FI's bridge leg minus the bridge's direct quote was 0.00 bps on Across and on Relay. On Mayan MCTP it was +1.99 bps: LI.FI's calldata sets `redeemFee` 19943021 against Mayan's own relayer fee of 82545 in the same units, shown to the user as a "Redeem Relayer Fee" line. Who keeps the difference was not determined. Stargate could not be compared (Quote, one size, one route, one moment). `mayanMCTP` is $526,017 of file volume (Ad hoc).

**Status records repeat the pattern on executed transfers.** Same-token rows with a fee step, all snapshots, distinct rows (Ad hoc):

| String | Rows | LI.FI median bps | Integrator median bps | Published rate that matches |
|---|---|---|---|---|
| `jumper.exchange` | 382 | 2.00 | 0 | Major bridge 2 bps ([Jumper](https://github.com/lifinance/jumper-docs/blob/main/jumper-fees.mdx), Doc) |
| `rabbykmsv2` | 143 | 0 | 25.00 | "a service fee of 0.25% is applied to bridges." ([Rabby](https://support.rabby.io/en/articles/14134280-how-to-use-rabby-bridge), Doc extracted) |
| `lifi-api` | 58 | 25.00 | 0 | LI.FI FAQ |
| `bitget` | 38 | 0 | 30.00 | Third-party routes "charge a flat service fee of 0.3%" ([Bitget](https://web3.bitget.com/ja/helpCenter/921), Doc) |
| `phantom` | 36 | 4.25 | 80.75 | Sum 85: "0.85% on most swaps." ([Phantom](https://help.phantom.com/articles/understand-cross-chain-swaps-in-phantom-51384804802195), Doc extracted) |
| `kyberswap` | 23 | 0 | 5.00 | EVM to EVM stable 0.05% ([KyberSwap](https://docs.kyberswap.com/getting-started/fee-schedule.md), Doc) |
| `Zerion` | 21 | 0 | 66.95 | Not looked up |
| `_ledger` | 19 | 20.00 | 70.00 | Not looked up |
| `safe-app` | 16 | 3.50 | 6.50 | Safe's own widget fee, with separate stablecoin tiers ([Safe](https://help.safe.global/articles/4682860081-how-does-the-widget-fee-work-for-native-bridge-transactions), Secondary, extracted) |

The matching column is my pairing (Inference). It shows that a `LIFI Fixed Fee` line does not mean LI.FI revenue: on `rabbykmsv2` the line reads 0.0025 and all of it goes to the integrator. It also shows that wallets charge end users on same-token transfers. `_binancewallet` (223 flag-false rows), `_arbitrum` (81), `Cow` (72), `jumperadvanced` (40) and `Pharos-Bridge` (3) have no same-token rows with a fee step in these snapshots (Ad hoc). For `jumper.exchange`, flag-false rows are stablecoins only (USDC 376, USDT 62, USDG 12, PYUSD 3), and all 12,466 of its rows with native ETH as the source asset in the file are flag true, $7,607,607 (Ad hoc). Sixteen USDC rows carry a fee step at a median 5 bps; no documented exception explains them.

**Written terms for the zero-rate strings do not exist in public.** Only LI.FI can say whether the zero for `_arbitrum`, `_binancewallet`, `Cow`, `Pharos-Bridge` or `os-prod` is a contract, a promotion or an offset. "Commercial discounts" and "custom fee models" could cover it, but no public text ties those terms to a named integrator (Inference).

## What the 79% figure does and does not describe

**What stands.** Transfers without `hasSourceSwaps` are 40,062 rows and $243,317,237.35, 79.07% of bridge volume (queries `84_revenue_sensitivity_to_fee_rate`, `85_under_monetised_segments`, Named query). Zero LIFI-named lines hold on 627 of 627 uniform bridge rows (query `75_status_fee_overall`, Named query, upper bound 0.61%) and on 309 of 309 at $100,000 and above (query `150_status_bridge_census_fee_usd_by_integrator`, Named query). Across all snapshots it is 0 of 1,178 distinct rows (Ad hoc).

**What changes.** The zero is close to a tautology: a fee step sets the flag, so the selection has removed every transfer with a fee step before the count starts. The uniform 2,000 split by route kind shows the effect. This is an unweighted sample whose USD is driven by a few large transfers (Ad hoc).

| Route kind, bridge-volume rows | Rows | Event USD | LIFI-named line | LI.FI fee above 0 | Integrator fee above 0 | LI.FI fee USD | Integrator fee USD |
|---|---|---|---|---|---|---|---|
| Flag false, same token | 410 | $2,370,516 | 0 | 0 | 0 | $0 | $0 |
| Flag false, different token | 217 | $378,986 | 0 | 0 | 0 | $0 | $0 |
| Flag true, `feeCollection` only, same token | 432 | $299,490 | 431 | 323 | 183 | $254.63 | $820.93 |
| Flag true, `feeCollection` only, different token | 408 | $125,534 | 408 | 375 | 206 | $137.82 | $514.32 |
| Flag true, `feeCollection` and DEX | 378 | $297,585 | 371 | 309 | 202 | $160.90 | $612.79 |
| Flag true, DEX only or other | 145 | $308,914 | 0 | 0 | 0 | $0 | $0 |

Four consequences follow. Counts in the first three are Ad hoc unless a query is named.

**Same-token bridges split about evenly by count and very unevenly by USD.** Of 842 same-token rows, 432 (51.3%) carry the fee step and 323 (38.4%) pay LI.FI a fee above 0. By USD the fee-step rows are 11.2%, and the LI.FI fee is 0.95 bps of same-token USD. A stricter count (exact symbol match, receiving chain differs) gives 394 fee-step and 372 no-step rows, 51.4% by count and 13.9% by USD. The gap comes from merging USDC variants, USDT variants and ETH with WETH, and from whether the destination is read from the event or from the receiving leg: the largest flag-false row in the sample, a $477,868 `jumper.exchange` Mayan transfer refunded on its source chain, can only fall in the event-based count. That explains most of the gap, not all of it. So "bridge-only pays nothing" is false for about half of plain bridges by count, and close to true for USD, because the paying rows are small.

**The 79% contains transfers that are not same-token.** In the uniform sample 13.8% of flag-false USD changes token inside the bridge, for example `lifiIntents` USDC to USDG. In the census 256 of 309 rows at $100,000 and above are same-symbol cross-chain. If the sample's 86.2% same-token share held across the file, same-token no-step volume would be about 68% of bridge volume (79.07% × 86.2%, Inference).

**"Pays LI.FI nothing" holds for the transaction and is unproven for LI.FI's income.** The status data cannot show a destination-side fee, an integrator-contract fee, a bridge rebate or an invoice. Token-unit gaps on 817 completed same-token flag-false rows are 0.26 bps USD-weighted against 0.19 bps listed, a 0.07 bps difference, with `polymerStandard` paying out exactly what it received on 243 of 243 rows (Ad hoc, pooled designs, not file-weighted). USD gaps are unusable at this scale because their interquartile range is about ±15 bps on bridges whose token-unit gap is 0. Three items are not explained.

| Item | Evidence | Size if LI.FI kept all of it | Who receives it |
|---|---|---|---|
| `lifiIntents` residual | Median 0.50 bps, quotes itemise under 0.02 bps. `governanceFee()` reads 0 on Ethereum, Arbitrum, Base (On-chain). LI.FI's solver Pioneer is documented: "LI.FI's own solver" ([Product stack](https://docs.li.fi/introduction/product-stack.md), Doc) | About $1,600 a week on $32.1M (Ad hoc, Inference) | Not determined. No document gives Pioneer's share of fills or margin. Direct order-server quote: 1.18 bps at $1,000, 5.00 bps at $100,000 |
| `NearIntents App Fee` | Description "Affiliate fee", no `feeSplit`; 2 bps on `jumper.exchange`, 10 bps on `Cow` | About $1,600 to $7,900 a week on $7.9M (Ad hoc, Inference) | Not determined |
| `mayan` (Swift) residual | Median 4.29 bps, no line | Not sized | Not determined. Mayan's 3 bps is the Fast MCTP rate, and Mayan documents "Swift has no protocol fee." ([Fees & Earning](https://docs.mayan.finance/integration/referral.md), Doc). **The cause is not determined.** $13.7M of file flag-false volume (Ad hoc) |

Also documented without a rate or scope: "Route quality improvements and positive slippage collection" (October 2025, [llms-full.txt](https://docs.li.fi/llms-full.txt), Doc). deBridge's quote returns `integratorPoints` at 25% of user points; whether LI.FI receives them was not found. Fee-wallet reconciliation of `FeesForwarded` logs for the week was not run; it would test the quoted-fee assumption at scale. Only LI.FI can rule out private terms.

**The named sizing base mixes things a fee rule treats differently.** Each basis point on the base is $23,893.75 a week (query `84_revenue_sensitivity_to_fee_rate`, Named query, volume held fixed). Bridge-only volume is $141,235,136.79 at partners, and `lifi_product` volume ($119,100,434.66) is 85.62% bridge-only, about $102.0M by multiplication (query `93_partner_revenue_concentration`, Named query; the product is mine). Jumper's stablecoin rows in that base sit under a published 0 bps. At $100,000 and above the base is concentrated: `_arbitrum` $54.2M, `jumper.exchange` $44.2M, `Pharos-Bridge` $16.7M, `_binancewallet` $14.2M, `Cow` $6.3M, of $145.46M (query 150, Named query). Among partners at that size, `_arbitrum`, `Pharos-Bridge` and `_binancewallet` hold $85.2M by addition. A change for each is a commercial negotiation, not a route rule (Inference). The treatment of Jumper as LI.FI's own product is an assumption: the page calls the fee "charged by **Jumper itself**", and a paid press release says "Jumper is now planned to be carved out as a standalone venture" ([Cointelegraph press release](https://cointelegraph.com/press-releases/jumper-to-launch-jump-token-sale-on-legion-as-it-spins-out-to-build-the-super-app-for-onchain-finance), Secondary, extracted, 2026-09-25). The `jumper.exchange` USDC to ETH quote reports the 2 bps in the `lifiFee` field (Quote); the docs do not say who receives it.

**Statement the evidence supports:** 79.07% of bridge volume starts with no source step (query 84). No transfer checked in that group carries a LI.FI fee in its quote or its transaction (queries 75 and 150). The group does not equal bridge-only: LI.FI's fee step sets the flag, so same-token bridges that pay sit outside it, and an unconfigured caller pays 0.25% on a same-token bridge. Which integrators sit at zero is observable; why, and whether LI.FI is paid another way, is not.

## Competitors charge same-token at the general rate or lower, and only Velora's quote reaches zero

**Aggregators: own fee only.** This table excludes the underlying bridge's fee, gas and integrator-set fees. Live tests were USDC Ethereum to Arbitrum at about $1,000 and $100,000. Same-token total reduction in bps of input, from output against input: LI.FI 25.0 and 25.0, Socket public 21.1 and 21.0, Rubic 41.1 and 41.0, Velora 1.5 and 1.0 (Quote).

| Vendor | Own fee, documented | Own fee line in quote, same-token / USDC to ETH | Integrator-set fee and vendor's share |
|---|---|---|---|
| Socket / Bungee | "Socket does not add any markup or hidden fees to transactions." ([docs](https://docs.socket.tech/about/fees-monetization), Doc) | 20 bps / 20 bps on public test endpoint, $5 to $100,000, recipient linked to Socket's router. Production credential Not tested. Not a production price | `feeBps` 0 to 10000; share not stated. "For direct bridge no-swap routes, fees are taken on the input side." ([docs](https://docs.socket.tech/llms-full.txt), Doc) |
| Squid | No rate. "Squid may charge additional platform fees" in future ([docs](https://docs.squidrouter.com/llms-full.txt), Doc). Own frontend: capped at 0.25%, stablecoin-to-stablecoin excluded (Search excerpt, [page](https://docs.squidrouter.com/additional-resources/frontend-fee) now not found) | Not tested (needs integrator ID) | "Squid takes 50% of any fees collected by an integratorAddress." ([docs](https://docs.squidrouter.com/api-and-sdk-integration/key-concepts/collect-fees-1), Doc) |
| Rango | "Rango charges 15 bps alongside the amount set by the API/SDK or Widget configuration." "Almost all EVM Bridges" covered ([docs](https://docs.rango.exchange/api-integration/rango-affiliate-program), Doc) | Not tested directly (Cloudflare 403). Indirect via Rubic's route list: 15.1 and 15.0 bps on USDC to USDC | Default 10 bps, maximum 3%. Docs also say 50% share on periodic settlement; not reconciled |
| Rubic | "default fixed fee in native tokens", no amount ([docs](https://docs.rubic.finance/api-docs/about/monetization/evm), Doc) | 40 bps / 40 bps, $5 to $1M; undocumented | Any percentage. Deposit routes 1%, 0.5% each ([docs](https://docs.rubic.finance/api-docs/about/monetization/non-evm), Doc) |
| Velora (ParaSwap) | "a flat 1 bps fee" without a partner ([docs](https://www.velora.xyz/docs/overview/monetization), Doc). No same-token rule | 0 / 1 bp. WETH to WETH 0. USDC to USDT 1 bp, so the zero follows same-token, not stablecoin. Undocumented | Delta "100% partner"; surplus 50/50. `partnerFeeBps=10` applied on same-token |
| 0x | "0x charges a 0.15% fee on cross-chain transactions." ([pricing](https://0x.org/pricing), Doc extracted) | Not tested (needs key) | `feeBps` 0 to 10,000, in addition |
| 1inch | Swap API, stablecoin / non-stablecoin bps by plan: 10/30, 7/20, 4/10, 2/5 ([docs](https://business.1inch.com/portal/documentation/faq/infrastructure-fee), Doc extracted). Fusion+ not named | Not tested (needs key) | Not found |
| KyberSwap | Cross-chain platform fee, EVM to EVM: "Stable tokens & Same native token" 0.05%, Common 0.10%, Exotic 0.15%, High-volatility 0.25% ([fee schedule](https://docs.kyberswap.com/getting-started/fee-schedule.md), Doc) | Not tested (no endpoint found) | Not found for cross-chain |
| Enso | "where it applies under your agreement", no rate ([docs](https://docs.enso.build/pages/build/reference/fees), Doc) | Not tested (needs key) | 50/50 by default |
| OKX | Start-up: "retain 20% of your revenue as our infrastructure fee." No cross-chain or stablecoin wording ([docs](https://web3.okx.com/onchainos/dev-docs-v5/dex-api/dex-api-fee), Doc extracted) | Not tested (needs key) | Maximum 3%, 10% on Solana |
| Uniswap | "As of December 27, 2025 Uniswap Labs does not charge interface fees" ([support](https://support.uniswap.org/hc/en-us/articles/20131678274957), Search excerpt, page returned 403) | Not tested (needs key) | Not found |
| XY Finance | Margin on third-party bridges Not found. Own yBridge has a rate, minimum and maximum ([docs](https://docs.xy.finance/fee-structure/ybridge-fee-information), Doc) | Not tested (DNS failure) | Share "based on the specific use case and transaction volume" |

Swing's hosts and Router's quote hosts did not resolve. Router Nitro is reported closed by 30 Sept 2026 ([Crypto Daily](https://cryptodaily.co.uk/2026/09/router-protocol-shutdown-route-token-burn), Secondary, extracted). OpenOcean returned a Cloudflare challenge.

**Wallets publish retail rates on bridges, and most do not discount same-token.** "if you want to bridge 1,000 USDT, for example, the MetaMask fee would be 8.75 USDT" ([MetaMask](https://support.metamask.io/manage-crypto/move-crypto/bridge/how-are-bridge-fees-calculated), Search excerpt). Ambire: "a flat **0.5% fee** on built-in swaps and bridges." ([Ambire](https://blog.ambire.com/reduce-swap-bridge-fees-proposal/), Doc extracted). Bitget's own liquidity: "USDT → USDT: 0.3%", "Major token → major token: 0.7%", "Other token pairs: 0.8% to 1.3%" ([Bitget](https://web3.bitget.com/ja/helpCenter/921), Doc). Backpack: "Backpack Wallet charges 0% on all bridge transactions" ([Backpack](https://learn.backpack.exchange/articles/zero-fee-crypto-wallet-swaps-bridges), vendor marketing, extracted).

**Bridge and intent protocols reached directly: the protocol's fee and the all-in price are separate figures.** All-in = input minus output plus separately paid ETH, in bps, USDC Ethereum to Arbitrum, excluding the user's source gas (Quote, my arithmetic). Polymer and Glacis have no public quote API found, so they were quoted through LI.FI with LI.FI's 25 bps line removed.

| Protocol | Protocol's own fee, documented | $1,000 | $100,000 | $1,000,000 | Separate price for swaps or non-stable pairs |
|---|---|---|---|---|---|
| Across | "Across takes 0% fees paid by users." ([DefiLlama](https://api.llama.fi/summary/fees/across?dataType=dailyFees&excludeTotalDataChart=true&excludeTotalDataChartBreakdown=true), Secondary). Quote: 1 bp relayer capital fee | 1.08 | 1.00 | Rejected; 1.00 at $900k | Not stated |
| Relay | Token Bridge "0.00%" ([fees](https://docs.relay.link/references/api/api_core_concepts/fees.md), Doc). Quote: 1 bp `swap` line, recipient not stated | 1.23 | 1.00 | 1.00 | Stablecoin Swap 0.01%, Major 0.06%, Minor 0.15% |
| Mayan MCTP | "zero if the output token is USDC and 3 basis points for other tokens." ([MCTP](https://docs.mayan.finance/architecture/mctp.md), Doc) | 0.82 | 0.008 | 0.0008 | 3 bps on non-USDC output |
| Mayan Fast MCTP | "Protocol fee is 3 basis points." | 4.65 | 4.11 | 4.10 | Not stated |
| CCTP (Circle) | "Standard Transfers are free."; Fast "0-13 basis points" by source chain ([fees](https://developers.circle.com/cctp/concepts/fees.md), Doc). Ethereum Fast 1 bp | 1 bp Fast, 0 Standard, by API rate | Same, calculated | Same, calculated | USDC only |
| Polymer | Standard: "1:1 USDC transfers with zero slippage" ([LI.FI blog](https://li.fi/knowledge-hub/li-fi-integrates-polymer-to-unlock-zero-slippage-stablecoin-transfers), Doc, co-launch post). No Polymer pricing found | Standard 0; Fast 2.0 | Standard 0; Fast 2.0 | Standard 0; Fast 2.0 | USDC only |
| Celer cBridge | "Protocol Fee ranges from 0% to 2%" ([FAQ](https://cbridge-docs.celer.network/reference/faq), Doc). Quote: 1 bp | 1.07 | 1.00 | No liquidity | Not stated |
| NEAR Intents (1Click) | Keyless "Additional 0.25% (25 bps)"; with key "0.01% (1 bp) for stablecoin pairs (USDC, USDT, DAI) and same-asset multichain routes" ([fees](https://docs.near-intents.org/resources/fees.md), Doc). **Keyless dry quote contradicts: echoes `fee: 1`** | 1.52 | 2.02 | No liquidity | "0.20% (20 bps) normally" |
| LayerSwap | "A percentage-based service fee defined per route (e.g. 0.05%)" ([fees](https://docs.layerswap.io/concepts/fees.md), Doc) | 10.25 | 0.027 | 0.0027 | Same-token market impact "typically \$0" |
| Glacis | Core "does not include any additional fees" ([docs](https://docs.glacislabs.com/glacis-core/messaging-fees/protocol-fees.md), Doc). Quote: `Airlift Fee` 1 bp | 6.6 | 1.06 | 1.01 | Not found |
| Stargate V2 | "dynamic fees" ([fees](https://stargateprotocol.gitbook.io/stargate/v2-user-docs/whats-new-in-stargate-v2/fees.md), Doc). On-chain read 6.0 to 6.07 bps, can be a rebate | 21.2 | 6.17 at $90k; pool cap 93,194.71 USDC | Over cap | Not found |
| deBridge DLN | "Variable protocol fee (4 bps)", "Taker margin (≈ 4 bps)", flat fee ([fee structure](https://docs.debridge.com/dln-details/overview/fee-structure.md), Doc). No stablecoin exemption found | 33.84 | 8.52 | 8.05 | Not found |
| Chainflip | "0.10% (0.01% for internal stablecoin swaps) \$0.5 USD minimum" ([docs](https://docs.chainflip.io/protocol/how-swapping-works), Doc). Test charged 10 bps on USDC to USDC across chains | 12.94 | 12.95 | No liquidity | 0.01% rate did not apply here |
| LI.FI Intents, direct | No fee lines; `governanceFee()` 0 | 1.18 | 5.00 | No quote | Not stated |

No figure was measured for Hop, Synapse, Wormhole Token Bridge, canonical rollup bridges or Gas.zip (no quote API, or the API failed). Their documents give Hop a "minimum fee of \$0.25 per Hop transfer" ([Hop](https://docs.hop.exchange/basics/fees.md), Doc, undated). Relay's platform fee of 0.00% does not make the transfer free: the 1 bp remains in the `swap` line. Against this table, the 25 bps default is about 25 times the direct fast price on this route, and the fee is almost the whole cost on `polymerStandard` (Inference). `polymerStandard` carries $124.3M of the file's flag-false USD (Ad hoc), and its direct equivalents cost 0.008 to 0.027 bps at $100,000. All of this is one route; Ethereum is the cheapest CCTP Fast source, so these bps may not hold on L2 to L2.

**Protocols pay integrators mostly through a fee the integrator adds.** Across, deBridge, Mayan and Chainflip let an integrator add a fee on top ([Across](https://docs.across.to/llms-full.txt), [deBridge](https://docs.debridge.com/home/monetization/affiliate-fees.md), [Mayan](https://docs.mayan.finance/integration/referral.md), [Chainflip](https://docs.chainflip.io/brokers), all Doc). Relay's revenue share is 0% on Token Bridge at both listed volume tiers ([Relay](https://docs.relay.link/references/api/api_core_concepts/fees.md), Doc). NEAR's "`fee` is split 50/50 with 1Click" ([fee configuration](https://docs.near-intents.org/integration/distribution-channels/1click-api/fee-config), Doc). deBridge's "Your integration automatically earns 25% of all points generated by your users." is the one documented default that pays on same-token flow with no user-visible line ([points](https://docs.debridge.com/home/monetization/debridge-points.md), Doc), and its USD value is unknown until a season closes. No aggregator statement on bridge rebates was found, and a private rebate would not be public.

**No dated evidence shows volume responding to a fee on bridge-only.** Dated changes exist (MetaMask 0.875% on bridges in February 2023, Bitget dynamic fees in November 2025, Uniswap to zero in December 2025, Ambire's vote in June 2026), and none has before-and-after volume or a partner reaction (Not found). Any elasticity estimate has to come from LI.FI's own data.

## No per-transfer free limit exists in what was checked; token tiers are common

**Free limit per transfer: Not found** at any aggregator, wallet or bridge protocol in the research, in documents or in quote sweeps. Socket's public 20 bps was $0.01 at $5 and $200 at $100,000; Rubic's 0.4% was $0.02 at $5 and $4,000 at $1M; LI.FI's default was 0.0025 at all four sizes (Quote). Absence covers public terms only.

**The size rules that exist work in the opposite direction from a free limit.** They set a floor, so small transfers pay proportionally more.

| Vendor | Rule | Label |
|---|---|---|
| XY yBridge | "If the trading volume multiplied by ***rate*** is less than the ***minimum***, then XY Finance will still charge the ***minimum*** as a basic commission." Maximum handled the same way | [Doc](https://docs.xy.finance/fee-structure/ybridge-fee-information). Figures such as a $15 Ethereum minimum and $1,000 maximum sit in a section marked "(Legacy)" ([docs](https://docs.xy.finance/llms-full.txt)); not used here |
| Hop | "minimum fee of \$0.25 per Hop transfer" | [Doc](https://docs.hop.exchange/basics/fees.md), undated |
| Chainflip | "\$0.5 USD minimum" | [Doc](https://docs.chainflip.io/protocol/how-swapping-works) |
| Synapse | "a percentage of the amount of tokens bridged, with a minimum fee amount." | [Forum proposal](https://forum.synapseprotocol.com/d/4-sip-03-min-bridge-fee-adjustments) |
| RocketX | "a dynamic fee starting from as small as $1 or 0.2% to 0.4%." | [Doc extracted](https://www.rocketx.exchange/blog/lowest-fee-cross-chain-swap-aggregator/) |
| KyberSwap Stop Market, not cross-chain | `feeRate = max( tierRate , minFee / orderValueAtTrigger )` | [Doc](https://docs.kyberswap.com/getting-started/fee-schedule.md) |
| Router Nitro partner fee | Minimum flat, bps, maximum flat | [Search excerpt](https://docs.routerprotocol.com/develop/asset-transfer-via-nitro/fee-management), page now 404 |

LayerSwap's quote moved from 10.25 bps at $1,000 to a flat $0.27 at $100,000, with its path changing to CCTPV2 alone. This is not documented as a tier, and the switch point was not tested. Across and Stargate limit by capacity, not price. Fee-free allowances that exist depend on holdings, not on transfer size: Ambire's top stake tier "grants fee-free swaps and bridges" ([Ambire](https://blog.ambire.com/reduce-swap-bridge-fees-proposal/), Doc extracted); RocketX "for FREE, without any charges, by HODLing $RVF" ([RocketX](https://www.rocketx.exchange/blog/lowest-fee-cross-chain-swap-aggregator/), Doc extracted). Enso offers integrators the design for their own fee: "A rule can optionally vary by trade size, using USD value ranges." with "a default fee, which applies when a trade's USD value can't be determined." ([Enso](https://docs.enso.build/pages/build/reference/fees.md), Doc extracted).

**Token and pair tiers are used in the market, with different boundaries.** Jumper splits stable, major and other at 0, 2 and 5 bps on bridges. KyberSwap gives same native token the stablecoin rate, 0.05%. Bitget's lowest cross-chain tier names USDT only. NEAR gives stablecoin pairs and same-asset routes 1 bp against 20 bps. Relay separates Token Bridge, Stablecoin Swap, Major Swap and Minor Swap. Mayan MCTP keys on USDC output. 1inch splits stablecoin and non-stablecoin on its Swap API. Velora's quotes key on same-token status regardless of asset. LI.FI's enterprise pricing states stablecoin flows "can carry a lower rate", and its status data shows Jumper's ETH rows paying where stablecoin rows do not. A LI.FI token tier has direct precedent; the definitions of "stable" and "major" are the design choice, and Jumper, KyberSwap and 1inch do not publish them (Not found).

**A free limit would interact with a concentrated base (Inference).** 309 transfers above $100,000 hold $145,463,135.63 of the $243,317,237.35 (query `84_revenue_sensitivity_to_fee_rate`, Named query), 59.8% by division. A free limit below that size gives up little USD, and places the fee on the transfers with the cheapest direct alternatives and on a few partners. Its effect on those partners' routing is not observable from public evidence.

## Not tested

**Not tested or not found.** Quote matrix across integrator strings and token pairs: the keyless limit (75 calls per 2 hours) returned 429 and no API key was used, so `integrator=jumper.exchange` on ETH to ETH, registered strings at notionals other than $10,000, `fee=0.01` with `Cow` or `_arbitrum`, named bridges under a zero-fee string and `/v1/advanced/routes` were not run. Direct quotes: only Ethereum to Arbitrum, only one moment. Comparison against live October contracts: not done. Who receives Jumper's 2 bps beyond the `lifiFee` field, and whether a LI.FI fee sits inside the Jumper fee: not stated. Rubic's and Socket's published source for 0.4% and 20 bps: not found. DefiLlama volume for Across, Relay, deBridge and Stargate: paywalled, so no take rates beyond NEAR Intents (5.48 bps) and Chainflip (5.56 bps), both all pairs (Secondary).

## Conclusion

The question is not whether to introduce a bridge-only fee but which zero-rate integrators LI.FI could reprice, at what rate and in which token class, since the default already charges 25 bps. The revenue base splits into at least three groups that behave differently: Jumper stablecoin flow under a published 0 bps, partner flow under unpublished terms with large transfers on near-free CCTP routes, and transfers that change token inside the bridge. The competitor evidence bears on the rate: same-token prices directly available are about 1 bp fast and near 0 on slow routes, integrators still charge end users 5 to 90 bps on same-token through LI.FI (Ad hoc), and no vendor has a free limit, so that element would be new to the market.

