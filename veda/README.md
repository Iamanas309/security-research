# Veda

DeFi vault primitive ("BoringVault"). ~$3B TVL, powers Kraken DeFi Earn, EtherFi Liquid Vaults,
Lido Earn. Reviewed against the Immunefi program (max bounty $1,000,000), July 2026.

## Scope covered

Two full architectures, manual review.

**Core vaults (mainnet ETH / BTC / USD):** `BoringVault`, `TellerWithMultiAssetSupport`,
`AccountantWithRateProviders`, `BoringOnChainQueue`, `BoringSolver` (all four entry points plus the
callback), `ManagerWithMerkleVerification` including Merkle leaf/proof construction and the
`DecodersAndSanitizers` pattern, `DroneLib`/`BoringDrone`, `Auth`/`RolesAuthority`. Full live
permission sweep of **62 privileged entry points** — all correctly gated.

**Yield-streaming deployment (Jan 2026, BoostedUSDC / BalancedUSDC):**
`AccountantWithYieldStreaming` (`vestYield`, `postLoss`, crystallization, TWAS, RAY virtual pricing,
fees), `TellerWithYieldStreaming` + `TellerWithBuffer`, `AaveV3BufferHelper`, `ERC4626BufferHelper`,
`AaveV3BufferLens`.

Cross-checked with Aderyn v0.1.9 (63 detectors, 410 files). Every "High" category touching these
contracts was a false positive, a known-safe role-gated pattern, or something already covered by
hand. Its single largest finding was ~1400 lines of "centralization risk for trusted owners" — which
independently confirmed what the manual pass concluded, that the risk surface here is
overwhelmingly operator-gated.

I ran the static tools Slither and Aderyn. They found some mediums and lows; I then confirmed each
one and proved they were harmless after manually reviewing every contract.

## Findings

| # | Finding | Severity | Status |
|---|---|---|---|
| 01 | [Unvalidated `teller` parameter in `BoringSolver`](./01-unvalidated-teller.md) | Informational (PoC included) | Published, not submitted |

## Trust model

Worth documenting because it's what most of the "findings" here collapse into.

`BoringVault` uses Solmate's `Auth`, delegating to an external `Authority` via
`canCall(user, target, functionSig)`, falling back to `owner` only when no authority is set.

For Liquid ETH (`0xf0bb20865277aBd641a307eCe5Ee04E79073416C`):
- `owner()` is `0x0` — renounced. Verified via the `OwnershipTransferred` log: the deployer set
  itself as owner at block 20014552 and renounced ~160 blocks (~32 min) later, so this was part of
  the deploy script, not a later governance action.
- `authority()` is a stock unmodified Solmate `RolesAuthority` (256-bit role bitmap).
- That authority's `owner()` is a real Gnosis Safe — confirmed **4-of-6** via `getOwners()` and
  `getThreshold()`. Its own `authority()` is `0x0`. End of chain.

No single EOA anywhere in the trust chain.

## Threads investigated and closed

Each of these was a real mechanism that didn't survive scrutiny. The reasons are the useful part.

- **Yield entry/exit asymmetry** (gains streamed, losses instant → front-run the loss). Real
  mechanism, but almost certainly the *disclosed known issue* the program already carves out. It's
  also loss-avoidance rather than theft, and likely operationally mitigated via private `postLoss`.

- **Odos `inputReceiver` decoder omission.** A genuine code defect — unconstrained fund destination.
  Strategist-gated and reached through an external integration, which the program rules put out of
  scope.

- **Streaming price manipulation** — `totalShares` dilution, flash-loan deposit-before-withdraw,
  whale exit, donation/inflation, timestamp manipulation. All safe by construction: crystallize-first
  ordering, virtual accounting that never reads `balanceOf`, a TWAS-protected deviation cap, and
  `block.timestamp` monotonicity.

- **Deviation-cap bypass via `setFirstDepositTimestamp` TWAS-baseline reset.** A real
  "guard lives in the caller, not the function" smell. Both walls hold anyway — only the Teller
  calls it, and only at `totalSupply() == 0`, and `vestYield` needs the strategist role.

- **Buffer mechanism / Merkle bypass.** The Teller does hold un-Merkle-verified `vault.manage`
  power. But the helpers emit only hardcoded parameterized Aave/ERC4626 calls with no injection
  point and no value leak, and active helpers sit behind an admin allowlist. Two-tier gate, clean.

- **Legacy `beforeTransfer` interface on Liquid USD** (`0x08c6F91e2B681FaF5e17227F2a44C307b3C1364C`)
  makes `toDenyList`/`operatorDenyList` unreachable. Not pursued.

- **Fee-rounding grief, uncapped `postLoss` drop, cooldown bypass.** Operator-trust and
  protocol-revenue impacts, low severity.

## Conclusion

No unprivileged, single-transaction, payable vulnerability found across two full architectures.
Every real defect resolves to operator trust, centralization, or a disclosed known issue — the
categories the program's own rules exclude.

Veda has been through Spearbit, Macro, and Seven Seas. Finding nothing payable there is the expected
outcome, and the honest framing is that the value of this review is the map of *why* each thread
dies, not a trophy.

