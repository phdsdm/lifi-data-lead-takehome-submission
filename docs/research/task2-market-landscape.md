# Partner analytics: competitors, churn evidence, analogues, governance

AI-assisted desk research for Task 2 (partner-facing data product). Every URL below was accessed on **2026-10-28**. "(inference)" marks conclusions drawn from the sources and not stated in them. Stripe pages were served in Swiss German with prices in CHF because of geolocation. I could not retrieve the USD prices.

## Findings that bear directly on Task 2

1. **LI.FI already publishes partner transfer data without authentication.** `GET https://li.quest/v2/analytics/transfers` takes an `integrator` filter and returns, per transfer: status and substatus, tool, both legs' amounts, USD values and timestamps, fee lines, and sender and receiver addresses. A test call with `integrator=jumper.exchange` and no API key returned HTTP 200 with that data. Docs: https://docs.li.fi/api-reference/get-a-paginated-list-of-filtered-transfers. The API overview says "All LI.FI APIs do not require API key. API key is only needed for higher rate limits" (https://docs.li.fi/api-reference/introduction). This has four consequences (inference):
   - Raw programmatic access to a partner's own transfers cannot be the premium tier.
   - This API is a further external surface whose numbers must agree with Omni.
   - The status-joined transfer record already exists in a backend service.
   - Anyone can pull any integrator's transfers by its string, so the defensible asset is the processing (pricing, definitions, benchmarks, health), not the raw data.
2. **The LI.FI documentation does not mention status webhooks.** A search of https://docs.li.fi/llms-full.txt for "webhook" returned no matches, and https://docs.li.fi/llms.txt tells integrators to poll `/status` every 10–30 seconds. Relay offers self-serve webhooks.
3. **Large wallets now choose a provider for each quote.** Phantom's cross-chain swapper was "powered by Li.Fi" in November 2023. Phantom now compares LI.FI, Relay, deBridge and Garden and "picks the lowest-priced option" by default. MetaMask now sources quotes from LI.FI and Socket plus nine direct providers. LI.FI's share at these partners is decided quote by quote (sources in section 4).
4. **No competitor offers what LI.FI is best placed to show.** I found no competitor that shows peer benchmarks, per-tool outcome quality or contractual SLA reporting to integrators. The strongest operational view is Relay's, the strongest business view is 0x's, and the strongest API observability is 1inch's (section 3).

---

## 1. New product ideas, ranked by fit

Ideas beyond the base features of a partner analytics product. Section 2 lists evidence on those base features: benchmarks with k-anonymity, warehouse extract, custom alerts and webhooks on aggregate thresholds, cohorts, the resilience panel, breadth, outcome quality, fee revenue, route flows, the freshness banner, restatement, reconciliation and RLS.

| Rank | Idea | Churn reason addressed | Free or premium |
|---|---|---|---|
| 1 | Quote funnel and quote conversion | Evaluating a competitor | Free; per-route detail premium |
| 2 | Unserved-demand log (no-route and error requests) | Both | Free |
| 3 | Transfer-status webhooks with a delivery log | Building in-house; competitor parity | Free |
| 4 | Tool and chain health page with incident impact | Building in-house; competitor | Free |
| 5 | API observability (requests, errors, latency, quota) | Evaluating a competitor (parity) | Basic free; longer retention premium |
| 6 | Fee rules in the portal with an outcome view | Building in-house | Configuration free; analysis premium |
| 7 | LI.FI fee statement for Dynamic Pricing partners | Evaluating a competitor | Free |
| 8 | Approval-exposure report | Evaluating a competitor (security) | Free |

**1. Quote funnel and quote conversion.**
- **What it is:** for each partner and route, the chain from quote requests to quotes returned, transfers started on-chain and transfers completed, cut by amount band. "Quote-to-start conversion" could replace active users as one of the 4–6 core metrics (inference).
- **Evidence:**
  - Phantom and MetaMask rank providers per quote (section 4).
  - Uniswap Labs lists "Quote volume, swap volume, fill rates" as its next dashboard analytics (https://blog.uniswap.org/uniswap-developer-platform-is-live, 16 Apr 2026).
  - Relay's dashboard keeps the "full history of quotes and intents" with status, route, amounts and timing (https://docs.relay.link/references/api/api-keys.md).
  - Plaid sells the step-by-step Link funnel only in Premium Link Analytics (https://plaid.com/docs/link/measuring-conversion/index.html.md).
  - Rango gives integrators an endpoint to report client-side failures ("the user rejects the transaction in the wallet or the wallet fails"). This covers the step between quote and on-chain start (https://docs.rango.exchange/api-integration/main-api-multi-step/api-reference/report-transaction-failure.md).
- **Main risk:** a quote that was never executed may be user abandonment rather than a quote lost to a competitor, so a "win rate" overstates losses. The funnel needs a quote id that travels from the quote log to the on-chain transfer. It also shows partners where LI.FI is uncompetitive.

**2. Unserved-demand log.**
- **What it is:** quote requests that returned no route or an error, broken down by reason, chain pair and token, with the USD amount requested.
- **Evidence:**
  - 1inch Observability breaks requests and error rate down by product, app and response code (https://business.1inch.com/whats-new/introducing-observability).
  - Relay's usage API groups calls "by API key, endpoint, status code, and error code" (https://docs.relay.link/references/api/get-usage.md).
  - Across says integrator IDs let it "monitor for anomalies… and alert you" (https://docs.across.to/llms-full.txt, FAQ on API keys).
- **Why it helps on both churn reasons:** it shows the coverage gaps a side-by-side test would find, and it shows how many chains and tokens an in-house build would need (inference).
- **Main risk:** requested USD must never be added to volume, and malformed requests can dominate the log. It hands partners a list of LI.FI's coverage gaps.

**3. Transfer-status webhooks with a delivery log.**
- **What it is:** each status change (pending, done, partial, refunded, failed) is pushed to the partner's endpoint, and the portal shows a log of the deliveries.
- **Evidence:** Relay webhooks are self-serve per App, with statuses waiting, depositing, pending, submitted, success, failure and refund; "Only `success` and `refund` are final" (https://docs.relay.link/references/api/api_guides/webhooks.md). LI.FI asks integrators to poll (finding 2).
- **Why it helps against in-house builds:** status tracking across every bridge is part of what an in-house team would have to rebuild (inference).
- **Main risk:** it is a product-engineering build with delivery guarantees. The webhook status must be the same field the portal counts, or the two will disagree.

**4. Tool and chain health page with incident impact.**
- **What it is:** for each tool and each chain, the success rate, refund rate and median completion time over 24 hours and 14 days across all LI.FI traffic. It lists open incidents, shows for each incident how many of the partner's own transfers are affected, and offers a "follow" option and a webhook alert.
- **Evidence:**
  - Plaid's Institutions page shows two weeks of success rates per institution and lists known issues with a "Follow" button. It shows the number of your Items an error affects and offers alerts by webhook (`INSTITUTION_STATUS_ALERT_TRIGGERED`) (https://plaid.com/docs/account/activity/index.html.md).
  - Relay's status page lists 63 chains as components but shows uptime only for its API (https://status.relay.link/).
  - Socket's status page lists 4 API components (https://status.socket.tech/).
  - LI.FI's status page runs on UptimeRobot, and its components failed to load (https://status.li.fi/).
- **Main risk:** publishing bridge failure rates strains relations with bridge providers. The page needs Kafka-latency data. A page that is often red can push partners away.

**5. API observability.**
- **What it is:** requests, error rate, latency and rate-limit consumption per API key, plus a request log searchable by transaction hash or request id.
- **Evidence:**
  - 1inch has four tabs (Overview, Logs, Swaps, Usage) with a 10–30-second refresh (https://business.1inch.com/whats-new/introducing-observability). Its retention is at least 30 days on paid plans, up to 90 days on higher tiers and 180 days on Enterprise (https://help.1inch.com/en/articles/12398075-pricing-and-subscriptions-faq).
  - Relay's dashboard has AND/OR filters, saved views and request-id search.
  - Jupiter's portal analytics "Track traffic, performance, and cost" (https://developers.jup.ag/docs/portal/setup.md).
  - Infura shows request stats per key from 15 minutes to 30 days (https://docs.metamask.io/developer-tools/dashboard/how-to/dashboard-stats/).
- **Main risk:** the data sits in Prometheus and Loki, not dbt, so this is a second pipeline outside the Omni reconciliation. Logs can contain wallet addresses.

**6. Fee rules in the portal with an outcome view.**
- **What it is:** the partner sets fee rules by chain, token, token pair and trade size. The portal then shows the fee rate actually earned and quote conversion by fee band.
- **Evidence:** Enso's developer portal Fees tab supports rule scopes (all trades, chain, token, pair), USD size ranges and a split calculator, and "Changes apply to newly quoted transactions, typically within about a minute" (https://docs.enso.build/pages/build/reference/fees.md). Mayan lets referrers set their fee on its explorer (https://docs.mayan.finance/integration/referral.md). Wallets charge 0.85% (Phantom) and 0.875% (MetaMask) (section 4), so fee revenue is a motive to own the routing layer (inference).
- **Main risk:** it nudges partners towards higher fees, which gives their users worse prices and loses quote comparisons. The link between fee level and conversion is confounded.

**7. LI.FI fee statement for Dynamic Pricing partners.**
- **What it is:** a monthly statement of the LI.FI fee charged, by route type, token type and size band, reconciled to the fee events.
- **Evidence:** under Dynamic Pricing, LI.FI resolves its rate per quote from the amount, the tokens and the chain pair. "The exact weighting is part of your commercial terms and is not published" (https://docs.li.fi/enterprise/dynamic-pricing). Stripe exposes itemised fee tables (`itemized_fees`, `icplus_fees`) to its users (https://docs.stripe.com/stripe-data/data-freshness).
- **Main risk:** it invites renegotiation, and a partner can pass the statement to a competitor. It needs sales sign-off.

**8. Approval-exposure report.**
- **What it is:** a count of the partner's users with unlimited token approvals to LI.FI contracts, and the USD amount exposed, with a prompt to revoke them.
- **Evidence:** the July 2024 exploit took $11.6M from 153 wallets, and "the vulnerability was limited to infinite approvals" (https://li.fi/knowledge-hub/incident-report-16th-july).
- **Main risk:** it reminds partners of the incident. It needs approval indexing on every chain and uses wallet-level data. The data is limited to approvals to LI.FI's own contracts.

---

## 2. Evidence on base features

- **Programmatic access as a premium feature.** Finding 1 argues against it. deBridge's referral statistics API (users, fulfilled orders, volume USD, fees USD) is public (https://docs.debridge.com/api-reference/referralprogram/returns-referral-statistics-for-given-referral-code.md). Saleable layers are warehouse delivery, benchmarks and longer retention (inference).
- **Benchmark parameters.**
  - Stripe Billing builds peer groups of "at least 100 similar businesses". Each peer must have at least 100 active subscriptions, and a business needs at least 5 active subscriptions to see benchmarks. Stripe shows the percentile plus high, median and low trends (https://docs.stripe.com/billing/subscriptions/analytics/benchmarking).
  - GA4 requires the "Modeling contributions & business insights" setting to be on: a business only sees benchmarks if it contributes data. GA4 shows the 25th, 50th and 75th percentiles, refreshes every 24 hours and requires "a minimum number of properties" (https://support.google.com/analytics/answer/13771577?hl=en).
  - Amplitude excludes customers who opted out and marks cells "unavailable" when the sample is too small (https://amplitude.com/benchmarks/professional-services/enterprise).
  - Plaid-wide benchmarks are sold only inside Premium Link Analytics.
  - The top 20 integrator strings carry 84.8% of rows, so a count rule (k partners per cell) is not enough. One dominant partner can be inferred from a route aggregate, which calls for an (n,k) dominance rule or a p-percent rule (inference). Both rules are defined in FCSM Statistical Policy Working Paper 22 (https://webarchive.library.unt.edu/web/20120915082757/http://www.fcsm.gov/working-papers/SPWP22_rev_ch3.pdf).
- **Warehouse delivery.**
  - Snowflake Secure Data Sharing copies no data and is live. The consumer pays for query compute. Reader accounts serve partners who have no Snowflake account, and the provider owns and pays for them. A direct share works only within one region (https://docs.snowflake.com/en/user-guide/data-sharing-intro).
  - Stripe Data Pipeline "sends a data share". Data is available within 12 hours of accepting the share, and a full load arrives every 3 hours (https://docs.stripe.com/stripe-data/access-data-in-warehouse). It is a paid product priced by payment volume: CHF 53/month for 1,000 payments, up to CHF 451 for 25,000, with Sigma included (https://stripe.com/data-pipeline/pricing).
- **History length as a tier lever.** Twilio Voice Insights is free with 7 days of history; Advanced Features give 30 days, the API and event streams from $0.0024/min (https://www.twilio.com/en-us/voice/insights). 1inch retains 30, 90 or 180 days depending on plan. 0x shows 12 months. LI.FI's portal shows one month or 100K transactions.
- **Provisional window.** 0x adds trades about every 15 minutes, and data is "only considered final 48 hours after the trade is completed" (https://docs.0x.org/evm/trade-analytics-api/introduction). GA4: "During that time [24–48 hours], data in your reports may change"; attribution can change for up to 12 days (https://support.google.com/analytics/answer/11198161?hl=en). These are precedents for marking the latest hours as provisional.
- **Fee payout explanation.** Mayan's referrer dashboard "shows what has been paid out and why any balance is not being paid out" (https://docs.mayan.finance/integration/referral.md). Relay exposes a balance-event history covering fee credits and withdrawals (https://docs.relay.link/references/api/get-balance-events.md). Both are models for reconciling reported fees to withdrawable balances.

---

## 3. Competitor and adjacent offerings

| Vendor | What integrators see | Surface | Price | Source |
|---|---|---|---|---|
| LI.FI (baseline) | Portal tiles. Transfer API with status, fees, legs (public). Fee-balance and withdrawal API. Fees dashboard added June 2026; token-level withdrawal March 2026; multi-user accounts October 2025; MFA and SSO | UI, API | Free | https://docs.li.fi/changelog/partner-portal ; https://docs.li.fi/changelog/monthly-updates ; https://docs.li.fi/api-reference/get-integrators-collected-fees-data-for-all-supported-chains |
| Socket / Bungee | Affiliate ID header for attribution; status endpoint; status page with 4 API components and uptime. No dashboard found | API, status page | "Free to use for third-party integrators" | https://docs.bungee.exchange/integrate/get-api-access ; https://status.socket.tech/ |
| Squid | Integrator ID by application form; route-status API; "Squid splits all fees collected by integrators 50/50". No dashboard found; status.squidrouter.com returned HTTP 526 | API | 50/50 fee split | https://docs.squidrouter.com/llms-full.txt |
| Rango | Affiliate page to "monitor their activities and earnings"; "detailed APIs" for dApps; a dashboard is promised for the "next version"; failure-report endpoint | UI, API | Rango adds 15 bps | https://docs.rango.exchange/api-integration/rango-affiliate-program |
| deBridge | Referral code gives order tracking and "Analytics: Monitor volume, fees, and user activity". Stats API with users, fulfilled orders, volume and fees; auto-cancellation of unprofitable orders after 5 minutes. Affiliate fee up to 10% | API, app page | Free | https://docs.debridge.com/home/monetization/referral-codes.md ; https://docs.debridge.com/home/monetization/affiliate-fees.md |
| Relay | Dashboard: request history (quotes and intents) with status, route, amounts and timing; AND/OR filters; saved views; per-App webhooks; usage API by status and error code. App fees accrue as a USDC balance, with balance and event APIs. Status page with 63 chains | UI, API, webhook | Self-serve; no charge found | https://docs.relay.link/references/api/api-keys.md ; https://docs.relay.link/features/app-fees.md |
| Across | API key and integrator ID required in production, "so we can provide you with analytics and support" and "monitor for anomalies". Deposit-status API. No self-serve dashboard found | API; analytics from the Across team | Not stated | https://docs.across.to/llms-full.txt |
| 0x | Trade Analytics in the dashboard: volume, trade count, users, trade size and revenue for 12 months, filtered by app, API, chain and time. API includes fees, gas and slippage; updated about every 15 minutes; final after 48 hours. Marketed for "new vs. returning users" and "whale trader alerts" | UI, API | Standard $1,000 and Enterprise $2,500 (billing period not shown). The Standard column marks realtime analytics unavailable. 0.15% fee on select pairs. "Uptime… is not a service guarantee" | https://0x.org/pricing ; https://0x.org/post/introducing-0x-trade-analytics |
| 1inch | Observability: requests, RPS and error rate by product, app and response code; request logs; on-chain USD swap volume (Classic, Intent, Cross-chain); quota usage with projection | UI | Business plans; retention 30/90/180 days | https://business.1inch.com/whats-new/introducing-observability |
| Jupiter | Portal analytics for "traffic, performance, and cost"; referral dashboard to manage referral accounts. "Jupiter takes 20% of your integrator fee" | UI | $0 / $25 / $100 / $500 per month (rate-limit tiers) | https://developers.jup.ag/docs/portal/setup.md ; https://developers.jup.ag/docs/swap/fees |
| KyberSwap | Optional `x-client-id` header sets the rate-limit tier. No dashboard found | API | Not stated | https://docs.kyberswap.com/developer-guide/start-here/rate-limits-and-client-id |
| Enso | Portal Fees tab (rules, split, calculator). Usage tracking is left to the integrator via on-chain `ShortcutExecuted` events | UI, on-chain | 50/50 fee split by default | https://docs.enso.build/pages/build/examples/request-referral.md |
| Uniswap Labs | Portal with API keys; analytics listed as the next feature. "The API is free" | UI (planned) | Free | https://blog.uniswap.org/uniswap-developer-platform-is-live |
| Rubic | `referrer` parameter "helps us track the origin of API calls"; tiers of 10 RPM, 400 RPM or custom. No dashboard found | API | Not stated | https://docs.rubic.finance/api-docs/about/referrer.md |
| Chainflip | Broker fee of 0–1000 bps "credited to the broker's account", withdrawn via the CLI. The explorer has a brokers page that could not be read by fetch. No broker dashboard documented | CLI, explorer | Not stated | https://docs.chainflip.io/brokers ; https://scan.chainflip.io/brokers |
| Wormhole / Mayan | Mayan referrer dashboard: balances across chains, split share, payouts and the reasons a balance is not paid. Weekly automatic payout. Wormholescan has public protocol analytics. Nothing per integrator found for Wormhole Connect | UI | Not stated | https://docs.mayan.finance/integration/referral.md ; https://wormhole.com/blog/wormholescan-upgrade-real-time-data-analytics-for-the-wormhole-ecosystem |
| NEAR Intents | Partner Dashboard issues the JWT. Explorer API "for distribution channels… building dashboards", filtered by chain, token, time and status, at 1 request per 5 seconds | API | Fee split 50/50; 25 bps without a key | https://docs.near-intents.org/integration/distribution-channels/1click-api/explorer/introduction ; https://docs.near-intents.org/integration/distribution-channels/1click-api/fee-config |

---

## 4. Why integrators leave an aggregator or build in-house

| Integrator | What changed | Driver stated or inferred | Source |
|---|---|---|---|
| Phantom | November 2023: cross-chain swapper "powered by Li.Fi". Now: LI.FI, Relay, deBridge and Garden; the engine "picks the lowest-priced option" by default; users can choose the provider; Phantom fee 0.85% | Price per quote (stated). Coverage (inference) | https://phantom.com/learn/blog/cross-chain-swapper ; https://help.phantom.com/articles/understand-cross-chain-swaps-in-phantom-51384804802195 |
| MetaMask | October 2023: bridging via Socket and LI.FI. Now: Li.fi and Socket plus Hop, Celer, Polygon PoS, Squid, Across, Stargate, Relay, Mayan and CCTP. MetaMask will "pull together quotes so you can find the most advantageous one"; fee 0.875% | Price comparison (stated). Direct integrations reduce dependence on aggregators (inference) | https://www.theblock.co/post/259803/metamask-adds-support-for-base-zksync-linea-on-bridge-service-with-socket-and-li-fi-aggregators ; https://support.metamask.io/trade/swap/user-guide-swaps/ |
| Uniswap Labs | October 2024: integrated Across directly. June 2026: cross-chain swaps "using Across and the Uniswap Protocol", with no aggregator | Speed ("L2-to-L2 transfers in just 3 seconds" under $10,000) and removal of reorg and lock-and-mint risk | https://across.to/blog/Uniswap-Labs-Integrates-Across-for-In-App-Bridging ; https://blog.uniswap.org/in-app-wallet-and-more-UX-improvements |
| OKX | Own aggregator that "searches and lists all available bridges", sold as the OKX DEX API; added deBridge in June 2024 | Owns and resells the routing layer (inference) | https://debridge.finance/blog/bringing-high-speed-bridging-to-okx-dex-and-okx-wallet ; https://www.fintechfutures.com/press-releases/flash-news-okx-dex-optimizes-cross-chain-algorithm-to-provide-best-pricing-transactions |
| SafePal | "Built its own swap meta-aggregator and wired in multiple sources" | Reliability over best quote ("a 0.2% better quote that fails 10% of the time"); support tickets per 1,000 swaps; fee transparency; control of the UX; latency; coverage. Sponsored article (SimpleSwap) | https://crypto.news/how-the-crypto-wallet-swap-provider-landscape-has-evolved/ |
| All LI.FI partners | July 2024 exploit: $11.6M taken from 153 wallets | Security, a likely evaluation criterion (inference) | https://li.fi/knowledge-hub/incident-report-16th-july |

**How strong the evidence is for each driver:**
- **Price per quote:** strong, from primary sources (Phantom, MetaMask).
- **Speed and settlement model:** stated by Across for Uniswap.
- **Owning the routing layer and its revenue:** inferred (OKX; wallet fees of 0.85–0.875%).
- **Reliability and support load:** only the sponsored article.
- **Revenue share:** visible in competitors' terms (Squid, NEAR Intents and Enso split 50/50; Jupiter keeps 20%; Rango adds 15 bps). I found no public case of a partner leaving over revenue share.

**Not found:**
- Any primary-source statement by a partner that it left LI.FI or built in-house, or that cites data or reporting as a reason.
- Primary-source evidence of provider changes at Rabby, Coinbase / Base App or Binance Wallet. LI.FI's own page says Rabby integrated LI.FI for bridging (https://li.fi/knowledge-hub/rabby-wallet-integrates-li-fi-to-power-bridge-feature). Coinbase's CDP Swap API is built on 0x (https://0x.org/case-studies/coinbase/developer-platform/); this is a developer product, not shown to be the Base App's engine.

**What this means for a partner product (inference):** at multi-provider wallets LI.FI is not replaced outright. It competes on every quote. The data that keeps those partners is quote competitiveness and outcome quality per route, which are the measures the wallet uses to rank providers.

---

## 5. Analogous B2B partner analytics and how they are monetised

| Vendor | What is shown | Free vs paid | Public price | Source |
|---|---|---|---|---|
| Stripe Sigma | SQL and AI reports, scheduled email, CSV, reports published in the Dashboard | Paid; included with Data Pipeline | CHF 12/month (250 payments) to CHF 369/month (25,000) | https://stripe.com/sigma/pricing |
| Stripe Data Pipeline | Data share to Snowflake, Redshift, Databricks or BigQuery, or Parquet files to S3, GCS or Azure; full refresh every 3 hours | Paid | CHF 53 to 451 per month by volume | https://stripe.com/data-pipeline/pricing |
| Stripe Billing benchmarks | Seven subscription metrics over 12 months; percentile against a group of at least 100 similar businesses | Price not stated | n/a | https://docs.stripe.com/billing/subscriptions/analytics/benchmarking |
| Plaid | Standard Link analytics free. Premium Link Analytics (funnel steps, segments, Plaid-wide benchmarks) requires a Premium Support Package. Institution health with alert webhooks; 14 days of logs | Mixed | Not public | https://plaid.com/docs/link/measuring-conversion/index.html.md ; https://plaid.com/docs/account/activity/index.html.md |
| Twilio Voice Insights | Free dashboards with 7 days of history. Advanced Features: 30 days, metrics and events API, event streams | Paid tier | From $0.0024/min | https://www.twilio.com/en-us/voice/insights |
| Shopify Partners | App installs, uninstalls and earnings (net of revenue share); CSV export of merchants, earnings and history | Free | n/a | https://shopify.dev/docs/apps/launch/distribution/track-app-usage.md |
| Alchemy / Infura / QuickNode | Alchemy: request history and usage charts; webhooks at "0.04 Compute Units" per byte (about 40 per event). Infura: request stats per key. QuickNode Streams: delivery to webhook, S3, Postgres or Snowflake | Usage-based | CU-based | https://support.alchemy.com/articles/1890990699-how-are-webhooks-priced ; https://www.quicknode.com/blog/introducing-streams-by-quicknode |
| Amplitude Benchmarks | Anonymised data from more than 2,600 companies; opt-out | Not stated | n/a | https://amplitude.com/benchmarks/professional-services/enterprise |
| GA4 benchmarking | Peer percentiles; reciprocal (only data contributors see benchmarks) | Free | n/a | https://support.google.com/analytics/answer/13771577?hl=en |
| Gr4vy / Primer (payments orchestration) | Processor performance. Gr4vy alerts on "spikes in decline rates, latency issues, or settlement delays" by email or webhook. Primer monitors thresholds such as authorisation rate below 90% | Not stated | n/a | https://gr4vy.com/analytics/ ; https://primer.io/blog/how-monitors-and-alerts-help-merchants-react-in-real-time-to-changes-in-payments |
| Adyen RevenueAccelerate / benchmarking | No primary documentation or pricing found | n/a | n/a | n/a |

**Patterns:**
- A customer's own summary numbers are free. Paid tiers add depth: funnel steps, longer history, API and event streams, SQL access and warehouse sync.
- Benchmarks are free when the customer contributes data (GA4), bundled into a premium support package (Plaid), or unpriced (Stripe).
- Stripe sells warehouse delivery as a paid add-on priced by volume.
- Stripe is the only vendor that publishes a minimum peer count (100). The others say they enforce minimums but do not give a number.
- Alerting on a provider's success rate exists as Plaid's institution webhooks and the payment orchestrators' threshold monitors.
- I found no SLA reporting at any vendor. 0x publishes a historical uptime of 99.92% and says it "is not a service guarantee".

---

## 6. Governance practice for external numbers

- **Definitions that explain why two numbers differ:** Shopify states why the Partner Dashboard and Dev Dashboard install counts diverge (only active stores are counted) and that earnings are net of revenue share (https://shopify.dev/docs/apps/launch/distribution/track-app-usage.md). Plaid states that its success rate combines Plaid, institution and user errors (https://plaid.com/docs/account/activity/index.html.md).
- **Freshness made visible:**
  - Stripe publishes freshness per table: 3 hours for API data, 24–120 hours for derived tables. The Dashboard shows the last update time, and queries can read `data_load_time` (https://docs.stripe.com/stripe-data/data-freshness).
  - Stripe's Report Type object carries `data_available_end` and a `version`; "Different versions… may take different run parameters or have different result schemas" (https://docs.stripe.com/api/reporting/report_type/object).
  - 1inch refreshes in 10–30 seconds. 0x refreshes about every 15 minutes and treats data as final after 48 hours.
- **Restatement:** 0x's 48-hour finality and GA4's "may change" statement (section 2). I found no vendor with a written restatement policy beyond these.
- **Status pages:** Relay lists components per chain; Socket lists them per API; LI.FI's UptimeRobot page did not load its components.
- **Minimum cohorts:**
  - Stripe uses at least 100 peers; GA4 says it requires a minimum number of properties; Amplitude marks small cells "unavailable".
  - Snowflake aggregation policies enforce a minimum group size. Small groups are merged into a NULL "remainder group". The feature requires Enterprise Edition and does not "guarantee protection against determined users" (https://docs.snowflake.com/en/user-guide/aggregation-policies).
  - The dominance and p-percent rules are defined in FCSM SPWP22 (link in section 2).
- **Embedded BI with row-level security (Apache Superset):**
  - `EMBEDDED_SUPERSET` must be `True`. The guest token is minted server-side by a service account; the caller needs `can_grant_guest_token`.
  - "Pass `rls` rules in the guest token request to restrict which rows are visible".
  - Token lifetime is set by `GUEST_TOKEN_JWT_EXP_SECONDS`, default 5 minutes.
  - Allowed Domains is set per dashboard, and "an empty list allows any origin".
  - "Semantic views cannot enforce guest-token SQL clauses."
  - Sources: https://superset.apache.org/user-docs/using-superset/embedding ; https://npmjs.com/package/@superset-ui/embedded-sdk
  - Implication (inference): partner datasets must be SQL datasets filtered by the partner id, not semantic views. The public analytics API and the status webhooks need to go into the same reconciliation as Superset and Omni.

## Not found or not covered

- An integrator dashboard at Socket/Bungee, Squid, KyberSwap, Rubic or Wormhole Connect.
- The contents of Chainflip's brokers page (it did not render through fetch).
- Adyen benchmarking and its pricing.
- The 1inch plan prices.
- Stripe prices in USD.
- Infura error-rate reporting.
- Primary-source statements from partners about leaving LI.FI.
