// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @notice Test-only reserve token whose issuer can change one account's balance without a PSM call.
/// This models rebases and other external balance changes that can make a previously funded PSM
/// temporarily under-reserved.
contract MockRebasingERC20 is ERC20 {
    constructor() ERC20("Rebasing DAI", "rDAI") { }

    function decimals() public pure override returns (uint8) {
        return 18;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function rebase(address account, int256 delta) external {
        if (delta > 0) {
            _mint(account, uint256(delta));
        } else if (delta < 0) {
            _burn(account, uint256(-delta));
        }
    }
}
