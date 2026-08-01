# Rhino.fi

Cross-chain stablecoin bridge (formerly DeversiFi). Reviewed against the Immunefi program
(max bounty $2,000,000), March 2026.

## Scope covered

8 of 9 in-scope assets.

| Asset | Chain | Result |
|---|---|---|
| Optimism Bridge | Optimism | Reviewed — `DVFDepositContract` + `BridgeVM` |
| BSC Bridge | BSC | Byte-identical to Optimism |
| MATIC Bridge | Polygon | Byte-identical to Optimism |
| ARB Bridge | Arbitrum | Byte-identical to Optimism |
| zkSync Bridge | zkSync Era | Runs a different, later implementation — reviewed, nothing reportable |
| ARB / BSC / MATIC MultiSig | — | Stock `GnosisSafeProxy`, deprioritized |
| zkEVM Bridge | Polygon zkEVM | Not reviewed — explorer and RPC infrastructure unreachable |

Architecture: four of the five bridges sit behind stock OZ `TransparentUpgradeableProxy` and run a
byte-identical `DVFDepositContract` (264 lines) plus a separately-deployed `BridgeVM` (55 lines,
created via `new BridgeVM()`, not inherited). zkSync runs a different, later implementation.

## Findings

| # | Finding | Severity | Status |
|---|---|---|---|
| 01 | [`depositWithId` accepts arbitrary token addresses](./01-phantom-deposit.md) | Informational | Published, not submitted |

## What I checked and ruled out

Each of these was a real lead that died for a specific reason. Included because the reasoning is
the point.

- **`BridgeVM.withdrawVmFunds()` has no access modifier.** Anyone can call it — but it sweeps to
  `owner()`, permanently bound to the parent `DVFDepositContract` (the parent is `msg.sender`
  during `new BridgeVM()`). Confirmed neither contract ever calls `transferOwnership` or
  `renounceOwnership`, so the binding can't drift. Funds go where they were already going.

- **Arbitrary-token reentrancy via `depositWithId`.** The `token` parameter is unconstrained, so
  `safeTransferFrom` hands control to attacker code — a genuine reentrancy window. Four variants
  tried, each closed:
  1. Reenter `withdrawWithData`/`swapWithData` — `_isAuthorized` re-reads `authorized[msg.sender]`
     fresh per call, and `msg.sender` is the attacker contract, never inherited from an earlier hop.
  2. Call `BridgeVM.execute()` directly — `onlyOwner`, owner is the proxy. Verified on-chain by
     reading the proxy's storage slot 105 to recover the real `BridgeVM` address, then confirming
     its `owner()` returns the proxy exactly.
  3. `delegatecall` into `BridgeVM.execute()` while forging `_owner` in the attacker's own storage.
     The check-forging genuinely works. It's still worthless — under `delegatecall` the entire
     borrowed execution reads and writes the *caller's* storage and spends the *caller's* balance,
     so `BridgeVM`'s real funds are never touched.
  4. No other call path to `vm.execute` exists — verified across the full source.

  **What reentrancy actually buys you: nothing.** The most it gets you is emitting
  `BridgedDepositWithId` multiple times in one transaction. But the backend pays on real value
  received, not on events:

  - Emit 10 deposit events with only 1 real token transfer → backend credits ~1 real deposit and
    ignores the 9 phantom ones. (Exactly what I proved on-chain.)
  - Make 10 real deposits of your own tokens → credited for 10, but you paid for 10. No free lunch.

  Events are free; value isn't. Reentrancy multiplies the free thing, not the valuable thing.

- **`swapWithData` slippage window.** The only thing executing between the two balance reads is
  `vm.execute(datas)`, controlled by the same authorized caller. EVM atomicity means nothing can
  interleave.

- **Third-party router approvals on `BridgeVM`.** Real mechanism — approvals live in the token's
  storage, so a compromised approved router could `transferFrom` around all of `BridgeVM`'s access
  control. Checked 5 tokens × 2 routers on Optimism, all zero. **Not exhaustive** — a full historical
  `Approval` scan wasn't feasible (public RPCs cap `eth_getLogs` at 50k blocks, ~3000 chunked
  requests needed). Open, not closed.

Rhino.fi is a well known DeFi bridge. I went through 8 of the 9 in-scope assets — the zkEVM bridge
was unreachable — and it was a badass project to audit.

## Out of scope by program rules

Nearly every fund-moving function (`withdrawV2`, `withdrawWithData`, `swapWithData`, `removeFunds`,
and others) is gated only by `authorized[msg.sender]`, with no on-chain proof or signature
verification. The whole security model is trust in the authorized backend keys. The program
explicitly excludes leaked-key and privileged-address impacts, so this isn't a submittable angle —
noting it because it defines where the real attack surface is and isn't.
