// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * A malicious "ERC20" whose transferFrom moves nothing and always reports success.
 *
 * SafeERC20Upgradeable.safeTransferFrom performs a low-level call to
 * transferFrom and accepts it when the call does not revert AND the return
 * data is either empty or decodes to `true`. This contract returns `true`
 * while transferring zero value, so the deposit contract treats a phantom
 * deposit as real and emits its accounting event.
 */
contract FakeToken {
    string public name = "PHANTOM";
    string public symbol = "PHANTOM";
    uint8 public decimals = 18;

    // instrumentation so the test can prove transferFrom actually ran
    uint256 public transferFromCalls;
    address public lastFrom;
    address public lastTo;
    uint256 public lastAmount;

    // balances are NEVER mutated by transferFrom below — they stay zero
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        transferFromCalls += 1;
        lastFrom = from;
        lastTo = to;
        lastAmount = amount;
        // deliberately move NOTHING, just claim success
        return true;
    }

    function transfer(address, uint256) external pure returns (bool) {
        return true;
    }

    function approve(address, uint256) external pure returns (bool) {
        return true;
    }

    function totalSupply() external pure returns (uint256) {
        return 0;
    }
}
