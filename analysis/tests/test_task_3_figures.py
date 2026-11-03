"""The figures task_3.md and task_3_appendix.md cite, pinned on the named queries.

Each pin reads one cell of one query's output. Rows are found by their label and never by position:
query 158 and query 164 have ties in row order. The expected values are the query's own precision, as
from the queries; the documents round them.

Basis: fee totals and per-integrator figures on the schedule (query 158 and those built on it);
figures split by token on the pooled basis (queries 165, 166, 167); figures on no-source-step volume by
token on the file's sending symbol (query 170). Query 180 is the DefiLlama check.

A pin that fails means a cited figure moved. The answer is to find out why, not to update the number here. Without the CSVs every test here skips (conftest.py).
"""

from __future__ import annotations

import re

import pandas as pd
import pytest

from figure_pins import cell, d2, d3, pin, row_of, usd0

Q33 = "33_rows_not_priced_by_provided_feed"
Q44 = "44_status_completion_rates"
Q65 = "65_started_volume"
Q75 = "75_status_fee_overall"
Q76 = "76_status_lifi_fee_rate_distribution"
Q83 = "83_revenue_model_weekly_lifi_fee"
Q84 = "84_revenue_sensitivity_to_fee_rate"
Q91 = "91_partner_fee_tier_gaps"
Q95 = "95_status_fee_line_kinds"
Q96 = "96_status_fee_line_lifi_share_by_kind"
Q97 = "97_status_fee_batch_vs_quote"
Q140 = "140_persona_shares"
Q143 = "143_status_extension_coverage_by_stratum"
Q147 = "147_status_extension_census_fee_usd"
Q150 = "150_status_bridge_census_fee_usd_by_integrator"
Q158 = "158_fee_schedule_weekly_by_integrator"
Q159 = "159_fee_schedule_check_against_uniform_2000"
Q161 = "161_volume_split_paying_by_route_kind"
Q163 = "163_ceiling_and_25bps_floor_by_class"
Q164 = "164_partner_integrators_paying_floor_and_band_median"
Q165 = "165_zero_rate_partners_scenarios"
Q166 = "166_pair_class_fee_today_and_25bps_floor"
Q167 = "167_stablecoin_pair_floor"
Q168 = "168_bridge_only_free_limit"
Q169 = "169_senders_no_source_step_above_100k"
Q170 = "170_bridge_only_by_token_class"
Q171 = "171_rates_and_loss_by_pair_class_and_size"
Q172 = "172_lifi_rate_by_pair_class_named_integrators"
Q173 = "173_integrator_fee_pool_and_shares"
Q174 = "174_execution_volume_bases_per_bp"
Q175 = "175_positive_slippage_on_swap_rows"
Q179 = "179_dex_step_paying_nothing_by_tool"
Q180 = "180_defillama_check_against_fee_schedule"

TODAY_ANNUAL_USD = 1_440_981  # query 158, the $1.44M every percentage in task_3.md is of
COMPLETION = 0.982  # query 44, applied by the queries of this family
WEEKS = 52


# --- data and method, status samples, the fee line (task_3.md §1 and §2) --------------------------

BRIDGE_VOLUME = "bridge volume: without the same-chain *Dex rows"
STARTED_VOLUME = "started volume: every row"
NO_STEP_ROWS = "bridge-volume rows without hasSourceSwaps"
NO_STEP_BASE = "bridge volume without hasSourceSwaps"

METHOD_PINS = [
    *pin(Q65, {"line": STARTED_VOLUME}, n_rows=124_858),
    *pin(Q65, {"line": BRIDGE_VOLUME}, usd=d2(307_741_849.38)),
    *pin(Q44, {"sample_design": "uniform_2000", "chain": "(all chains)"}, sampled=2_000, completed=1_964, pct_completed=d2(98.2)),
    *pin(Q75, {"grp": "all sampled (uniform 2,000)"}, sampled=2_000),
    # "None of the transfers checked in that sample carries a LI.FI fee."
    *pin(Q75, {"grp": NO_STEP_ROWS}, sampled=627, with_lifi_fee=0),
    *pin(Q147, {"integrator": "total"}, events=751),
    *pin(Q150, {"integrator": "total"}, events=309, lifi_fee_gt_0=0),
    *pin(Q84,{"base": "all bridge volume"}, annual_at_1bps=usd0(1_571_453), annual_at_25bps=usd0(39_286_324)),
    *pin(Q84, {"base": NO_STEP_BASE}, file_usd=d2(243_317_237.35)),
    *pin(Q95, {"line_name": "(all LIFI-named lines)"}, lines=1_213, split_adds_up=1_213),
    *pin(Q97, {"design": "uniform_2000"}, compared=221, same_amount=221),
    *pin(Q76, {"line": "LIFI-named line", "lifi_rate_bps": 25.0}, n_integrators=67),
    *pin(Q140, {"persona": "P1 multi-provider wallet"}, integrators_included="metamask-bridge, phantom"),
]

# --- the schedule and the volume split --------------------------------------------------------------

# Query 158: the total row and _ledger . Its unstable cell and its tie in row order fall
# on Trustware-prod-routing and seat32, which are not pinned.
SCHEDULE_PINS = [
    *pin(
        Q158,
        {"level": "total"},
        lifi_weekly_quoted_usd=d2(28_219.12),
        lifi_weekly_completed_usd=d2(27_711.18),
        lifi_annual_usd=usd0(1_440_981),
        lifi_bps_of_bridge_usd=d3(0.917),
        integrator_weekly_quoted_usd=d2(106_832.61),
        integrator_annual_usd=usd0(5_455_300),
        strings=580,
        census_rows=751,
    ),
    *pin(Q158, {"level": "integrator", "name": "_ledger"}, lifi_annual_usd=usd0(209_773), lifi_bps_of_bridge_usd=d3(20.271)),
    # The overlap's four zero-rate partners; test_158_the_four_zero_rate_partners_hold_0_85m_of_the_pool sums them.
    # The row order around these cells is not relied on.
    *pin(Q158, {"level": "integrator", "name": "rabbykmsv2"}, integrator_annual_usd=usd0(639_225)),
    *pin(Q158, {"level": "integrator", "name": "bitget"}, integrator_annual_usd=usd0(136_921)),
    *pin(Q158, {"level": "integrator", "name": "Zerion"}, integrator_annual_usd=usd0(30_298)),
    *pin(Q158, {"level": "integrator", "name": "kyberswap"}, integrator_annual_usd=usd0(46_547)),
]

SOURCE_STEP_NOTHING = "source step paying nothing"
SPLIT_PINS = [
    *pin(
        Q161,
        {"view_name": "total", "paying": "nothing"},
        weekly_usd=d2(270_342_037.18),
        pct_of_bridge_volume=d2(87.85),
        annual_per_1bp_usd=usd0(1_380_475),
        annual_at_25bps_usd=usd0(34_511_864),
    ),
    *pin(Q161, {"view_name": "total", "paying": "paying"}, weekly_usd=d2(37_399_812.20), annual_lifi_fee_today_usd=usd0(1_440_981)),
    *pin(
        Q161,
        {"view_name": "segment", "paying": "nothing", "segment": "bridge_only"},
        weekly_usd=d2(207_797_297.11),
        pct_of_bridge_volume=d2(67.52),
        annual_per_1bp_usd=usd0(1_061_096),
        annual_at_25bps_usd=usd0(26_527_403),
    ),
    *pin(Q161, {"view_name": "segment", "paying": "nothing", "segment": "token_change"}, weekly_usd=d2(39_897_229.17)),
    *pin(Q161, {"view_name": "segment", "paying": "nothing", "segment": "dex_step"}, weekly_usd=d2(22_647_510.89)),
    *pin(Q161, {"view_name": "segment", "paying": "paying", "segment": "bridge_only"}, weekly_usd=d2(18_235_843.54)),
    *pin(
        Q161,
        {"view_name": SOURCE_STEP_NOTHING, "route_kind": "all source-step rows paying nothing"},
        weekly_usd=d2(27_024_799.83),
        pct_of_bridge_volume=d2(8.78),
        annual_per_1bp_usd=usd0(137_999),
        annual_at_25bps_usd=usd0(3_449_986),
    ),
    *pin(Q161, {"view_name": SOURCE_STEP_NOTHING, "route_kind": "of which bridge-only"}, weekly_usd=d2(3_827_670.18)),
]

# --- ceiling, floors and partners --------------------------------------------------------------------

FLOOR = "floor: volume paying above zero to 25 bps"
ALL_PARTNERS = "(all partner strings paying above zero)"
TOP_BAND, MIDDLE_BAND = "$1M and above", "$100k to $1M"

PARTNER_PINS = [
    *pin(Q163, {"scenario": "ceiling: all bridge volume to 25 bps"}, annual_increase_usd=usd0(37_904_141)),
    *pin(Q163, {"scenario": FLOOR, "integrator_class": "all"}, annual_increase_usd=usd0(3_392_277), annual_fee_today_usd=usd0(1_440_981)),
    *pin(Q163, {"scenario": FLOOR, "integrator_class": "partner"}, annual_increase_usd=usd0(1_861_363)),
    *pin(Q163, {"scenario": FLOOR, "integrator_class": "lifi_product"}, annual_increase_usd=usd0(1_530_891)),
    *pin(Q164, {"name": ALL_PARTNERS}, annual_increase_to_25bps_usd=usd0(1_861_363), annual_increase_to_band_median_usd=usd0(417_534)),
    *pin(Q164, {"name": "(band total)", "volume_band": TOP_BAND}, strings=6, band_median_bps=d3(4.66)),
    *pin(Q164, {"name": "(band total)", "volume_band": MIDDLE_BAND}, strings=23, band_median_bps=d3(20.248)),
    *pin(Q164, {"name": "(band total)", "volume_band": "under $100k"}, band_median_bps=d3(25.075)),
    # A2.1.1, the increase to 25 bps.
    *pin(Q164, {"name": "safe-app"}, annual_increase_to_25bps_usd=usd0(474_307)),
    *pin(Q164, {"name": "mbridge-stable"}, annual_increase_to_25bps_usd=usd0(356_249)),
    *pin(Q164, {"name": "phantom"}, annual_increase_to_25bps_usd=usd0(325_273), weekly_paying_usd=d2(3_080_985.67)),
    *pin(Q164, {"name": "metamask-bridge"}, annual_increase_to_25bps_usd=usd0(160_705), weekly_paying_usd=d2(1_573_228.48)),
    *pin(Q164, {"name": "Reah-PRD"}, annual_increase_to_25bps_usd=usd0(111_260)),
]

# A2.1.2's table in the appendix: band, rate today, the band's median, yearly increase.
BAND_MEDIAN_TABLE = [
    ("Reah-PRD", MIDDLE_BAND, 1.218, 89_027),
    ("Fireblocks", MIDDLE_BAND, 2.5, 64_752),
    ("mbridge-stable", TOP_BAND, 0.499, 60_503),
    ("safe-app", TOP_BAND, 3.5, 36_229),
    ("onekey", MIDDLE_BAND, 9.946, 31_381),
    ("sushi", MIDDLE_BAND, 5.217, 20_687),
    ("base-app", MIDDLE_BAND, 5.06, 19_978),
    ("phantom", TOP_BAND, 4.325, 5_275),
    ("metamask-bridge", TOP_BAND, 4.996, 0),
    ("tangem", TOP_BAND, 14.123, 0),
    ("_ledger", TOP_BAND, 20.271, 0),
]
for name, band, rate, increase in BAND_MEDIAN_TABLE:
    PARTNER_PINS += pin(
        Q164,
        {"name": name, "volume_band": band},
        paying_rate_bps=d3(rate),
        annual_increase_to_band_median_usd=usd0(increase),
    )

# Query 91 holds the modal rates the appendix's A2 names, and rabbykmsv2's $721,675.
PARTNER_PINS += [
    *pin(Q91, {"partner": "rabbykmsv2"}, annual_uplift_to_25bps_usd=usd0(721_675)),
    *pin(Q91, {"partner": "phantom"}, modal_lifi_bps=d2(4.25)),
    *pin(Q91, {"partner": "metamask-bridge"}, modal_lifi_bps=d2(5.0)),
    *pin(Q91, {"partner": "base-app"}, modal_lifi_bps=d2(5.0)),
]

# --- splits by token -----------------------------------------------------------------------------
#
# Queries 165 to 172 take their pair class from data/reference/token_class.csv, a hand-maintained
# input. A change to that file moves the pins below, which are figures task_3.md and its appendix cite.
# Queries 168 and 169 carry the class in the family's shared frame without splitting by it.

ALL_FOUR = "(all four)"
ALL_VOLUME = "all volume"
FILE_EXACT = "file, exact"
NOT_STABLE = "not stablecoin pairs (free on stablecoin pairs)"
ALTCOINS = "altcoin pairs only"
POOLED_STEP = {"basis": "pooled", "scope": "source-step rows"}
FILE_BASIS = "file, no-step rows, sending symbol"
LOSS_BAND = {"scope": "source-step rows", "band": "$100 to $10k"}
UNDER_10K = {"scope": "source-step rows", "band": "under $10k"}

TOKEN_CLASS_PINS = [
    # Query 165. The two all-volume rows do not depend on the token list; the others do.
    *pin(Q165, {"scenario": ALL_VOLUME, "integrator": ALL_FOUR, "basis": FILE_EXACT}, annual_per_1bp_usd=usd0(40_384), annual_at_25bps_usd=usd0(1_009_605)),
    *pin(Q165, {"scenario": ALL_VOLUME, "integrator": "rabbykmsv2", "basis": FILE_EXACT}, annual_at_25bps_usd=usd0(721_675)),
    *pin(
        Q165,
        {"scenario": NOT_STABLE, "integrator": ALL_FOUR, "basis": "pooled"},
        annual_per_1bp_usd=usd0(19_391),
        annual_at_5bps_usd=usd0(96_956),
        annual_at_20bps_usd=usd0(387_825),
    ),
    *pin(Q165, {"scenario": NOT_STABLE, "integrator": "rabbykmsv2", "basis": "pooled"}, annual_at_5bps_usd=usd0(58_560)),
    *pin(Q165, {"scenario": ALTCOINS, "integrator": ALL_FOUR, "basis": "pooled"}, annual_at_5bps_usd=usd0(10_196), annual_at_25bps_usd=usd0(50_980)),
    *pin(Q165, {"scenario": ALTCOINS, "integrator": "rabbykmsv2", "basis": "pooled"}, pct_of_source_step_volume=d2(3.13), annual_at_25bps_usd=usd0(22_586)),
    # Query 166: the altcoin floor, and stablecoin pairs cut to zero.
    *pin(
        Q166,
        {**POOLED_STEP, "pair_class": "alt"},
        annual_increase_25bps_floor_usd=usd0(546_441),
        weekly_usd=d2(6_983_204.69),
        of_which_from_volume_paying_nothing_usd=usd0(112_596),
        pct_paying_under_10bps=d2(65.24),
    ),
    *pin(Q166, {**POOLED_STEP, "pair_class": "stable"}, annual_fee_today_usd=usd0(535_939)),
    # Query 167: the stablecoin pair floor.
    *pin(Q167, {**POOLED_STEP, "floor_bps": 1}, annual_increase_usd=usd0(111_609), weekly_usd=d2(34_291_635.13)),
    *pin(Q167, {**POOLED_STEP, "floor_bps": 2}, annual_increase_usd=usd0(234_283)),
    *pin(Q167, {**POOLED_STEP, "floor_bps": 5}, annual_increase_usd=usd0(663_270)),
    # Query 168: the free limit, on bridge-only volume.
    *pin(Q168, {"scenario": "excess above $10k", "rows_from": "all"}, annual_per_1bp_usd=usd0(834_673)),
    *pin(Q168, {"scenario": "excess above $10k", "rows_from": "no_step_uniform"}, rows_observed=21),
    *pin(Q168, {"scenario": "excess above $100k", "rows_from": "all"}, annual_per_1bp_usd=usd0(560_997)),
    *pin(Q168, {"scenario": "whole transfer at $100k and above", "rows_from": "all"}, annual_per_1bp_usd=usd0(697_338)),
    # Query 169: senders above $100k with no source step.
    *pin(Q169, {"top_senders": "all"}, senders=244),
    *pin(Q169, {"top_senders": "10"}, pct_of_no_step_usd_at_100k_and_above=d2(51.09)),
    # Query 170, the file's sending symbol.
    *pin(Q170, {"basis": FILE_BASIS, "pair_class": "not stable"}, annual_per_1bp_usd=usd0(97_498)),
    *pin(Q170, {"basis": FILE_BASIS, "pair_class": "stable"}, pct_of_basis=d2(92.15)),
    *pin(Q170, {"basis": FILE_BASIS, "pair_class": "alt"}, annual_at_25bps_usd=usd0(17_474)),
    # Query 171: median loss at $100 to $10k, and the uniform sample's rates under $10k.
    *pin(Q171, {**LOSS_BAND, "pair_class": "alt"}, loss_ex_lifi_line_bps=d2(104.36)),
    *pin(Q171, {**LOSS_BAND, "pair_class": "major"}, loss_ex_lifi_line_bps=d2(6.34)),
    *pin(Q171, {**LOSS_BAND, "pair_class": "stable"}, loss_ex_lifi_line_bps=d2(2.11)),
    *pin(Q171, {**UNDER_10K, "pair_class": "alt"}, uniform_integrator_bps=d3(49.105), uniform_lifi_bps=d3(11.002)),
    *pin(Q171, {**UNDER_10K, "pair_class": "major"}, uniform_integrator_bps=d3(21.924)),
    *pin(Q171, {**UNDER_10K, "pair_class": "stable"}, uniform_integrator_bps=d3(21.773), uniform_lifi_bps=d3(11.595)),
    # Query 172: rates by pair class at the three named integrators.
    *pin(Q172, {"integrator": "metamask-bridge", "pair_class": "stable"}, rows_pooled=43, paying_nothing_rows=41, modal_rate_bps=d2(0.0)),
    *pin(Q172, {"integrator": "metamask-bridge", "pair_class": "major"}, modal_rate_bps=d2(5.0)),
    *pin(Q172, {"integrator": "metamask-bridge", "pair_class": "alt"}, modal_rate_bps=d2(5.0)),
    *pin(Q172, {"integrator": "jumper.exchange", "pair_class": "stable"}, modal_rate_bps=d2(0.0)),
    *pin(Q172, {"integrator": "jumper.exchange", "pair_class": "major"}, modal_rate_bps=d2(2.0)),
    *pin(Q172, {"integrator": "jumper.exchange", "pair_class": "alt"}, modal_rate_bps=d2(5.0)),
    *pin(Q172, {"integrator": "tangem", "pair_class": "stable"}, modal_rate_bps=d2(5.0)),
    *pin(Q172, {"integrator": "tangem", "pair_class": "major"}, modal_rate_bps=d2(20.0)),
    *pin(Q172, {"integrator": "tangem", "pair_class": "alt"}, modal_rate_bps=d2(20.0)),
]

# --- families B and C, and the residual's tools -------------------------------------------------------

OTHER_PINS = [
    *pin(
        Q173,
        {"grp": "all integrators"},
        annual_usd=usd0(5_455_300),
        annual_at_10pct_share_usd=usd0(545_530),
        annual_at_50pct_share_usd=usd0(2_727_650),
    ),
    *pin(Q173, {"grp": "rabbykmsv2"}, annual_usd=usd0(639_225), annual_at_5pct_share_usd=usd0(31_961)),
    *pin(Q174, {"base": "not on lifiIntents"}, annual_per_1bp_usd=usd0(1_366_343)),
    *pin(Q174, {"base": "polymerStandard, no source step"}, weekly_usd=d2(124_302_947.98), annual_per_1bp_usd=usd0(634_741)),
    *pin(Q175, {"route_kind": "all source-step rows", "segment": "all"}, annual_positive_usd=usd0(590_705)),
    *pin(Q175, {"route_kind": "no_source_step", "segment": "all"}, annual_positive_usd=usd0(1_686_884)),
    *pin(Q179, {"tools": "custom"}, weekly_usd=d2(8_443_750.14)),
]

# --- query 180, DefiLlama against the schedule -------------------------------------------------
#
# These hold as of the committed snapshot data/reference/defillama_lifi_daily.csv: DefiLlama can revise
# past days, so a re-fetch can move them.

SAME_SCOPE = "1. Same scope"
YEARS = "3. Calendar years"
ANNUALISED = "2026 annualised by days"

DEFILLAMA_PINS = [
    *pin(Q180, {"section": SAME_SCOPE, "item": "volume, started"}, defillama_usd=d2(306_113_735), ours_usd=d2(307_969_358.59)),
    *pin(Q180, {"section": SAME_SCOPE, "item": "volume, bridge volume"}, defillama_usd=d2(306_113_735), ours_usd=d2(307_741_849.38)),
    *pin(Q180, {"section": SAME_SCOPE, "item": "all fees"}, defillama_usd=d2(134_463), ours_usd=d2(135_051.74)),
    *pin(Q180, {"section": SAME_SCOPE, "item": "LI.FI fee without Jumper"}, defillama_usd=d2(24_883), ours_usd=d2(25_282.97)),
    *pin(Q180, {"section": SAME_SCOPE, "item": "integrators' fees with Jumper"}, defillama_usd=d2(109_580), ours_usd=d2(109_768.77)),
    *pin(Q180, {"section": YEARS, "item": "2026 to the snapshot date", "measure": "fees"}, defillama_usd=d2(11_263_240.67)),
    *pin(Q180, {"section": YEARS, "item": "2026 to the snapshot date", "measure": "revenue"}, defillama_usd=d2(2_122_252.91)),
    *pin(Q180, {"section": YEARS, "item": ANNUALISED, "measure": "fees"}, defillama_usd=d2(13_391_149.33)),
    *pin(Q180, {"section": YEARS, "item": ANNUALISED, "measure": "revenue"}, defillama_usd=d2(2_523_199.71)),
    *pin(Q180, {"section": YEARS, "item": f"{ANNUALISED}, without the largest revenue day", "measure": "revenue"}, defillama_usd=d2(2_369_843.48)),
]


@pytest.mark.parametrize(
    ("query", "where", "column", "expected"),
    METHOD_PINS + SCHEDULE_PINS + SPLIT_PINS + PARTNER_PINS + TOKEN_CLASS_PINS + OTHER_PINS + DEFILLAMA_PINS,
)
def test_cited_figure(result, query: str, where: dict[str, object], column: str, expected: object):
    assert row_of(result(query), where)[column] == expected


# --- figures that take more than one cell ---------------------------------------------------------


def test_159_the_schedule_is_inside_the_uniform_interval_on_all_six_checks(result):
    checks = result(Q159).query("kind == 'check'")
    assert len(checks) == 6
    assert checks["inside_uniform_interval"].tolist() == [True] * 6


def test_33_coingecko_filled_377_rows_and_left_4_unpriced(result):
    frame = result(Q33)
    assert frame["rows_coingecko_priced"].sum() == 377
    assert frame["rows_unpriced"].sum() == 4


def test_143_the_integrator_sample_holds_4165_events(result):
    frame = result(Q143)
    assert frame["events_in_snapshot"].sum() == 4_165
    # "30 per integrator with 100 or more source-step transfers, 10 with 10 to 99, and all of them below that".
    assert set(frame.loc[frame["tier"] == "30 of 100+", "planned"]) == {30}
    assert set(frame.loc[frame["tier"] == "10 of 10-99", "planned"]) == {10}
    below = frame[frame["tier"] == "all under 10"]
    assert (below["planned"] == below["rows_in_data"]).all()


def test_83_the_uniform_weighting_range(result):
    # "$1.5M to $2.5M" is the lowest and the highest estimator's point estimate.
    annual = result(Q83)["annual_lifi_fee_usd"]
    assert annual.min() == usd0(1_480_737)
    assert annual.max() == usd0(2_540_331)


def test_84_share_of_bridge_volume_with_no_source_step(result):
    no_step = cell(result, Q84, {"base": NO_STEP_BASE}, "file_usd")
    bridge = cell(result, Q84, {"base": "all bridge volume"}, "file_usd")
    assert 100 * no_step / bridge == d2(79.07)


def test_76_the_default_rate_is_on_every_lifi_api_transfer(result):
    # lifi-api appears on one rate line only, the 25 bps one. "integrators" lists "name count, ...".
    frame = result(Q76)
    with_lifi_api = frame[frame["integrators"].fillna("").str.contains(r"(?:^|, )lifi-api \d")]
    assert with_lifi_api["lifi_rate_bps"].tolist() == [25.0]


def shares_by_integrator(frame: pd.DataFrame) -> dict[str, set[tuple[str, float]]]:
    """Query 96 as integrator -> the (recipient type, LI.FI's share of the line) it appears on."""
    shares: dict[str, set[tuple[str, float]]] = {}
    for row in frame.itertuples():
        for name in re.findall(r"(?:^|, )(.+?) \d+(?=,|$)", row.integrators):
            shares.setdefault(name, set()).add((row.recipient_types, row.lifi_share_of_line))
    return shares


def test_96_who_keeps_the_fee_line(result):
    shares = shares_by_integrator(result(Q96))
    # Idea 2's four partners: LI.FI's share of the line is 0 everywhere they appear.
    assert shares["rabbykmsv2"] == {("FIXED", 0.0)}
    assert shares["Zerion"] == {("FIXED", 0.0)}
    assert shares["kyberswap"] == {("FIXED", 0.0)}
    assert shares["bitget"] == {("SHARED", 0.0)}
    # Idea 3's precedent: LI.FI keeps 5%.
    assert shares["phantom"] == {("SHARED", 0.05)}
    assert shares["base-app"] == {("SHARED", 0.05)}
    # Idea 4: the line pays LI.FI alone at metamask-bridge.
    assert shares["metamask-bridge"] == {("DYNAMIC", 1.0)}


def test_168_the_100k_excess_is_exact(result):
    # "The $0.56M is exact": it reads the census rows only, no sampled row.
    rows_from = result(Q168).query("scenario == 'excess above $100k'")["rows_from"]
    assert set(rows_from) == {"all", "no_step_census", "source_census"}


def test_179_custom_is_mainly_usdai_to_pyusd(result):
    row = row_of(result(Q179), {"tools": "custom"})
    assert row["top_pairs"].startswith("USDai to PYUSD")
    assert row["top_integrators"].startswith("USDai")


def test_a1_2_is_token_change_plus_dex_step(result):
    # Appendix A1.2: about $63M a week, $0.32M per bp, $8.0M at 25 bps.
    segments = [
        row_of(result(Q161), {"view_name": "segment", "paying": "nothing", "segment": segment})
        for segment in ("token_change", "dex_step")
    ]
    assert sum(row["weekly_usd"] for row in segments) == d2(62_544_740.06)
    assert sum(row["annual_per_1bp_usd"] for row in segments) == usd0(319_378)
    assert sum(row["annual_at_25bps_usd"] for row in segments) == usd0(7_984_461)


def test_a1_3_the_lifi_line_at_zero_is_about_8m_a_week(result):
    frame = result(Q161).query("view_name == @SOURCE_STEP_NOTHING and segment == 'LIFI-named line, LI.FI part 0'")
    assert len(frame) == 2
    assert frame["weekly_usd"].sum() == d2(8_390_444.75)


def test_idea_1_altcoin_volume_without_a_source_step_is_2_6m_a_week(result):
    # "a further $2.6M a week": altcoin volume on all bridge volume less that on source-step rows.
    all_volume = cell(result, Q166, {"basis": "pooled", "scope": "all bridge volume", "pair_class": "alt"}, "weekly_usd")
    source_step = cell(result, Q166, {**POOLED_STEP, "pair_class": "alt"}, "weekly_usd")
    assert all_volume == d2(9_629_988.59)
    assert all_volume - source_step == pytest.approx(2_646_783.90, abs=0.02)


def test_158_the_four_zero_rate_partners_hold_0_85m_of_the_pool(result):
    # "$0.85M of the $5.5M pool". One step of the query's rounding for each of the four cells.
    annual = [
        cell(result, Q158, {"level": "integrator", "name": name}, "integrator_annual_usd")
        for name in ("rabbykmsv2", "bitget", "Zerion", "kyberswap")
    ]
    assert sum(annual) == pytest.approx(852_991, abs=4)


def test_idea_4_stepped_increases_at_the_two_multi_provider_wallets(result):
    wallets = [row_of(result(Q164), {"name": name}) for name in ("phantom", "metamask-bridge")]
    weekly = sum(row["weekly_paying_usd"] for row in wallets)
    assert weekly == pytest.approx(4_654_214.15, abs=0.02)  # $4.65M a week
    per_bp = weekly * COMPLETION * WEEKS / 10_000
    assert per_bp == pytest.approx(23_766, abs=1)  # about +$24k a year per bp
    assert 100 * per_bp / TODAY_ANNUAL_USD == pytest.approx(1.65, abs=0.01)  # the memo's 1.6%
    assert sum(row["annual_increase_to_25bps_usd"] for row in wallets) == pytest.approx(485_978, abs=2)  # about +$0.49M


@pytest.mark.parametrize(
    ("query", "where", "column", "percent"),
    [
        pytest.param(Q166, {**POOLED_STEP, "pair_class": "alt"}, "annual_increase_25bps_floor_usd", 37.9, id="idea-1"),
        pytest.param(Q165, {"scenario": NOT_STABLE, "integrator": ALL_FOUR, "basis": "pooled"}, "annual_at_5bps_usd", 6.7, id="idea-2"),
        pytest.param(Q173, {"grp": "all integrators"}, "annual_at_10pct_share_usd", 37.9, id="idea-3"),
        pytest.param(
            Q161,
            {"view_name": "segment", "paying": "nothing", "segment": "bridge_only"},
            "annual_per_1bp_usd",
            73.6,
            id="must-mention",
        ),
    ],
)
def test_share_of_todays_revenue(result, query: str, where: dict[str, object], column: str, percent: float):
    # task_3.md §4's table and the must-mention: 38%, 7%, 38%, 74% of today's $1.44M.
    assert 100 * cell(result, query, where, column) / TODAY_ANNUAL_USD == pytest.approx(percent, abs=0.05)
