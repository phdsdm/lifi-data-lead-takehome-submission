# analysis/

Everything that produces a number quoted in `task_1.md`, `task_2.md` or `task_3.md` lives here. The rule: a quoted number cites a named query and is pinned by a test.

The query numbers have gaps: this repository holds the queries the documents cite, plus those the notebooks and reference notes use, and each keeps the name it is cited by. The raw API responses (112 MB of `.jsonl`) are not committed, so the notebooks that fetched them read as executed records rather than re-run.

## Data files

The two CSVs are provided by LI.FI and are not committed. Drop them in before running anything:

```
data/transfers_started.csv   # 124,858 LiFiTransferStarted events, 6 EVM chains, 2026-10-13 to 2026-10-19 UTC
data/prices.csv              # 40,754 hourly USD prices keyed by chain and token address
```

`data/README_data_final.md` (committed) documents the columns and known limitations. The two CSVs can sit in another folder named by `LIFI_DATA_DIR` (below). The reference snapshots under `data/reference/` are committed and always read from the repository.

Every figure in the submission was computed on the copies below. Rows exclude the header line.

| File | Bytes | Rows | SHA-256 |
|---|---|---|---|
| `transfers_started.csv` | 80,068,219 | 124,858 | `362b2fe6c8162a83e434e6b17b8669d52b01e265aac490d48cf36c95ec2c2e60` |
| `prices.csv` | 3,939,766 | 40,754 | `cd9aac497bba6bd05ceec8bc16129bc60202c29547475e4024e9730eee58b0c3` |

To check a copy, compare the first column of `shasum -a 256` with the table (`sha256sum` on Linux prints the same):

```
$ shasum -a 256 data/transfers_started.csv data/prices.csv
362b2fe6c8162a83e434e6b17b8669d52b01e265aac490d48cf36c95ec2c2e60  data/transfers_started.csv
cd9aac497bba6bd05ceec8bc16129bc60202c29547475e4024e9730eee58b0c3  data/prices.csv
```

The values live in `lifi/checksums.py`; `tests/test_checksums.py` checks that this table lists the same ones. A file that differs is reported, not refused. `uv run pytest -q` shows a `DataChecksumWarning` in its warnings summary, and `lifi-build-db` (and `lifi-query` when it builds a missing database) prints a warning to stderr before building. Each warning names the file, the expected and the found checksum and both sizes. Any change to the content changes the checksum, line endings included, so a figure computed from that copy may differ from the one the documents quote, and a test that pins it may fail for that reason alone. A missing file is handled differently: the tests skip and the build stops, naming the file.

## Layout

| Path | What |
|---|---|
| `lifi/` | Python package. `load.py`: pandas frames from the CSVs, `bridge_data` parsed with `json.loads` so `min_amount` stays an exact integer, a missing file raises `MissingDataFile`, a missing pricing snapshot `MissingReferenceSnapshot`. `build_db.py` (`lifi-build-db`): rebuilds `analysis/lifi.duckdb` with tables `transfers` (bridge_data keys as typed columns, `min_amount` HUGEINT, timestamps UTC), `prices`, one `ref_<stem>` per `data/reference/*.csv`, and the view `transfers_priced` with the headline USD column (below). `query.py` (`lifi-query`): runs a named query against the file; `run(name)` returns a DataFrame. `paths.py`: where the CSVs, the snapshots and the database file are, with the two environment overrides below. `checksums.py`: the recorded SHA-256 of the two CSVs and the mismatch warning (above). |
| `queries/<nn>_<name>.sql` | One question per file; header comment gives the question, the grain and the definition applied. The file name is the citation the documents use |
| `notebooks/<nn>_<topic>.ipynb` | Exploration, committed executed so outputs read without a kernel |
| `tests/` | `test_build_db.py` checks the build (row counts, exact `min_amount`, no nulls from `bridge_data`, the reference tables, a build from a folder holding only the two CSVs, the runner); `test_transfers_priced.py` pins the view's totals and row counts to notebook 02 §8 and checks the price policy, the missing-snapshot failure and that a `reference/` folder beside the CSVs is ignored; `test_checksums.py` warns when a provided CSV differs from the recorded copy, and checks the warning on modified copies and the table above against the code; `test_queries.py` executes every query file; `test_task_1_figures.py`, `test_task_2_figures.py` and `test_task_3_figures.py` pin the figures the documents quote. Without the data files the tests skip, naming the missing file |

## Running

```
uv sync                         # creates .venv with pandas, duckdb, jupyter, pytest and installs lifi/ (editable)
uv run lifi-build-db            # rebuilds analysis/lifi.duckdb from the CSVs in a few seconds; prints tables and row counts
uv run lifi-query <name>        # runs queries/<name>.sql against the file and prints the result; --csv for CSV, --db for another file
uv run pytest -q                # the check command: the build checks, every query file and the figure pins
uv run jupyter lab              # exploration; start from notebooks/00_explore.ipynb
```

`<name>` is the file stem (`lifi-query 01_referrer_summary`); a path to any `.sql` file also works. `lifi-query` builds the database first when the file is missing. From a notebook, `from lifi import run` then `run("01_referrer_summary")` gives the result as a DataFrame and `run_sql("select ...")` runs inline SQL; `HUGEINT` columns come back as exact Python ints.

Two environment variables, both optional:

```
LIFI_DATA_DIR   directory holding transfers_started.csv and prices.csv; default data/ in the repository
LIFI_DB_PATH    the database file; default analysis/lifi.duckdb (gitignored, rebuilt from the CSVs)
```

The reference snapshots are always read from `data/reference/` in the repository, whatever `LIFI_DATA_DIR` says: they are committed, and a copy elsewhere could drift from them unnoticed. A folder named by `LIFI_DATA_DIR` needs only the two CSVs; a `reference/` folder inside it is ignored. No environment variable moves the snapshots; the tests point the build at synthetic ones through `build`'s `reference` argument.

Loading is pandas `read_csv`: the files are small. `bridge_data` is parsed with `json.loads`, so `min_amount` stays an exact integer (14,864 rows exceed int64) and is stored as DuckDB `HUGEINT`, never float; the view shifts it by the token's decimals at pricing time. Timestamps are stored as naive UTC `TIMESTAMP`. Reference snapshots load with the types pandas infers, except that an integer column with a missing value stays an integer (`BIGINT` with NULL) instead of becoming `DOUBLE`: in `ref_lifi_chain_id_registry`, `api_chain_id` (NULL for Aptos), `connections_code`, `connections_to_tokens` and `quote_onchain_destination_chain_id`.

A missing data file produces a message naming the file and this README, not a DuckDB stack trace; the tests skip with the same message.

## The view `transfers_priced` and the headline USD column

One row per transfer, every column of `transfers` followed by the columns below. The price policy is as implemented in `notebooks/02_activity_and_prices.ipynb` §8: the provided price first, CoinGecko's where the provided one is missing, each row flagged by `price_source`.

| Column | What |
|---|---|
| `hour` | `block_time` truncated to the hour (UTC), the key of both price feeds |
| `symbol`, `decimals` | From `prices.csv` for the (chain, token) pair, else from LI.FI's token list `data/reference/lifi_api_tokens_by_chain.csv` for the source chain's id (reference data). The polygon native asset (POL at the zero address) is in that list with 18 decimals, as in `lifi_api_chains.csv` |
| `decimals_source` | `provided`, `lifi`, or NULL when neither knows the token |
| `price_usd_provided` | `prices.csv` for (chain, `sending_asset_id`, hour) |
| `price_usd_coingecko` | `data/reference/coingecko_hourly_prices_2026-10-13_to_2026-10-19.csv` for the same key (reference data) |
| `price_usd` | `price_usd_provided`, else `price_usd_coingecko` |
| `price_source` | `provided`, `coingecko`, or NULL when neither feed prices the row |
| `amount_token` | `min_amount / 10^decimals`, the shift done on `min_amount`'s exact digits, never through a float first |
| `amount_usd` | `amount_token × price_usd`: the headline USD column |
| `amount_usd_provided` | `amount_token × price_usd_provided`: the provided feed only, NULL where it has no price |

Totals, pinned by `tests/test_transfers_priced.py` to the figures of notebook 02 §8: `amount_usd` sums to $307,969,358.59 over 124,854 priced rows, of which 377 are priced by CoinGecko; `amount_usd_provided` sums to $307,935,992.59 over 124,477 rows; 4 rows are priced by neither feed and keep NULL USD. A figure from `amount_usd` includes the CoinGecko-priced rows; `price_source` separates them.

The build reads the two snapshots the view needs from `data/reference/` in the repository and stops, before touching the database, with a message naming the one that is missing (`MissingReferenceSnapshot`), so `amount_usd` never falls back to the provided feed alone. The snapshots are committed, so a missing one makes the tests error rather than skip.
