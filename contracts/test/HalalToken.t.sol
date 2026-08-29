// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import { Deployers } from "./utils/Deployers.sol";
import { HalalToken } from "../src/HalalToken.sol";

contract HalalTokenTest is Deployers {
    function setUp() public {
        deployAll();
    }

    function test_InitialState() public view {
        assertEq(token.name(), "Halal");
        assertEq(token.symbol(), "HLC");
        assertEq(token.totalSupply(), 10_000_000e18);
        assertEq(token.balanceOf(address(teamVesting)), 6_000_000e18);
        assertEq(token.balanceOf(address(treasuryVesting)), 4_000_000e18);
    }

    function test_GenesisMintOnlyOnce() public {
        vm.expectRevert(HalalToken.GenesisAlreadyMinted.selector);
        vm.prank(address(timelock));
        token.initialMint(address(teamVesting), address(treasuryVesting));
    }

    function test_RevertWhen_GenesisVestingRecipientsAreSame() public {
        HalalToken freshToken = new HalalToken(address(this));
        vm.expectRevert(HalalToken.GenesisRecipientsNotDistinct.selector);
        freshToken.initialMint(address(0xBEEF), address(0xBEEF));
    }

    function test_DeployerHasNoRolesAfterSetup() public view {
        assertFalse(token.hasRole(token.DEFAULT_ADMIN_ROLE(), deployer));
        assertFalse(token.hasRole(token.MINTER_ROLE(), deployer));
        assertFalse(token.hasRole(token.BURNER_ROLE(), deployer));
    }

    function test_TimelockIsAdmin() public view {
        assertTrue(token.hasRole(token.DEFAULT_ADMIN_ROLE(), address(timelock)));
    }

    function test_PSMHasMinterRole() public view {
        assertTrue(token.hasRole(token.MINTER_ROLE(), address(psm)));
    }

    function test_PSMHasBurnerRole() public view {
        assertTrue(token.hasRole(token.BURNER_ROLE(), address(psm)));
    }

    function test_TokenHasVotes() public {
        giveVotingPower(address(0xBEEF), 1_000e18);
        assertEq(token.getVotes(address(0xBEEF)), 1_000e18);
    }

    function test_RevertWhen_UnauthorizedMint() public {
        vm.expectRevert();
        token.mint(address(this), 1e18);
    }

    function test_MinterRoleCanMint() public {
        bytes32 minterRole = token.MINTER_ROLE();
        vm.prank(address(timelock));
        token.grantRole(minterRole, address(this));
        token.mint(address(0xCAFE), 500e18);
        assertEq(token.balanceOf(address(0xCAFE)), 500e18);
    }

    function test_RevertWhen_MintOrBurnRoleTargetsEOA() public {
        bytes32 minterRole = token.MINTER_ROLE();
        bytes32 burnerRole = token.BURNER_ROLE();
        vm.startPrank(address(timelock));
        vm.expectRevert(HalalToken.RoleRecipientNotContract.selector);
        token.grantRole(minterRole, address(0xCAFE));
        vm.expectRevert(HalalToken.RoleRecipientNotContract.selector);
        token.grantRole(burnerRole, address(0xCAFE));
        vm.stopPrank();
    }

    function test_PsmCanBurnItsOwnTokens() public {
        vm.prank(address(psm));
        token.burn(0);
    }

    function test_RevertWhen_UnauthorizedBurn() public {
        vm.expectRevert();
        token.burn(1e18);
    }

    function test_RevertWhen_ZeroAdminAtDeploy() public {
        vm.expectRevert(HalalToken.ZeroAddress.selector);
        new HalalToken(address(0));
    }

    function test_PermitApproval() public {
        (address alice, uint256 aliceKey) = makeAddrAndKey("alice");
        giveVotingPower(alice, 100e18);

        uint256 deadline = block.timestamp + 1 hours;
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                token.DOMAIN_SEPARATOR(),
                keccak256(
                    abi.encode(
                        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                        alice,
                        address(0xD00D),
                        50e18,
                        token.nonces(alice),
                        deadline
                    )
                )
            )
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(aliceKey, digest);

        token.permit(alice, address(0xD00D), 50e18, deadline, v, r, s);
        assertEq(token.allowance(alice, address(0xD00D)), 50e18);
    }
}
