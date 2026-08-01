# Security Research

Smart contract security reviews and notes. Mostly EVM, mostly bridges, vaults, and lending forks.

I'm Anas. I've been into crypto since 2021, started learning blockchain development in 2024, and
built cross-chain and DeFi projects in Solidity. I'm now a full-time security researcher.

---

## Reviews

| Protocol | Focus | Scope reviewed | Outcome | Date |
|---|---|---|---|---|
| [Rhino.fi](./rhino-fi/) | Cross-chain bridge | 8 of 9 in-scope assets, 5 chains | 1 informational finding, published | Jul 2026 |
| [USDT0](./usdt0/) | Omnichain OFT (LayerZero) | 11 of 22 chains | No findings | May 2026 |
| [Veda](./veda/) | Vault primitive (BoringVault) | 2 full architectures, 62 privileged entry points | 1 validation gap w/ PoC, assessed non-payable | Jul 2026 |

---

## On severity and disclosure

Every finding you see in this repository is either already patched, informational, or not
submittable under Immunefi's own rules. The purpose of making them public is pure learning.

Thank you — enjoy reading!
