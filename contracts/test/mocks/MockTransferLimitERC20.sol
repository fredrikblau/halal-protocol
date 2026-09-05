// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice Test-only reserve token that rejects transfers above a fixed anti-whale limit.
/// Minting is unrestricted so tests can distinguish a token transfer failure from a balance
/// shortage. The limit applies only to transfers between accounts, not minting or burning.
contract MockTransferLimitERC20 is ERC20 {
    uint256 public immutable maxTransfer;

    error TransferLimitExceeded(uint256 amount, uint256 maxTransfer);

    constructor(uint256 maxTransfer_) ERC20("Transfer Limit DAI", "tlDAI") {
        maxTransfer = maxTransfer_;
    }

    function decimals() public pure override returns (uint8) {
        return 18;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function _update(address from, address to, uint256 value) internal override {
        if (from != address(0) && to != address(0) && value > maxTransfer) {
            revert TransferLimitExceeded(value, maxTransfer);
        }
        super._update(from, to, value);
    }
}
