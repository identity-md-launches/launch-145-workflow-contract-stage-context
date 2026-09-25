// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title MembershipBadge
/// @notice Soulbound ERC-721 membership badge. Any address holding at least `threshold` units of the
///         membership token may mint exactly one badge for itself. Badges can never be transferred or
///         approved. A badge is kept if the holder later drops below the threshold, but `isLapsed`
///         then reports true so the site can mark the member as lapsed.
/// @dev Fully configured by the constructor: no owner, no admin functions, no upgrade path.
contract MembershipBadge is ERC721 {
    /// @notice The ERC-20 whose balance gates minting.
    IERC20 public immutable token;

    /// @notice Minimum token balance (in the token's minor units) required to mint. Immutable.
    uint256 public immutable threshold;

    /// @notice Number of badges minted so far. Token ids are assigned sequentially starting at 1.
    uint256 public totalMinted;

    mapping(address member => uint256 tokenId) private _badgeOf;

    /// @notice Emitted once per mint, alongside the standard ERC-721 `Transfer` from address(0).
    event BadgeMinted(address indexed member, uint256 indexed tokenId);

    /// @dev The caller's token balance is below the threshold.
    error NotEligible(address account, uint256 balance, uint256 required);
    /// @dev The caller already holds a badge.
    error AlreadyMember(address account, uint256 tokenId);
    /// @dev Any transfer or approval path was attempted.
    error Soulbound();
    /// @dev Constructor rejected a zero token address or a zero threshold.
    error InvalidConfiguration();

    /// @param token_ Address of the membership ERC-20.
    /// @param threshold_ Minimum balance, in minor units, needed to mint. Must be non-zero.
    constructor(address token_, uint256 threshold_) ERC721("Membership Badge", "MBADGE") {
        if (token_ == address(0) || threshold_ == 0) revert InvalidConfiguration();
        token = IERC20(token_);
        threshold = threshold_;
    }

    /// @notice Mint the caller's single badge. Reverts if the caller already has one or is not eligible.
    /// @return tokenId The id of the newly minted badge.
    function mint() external returns (uint256 tokenId) {
        address member = msg.sender;
        uint256 existing = _badgeOf[member];
        if (existing != 0) revert AlreadyMember(member, existing);
        uint256 balance = token.balanceOf(member);
        if (balance < threshold) revert NotEligible(member, balance, threshold);

        tokenId = ++totalMinted;
        _badgeOf[member] = tokenId;
        // Deliberately `_mint`, not `_safeMint`: the badge is soulbound, so the receiver hook that
        // `_safeMint` adds would only introduce an external call (and reentrancy surface) into mint().
        // forge-lint: disable-next-line(unsafe-oz-erc721-mint)
        _mint(member, tokenId);
        emit BadgeMinted(member, tokenId);
    }

    /// @notice True when `account` currently holds at least `threshold` tokens, regardless of badge status.
    function isEligible(address account) public view returns (bool) {
        return token.balanceOf(account) >= threshold;
    }

    /// @notice True when `account` holds a badge.
    function hasBadge(address account) public view returns (bool) {
        return _badgeOf[account] != 0;
    }

    /// @notice True when `account` holds a badge but its token balance is now below the threshold.
    function isLapsed(address account) public view returns (bool) {
        return hasBadge(account) && !isEligible(account);
    }

    /// @notice Token id of `account`'s badge, or 0 if it has none.
    function badgeOf(address account) external view returns (uint256) {
        return _badgeOf[account];
    }

    // ---------------------------------------------------------------------------------------------
    // Soulbound: every transfer and approval path reverts. Only minting (from == address(0)) passes.
    // ---------------------------------------------------------------------------------------------

    /// @dev Blocks transferFrom, safeTransferFrom and any burn; `_mint` passes because `from` is zero.
    function _update(address to, uint256 tokenId, address auth) internal override returns (address) {
        if (_ownerOf(tokenId) != address(0)) revert Soulbound();
        return super._update(to, tokenId, auth);
    }

    /// @inheritdoc ERC721
    function approve(address, uint256) public pure override {
        revert Soulbound();
    }

    /// @inheritdoc ERC721
    function setApprovalForAll(address, bool) public pure override {
        revert Soulbound();
    }
}
