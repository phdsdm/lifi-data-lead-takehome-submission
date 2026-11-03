# LI.FI Data Product Lead take-home

Submission for LI.FI's Data Product Lead take-home challenge.

| File | What |
|---|---|
| `task_1.md` | Understanding the data |
| `task_2.md` | Partner-facing data product |
| `task_3.md` | Revenue opportunities from data |
| `task_3_appendix.md` | All revenue ideas considered, as a tree (mostly AI-generated, with my review and modifications) |
| `analysis/` | DuckDB queries, notebooks and tests behind the figures quoted above (`analysis/README.md`) |
| `data/reference/` | Reference data the queries read: LI.FI API, CoinGecko and DefiLlama snapshots, and two hand-maintained maps |
| `docs/research/` | Research notes the task documents cite |
| `docs/figures/` | Images the task documents embed |

## Summary

- **Task 1:** what one row of the file means, the pitfalls before computing USD volume by integrator, bridge and chain, how I would validate last week's bridge volume, and the metric definitions the other two tasks share.
- **Task 2:** an improved partner analytics product aimed at retention: execution performance, coverage and reliability, user insights, a fee planner and compliance exports, with data readiness, metrics, monetisation, governance and success criteria.
- **Task 3:** I propose an altcoin floor, zero-rate partners paying on non-stablecoin pairs, and a share of integrators' fees, with stepped increases at multi-provider wallets as a way to measure how volume responds. Bridge-only pricing is sized and named, but not proposed, because of the risk.

## Assumptions

- The provided file is treated as one typical week, and yearly figures in task three are × 52, despite data only having 6 source EVM chains. Did some sanity checks against DefiLlama data, which shows monthly fees moving several times over during 2026.
- USD uses the provided hourly prices, with CoinGecko filling the few rows the feed misses.
- Started volume and bridge volume follow `task_1.md` §5. LI.FI's own products are kept apart from partners.
- The provided files hold no fees, so fee figures come from LI.FI's status API on selected transfers. The quoted fee is taken as the fee charged, which on-chain fee events support for the weekly total, not transfer by transfer.
- Jumper is treated as LI.FI's own product. A carve-out is reported, so this may change.
- Every Task 3 estimate considers volume fixed, not considering price elasticity at this stage.  

## AI usage

I used Claude Code throughout, with a set of specialised agents, and every merge went through an AI review.

- **Data-analyst agent:** named queries, executed notebooks and working notes, including the status API fetches.
- **Implementer agent:** the loading layer, the query runner and the tests.
- **Code-reviewer agent:** a verdict before each merge, recomputing figures independently.
- **Research agents:** the market landscape and the bridge-only fee research in `docs/research/`.
- **Main session:** Orchestrator, writing working notes and drafts. It also wrote proposed edits and corrections to the task documents, including quoted numbers and references, that I reviewed. General discussion partner, and it also ran some small investigations directly to address my questions.

**What I did:** Set the questions, made the decisions, chose the definitions and the ideas, and wrote the task documents from working notes and research. I am responsible for every sentence in them. `task_3_appendix.md` is mostly AI-written, through a series of reviews and iterations, with the structure and direction set by me. I did use AI to generate data exploration notebooks, but I myself did explore the data to understand the nuances and meaning. 

Note that the agent configuration, review records and working notes are not in this repository. 


## Running the analysis

The two provided CSVs are not committed. Drop them into `data/` as `transfers_started.csv` and `prices.csv`, then:

```
uv sync
uv run pytest -q
```

`analysis/README.md` explains the layout and the query runner. The notebooks that fetched API data are committed executed; the raw API responses are not in this repository, so read those notebooks as records rather than re-running them.
