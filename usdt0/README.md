# USDT0

Omnichain USDT / XAUt built on LayerZero's OFT standard. Reviewed against the Immunefi program
(max bounty $6,000,000, 349 assets in scope), May 2026.

**Result: no vulnerability found.** 11 chains verified independently, three distinct contract
families identified and checked. This page is about how that conclusion was reached, since a
negative result is only worth anything if you can show what would have caught a positive one.

## Scope covered

11 of 22 chains: Ethereum, Optimism, Arbitrum, Polygon PoS, Ink, Hedera, Monad, MegaEth, Flare,
Berachain, Mantle.

Not covered: Conflux, HyperEVM, Morph, Plasma, Rootstock, Sei, Stable, Tempo, Unichain, XLayer, and
Corn (blocked on dead explorer/RPC infrastructure, and its scope membership was never confirmed).

**Why I stopped at 11.** Eleven consecutive clean results across independently-verified chains was a
strong enough signal that the remainder are the same deployment scripts run again. The one genuine
deviation found — Berachain's older contract variant — was still safe.

> USDTO is a well writter and well organized code by experience developers and audited by the top tier firms
> After successfully reveiwing 11 assets, i came to a conclusion that i am not gonna find anything here, lol

## Architecture

- **Pure OFT chains** lock real USDT in Ethereum's OFT Adapter, then mint/burn USDT0 freely across
  every other OFT-enabled chain via LayerZero messaging. 1:1 backing is a system-wide aggregate
  property, not a per-transaction one.
- **Legacy Mesh** connects chains with pre-existing native USDT (Ethereum, Tron, TON, Solana, Celo)
  through Arbitrum as hub, in two hops — legacy chain to Arbitrum via a liquidity pool, then
  Arbitrum to destination via normal OFT mint/burn.
- Arbitrum is therefore a concentration point, hosting both the Legacy Mesh pool and regular OFT hub
  duty. Prioritized accordingly.

The Ethereum Adapter's own contract (`OAdapterUpgradeable.sol`) contains only a constructor and
`initialize()`. The actual lock/unlock logic backing the peg lives in LayerZero's inherited
`OFTAdapterUpgradeable`. The program's rules put referenced libraries and inherited contracts in
scope, so that inherited code is fair game — but the genuinely USDT0-specific surface on that chain
is just the constructor and initializer.

## Contract families found

The 11 chains don't all run the same Token implementation. What's actually deployed:

| Family | Chains |
|---|---|
| `ArbitrumExtensionV2` | Arbitrum |
| `TetherTokenOFTExtension` (90-line) | Optimism, Ink, Monad, MegaEth, Flare, Mantle |
| `TetherTokenOFTExtension` (51-line, older variant) | Berachain |
| `HTSConnectorUpgradeable` | Hedera |

Hedera was the genuine outlier: not a standard EVM chain, and its single contract fuses OFT logic
directly with Hedera Token Service, which explains the apparently "missing" second Token contract.
Reviewed in full.

Also verified live on every chain in the sweep: `oftContract()` matches the documented OFT address
exactly, and `owner()` matches the documented Safe.

## Also checked

- `WithBlockedList.onlyNotBlocked` — correct, not the logic inversion it resembles.
- `TetherToken._beforeTokenTransfer` — a real second layer of blocklist enforcement.
- EIP-3009 `transferWithAuthorization` / `receiveWithAuthorization` — replay protection confirmed
  correct.
- `ArbitrumExtensionV2` proxy initialization — properly initialized, not left open.
- `lzReceive` access control — `OnlyEndpoint` plus `OnlyPeer` on `_getPeerOrRevert(_origin.srcEid)`,
  which is the real backbone of the whole inbound path.

