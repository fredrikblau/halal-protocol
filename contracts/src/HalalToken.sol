// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import { ERC20Votes } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { Nonces } from "@openzeppelin/contracts/utils/Nonces.sol";

/// @title HalalToken (HLC)
/// @notice Governance + settlement token for the Halal protocol. ERC20Votes for snapshot-based
/// governance, ERC20Permit for gasless approvals, and AccessControl-gated minting/burning so the
/// PSM and any future accounting-aware module can be granted narrow rights by DAO vote without
/// redeploying the token (see AddingFeature.md in the repo docs for the extension pattern).
///
/// Genesis supply is minted via `initialMint`, not the constructor: vesting contracts need this
/// token's address to be deployed, so the token must exist first with an empty supply, then have
/// `initialMint` called once the vesting contracts are live. This avoids predicting contract
/// addresses ahead of deployment.
contract HalalToken is ERC20, ERC20Permit, ERC20Votes, AccessControl {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant BURNER_ROLE = keccak256("BURNER_ROLE");

    uint256 public constant TEAM_ALLOCATION = 6_000_000e18;
    uint256 public constant TREASURY_ALLOCATION = 4_000_000e18;

    bool public genesisMinted;

    error ZeroAddress();
    error NotContract();
    error RoleRecipientNotContract();
    error GenesisAlreadyMinted();
    error GenesisRecipientsNotDistinct();

    /// @param admin Temporary deployer-controlled admin; deploy script must transfer this to the DAO
    /// timelock and revoke the deployer's own admin role once the full system is wired up. The
    /// deployer is deliberately not a minter; deployment grants MINTER_ROLE only to the PSM.
    constructor(address admin) ERC20("Halal", "HLC") ERC20Permit("Halal") {
        if (admin == address(0)) revert ZeroAddress();
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
    }

    /// @notice One-time genesis mint of the fixed 6M/4M team/treasury allocation. Callable once by
    /// whoever holds DEFAULT_ADMIN_ROLE at deploy time (the deployer, before roles are handed to the
    /// DAO).
    function initialMint(address teamVesting, address treasuryVesting) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (genesisMinted) revert GenesisAlreadyMinted();
        if (teamVesting == address(0) || treasuryVesting == address(0)) revert ZeroAddress();
        if (teamVesting == treasuryVesting) revert GenesisRecipientsNotDistinct();
        // Genesis balances are intentionally held by vesting contracts, not externally owned
        // accounts. Since this one-time mint cannot be corrected after execution, reject a
        // mistyped or undeployed recipient before any supply is created.
        if (teamVesting.code.length == 0 || treasuryVesting.code.length == 0) revert NotContract();
        genesisMinted = true;
        _mint(teamVesting, TEAM_ALLOCATION);
        _mint(treasuryVesting, TREASURY_ALLOCATION);
    }

    /// @notice Mints new HLC. Restricted to MINTER_ROLE, which the DAO grants to the PSM (collateralized
    /// mint/burn against deposited reserves) and, on a case-by-case governance vote, to future modules.
    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) {
        _mint(to, amount);
    }

    /// @notice Grants a minting or accounting-aware burning role only to deployed modules.
    /// Governance may still grant other roles to addresses such as the temporary deployment
    /// administrator, but an EOA must never become an independent token issuer or burner.
    function grantRole(bytes32 role, address account) public override onlyRole(getRoleAdmin(role)) {
        if ((role == MINTER_ROLE || role == BURNER_ROLE) && account.code.length == 0) {
            revert RoleRecipientNotContract();
        }
        _grantRole(role, account);
    }

    /// @notice Burns HLC through an accounting-aware protocol module such as HalalPSM.
    ///
    /// A public self-burn would let a PSM depositor destroy HLC without reducing that address's
    /// redemption credit, leaving the corresponding reserve claim stranded and breaking the
    /// supply/accounting relationship. Grant BURNER_ROLE only to modules that retire their own
    /// claims atomically; ordinary holders should use that module's cancellation or withdrawal
    /// entrypoint instead.
    function burn(uint256 amount) external onlyRole(BURNER_ROLE) {
        _burn(msg.sender, amount);
    }

    function _update(address from, address to, uint256 value) internal override(ERC20, ERC20Votes) {
        super._update(from, to, value);
    }

    function nonces(address owner) public view override(ERC20Permit, Nonces) returns (uint256) {
        return super.nonces(owner);
    }
}
