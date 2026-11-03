"""The figures task_1.md cites, pinned on the named queries.

Each pin reads one cell of one query's output, at the query's own precision; the document rounds them.
Where the document's rounded value is not plain from the cell, the comment gives it. Figures from the
status samples and the CoinGecko snapshot depend on the committed reference data, as the document says.

A pin that fails means a cited figure moved. The answer is to find out why, not to update the number here. Without the CSVs every test here skips (conftest.py).
"""

from __future__ import annotations

import pandas as pd
import pytest

from figure_pins import cell, d1, d2, d4, pin, rounded, row_of

Q01 = "01_referrer_summary"
Q03 = "03_destination_call_by_bridge"
Q04 = "04_window_hours_and_gaps_by_chain"
Q06 = "06_key_uniqueness"
Q07 = "07_repeated_transaction_id_pairs"
Q09 = "09_integrator_rows_and_senders"
Q11 = "11_status_min_amount_vs_sending_amount"
Q13 = "13_status_time_to_completion_by_bridge"
Q24 = "24_integrator_usd_without_rows_above_1m"
Q28 = "28_usd_concentration"
Q29 = "29_rows_above_1m_usd"
Q31 = "31_started_volume_candidates"
Q32 = "32_usd_by_price_source"
Q33 = "33_rows_not_priced_by_provided_feed"
Q35 = "35_price_hour_alignment"
Q36 = "36_price_feed_total_provided_vs_coingecko"
Q42 = "42_status_received_over_sent_and_gas"
Q43 = "43_status_fee_lines_by_integrator"
Q44 = "44_status_completion_rates"
Q45 = "45_file_level_counts_and_flag_shares"
Q46 = "46_receiver_sentinel_by_destination"
Q47 = "47_min_amount_above_int64"
Q48 = "48_usd_by_destination_chain"
Q51 = "51_price_feed_hours_beyond_1_5x"
Q53 = "53_rows_by_destination_chain_type"
Q54 = "54_reference_coverage_counts"
Q55 = "55_status_edge_case_checks"
Q57 = "57_token_symbols_addresses_decimals"
Q58 = "58_status_source_steps"
Q61 = "61_integrator_name_families"
Q65 = "65_started_volume"
Q67 = "67_started_volume_by_partner"
Q101 = "101_active_threshold_sensitivity"
Q102 = "102_active_integrators_and_partners"
Q103 = "103_active_rule_edge_cases"
Q104 = "104_daily_active_integrators_and_partners"
Q105 = "105_price_feed_integrity"
Q131 = "131_relayer_rule_market"
Q152 = "152_partner_users_receiver_default"
Q158 = "158_fee_schedule_weekly_by_integrator"

STARTED = "started volume: every row"
BRIDGE = "bridge volume: without the same-chain *Dex rows"
SAME_CHAIN = "same-chain *Dex rows, reported separately"
ROUND_TRIP = "in started volume, noted: the round trip, both legs"
UNIFORM = {"sample_design": "uniform_2000", "chain": "(all chains)"}

# --- §1, grain and what the row is not -------------------------------------------------------------

GRAIN_PINS = [
    *pin(
        Q04,
        {"chain": "(all chains)"},
        first_row=pd.Timestamp("2026-10-13 00:00:00"),
        last_row=pd.Timestamp("2026-10-19 23:59:49"),
        hours_in_window=168,
    ),
    *pin(Q44, {"sample_design": "equal_per_chain_600", "chain": "(all chains)"}, sampled=600),
    *pin(Q44, UNIFORM, sampled=2_000, pct_completed=d2(98.2), pct_refunded=d2(1.5), wilson_low=d2(97.52), wilson_high=d2(98.70)),
    *pin(Q55, {"checked": "edge-case hash lookups with status DONE"}, passing=294, out_of=294),
    # 67.8%, 32%, one contract, six source chains.
    *pin(
        Q45,
        {},
        pct_has_source_swaps=d2(67.82),
        pct_sender_is_receiver=d2(67.79),
        pct_native_asset=d2(31.99),
        contract_addresses=1,
        source_chains=6,
    ),
    *pin(Q65, {"line": SAME_CHAIN}, n_rows=295),
    *pin(Q54, {"checked": "EVM chains in /v1/chains (first fetch, five chain types)"}, value=65),
    *pin(Q54, {"checked": "chains in /v1/chains with all six chain types (Stellar added under STL)"}, value=71),
    *pin(Q54, {"checked": "destination ids named in LI.FI's chain-id registry"}, value=69),
    *pin(Q54, {"checked": "destination ids listed by /v1/chains with all six chain types"}, value=64, out_of=69),
    *pin(Q54, {"checked": "token pairs known to LI.FI's token list"}, value=255),
    # The 5 unlisted ids: Tron's contract-side id and four delisted chains.
    *pin(Q53, {"chain_type": "(all)"}, unlisted_ids=5),
    *pin(Q53, {"chain_type": "TVM"}, unlisted_ids=1),
    *pin(Q53, {"chain_type": "EVM"}, unlisted_ids=4),
    # Keys: the event key is unique, 6 repeated ids, 11 transactions with two events.
    *pin(
        Q06,
        {},
        n_rows=124_858,
        distinct_event_keys=124_858,
        repeated_transaction_ids=6,
        max_rows_per_transaction_id=2,
        multi_event_transactions=11,
        max_events_per_transaction=2,
    ),
]

# --- Table 1 ---------------------------------------------------------------------------------------

FIELD_PINS = [
    # "only 13% for base-app and phantom".
    *pin(Q09, {"integrator": "base-app"}, pct_sender_is_receiver=d2(12.92)),
    *pin(Q09, {"integrator": "phantom"}, pct_sender_is_receiver=d2(12.71)),
    *pin(Q131, {"integrators_per_address": "5 or more (relayer)"}, addresses=123, pct_all_rows=d2(11.10), pct_rows_self_receive=d1(0.1)),
    *pin(Q01, {}, n_rows=124_858, zero_referrer_rows=122_796),
    *pin(Q46, {"destination_chain_id": "(all)"}, sentinel_rows=16_668, pct_of_all_rows=d2(13.35)),
    *pin(Q11, {"sample": "all_2600", "has_source_swaps": "false"}, events=831, amount_equal=831),
    *pin(Q58, {"sample": "uniform_2000", "has_source_swaps": True}, pct_fee_collection_only=d1(61.7)),
]

# --- §2, pitfalls ----------------------------------------------------------------------------------

PITFALL_PINS = [
    *pin(Q47, {}, rows_above_int64=14_864, pct_above_int64=d2(11.9)),
    # 381 rows without a provided price, 377 filled, 4 left.
    *pin(Q32, {"price_source": "(all)", "decimals_source": "(all)"}, rows_unpriced_provided=381, rows_unpriced_headline=4),
    *pin(Q33, {"chain": "polygon", "symbol": "POL"}, n_rows=364),
    # "22 rows above $1M are 24.7% of USD".
    *pin(Q28, {"policy": "headline"}, rows_above_1m=22, pct_usd_above_1m=d2(24.72)),
    # "one address's 9.52M USDC round trip is 6.2%".
    *pin(Q65, {"line": ROUND_TRIP}, n_rows=2, pct_of_started_usd=d4(6.1832)),
    *pin(Q24, {"integrator": "Pharos-Bridge"}, rows_above_1m=2, rank_with_every_row=5, rank_without_rows_above_1m=33),
    *pin(Q67, {"partner": "(lifi_product)"}, pct_started_usd=d4(38.6968)),  # 38.7%
    # "How much the choices matter": under 0.1% three times, then 28.8% and 35.5%.
    *pin(
        Q31,
        {"measure": "pct_vs_baseline"},
        provided_price_only=d4(-0.0108),
        without_same_chain_rows=d4(-0.0739),
        repeated_ids_once=d4(-0.0082),
        without_underscore_strings=d4(-28.8143),
        without_jumper_lifi_strings=d4(-35.5469),
    ),
]

# --- §4, limits ------------------------------------------------------------------------------------

LIMIT_PINS = [
    # The pooled sample's median and p90, as task_2.md quotes them.
    *pin(Q13, {"bridge": "(all bridges)"}, all_completed=2_557, all_median_s=d1(3.0), all_p90_s=d1(38.0)),
    *pin(Q42, {"sample": "uniform_2000"}, median_received_over_sent=d4(0.9965)),
    *pin(Q43, {"integrator": "(uniform 2,000)"}, lifi_fee_bps=d1(1.5)),
    *pin(Q152, {"partner": "phantom"}, distinct_tx_from=703, users_receiver_default=2_236),
    *pin(Q158, {"level": "total"}, lifi_bps_of_bridge_usd=d1(0.9)),
]

# --- §5, definitions ---------------------------------------------------------------------------------

ACTIVE_PARTNERS = "active partners: started USD >= 100, pooled over the partner's integrators"
ACTIVE_INTEGRATORS = "active integrators: started USD >= 100, partner-class strings"

DEFINITION_PINS = [
    *pin(Q67, {"partner": "_arbitrum"}, usd=d2(61_593_656.84), rows_coingecko=0),
    *pin(Q65, {"line": STARTED}, usd=d2(307_969_358.59), n_rows=124_858, rows_unpriced=4, rows_coingecko=377),
    *pin(Q65, {"line": BRIDGE}, usd=d2(307_741_849.38)),
    *pin(Q103, {"case": "under_10_transfers_at_100000_usd_plus", "partner": "mbridge-stable"}, transfers=5, usd=d2(2_847_475.60)),
    *pin(Q103, {"case": "one_sender_at_10000_usd_plus", "partner": "Banxa-EUIV---Production"}, transfers=213, senders=1),
    *pin(Q103, {"case": "below_1000_usd_with_20plus_transfers", "partner": "request-network-api"}, transfers=163, senders=53, usd=d2(519.26)),
    *pin(Q102, {"line": ACTIVE_INTEGRATORS}, candidates=563, passing=280, failing=283),
    *pin(Q102, {"line": ACTIVE_PARTNERS}, candidates=562, passing=279),
    *pin(Q102, {"line": "of which underscore integrators"}, candidates=6, passing=6),
    *pin(Q104, {"weekday": "(seven-day average)"}, integrators_any_transfer=d1(250.1)),
]

# Table 2: floor, active of 563, share of integrator USD excluded, share of rows excluded.
ACTIVE_FLOOR_TABLE = [
    (0, 563, 0.0, 0.0),
    (10, 426, 0.0002, 0.416),
    (100, 280, 0.0032, 1.524),
    (1_000, 174, 0.0251, 3.378),
    (10_000, 92, 0.1881, 7.273),
    (100_000, 49, 0.9984, 15.125),
]
for floor, active, pct_usd, pct_rows in ACTIVE_FLOOR_TABLE:
    DEFINITION_PINS += pin(
        Q101,
        {"level": "integrator", "threshold_usd": floor},
        active=active,
        total=563,
        pct_usd_excluded=d4(pct_usd),
        pct_rows_excluded=rounded(pct_rows, 3),
    )

# --- Appendix A ------------------------------------------------------------------------------------

APPENDIX_PINS = [
    *pin(Q105, {"check": "rows"}, count=40_754),
    *pin(Q105, {"check": "duplicate keys (keys with more than one row)"}, count=0),
    *pin(Q105, {"check": "rows with price_usd <= 0"}, count=0),
    *pin(Q65, {"line": STARTED}, usd_coingecko=d2(33_366.00)),
    *pin(Q36, {"chain": "(all)"}, pct_difference=d4(-0.037)),
    # "+0.004% / −0.008%".
    *pin(Q35, {"policy": "headline", "hour_offset": -1}, pct_vs_offset_0=d4(0.0035)),
    *pin(Q35, {"policy": "headline", "hour_offset": 1}, pct_vs_offset_0=d4(-0.0078)),
]


@pytest.mark.parametrize(
    ("query", "where", "column", "expected"),
    GRAIN_PINS + FIELD_PINS + PITFALL_PINS + LIMIT_PINS + DEFINITION_PINS + APPENDIX_PINS,
)
def test_cited_figure(result, query: str, where: dict[str, object], column: str, expected: object):
    assert row_of(result(query), where)[column] == expected


# --- figures that take more than one cell ---------------------------------------------------------


def test_04_every_chain_has_168_of_168_hours_and_the_largest_gap_is_21_7_minutes(result):
    frame = result(Q04)
    assert set(frame["hours_with_rows"]) == {168}
    assert len(frame) == 7  # six chains and the all-chains row
    assert frame["max_gap_minutes"].max() == d1(21.7)


def test_01_zero_referrer_is_98_3_percent(result):
    # The query rounds to 98.35; unrounded the share is 98.3485, which the document gives as 98.3.
    share = 100 * cell(result, Q01, {}, "zero_referrer_rows") / cell(result, Q01, {}, "n_rows")
    assert round(share, 1) == 98.3


def test_53_non_evm_is_13_3_percent_of_rows(result):
    # The query rounds to 13.35; unrounded the share is 13.3496, which the document gives as 13.3.
    where = {"chain_type": "(non-EVM, all types)"}
    assert row_of(result(Q53), where)["pct_rows"] == d2(13.35)
    share = 100 * cell(result, Q53, where, "n_rows") / cell(result, Q53, {"chain_type": "(all)"}, "n_rows")
    assert round(share, 1) == 13.3


def test_48_destinations_and_robinhood_chain(result):
    frame = result(Q48)
    assert frame["destination_chain_id"].nunique() == 69
    robinhood = row_of(frame, {"name": "Robinhood Chain"})
    assert robinhood["pct_rows"] == d2(21.65)  # 21.7%
    assert round(100 * robinhood["n_rows"] / frame["n_rows"].sum(), 1) == 21.7


def test_46_and_48_tron_appears_under_two_ids(result):
    for query in (Q46, Q48):
        tron = result(query).query("name == 'Tron'")
        assert len(tron) == 2
        assert tron["destination_chain_id"].nunique() == 2


def test_07_six_repeated_ids(result):
    assert len(result(Q07)) == 6


def test_54_all_31_bridge_keys_are_in_the_tool_list(result):
    frame = result(Q54)
    rows = frame[frame["checked"].str.startswith("bridge strings matching a tool key")]
    assert rows["value"].sum() == 31
    assert set(rows["out_of"]) == {31}


def test_61_seven_families_of_variant_strings(result):
    frame = result(Q61)
    assert len(frame[frame["stem"] != "(all 7 families)"]) == 7
    assert row_of(frame, {"stem": "(all 7 families)"})["strings"] == 17


def test_03_only_across_and_stargate_set_the_destination_call(result):
    frame = result(Q03)
    flagged = frame[(frame["bridge"] != "(all bridges)") & (frame["destination_call_rows"] > 0)]
    assert set(flagged["bridge"]) == {"across", "stargateV2"}


def test_03_the_same_chain_rows_are_exactly_the_three_exchange_tools(result):
    # §5: "exactly the three exchange tools lifiIntentsDex, m0Dex and paxosDex", the 295 rows of query 65.
    tools = result(Q03).query("bridge in ['lifiIntentsDex', 'm0Dex', 'paxosDex']")
    assert len(tools) == 3
    assert tools["n_rows"].sum() == cell(result, Q65, {"line": SAME_CHAIN}, "n_rows") == 295


def test_57_usdc_is_two_tokens_on_three_chains_and_18_decimals_on_bnb(result):
    frame = result(Q57)
    usdc = frame[frame["symbol"] == "USDC"]
    tokens_per_chain = usdc.groupby("chain")["token_address"].nunique()
    assert set(tokens_per_chain[tokens_per_chain == 2].index) == {"arbitrum", "optimism", "polygon"}
    assert row_of(frame, {"symbol": "USDC", "chain": "bnb"})["decimals"] == 18
    assert row_of(frame, {"symbol": "USDT", "chain": "bnb"})["decimals"] == 18


def test_51_gear_beyond_1_5x_for_23_hours_peaking_at_2_6x(result):
    gear = result(Q51).query("symbol == 'GEAR'")
    assert len(gear) == 23
    assert set(gear["hours_beyond_band_for_token"]) == {23}
    assert gear["ratio"].min() >= 1.5
    assert gear["ratio"].max() == d4(2.6217)


def test_32_coingecko_filled_377_rows_for_33366_usd(result):
    # Query 32 splits the fill by where the decimals came from.
    filled = result(Q32).query("price_source == 'coingecko'")
    assert filled["n_rows"].sum() == 377
    assert filled["usd"].sum() == pytest.approx(33_366.00, abs=0.02)
    assert row_of(result(Q32), {"price_source": "(none)", "decimals_source": "lifi"})["n_rows"] == 4


def test_29_lists_the_22_rows_above_1m(result):
    frame = result(Q29)
    assert len(frame) == 22
    assert frame["usd"].min() > 1_000_000


def test_65_and_29_the_round_trip_is_two_legs_of_9_52m(result):
    # The two legs, $9,521,501.02 and $9,520,869.56, sum to query 65's round-trip line.
    legs = result(Q29).query("usd > 9_500_000 and usd < 9_600_000")
    assert len(legs) == 2
    assert legs["usd"].sum() == pytest.approx(cell(result, Q65, {"line": ROUND_TRIP}, "usd"), abs=0.02)


def test_31_the_price_feed_same_chain_and_repeated_ids_each_move_under_a_tenth_of_a_percent(result):
    row = row_of(result(Q31), {"measure": "pct_vs_baseline"})
    for choice in ("provided_price_only", "without_same_chain_rows", "repeated_ids_once"):
        assert abs(row[choice]) < 0.1


def test_152_phantom_is_under_counted_about_three_times(result):
    # "under-counts relayed partners about three times": 2,236 users against 703 signing addresses.
    where = {"partner": "phantom"}
    assert round(cell(result, Q152, where, "users_receiver_default") / cell(result, Q152, where, "distinct_tx_from")) == 3


def test_104_daily_active_integrators_range(result):
    days = result(Q104).dropna(subset=["day_utc"])["integrators_any_transfer"]
    assert len(days) == 7
    assert days.min() == 219
    assert days.max() == 271
