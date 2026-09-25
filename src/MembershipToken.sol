// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title MembershipToken
/// @notice Fixed-supply ERC-20 used to qualify for the membership badge.
/// @dev The whole supply is minted once, to the deployer, inside the constructor. There is no mint
///      function, no owner and no admin path of any kind after construction. When launched through
///      the project factory the deployer is the factory, which then seeds the pool and distributor.
contract MembershipToken is ERC20 {
    /// @notice Total supply, fixed forever: 1,000,000,000 tokens with 18 decimals (10^27 minor units).
    uint256 public constant TOTAL_SUPPLY = 1_000_000_000 ether;

    constructor() ERC20("Membership Club Token", "MCLUB") {
        _mint(msg.sender, TOTAL_SUPPLY);
    }
}
