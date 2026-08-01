# `BoringSolver` accepts an unvalidated `teller`, so shares can be redeemed without ever being burned

**Severity: Informational.** Not reachable under the live authority configuration as of July 2026,
and substitution-safe. A working PoC is included because the mechanism is real — but I concluded it
is **not payable**, and the reasoning is in "Why this is not payable" below. Read that section
before the PoC output.

| | |
|---|---|
| Target | `BoringSolver` — live instance `0x23aff90ed3b3effcf78fb41ab001c525a6c32a01` |
| Vault under test | Liquid ETH `0xf0bb20865277aBd641a307eCe5Ee04E79073416C` |
| PoC | mainnet fork, block 20842935, against real production contracts |
| Status | Not submitted. Published with the reachability and non-payable assessments attached. |

## Mechanism

`boringRedeemSolve`, `boringRedeemMintSolve`, `boringRedeemSelfSolve` and
`boringRedeemMintSelfSolve` all take `teller` as a caller-supplied address. The only validation, in
`_boringRedeemSolve` / `_boringRedeemMintSolve`:

```solidity
if (boringVault != address(teller.vault()))
    revert BoringSolver___BoringVaultTellerMismatch(boringVault, address(teller));
```

This checks only that the supplied `teller` *claims* to point at the right vault. A contract with a
`vault()` getter returning the real vault address satisfies it trivially. Nothing verifies `teller`
is the legitimate Teller before `teller.bulkWithdraw(...)` is called on it.

## PoC

Mainnet fork at block 20842935, against the actual production `BoringVault`,
`BoringOnChainQueue`, `BoringSolver` and `TellerWithMultiAssetSupport` — not mocks.

`MaliciousTeller` returns the real vault address from `vault()`, and its `bulkWithdraw` never calls
the vault's `exit()` at all — it pays out from its own pre-funded WETH. The queue transfers 100 real
shares to the Solver through the normal untouched flow, then `boringRedeemSolve` is called with the
malicious teller instead of the real one.

Measured:

| | |
|---|---|
| User payout | `103,514,955,618,272,503,100` wei WETH (~103.5 WETH) — full amount, as promised |
| `totalSupply()` before | `144,575,425,334,125,925,673,351` |
| `totalSupply()` after | `144,575,425,334,125,925,673,351` — **unchanged** |
| `balanceOf(BoringSolver)` after | `100,000,000,000,000,000,000` — 100 real, never-burned shares |

The shares are never burned. They end up held by the Solver contract itself — not by the caller —
where only `rescueTokens` (also `requiresAuth`) can move them. See "Why this is not payable" below.

### Running it

The test is [`MaliciousTellerPoC.t.sol`](./MaliciousTellerPoC.t.sol). It extends the boring-vault
repo's own `BoringQueueTest` harness, so it needs that repo's remappings and fork setup — it won't
compile standalone. Drop it into a clone of [`veda-labs/boring-vault`](https://github.com/veda-Labs/boring-vault)
at `test/MaliciousTellerPoC.t.sol` and run:

```bash
forge test --match-test testMaliciousTellerBypassesRealBurn -vvvv
```

## Reachability

The contract's own documentation presents self-solving as an intended user feature:

```solidity
//============================== USER SOLVE FUNCTIONS ===============================

/**
 * @notice Allows a user to solve their own request to redeem Boring Vault shares.
 */
function boringRedeemSelfSolve(BoringOnChainQueue.OnChainWithdraw calldata request, address teller)
    external
    requiresAuth
{
    if (request.user != msg.sender) revert BoringSolver___OnlySelf();
}
```

Note that `requiresAuth` sits alongside the `OnlySelf` check — the comment says "a user," but the
modifier still has to pass first. So I checked what the live authority actually grants, against the
live solver and its `RolesAuthority` `0x485Bde66Bb668a51f2372E34e45B1c6226798122`:

| Function | Selector | `isCapabilityPublic` | `getRolesWithCapability` |
|---|---|---|---|
| `boringRedeemSelfSolve` | `0x72faf4a4` | `false` | `0x0` — no roles |
| `boringRedeemMintSelfSolve` | `0x8f386608` | `false` | `0x0` — no roles |
| `boringRedeemSolve` | `0x5ff8a71f` | `false` | `0x…200000000` — one role (bit 33) |

Reproduce with:

```bash
cast call 0x485Bde66Bb668a51f2372E34e45B1c6226798122 \
  "getRolesWithCapability(address,bytes4)(bytes32)" \
  0x23aff90ed3b3effcf78fb41ab001c525a6c32a01 0x72faf4a4
```

Solmate's `isAuthorized` is `(authority != 0 && authority.canCall(...)) || user == owner`. The
capability is not public, no role holds it, and the solver's `owner()` is `0x0` — renounced. Both
halves are false for every caller. **As configured today, the self-solve entry points are unreachable
by anyone** — the `OnlySelf` check is never even reached — and only one role bit reaches
`boringRedeemSolve`.

**That is a configuration fact, not a code fact.** The validation gap lives in deployed code. What
prevents it being reached is a mutable authority config that a 4-of-6 Safe can change at any time —
and the contract's own comments say user self-solving is the intent. If that capability is ever made
public or granted to a role, every user reaching it meets an unvalidated `teller` parameter.

That is the reason this is written up rather than deleted. Not exploitable today. The gap is
durable; the thing containing it is not.

## Why this is not payable

In the worst case for the protocol and the best case for the attacker, the attacker pays to withdraw
funds they deposited themselves. They walk away with nothing extra. What's left behind is un-burned
shares sitting in the Solver contract — and the only thing that can move those is `rescueTokens`,
which is itself `requiresAuth`.

Conservation of value holds. Passing a fake teller instead of a real one doesn't change the ceiling
on what can be extracted, because the real tellers' `bulkWithdraw` is `requiresAuth` too.

## Scope of verification

The gap is confirmed present in the **live** solver's own verified source
(`0x23aff90ed3b3effcf78fb41ab001c525a6c32a01`), not only in the repo's `main` and the retired
`0xe3F8fa039fF7A8Fe42fA2C6e9DC8565EcE6f7042` instance the PoC was executed against:

- `_boringRedeemSolve` — the `boringVault != address(teller.vault())` check is the only validation.
- `_boringRedeemMintSolve` — applies that same `vault()`-only check to **both** `fromTeller` and
  `toTeller`, each equally caller-supplied. Same gap, twice.

The PoC itself was not re-executed against the live instance — the code path is confirmed by reading
its verified source, not by a second fork run.

## Recommendation

Validate `teller` against a registry or allowlist of known-legitimate Tellers, rather than trusting
a `vault()` getter the caller controls.
