// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC721Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IERC721Metadata} from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Metadata.sol";
import {MembershipToken} from "../src/MembershipToken.sol";
import {MembershipBadge} from "../src/MembershipBadge.sol";

/// @dev A minting contract with no onERC721Received, to show plain contracts can hold a badge.
contract PlainMinter {
    function mintOn(MembershipBadge badge) external returns (uint256) {
        return badge.mint();
    }
}

contract MembershipBadgeTest is Test {
    uint256 internal constant THRESHOLD = 100 ether;

    MembershipToken internal token;
    MembershipBadge internal badge;

    address internal deployer = makeAddr("deployer");
    address internal alice = makeAddr("alice");
    address internal bob = makeAddr("bob");
    address internal carol = makeAddr("carol");

    function setUp() public {
        vm.startPrank(deployer);
        token = new MembershipToken();
        badge = new MembershipBadge(address(token), THRESHOLD);
        vm.stopPrank();
    }

    function _fund(address who, uint256 amount) internal {
        vm.prank(deployer);
        token.transfer(who, amount);
    }

    function _mintAs(address who) internal returns (uint256 id) {
        vm.prank(who);
        id = badge.mint();
    }

    // ------------------------------------------------------------------ construction

    function test_constructorStoresConfiguration() public view {
        assertEq(address(badge.token()), address(token));
        assertEq(badge.threshold(), THRESHOLD);
        assertEq(badge.totalMinted(), 0);
        assertEq(badge.name(), "Membership Badge");
        assertEq(badge.symbol(), "MBADGE");
    }

    function test_constructorRejectsZeroToken() public {
        vm.expectRevert(MembershipBadge.InvalidConfiguration.selector);
        new MembershipBadge(address(0), THRESHOLD);
    }

    function test_constructorRejectsZeroThreshold() public {
        vm.expectRevert(MembershipBadge.InvalidConfiguration.selector);
        new MembershipBadge(address(token), 0);
    }

    function test_constructorIsNonpayable() public {
        bytes memory code = abi.encodePacked(type(MembershipBadge).creationCode, abi.encode(address(token), THRESHOLD));
        vm.deal(address(this), 1 ether);
        address failed;
        assembly {
            failed := create(1, add(code, 0x20), mload(code))
        }
        assertEq(failed, address(0));
    }

    function test_deployerHoldsNoPrivilege() public view {
        // The deployer of the badge gets nothing: no badge, no special view state.
        assertFalse(badge.hasBadge(deployer));
        assertEq(badge.badgeOf(deployer), 0);
    }

    function test_supportsInterfaces() public view {
        assertTrue(badge.supportsInterface(type(IERC165).interfaceId));
        assertTrue(badge.supportsInterface(type(IERC721).interfaceId));
        assertTrue(badge.supportsInterface(type(IERC721Metadata).interfaceId));
    }

    // ------------------------------------------------------------------ eligibility

    function test_isEligibleFalseBelowThreshold() public {
        assertFalse(badge.isEligible(alice));
        _fund(alice, THRESHOLD - 1);
        assertFalse(badge.isEligible(alice));
    }

    function test_isEligibleTrueAtAndAboveThreshold() public {
        _fund(alice, THRESHOLD);
        assertTrue(badge.isEligible(alice));
        _fund(alice, 1);
        assertTrue(badge.isEligible(alice));
    }

    function test_isEligibleDoesNotDependOnBadge() public {
        _fund(alice, THRESHOLD);
        _mintAs(alice);
        assertTrue(badge.isEligible(alice));
    }

    function testFuzz_isEligibleMatchesBalance(uint256 balance) public {
        balance = bound(balance, 0, token.TOTAL_SUPPLY());
        _fund(alice, balance);
        assertEq(badge.isEligible(alice), balance >= THRESHOLD);
    }

    // ------------------------------------------------------------------ minting

    function test_mintSucceedsExactlyAtThreshold() public {
        _fund(alice, THRESHOLD);

        vm.expectEmit(true, true, true, true, address(badge));
        emit IERC721.Transfer(address(0), alice, 1);
        vm.expectEmit(true, true, true, true, address(badge));
        emit MembershipBadge.BadgeMinted(alice, 1);

        uint256 id = _mintAs(alice);

        assertEq(id, 1);
        assertEq(badge.ownerOf(1), alice);
        assertEq(badge.balanceOf(alice), 1);
        assertEq(badge.badgeOf(alice), 1);
        assertTrue(badge.hasBadge(alice));
        assertFalse(badge.isLapsed(alice));
        assertEq(badge.totalMinted(), 1);
    }

    function test_mintAssignsSequentialIdsStartingAtOne() public {
        _fund(alice, THRESHOLD);
        _fund(bob, THRESHOLD);
        _fund(carol, THRESHOLD);
        assertEq(_mintAs(alice), 1);
        assertEq(_mintAs(bob), 2);
        assertEq(_mintAs(carol), 3);
        assertEq(badge.badgeOf(bob), 2);
        assertEq(badge.badgeOf(carol), 3);
        assertEq(badge.totalMinted(), 3);
    }

    function test_mintDoesNotMoveTokens() public {
        _fund(alice, THRESHOLD);
        _mintAs(alice);
        assertEq(token.balanceOf(alice), THRESHOLD);
        assertEq(token.balanceOf(address(badge)), 0);
    }

    function test_mintRevertsBelowThreshold() public {
        _fund(alice, THRESHOLD - 1);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(MembershipBadge.NotEligible.selector, alice, THRESHOLD - 1, THRESHOLD));
        badge.mint();
        assertFalse(badge.hasBadge(alice));
        assertEq(badge.totalMinted(), 0);
    }

    function test_mintRevertsWithZeroBalance() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(MembershipBadge.NotEligible.selector, alice, 0, THRESHOLD));
        badge.mint();
    }

    function test_secondMintReverts() public {
        _fund(alice, THRESHOLD);
        _mintAs(alice);
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(MembershipBadge.AlreadyMember.selector, alice, 1));
        badge.mint();
        assertEq(badge.balanceOf(alice), 1);
        assertEq(badge.totalMinted(), 1);
    }

    function test_secondMintRevertsEvenWhenLapsed() public {
        _fund(alice, THRESHOLD);
        _mintAs(alice);
        vm.prank(alice);
        token.transfer(bob, THRESHOLD);
        assertTrue(badge.isLapsed(alice));
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(MembershipBadge.AlreadyMember.selector, alice, 1));
        badge.mint();
    }

    function test_mintOnlyForCaller_cannotMintForOthers() public {
        // There is no mint(address): the only mint path targets msg.sender.
        _fund(alice, THRESHOLD);
        (bool ok,) = address(badge).call(abi.encodeWithSignature("mint(address)", alice));
        assertFalse(ok);
        (ok,) = address(badge).call(abi.encodeWithSignature("safeMint(address)", alice));
        assertFalse(ok);
        assertFalse(badge.hasBadge(alice));
    }

    function test_plainContractCanMint() public {
        PlainMinter minter = new PlainMinter();
        _fund(address(minter), THRESHOLD);
        uint256 id = minter.mintOn(badge);
        assertEq(badge.ownerOf(id), address(minter));
        assertTrue(badge.hasBadge(address(minter)));
    }

    function test_sameTokensCanQualifyDifferentAddressesSequentially() public {
        // The gate is a balance snapshot: moving tokens after minting lets another address qualify.
        // The first badge stays but is reported lapsed. Documented as expected behaviour.
        _fund(alice, THRESHOLD);
        _mintAs(alice);
        vm.prank(alice);
        token.transfer(bob, THRESHOLD);
        _mintAs(bob);
        assertTrue(badge.hasBadge(alice));
        assertTrue(badge.isLapsed(alice));
        assertTrue(badge.hasBadge(bob));
        assertFalse(badge.isLapsed(bob));
    }

    // ------------------------------------------------------------------ lapsed semantics

    function test_isLapsedFalseWithoutBadge() public {
        assertFalse(badge.isLapsed(alice));
        _fund(alice, THRESHOLD - 1);
        assertFalse(badge.isLapsed(alice));
    }

    function test_badgeStaysAndIsLapsedAfterBalanceDrops() public {
        _fund(alice, THRESHOLD);
        uint256 id = _mintAs(alice);
        assertFalse(badge.isLapsed(alice));

        vm.prank(alice);
        token.transfer(bob, 1);

        assertTrue(badge.hasBadge(alice));
        assertEq(badge.ownerOf(id), alice);
        assertEq(badge.balanceOf(alice), 1);
        assertEq(badge.badgeOf(alice), id);
        assertFalse(badge.isEligible(alice));
        assertTrue(badge.isLapsed(alice));
    }

    function test_lapsedClearsWhenBalanceRecovers() public {
        _fund(alice, THRESHOLD);
        _mintAs(alice);
        vm.prank(alice);
        token.transfer(bob, THRESHOLD);
        assertTrue(badge.isLapsed(alice));

        _fund(alice, THRESHOLD);
        assertFalse(badge.isLapsed(alice));
        assertTrue(badge.hasBadge(alice));
    }

    function testFuzz_lapsedMatchesBalanceAfterMint(uint256 remaining) public {
        remaining = bound(remaining, 0, THRESHOLD);
        _fund(alice, THRESHOLD);
        _mintAs(alice);
        vm.prank(alice);
        token.transfer(bob, THRESHOLD - remaining);
        assertTrue(badge.hasBadge(alice));
        assertEq(badge.isLapsed(alice), remaining < THRESHOLD);
    }

    // ------------------------------------------------------------------ soulbound

    function _mintedBadge() internal returns (uint256 id) {
        _fund(alice, THRESHOLD);
        id = _mintAs(alice);
    }

    function test_transferFromReverts() public {
        uint256 id = _mintedBadge();
        vm.prank(alice);
        vm.expectRevert(MembershipBadge.Soulbound.selector);
        badge.transferFrom(alice, bob, id);
        assertEq(badge.ownerOf(id), alice);
    }

    function test_safeTransferFromReverts() public {
        uint256 id = _mintedBadge();
        vm.prank(alice);
        vm.expectRevert(MembershipBadge.Soulbound.selector);
        badge.safeTransferFrom(alice, bob, id);
    }

    function test_safeTransferFromWithDataReverts() public {
        uint256 id = _mintedBadge();
        vm.prank(alice);
        vm.expectRevert(MembershipBadge.Soulbound.selector);
        badge.safeTransferFrom(alice, bob, id, "");
    }

    function test_transferToSelfReverts() public {
        uint256 id = _mintedBadge();
        vm.prank(alice);
        vm.expectRevert(MembershipBadge.Soulbound.selector);
        badge.transferFrom(alice, alice, id);
    }

    function test_transferByStrangerReverts() public {
        uint256 id = _mintedBadge();
        vm.prank(bob);
        vm.expectRevert(MembershipBadge.Soulbound.selector);
        badge.transferFrom(alice, bob, id);
    }

    function test_approveReverts() public {
        uint256 id = _mintedBadge();
        vm.prank(alice);
        vm.expectRevert(MembershipBadge.Soulbound.selector);
        badge.approve(bob, id);
        assertEq(badge.getApproved(id), address(0));
    }

    function test_setApprovalForAllReverts() public {
        _mintedBadge();
        vm.prank(alice);
        vm.expectRevert(MembershipBadge.Soulbound.selector);
        badge.setApprovalForAll(bob, true);
        assertFalse(badge.isApprovedForAll(alice, bob));

        // Also reverts for an address with no badge at all.
        vm.prank(bob);
        vm.expectRevert(MembershipBadge.Soulbound.selector);
        badge.setApprovalForAll(alice, true);
    }

    function test_transferOfNonexistentTokenStillReverts() public {
        vm.prank(alice);
        vm.expectRevert();
        badge.transferFrom(alice, bob, 42);
    }

    function test_noBurnPath() public {
        uint256 id = _mintedBadge();
        (bool ok,) = address(badge).call(abi.encodeWithSignature("burn(uint256)", id));
        assertFalse(ok);
        assertEq(badge.ownerOf(id), alice);
    }

    function test_ownerOfUnmintedReverts() public {
        vm.expectRevert(abi.encodeWithSelector(IERC721Errors.ERC721NonexistentToken.selector, 1));
        badge.ownerOf(1);
    }

    // ------------------------------------------------------------------ runtime shape

    function test_runtimeHasNoDelegatecallCallcodeOrSelfdestruct() public view {
        bytes memory runtime = address(badge).code;
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
