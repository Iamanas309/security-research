# `depositWithId` accepts arbitrary token addresses without on-chain validation

**Severity: Informational.** No loss of funds demonstrated — disproven against the live backend.

| | |
|---|---|
| Target | Rhino.fi BSC Bridge proxy `0xB80A582fa430645A043bB4f6135321ee01005fEf` |
| Implementation | `DVFDepositContract` — same `depositWithId` code on Optimism / MATIC / ARB |
| PoC | [`poc/PhantomDepositFork.t.sol`](./poc/PhantomDepositFork.t.sol) — BSC mainnet fork, live production bytecode |
| Status | Assessed as informational. Not submitted. |

## Summary

`DVFDepositContract.depositWithId(address token, uint256 amount, uint256 commitmentId)` is
permissionless and takes `token` as a fully caller-controlled address, with no allowlist and no
on-chain validation. It calls
`IERC20Upgradeable(token).safeTransferFrom(msg.sender, address(this), amount)` and then emits
`BridgedDepositWithId(msg.sender, tx.origin, token, amount, commitmentId)`.

`SafeERC20`'s `safeTransferFrom` accepts a low-level call that does not revert and returns either
empty data or `true`. A caller-deployed "token" whose `transferFrom` returns `true` while moving
nothing therefore drives `depositWithId` to completion and emits a `BridgedDepositWithId` event for
an arbitrary `amount` while transferring **zero real value**.

## Impact — a fake accounting event, and nothing more

I proved on-chain that a fake token contract drives `depositWithId` to completion and makes the
bridge emit a real accounting event for value that never moved. But the protocol doesn't only trust
that event — the backend also verifies whether the funds actually arrived.

Testing against the live production backend (`api.rhino.fi`) confirmed:

- A phantom `depositWithId` with a valid, in-TTL commitment was **never credited** on the
  destination chain, and never appeared as a tracked bridge in the backend history.
- The backend advances a bridge to `EXECUTED` only after its watcher observes a **real ERC20
  `Transfer` of the quoted token** into the contract (`depositDiscoveredAt` → `depositConfirmedAt`
  → `isConfirmed` → withdrawal). It reconciles against real token inflow, not against the contract's
  self-reported event.

So the phantom event moves no value. The residual concern is on-chain input hygiene, and the
possibility of confusing a naive event-only indexer — not theft, and not freezing of funds.
Off-chain reconciliation is the load-bearing control here, and it holds. That is why this is
informational.

## Proof of concept

Both files are in [`poc/`](./poc/). The fork test runs against the **live deployed BSC bridge**, not
a local copy — whatever Rhino actually has deployed today.

```bash
BSC_RPC_URL=https://bsc-dataseed.bnbchain.org \
  forge test --match-path test/PhantomDepositFork.t.sol -vv
```

[`FakeToken.sol`](./poc/FakeToken.sol) is a minimal "ERC20" whose `transferFrom` moves nothing and
always reports success, with instrumentation so the test can prove it actually ran:

```solidity
function transferFrom(address from, address to, uint256 amount) external returns (bool) {
    transferFromCalls += 1;
    lastFrom = from;
    lastTo = to;
    lastAmount = amount;
    // deliberately move NOTHING, just claim success
    return true;
}
```

What the test asserts against production:

```solidity
assertGt(LIVE_BRIDGE.code.length, 0, "live bridge has bytecode");
assertEq(fake.transferFromCalls(), 1, "live bridge invoked transferFrom");
assertEq(fake.lastTo(), LIVE_BRIDGE, "pull target was the live bridge");
assertEq(fake.balanceOf(LIVE_BRIDGE), bridgeBalBefore, "live bridge received 0 real value");
```

The transaction succeeds, `BridgedDepositWithId` is emitted for the full phantom amount, and the
receipt contains exactly one log — the event — with zero real-token `Transfer` logs.

## Recommendation

Validate `token` in `depositWithId` on-chain — restrict to an allowlist of supported tokens, and/or
verify a real balance delta (`balanceAfter - balanceBefore == amount`) before emitting
`BridgedDepositWithId`, so the emitted accounting event cannot reference a token that delivered no
value.
