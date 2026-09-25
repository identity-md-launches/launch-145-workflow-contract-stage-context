// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {MembershipToken} from "../src/MembershipToken.sol";

contract MembershipTokenTest is Test {
    uint256 internal constant EXPECTED_SUPPLY = 1_000_000_000 * 1e18;

    MembershipToken internal token;
    address internal deployer = makeAddr("deployer");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");

    function setUp() public {
        vm.prank(deployer);
        token = new MembershipToken();
    }

    // ------------------------------------------------------------------ construction

    function test_metadata() public view {
        assertEq(token.name(), "Membership Club Token");
        assertEq(token.symbol(), "MCLUB");
        assertEq(token.decimals(), 18);
    }

    function test_fixedSupplyMintedToDeployer() public view {
        assertEq(token.TOTAL_SUPPLY(), EXPECTED_SUPPLY);
        assertEq(token.totalSupply(), EXPECTED_SUPPLY);
        assertEq(token.totalSupply(), 1e27);
        assertEq(token.balanceOf(deployer), EXPECTED_SUPPLY);
    }

    function test_constructorEmitsSingleMintTransfer() public {
        vm.expectEmit(true, true, true, true);
        emit IERC20.Transfer(address(0), deployer, EXPECTED_SUPPLY);
        vm.prank(deployer);
        new MembershipToken();
    }

    function test_constructorHasNoArgumentsAndIsNonpayable() public {
        // Creation code without any appended arguments deploys fine.
        bytes memory code = type(MembershipToken).creationCode;
        address deployed;
        assembly {
            deployed := create(0, add(code, 0x20), mload(code))
        }
        assertTrue(deployed != address(0));
        assertEq(MembershipToken(deployed).balanceOf(address(this)), EXPECTED_SUPPLY);

        // Sending value with the deployment reverts (nonpayable constructor).
        vm.deal(address(this), 1 ether);
        address failed;
        assembly {
            failed := create(1, add(code, 0x20), mload(code))
        }
        assertEq(failed, address(0));
    }

    // ------------------------------------------------------------------ no mint path

    function test_noMintSelectorExists() public {
        string[6] memory signatures = [
            "mint(address,uint256)",
            "mint(uint256)",
            "mint()",
            "issue(uint256)",
            "transferOwnership(address)",
            "setMinter(address)"
        ];
        for (uint256 i; i < signatures.length; ++i) {
            bytes memory data = abi.encodeWithSignature(signatures[i], deployer, uint256(1));
            vm.prank(deployer);
            (bool ok,) = address(token).call(data);
            assertFalse(ok, signatures[i]);
            assertEq(token.totalSupply(), EXPECTED_SUPPLY, signatures[i]);
        }
    }

    function testFuzz_supplyIsConservedByTransfers(uint256 amount, uint256 back) public {
        amount = bound(amount, 0, EXPECTED_SUPPLY);
        back = bound(back, 0, amount);

        vm.prank(deployer);
        token.transfer(alice, amount);
        vm.prank(alice);
        token.transfer(bob, back);

        assertEq(token.totalSupply(), EXPECTED_SUPPLY);
        assertEq(token.balanceOf(deployer) + token.balanceOf(alice) + token.balanceOf(bob), EXPECTED_SUPPLY);
        assertEq(token.balanceOf(alice), amount - back);
        assertEq(token.balanceOf(bob), back);
    }

    // ------------------------------------------------------------------ standard ERC-20 behaviour

    function test_transferMovesExactAmount() public {
        vm.prank(deployer);
        assertTrue(token.transfer(alice, 5 ether));
        assertEq(token.balanceOf(alice), 5 ether);
        assertEq(token.balanceOf(deployer), EXPECTED_SUPPLY - 5 ether);
    }

    function test_transferRevertsWhenBalanceInsufficient() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientBalance.selector, alice, 0, 1));
        token.transfer(bob, 1);
    }

    function test_approveAndTransferFrom() public {
        vm.prank(deployer);
        token.approve(alice, 10 ether);
        assertEq(token.allowance(deployer, alice), 10 ether);

        vm.prank(alice);
        assertTrue(token.transferFrom(deployer, bob, 4 ether));
        assertEq(token.balanceOf(bob), 4 ether);
        assertEq(token.allowance(deployer, alice), 6 ether);
    }

    function test_transferFromRevertsBeyondAllowance() public {
        vm.prank(deployer);
        token.approve(alice, 1 ether);
        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, alice, 1 ether, 2 ether)
        );
        token.transferFrom(deployer, bob, 2 ether);
    }

    function test_runtimeHasNoDelegatecallCallcodeOrSelfdestruct() public view {
        bytes memory runtime = address(token).code;
        assertGt(runtime.length, 0);
        assertLe(runtime.length, 24_576);
        for (uint256 i; i < runtime.length; ++i) {
            uint8 op = uint8(runtime[i]);
            if (op >= 0x60 && op <= 0x7f) {
                i += op - 0x5f;
                continue;
            }
            assertTrue(op != 0xf4 && op != 0xf2 && op != 0xff, "forbidden opcode");
        }
    }
}
