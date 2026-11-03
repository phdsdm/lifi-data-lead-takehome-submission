# Task 3 — Where are we leaving money on the table?

> A memo to the CEO. Labels such as A2.2.1 refer to the tree in `task_3_appendix.md`. Figures read `<figure> (query <name>)`.

## 1. Data used and method

**Provided file.** 124,858 `LiFiTransferStarted` events from 13 to 19 October 2026 on six EVM source chains, with $307.74M of bridge volume (query `65_started_volume`). The file's own notes say it is a sample that doesn't cover every chain or contract event. USD values use the provided hourly prices, with CoinGecko filling 377 rows the feed didn't contain (query `33_rows_not_priced_by_provided_feed`).

**Fetched from LI.FI's API.** The provided file contains no fees, so we called `GET /v1/status` by transaction hash on selected transfers. Each response includes the quote's fee lines, which split the fee between LI.FI and the integrator.

| Fetch                 | Transfers | How selected                                                                                                                                 | Used for                                                        | Query                                                 |
| --------------------- | --------- | -------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------- | ----------------------------------------------------- |
| Uniform sample        | 2,000     | Random draw from the file                                                                                                                    | Overall rates and the 98.2% completion rate                     | `75_status_fee_overall`, `44_status_completion_rates` |
| Swap-route census     | 751       | Every transfer with a source step at $10k or more                                                                                            | Exact quoted fees on large transfers                            | `147_status_extension_census_fee_usd`                 |
| Integrator sample     | 4,165     | 30 per integrator with 100 or more source-step transfers, 10 with 10 to 99, and all of them below that | Each integrator's rate                                          | `143_status_extension_coverage_by_stratum`            |
| No-source-step census | 309       | Every transfer without a source step at $100k or more                                                                                        | Whether large transfers without a source step carry a LI.FI fee | `150_status_bridge_census_fee_usd_by_integrator`      |

**How revenue estimates are calculated.** Rate × the file's weekly volume × 98.2% completion × 52 weeks. Sizes apply to the file's coverage only: we did not scale up for missing chains or events, and volume is held fixed, with no reaction to a price change. We assume the quoted LI.FI fee is the fee charged. Transfers above the census limits are taken exactly, and those below use each integrator's own sampled rate. On this basis, LI.FI's baseline revenue is about $1.44M a year (query `158_fee_schedule_weekly_by_integrator`), which falls inside the uniform sample's interval (query `159_fee_schedule_check_against_uniform_2000`); weighting the uniform sample to the file instead gives $1.5M to $2.5M (query `83_revenue_model_weekly_lifi_fee`). We also show each idea as a percentage of $1.44M.

**Check against on-chain fees.** DefiLlama reads LI.FI's fee events on chain. For the same week, on the same six chains, bridges only and without Jumper, it shows $24,883 of LI.FI fee against our $25,283, and $134,463 of total fees against our $135,052 with Jumper (query `180_defillama_check_against_fee_schedule`). It also shows what our scope leaves out: across all chains and same-chain swaps, users paid about $13M a year in fees in 2026, of which LI.FI kept roughly $2.4M to $2.5M (same query, annualised from 2026 to date; the upper figure includes one unusually large day, and some of Jumper's fee may remain in both). Our sizes stay on the file's scope.

## 2. Current fee model & estimates 

-  An integrator may set its own fee; LI.FI takes a separate fee; some large integrators are on lower custom tiers; revenue is recognised on completed transfers only. Assumptions: 
	- **LI.FI's fee:** `feeSplit.lifiFee` on the quote's LIFI-named line. The integrator's fee is the other part of the same line (query `95_status_fee_line_kinds`).
	- **Quoted equals charged:** the status record's batch calls repeat the quoted amount on 221 of 221 transfers (query `97_status_fee_batch_vs_quote`). Collection is not observed transfer by transfer, but the weekly total matches on-chain fee events (see the check in section 1).
	- **Completion:** revenue = rate × volume × 98.2% completion (query `44_status_completion_rates`).
	- **Annualising:** We take the sample data of the provided week, and annualise it, annual = weekly × 52. Every size covers this file only: six EVM source chains and a sample of LI.FI's events. We did not consider any volume impact from fee changes at this stage.
	- **Tiers:** "default" (25 bps, on every `lifi-api` transfer and 67 integrator strings) and "custom tier" are readings of the observed rates. (query `76_status_lifi_fee_rate_distribution`).
- LI.FI earns about $1.44M a year on this file's coverage, about 0.9 bps of bridge volume (query `158_fee_schedule_weekly_by_integrator`).
- **About 88% of bridge volume carries no LI.FI fee in its quote or transaction** (query `161_volume_split_paying_by_route_kind`): 79.07% has no source step (query `84_revenue_sensitivity_to_fee_rate`) and 8.78% has one but pays nothing, and bridge-only volume paying nothing is 67.52% (query `161_volume_split_paying_by_route_kind`). None of the no-source-step transfers checked carries a LI.FI fee, 0 of 627 and 0 of 309 (queries `75_status_fee_overall`, `150_status_bridge_census_fee_usd_by_integrator`), though a LI.FI fee step would itself set the flag, so this group is free nearly by construction. Which integrators sit at zero is observable; whether LI.FI is paid another way is not.

## 3. Idea tree

A more complete breakdown of potential fee increase measures is in `task_3_appendix.md`, we ordered those ideas into a hierarchical structure. There we did not consider feasibility, only the size of each measure, to have a reference. Here we list the ideas that strike a balance between financial impact and feasibility.

All sizes are yearly increases on today's LI.FI fee, with volume held fixed. **They overlap and do not add.** Percentages are of today's $1.44M.

### Idea 1 (A2.2.1): a 25 bps floor on altcoin transfers

Transfers with a source step and an altcoin on either side pay LI.FI at least 25 bps. Without a source step there is no fee step to charge on, a further $2.6M a week (query `166_pair_class_fee_today_and_25bps_floor`). Stablecoin and blue-chip rates do not change.

- **Size:** about +$0.55M/year, on about $7.0M a week of altcoin volume (query `166_pair_class_fee_today_and_25bps_floor`).
- **Reasoning:**
  - On transfers with a source step, altcoin transfers already lose a median 104 bps to slippage and other costs, against 6 bps for blue-chip pairs and 2 bps for stablecoin pairs, at $100 to $10k (query `171_rates_and_loss_by_pair_class_and_size`).
  - On transfers with a source step, integrators already charge about 49 bps on altcoins against about 22 bps on other tokens under $10k, while LI.FI takes about 11 bps on altcoins and about 12 bps on stablecoin pairs (query `171_rates_and_loss_by_pair_class_and_size`).
  - `jumper.exchange`, `metamask-bridge` and `tangem` already pay different LI.FI rates by token, though only `jumper.exchange` sets altcoins above blue-chips (query `172_lifi_rate_by_pair_class_named_integrators`), and KyberSwap, NEAR Intents and Relay publish token tiers.
- **Risk:** about 65% of altcoin volume pays LI.FI under 10 bps currently (query `166_pair_class_fee_today_and_25bps_floor`), so discounted partners have to agree, and altcoin quotes get worse, risking lost volume.
- **Validation:**
	- *Rollout:* an experiment on Jumper first, assigning wallets at random between the increased altcoin floor and today's 5 bps (query `172_lifi_rate_by_pair_class_named_integrators`), and monitoring the impact on altcoin volume. Then a staged rollout by partner, with partners not yet switched as the comparison group, with difference-in-differences method to track impact on altcoin volume.  We could also increase gradually, for example a 10 bps floor before 25 bps.
	-  *Metric:* LI.FI fee in bps on altcoin transfers.
	- *Guardrails:* altcoin transfers and USD in each group, quote-to-execution conversion, completion rate, and partner churn. LI.FI's rate on these transfers more than doubles, from about 10 bps (query `166_pair_class_fee_today_and_25bps_floor`), so its income falls only if altcoin volume drops by more than about half.

### Idea 2 (A1.3.2): Current zero-rate partners pay on non-stablecoin pairs

`rabbykmsv2`, `bitget`, `Zerion` and `kyberswap` pay LI.FI nothing, and their fee line goes entirely to them (query `96_status_fee_line_lifi_share_by_kind`). They would stay free on stablecoin-to-stablecoin transfers and pay on the rest. `metamask-bridge` already shows this pattern: no LI.FI fee on 41 of 43 sampled stablecoin pairs and 5 bps on other pairs (query `172_lifi_rate_by_pair_class_named_integrators`).

- **Size:** +$19k per bp: +$0.1M at 5 bps and +$0.39M at 20 bps. `rabbykmsv2` alone is about $59k at 5 bps (query `165_zero_rate_partners_scenarios`).
- **Reasoning:** reversing a zero rate outright risks losing the partner. Keeping stablecoin pairs free keeps some advantage for the partner.
- **Risk:** Sensitive partner negotiation, the partner may leave or route elsewhere. There might be some other contractual compensation for the 0 LI.FI fee. 
- **Validation:**
	- *Rollout*: user price sensitivity could be tested on Jumper first, with A/B testing. 
	- *Metric:* LI.FI fee in bps on the partner's non-stablecoin volume.
	- *Design:* before/after at contract renewal, one partner at a time, compared with zero-rate partners not yet changed.
	- *Guardrails:* the partner's weekly volume and transfers against its trend, its own fee rate, and partner churn.

### Idea 3 (B1): a share of integrators' own fees

This reaches every integrator that sets a fee, including the four in idea 2. Instead of having 0 or very low LI.FI fees, while the integrator might set high bps fees, the proposal is to introduce a dynamic LI.FI fee based on the integrator's fee. In other words, LI.FI would keep a share of the fee each integrator sets. The size assumes the user's price does not change, as in the appendix. If an integrator raises its own fee to compensate, that is a user price increase and volume may respond. It can follow token-based fees, with lower fees on stablecoins and blue-chips and higher fees on altcoins.

- **Size:** the pool is about $5.5M a year. A 10% share gives about +$0.55M, or 38%, and 50% gives about +$2.7M (query `173_integrator_fee_pool_and_shares`).
- **Reasoning:** LI.FI already keeps 5% on `phantom` and `base-app` (query `96_status_fee_line_lifi_share_by_kind`), and Squid, Enso and NEAR Intents split integrator fees 50/50 by default (`docs/research/task3-bridge-only-fees.md`).
- **Risk:** partner income falls, or integrators raise their fee to compensate.
- **Validation:**
  - *Metric:* LI.FI's share of integrator fees, and the integrator's own fee rate.
  - *Design:* before/after at contract renewal, one partner at a time, starting at 5%, compared with partners whose terms did not change.
  - *Guardrails:* the partner's volume against its trend, its fee rate rising, quote-to-execution conversion, and partner churn.

### Bonus: Idea 4 (A2.1.3): stepped increases at multi-provider wallets

`phantom` and `metamask-bridge` choose a provider per quote, on their own public statements: Phantom picks the lowest-priced option by default, and MetaMask lists quotes for the user to compare (`docs/research/task2-market-landscape.md`). Treating them as the two multi-provider wallets is our judgement (query `140_persona_shares`). Raising LI.FI's rate by 1 bp at a time tests our price directly against competitors.

We mention it because it could be a great way to test price elasticity and the volume or routing impact of fee changes, measured directly against competitors. That would give a first read for the other price-changing ideas.

- **Size:** small, at about +$24k a year per bp, or 1.6% of today's revenue. At 25 bps it would be about +$0.49M (query `164_partner_integrators_paying_floor_and_band_median`). Its main value is measuring how volume responds to a fee.
- **Reasoning:** where a step reaches the user's price, the price is self-correcting: if LI.FI's rate is too high it loses quotes, and we can step back without a renegotiation. Going from 5 to 6 bps (query `164_partner_integrators_paying_floor_and_band_median`), LI.FI's income on that partner falls only if volume drops by more than about 17%.
- **Risk:** LI.FI's docs say enterprise pricing is agreed per integration, so a step may need the partner's agreement. At `metamask-bridge` the line pays LI.FI alone, so a step comes out of what the user receives. At `phantom` LI.FI's part is a share of Phantom's fee, so a step raises the user's price or cuts Phantom's income (query `96_status_fee_line_lifi_share_by_kind`).
- **Validation:**
	- *Rollout:* one partner steps up by 1 bp every few weeks, with the other partner as the comparison, stopping when the fall in win rate outweighs the fee gain. Such tests could be done on the Jumper app as well, but here we also see the direct effect of competition, which is hard to estimate otherwise.
	- *Metric:* LI.FI's quote win rate per partner, from LI.FI's quote logs, which the provided data does not include. Weekly volume is the backup.
	- *Guardrails:* the partner's weekly volume and transfers against its trend, and partner feedback.

### A must-mention (A1.1): a low fee on bridge-only volume that pays nothing

We add it here as the elephant in the room. Bridge-only means the same token across chains with no DEX step. About $208M of volume a week pays no LI.FI fee (query `161_volume_split_paying_by_route_kind`). Default callers already pay 25 bps, so this means repricing named integrators, at a low rate: among partners `_arbitrum`, `Pharos-Bridge` and `_binancewallet` are the largest at $100k and above (query `150_status_bridge_census_fee_usd_by_integrator`), and `jumper.exchange`, second largest at that size, publishes 0 bps on stablecoin bridges (`docs/research/task3-bridge-only-fees.md`), which this would reverse.

- **Size:** Without considering volume impact +$1.06M per bp, or 74% of today's revenue for each bp (query `161_volume_split_paying_by_route_kind`). This is the largest pool, but the volume with the cheapest direct alternatives.
- **Variation (A1.1.1):** charge only above a free limit per transfer: +$0.83M per bp above $10k, +$0.56M per bp above $100k (query `168_bridge_only_free_limit`). Small transfers stay free, but no aggregator, wallet or bridge we checked has such a limit.
- **Risk:** Very competitive, any fee change risking losing traffic. The rate has to stay near what direct routes cost. The cheapest direct fast bridges quoted about 1 bp and CCTP Standard routes 0 on USDC from Ethereum to Arbitrum (`docs/research/task3-bridge-only-fees.md`, quotes of 2026-11-02). The fee falls on large senders, who can have easy access to the cheapest alternatives. (query `169_senders_no_source_step_above_100k`). These partners may also pay LI.FI in ways we cannot see.

## 4. How the ideas compare

| Idea                        | Yearly increase              | Share of today's $1.44M | Who has to agree                               | Main risk                  | Reversible     |
| --------------------------- | ---------------------------- | ----------------------- | ---------------------------------------------- | -------------------------- | -------------- |
| 1. Altcoin floor            | About +$0.55M                | 38%                     | Discounted partners; none for a test on Jumper | Altcoin quotes get worse   | Yes            |
| 2. Zero-rate partners       | +$0.1M at 5 bps              | 7%                      | Four partners                                  | Losing a partner           | At renewal     |
| 3. Share of integrator fees | About +$0.55M at a 10% share | 38%                     | Each partner                                   | Partner income falls       | At renewal     |
| 4. Stepped increases        | About +$24k per bp           | 1.6% per bp             | Possibly the two partners                      | Quotes lost to competitors | Yes, step back |

**Overlaps:** ideas 2 and 3 overlap only on the four zero-rate partners, $0.85M of the $5.5M pool (query `158_fee_schedule_weekly_by_integrator`), so about $85k of idea 3 at a 10% share; one should be chosen for each of those. Ideas 1 and 4 both raise low-rate partners' altcoin volume. Idea 1 includes about $0.11M from volume paying nothing (query `166_pair_class_fee_today_and_25bps_floor`), of which about $51k is at the four partners (query `165_zero_rate_partners_scenarios`). `phantom` is in ideas 1, 3 and 4.

## 5. Where to start

**Start with idea 1, on Jumper.** It can run before any partner has to agree. Token-based rates already exist at three integrators, though only `jumper.exchange` sets altcoins above blue-chips (query `172_lifi_rate_by_pair_class_named_integrators`), it leaves stablecoin and blue-chip prices alone, and it can be reversed.

**Then ideas 2 and 3, at contract renewal.** Both need the partner's agreement, so they follow once idea 1 has given a first read on how volume responds.

**Bonus idea 4 as the testing environment, where partners' terms allow.** It earns little by itself, but it is the only idea that measures how volume responds to a fee against real competitors, and every size in this memo holds volume fixed. Its result would adjust idea 1's rollout to partners. It cannot show whether a partner would leave over ideas 2 or 3. A step can be reversed quickly.

## 6. What we would need to know

- Why the zero-rate integrators pay nothing, and whether LI.FI is paid some other way. Only LI.FI's fee configuration and contracts can settle this.
- How volume responds to a fee. The data has no fee change to observe, so every size holds volume fixed. Idea 4 is designed to measure it.
- Fees collected transfer by transfer, from LI.FI's ledger or `FeesForwarded` events, to replace quoted fees.
- Whether Jumper's fee stays LI.FI revenue. A paid press release says Jumper is planned to be carved out as a standalone venture.
