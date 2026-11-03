# Data README

This folder contains two CSV files for the take-home challenge. All data comes from public sources. It is public on-chain data plus public market prices.

## Export window

- Start: 2026-10-13 00:00:00 UTC (inclusive)
- End: 2026-10-20 00:00:00 UTC (exclusive)
- This is 7 full days, Tuesday to Monday.

## `transfers_started.csv`

One row per `LiFiTransferStarted` event emitted by the LI.FI Diamond contract. The file covers 6 EVM source chains: `ethereum`, `arbitrum`, `base`, `optimism`, `polygon`, `bnb`.

- Rows: 124,858
- Order: `block_time`, then `chain`, then `log_index`

| Column | Type | Description |
|---|---|---|
| `chain` | text | Chain where the event was emitted (source chain), as a name |
| `block_time` | timestamp (UTC) | Time of the block that contains the event |
| `block_number` | integer | Block number on `chain` |
| `tx_hash` | hex text | Hash of the transaction that emitted the event |
| `log_index` | integer | Position of the event inside the block |
| `contract_address` | hex text | Address of the contract that emitted the event |
| `tx_from` | hex text | Address that signed and sent the transaction |
| `bridge_data` | JSON text | The `bridgeData` struct of the event, exactly as emitted |

Keys inside `bridge_data`:

| Key | Description |
|---|---|
| `transactionId` | LI.FI transaction identifier |
| `bridge` | Name of the bridge used |
| `integrator` | Integrator string passed with the transaction |
| `referrer` | Referrer address |
| `sendingAssetId` | Token contract address |
| `receiver` | Receiving address |
| `minAmount` | Amount, in the token's smallest unit |
| `destinationChainId` | Destination chain ID |
| `hasSourceSwaps` | Whether the transaction includes swaps on the source chain |
| `hasDestinationCall` | Whether the transaction includes a call on the destination chain |

## `prices.csv`

Hourly USD prices for the tokens that appear as `sendingAssetId` in `transfers_started.csv`, on the same chain.

- Rows: 40,754

| Column | Type | Description |
|---|---|---|
| `chain` | text | Chain name, same values as `transfers_started.chain` |
| `token_address` | hex text | Token contract address |
| `symbol` | text | Token symbol |
| `decimals` | integer | Token decimals |
| `hour` | timestamp (UTC) | Start of the hour |
| `price_usd` | float | Average USD price in that hour |

## Known limitations

- This is a sample. It does not cover every chain or every LI.FI contract event.
- Prices come from a public aggregated price feed. They are not guaranteed to be complete or exact.
- Addresses are lowercase hex strings.
