"""The figures task_2.md cites, pinned on the named queries.

Each pin reads one cell of one query's output, at the query's own precision; the documents round them.

A pin that fails means a cited figure moved. The answer is to find out why, not to update the number here. Without the CSVs every test here skips (conftest.py).
"""

from __future__ import annotations

import pandas as pd
import pytest

from figure_pins import cell, d1, d2, d4, pin, row_of

Q13 = "13_status_time_to_completion_by_bridge"
Q23 = "23_integrator_rows_senders_usd"
Q28 = "28_usd_concentration"
Q44 = "44_status_completion_rates"
Q46 = "46_receiver_sentinel_by_destination"
Q65 = "65_started_volume"
Q67 = "67_started_volume_by_partner"
Q68 = "68_partner_concentration"
Q123 = "123_partner_completion_rate"
Q124 = "124_partner_time_to_completion"
Q125 = "125_partner_net_cost_to_user"
Q127 = "127_benchmark_routes"
Q131 = "131_relayer_rule_market"
Q140 = "140_persona_shares"
Q152 = "152_partner_users_receiver_default"
Q153 = "153_receiver_rule_shared_and_bulk_checks"
Q154 = "154_partner_weekly_users_by_volume_band"
Q155 = "155_coverage_status_summary"
Q156 = "156_coverage_status_not_operational_windows"
Q157 = "157_near_share_of_bridge_rows_by_day"

PARTNERS = ("base-app", "phantom", "metamask-bridge")
POOLED = "pooled_2600"
LOW_BAND, HIGH_BAND = "$0–$100", "above $10k"
ALL_VALUES = "(all values)"

# --- §4.1 bridge volume ------------------------------------------------------------------------------

VOLUME_PINS = [
    *pin(Q65, {"line": "bridge volume: without the same-chain *Dex rows"}, usd=d2(307_741_849.38), n_rows=124_563),
    *pin(Q65, {"line": "same-chain *Dex rows, reported separately"}, usd=d2(227_509.22), n_rows=295),
    *pin(Q154, {"partner": "base-app", "band": HIGH_BAND}, usd_total=d2(708_467.56)),
    *pin(Q154, {"partner": "phantom", "band": HIGH_BAND}, usd_total=d2(3_081_104.41)),
    *pin(Q154, {"partner": "metamask-bridge", "band": HIGH_BAND}, usd_total=d2(3_060_937.31)),
]

# --- §4.2 completion and §4.3 time to completion ----------------------------------------------------

STATUS_PINS = [
    *pin(Q44, {"sample_design": "uniform_2000", "chain": "(all chains)"}, pct_completed=d2(98.2), pct_refunded=d2(1.5), pct_partial=d2(0.3)),
    *pin(Q123, {"partner": "base-app", "sample": POOLED}, pct_completed=d2(96.26)),
    *pin(Q123, {"partner": "phantom", "sample": POOLED}, pct_completed=d2(98.21)),
    *pin(Q123, {"partner": "metamask-bridge", "sample": POOLED}, pct_completed=d2(98.20)),
    *pin(
        Q13,
        {"bridge": "(all bridges)"},
        all_completed=2_557,
        all_median_s=d1(3.0),
        all_p90_s=d1(38.0),
        all_receiving_before_sending=105,
        all_max_s=2_880,  # the longest completion, 48 minutes
    ),
    *pin(Q13, {"bridge": "across"}, all_receiving_before_sending=75),
    # Per partner, median/p90: 6/23, 4/29, 2.5/13.
    *pin(Q124, {"section": "partner", "partner": "base-app", "sample": POOLED, "tool": "(all tools)"}, median_s=d1(6.0), p90_s=d1(23.2)),
    *pin(Q124, {"section": "partner", "partner": "phantom", "sample": POOLED, "tool": "(all tools)"}, median_s=d1(4.0), p90_s=d1(29.0)),
    *pin(Q124, {"section": "partner", "partner": "metamask-bridge", "sample": POOLED, "tool": "(all tools)"}, median_s=d1(2.5), p90_s=d1(12.7)),
]

# By tool, median/p90 as §4.3 lists them: 1/10, 2/10, 9/27, 35/112, 1,153/1,403.
TOOL_TIME_TABLE = [
    ("relaydepository", 1.0, 10.0),
    ("across", 2.0, 10.0),
    ("mayan", 9.0, 27.3),
    ("near", 35.0, 112.0),
    ("polymerStandard", 1_153.0, 1_402.6),
]
for tool, median, p90 in TOOL_TIME_TABLE:
    STATUS_PINS += pin(Q13, {"bridge": tool}, all_median_s=d1(median), all_p90_s=d1(p90))

# --- §4.4 users, with §2.3's figure of metamask-bridge --------------------------------------------

USER_PINS = [
    *pin(Q154, {"partner": "base-app", "band": HIGH_BAND}, users_total=2_569, pct_users=d2(0.35), pct_usd=d2(42.27)),
    *pin(Q154, {"partner": "phantom", "band": HIGH_BAND}, users_total=2_236, pct_users=d2(1.25), pct_usd=d2(80.49)),
    *pin(Q154, {"partner": "metamask-bridge", "band": HIGH_BAND}, users_total=5_403, pct_users=d2(0.93), pct_usd=d2(49.38)),
    *pin(Q154, {"partner": "base-app", "band": LOW_BAND}, pct_users=d2(81.74)),
    *pin(Q154, {"partner": "phantom", "band": LOW_BAND}, pct_users=d2(67.67)),
    *pin(Q154, {"partner": "metamask-bridge", "band": LOW_BAND}, pct_users=d2(67.68)),
    # "15 of phantom's 28 users above $10k".
    *pin(Q154, {"partner": "phantom", "band": HIGH_BAND}, users=28, relayer_placeholder_users=15),
]

# docs/figures/task2-users-by-volume-band.png, metamask-bridge: share of users, share of USD by band.
# The two bands the text also quotes are pinned above.
USERS_FIGURE_TABLE = [
    (LOW_BAND, 2.85),
    ("$100–$500", 7.72),
    ("$500–$2,000", 15.69),
    ("$2,000–$10k", 24.36),
]
for band, pct_usd in USERS_FIGURE_TABLE:
    USER_PINS += pin(Q154, {"partner": "metamask-bridge", "band": band}, pct_usd=d2(pct_usd))
USER_PINS += [
    *pin(Q154, {"partner": "metamask-bridge", "band": "$100–$500"}, pct_users=d2(19.29)),
    *pin(Q154, {"partner": "metamask-bridge", "band": "$500–$2,000"}, pct_users=d2(8.68)),
    *pin(Q154, {"partner": "metamask-bridge", "band": "$2,000–$10k"}, pct_users=d2(3.42)),
]

# --- §4.6 coverage status, with §2.2's mock-up --------------------------------------------------------

COVERAGE_PINS = [
    *pin(
        Q155,
        {"dimension_type": "tool", "row_kind": "dimension", "value": ALL_VALUES},
        values_total=28,
        values_with_status=14,
        windows_with_baseline=1_344,
        windows_with_status=433,
        pct_operational=d1(95.6),
        pct_degraded=d1(2.8),
        pct_outage=d1(1.6),
        outage=7,
    ),
    *pin(Q155, {"dimension_type": "overall", "row_kind": "dimension", "value": ALL_VALUES}, windows_with_status=48, operational=48),
    # The mock-up's labels: near 6 outage, 1 degraded, 6 windows without status; gasZipBridge 5 degraded, 1 without.
    *pin(Q155, {"dimension_type": "tool", "row_kind": "value", "value": "near"}, outage=6, degraded=1, windows_with_status=42),
    *pin(Q155, {"dimension_type": "tool", "row_kind": "value", "value": "gasZipBridge"}, outage=0, degraded=5, windows_with_status=47),
    *pin(Q155, {"dimension_type": "tool", "row_kind": "value", "value": "across"}, operational=48),
    *pin(Q155, {"dimension_type": "tool", "row_kind": "value", "value": "relaydepository"}, operational=48),
    *pin(Q155, {"dimension_type": "tool", "row_kind": "value", "value": "mayan"}, operational=48),
    *pin(Q157, {"day": pd.Timestamp("2026-10-14")}, near_rows=534),
    *pin(Q157, {"day": pd.Timestamp("2026-10-15")}, near_rows=104, bridge_rows=19_909),
]

# --- §4.7 supporting breakdowns and §5 -----------------------------------------------------------------

BREAKDOWN_PINS = [
    *pin(Q46, {"destination_chain_id": "(all)"}, sentinel_rows=16_668),
    *pin(Q131, {"integrators_per_address": "5 or more (relayer)"}, addresses=123, pct_all_rows=d2(11.10)),
    *pin(Q152, {"partner": "phantom"}, distinct_tx_from=703, users_receiver_default=2_236, relayer_signed_rows_to_placeholder=2_046),
    *pin(Q152, {"partner": "base-app"}, distinct_tx_from=1_043, users_receiver_default=2_584),
    *pin(Q152, {"partner": "metamask-bridge"}, distinct_tx_from=5_017, users_receiver_default=5_403),
    *pin(Q153, {}, receivers_10plus_signers=40, pct_rows_receivers_10plus_signers=d2(1.54), receivers_100plus_signers=0),
    *pin(Q125, {"partner": "base-app", "sample": POOLED}, net_cost_bps=d1(169.4)),
    *pin(Q125, {"partner": "phantom", "sample": POOLED}, net_cost_bps=d1(84.4)),
    *pin(Q125, {"partner": "metamask-bridge", "sample": POOLED}, net_cost_bps=d1(48.8)),
    *pin(Q125, {"partner": "(all sampled)", "sample": POOLED}, net_cost_bps=d1(8.1)),
    *pin(Q127, {"row_kind": "route", "route": "Ethereum → Arbitrum"}, top_partner_usd="_arbitrum", top_usd_share_pct=d1(75.6)),
]

# --- the persona shares ---
#
# Who is in a persona is a judgement, not a fact in the data: query 140 lists the strings by hand, by name
# and by what is publicly known of each product (its header comment). These pins hold the shares of
# that assignment. A changed assignment moves them. tangem brings in tangem-pay-prod, so P2's nine partners are ten strings.

P1 = "P1 multi-provider wallet"
P2 = "P2 single-provider wallet or dApp"
P3 = "P3 own-funds execution and custody platform"
P4 = "P4 chain bridge portal"
P3_STRINGS = ["Fireblocks", "safe-app", "USDai", "mbridge-stable", "definitive-prod", "metrika-capital"]

PERSONA_PINS = [
    *pin(Q140, {"persona": P1}, partners=2, pct_rows=d1(10.1), pct_usd=d1(2.0), integrators_included="metamask-bridge, phantom"),
    *pin(
        Q140,
        {"persona": P2},
        partners=9,
        integrators=10,
        pct_rows=d1(25.9),
        pct_usd=d1(21.8),
        integrators_included="Cow, _binancewallet, bitget, derive-v3, oku.trade, onekey, rabbykmsv2, tangem, tangem-pay-prod, trezor-suite",
    ),
    *pin(
        Q140,
        {"persona": P3},
        partners=6,
        pct_rows=d1(0.5),
        pct_usd=d1(5.9),
        integrators_included="Fireblocks, USDai, definitive-prod, mbridge-stable, metrika-capital, safe-app",
    ),
    *pin(
        Q140,
        {"persona": P4},
        partners=3,
        pct_rows=d1(2.0),
        pct_usd=d1(27.3),
        integrators_included="HashPort-Wallet-Prod, Pharos-Bridge, _arbitrum",
    ),
    # Not a persona figure: LI.FI's own products, outside every persona, and _arbitrum alone.
    *pin(Q67, {"partner": "(lifi_product)"}, pct_started_usd=d4(38.6968)),
    *pin(Q68,{"cut": "top 1"}, pct_started_usd=d2(20.0)),
    *pin(Q28, {"policy": "headline"}, median_row_usd=d2(43.04)),
]


@pytest.mark.parametrize(
    ("query", "where", "column", "expected"),
    VOLUME_PINS + STATUS_PINS + USER_PINS + COVERAGE_PINS + BREAKDOWN_PINS + PERSONA_PINS,
)
def test_cited_figure(result, query: str, where: dict[str, object], column: str, expected: object):
    assert row_of(result(query), where)[column] == expected


# --- figures that take more than one cell ---------------------------------------------------------


def test_154_base_app_has_two_coingecko_priced_rows(result):
    assert result(Q154).query("partner == 'base-app'")["coingecko_rows"].sum() == 2


def test_154_relayers_are_81_3_percent_of_phantoms_top_band(result):
    where = {"partner": "phantom", "band": HIGH_BAND}
    share = 100 * cell(result, Q154, where, "relayer_placeholder_usd") / cell(result, Q154, where, "usd")
    assert share == pytest.approx(81.3, abs=0.05)


def test_123_interval_widths_and_no_partner_distinguishable_from_the_market(result):
    # "with intervals 4.5 to 7.8 points wide, so none is distinguishable from the market".
    market = cell(result, Q123, {"partner": "(all sampled)", "sample": POOLED}, "pct_completed")
    widths = []
    for partner in PARTNERS:
        row = row_of(result(Q123), {"partner": partner, "sample": POOLED})
        widths.append(row["wilson_high"] - row["wilson_low"])
        assert row["wilson_low"] <= market <= row["wilson_high"]
    assert min(widths) == pytest.approx(4.5, abs=0.05)
    assert max(widths) == pytest.approx(7.8, abs=0.05)


def test_156_near_is_six_of_the_seven_tool_outage_windows(result):
    outages = result(Q156).query("dimension_type == 'tool' and status == 'outage'")
    assert len(outages) == 7
    assert (outages["value"] == "near").sum() == 6


def test_157_lifi_bridge_rows_peaked_the_day_near_fell(result):
    frame = result(Q157)
    assert frame["bridge_rows"].max() == 19_909
    assert row_of(frame, {"bridge_rows": 19_909})["day"] == pd.Timestamp("2026-10-15")


def test_23_p3_median_transfer_runs_from_91_88_to_408700_99(result):
    # The persona's six partners each have one string, so query 23's row is the partner's median.
    frame = result(Q23)
    medians = {name: row_of(frame, {"integrator": name})["median_row_usd"] for name in P3_STRINGS}
    assert min(medians.values()) == d2(91.88)
    assert max(medians.values()) == d2(408_700.99)
    assert medians["metrika-capital"] == d2(91.88)
    assert medians["mbridge-stable"] == d2(408_700.99)
