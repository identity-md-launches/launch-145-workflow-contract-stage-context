# Membership contracts: integration notes

Two contracts, both in `src/`, compiled with solc 0.8.26 (optimizer on, 200 runs, `bytecode_hash = "none"`,
`evm_version = "cancun"`). Target network: Sepolia (chainId 11155111). Neither contract has an owner,
an admin function, a proxy, an upgrade path, `DELEGATECALL`, `CALLCODE` or `SELFDESTRUCT`.

The ABI JSON files in `docs/abi/` are exported with `forge inspect <Contract> abi --json` from the exact
sources in `src/` and are what the site should load.

| Contract          | Source                    | ABI                            |
| ----------------- | ------------------------- | ------------------------------ |
| `MembershipToken` | `src/MembershipToken.sol` | `docs/abi/MembershipToken.json` |
| `MembershipBadge` | `src/MembershipBadge.sol` | `docs/abi/MembershipBadge.json` |

Deployed addresses, the pool reference and ABI hashes are **not** in this repository. The frontend reads
them from the deployment handoff (`.imd/reads/deployment.json`) produced by the launch, never from
hard-coded values.

## MembershipToken (ERC-20)

| Property        | Value                                       |
| --------------- | ------------------------------------------- |
| Name / symbol   | `Membership Club Token` / `MCLUB`           |
| Decimals        | 18                                          |
| Total supply    | 1,000,000,000 MCLUB = `10^27` minor units    |
| Constructor     | no arguments, nonpayable                    |
| Minted to       | `msg.sender` of the constructor, in full    |
| Mint after that | none: there is no `mint`, no owner, no role |

`TOTAL_SUPPLY()` is a public constant returning `1_000_000_000e18`. The whole supply is minted once in
the constructor to whoever deploys it. In the evm_project launch the deployer is the ProjectFactory,
which then seeds the pool and the MerkleDistributor from that balance. Everything else is stock
OpenZeppelin 5.4.0 `ERC20`: `transfer`, `approve`, `transferFrom`, `allowance`, no fee on transfer,
no hooks, no pausing.

## MembershipBadge (soulbound ERC-721)

| Property      | Value                                                            |
| ------------- | ---------------------------------------------------------------- |
| Name / symbol | `Membership Badge` / `MBADGE`                                    |
| Constructor   | `constructor(address token, uint256 threshold)`, nonpayable      |
| Token ids     | sequential, starting at 1; `0` means "no badge"                  |
| Transfers     | every path reverts with `Soulbound()`                            |
| Approvals     | every path reverts with `Soulbound()`                            |
| Burn          | no burn function                                                 |
| `tokenURI`    | stock OpenZeppelin; returns an empty string (no base URI is set) |

### Constructor parameters

| Parameter   | Type      | Meaning                                                                            |
| ----------- | --------- | ---------------------------------------------------------------------------------- |
| `token`     | `address` | The MembershipToken address. In the manifest this is `$token`. Zero reverts.       |
| `threshold` | `uint256` | Minimum MCLUB balance **in minor units (18 decimals)** required to mint. Zero reverts. |

Both values are `immutable`; there is no setter. To change the threshold you deploy a new badge
contract. The constructor reverts with `InvalidConfiguration()` on a zero token address or a zero
threshold. Choosing the threshold (e.g. `100e18` for 100 MCLUB) is a launch-time decision recorded
in `launch.json` by the manifest assignment; the contract does not prescribe it.

### Functions

| Signature                                        | Kind    | Behaviour                                                                                                                                                                                                                       |
| ------------------------------------------------ | ------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `mint() returns (uint256 tokenId)`               | write   | Mints exactly one badge to `msg.sender`. Reverts `AlreadyMember(account, tokenId)` if the caller already has one (checked first), then `NotEligible(account, balance, required)` if `token.balanceOf(msg.sender) < threshold`. |
| `isEligible(address) returns (bool)`             | view    | `token.balanceOf(account) >= threshold`. Independent of badge status.                                                                                                                                                          |
| `hasBadge(address) returns (bool)`               | view    | True once the address has minted. Never becomes false again.                                                                                                                                                                   |
| `isLapsed(address) returns (bool)`               | view    | `hasBadge(account) && !isEligible(account)`. False for addresses with no badge.                                                                                                                                                |
| `badgeOf(address) returns (uint256)`             | view    | The address's token id, or `0` if none.                                                                                                                                                                                        |
| `token() returns (address)`                      | view    | The gating ERC-20.                                                                                                                                                                                                             |
| `threshold() returns (uint256)`                  | view    | The immutable minimum balance, in minor units.                                                                                                                                                                                 |
| `totalMinted() returns (uint256)`                | view    | Number of badges minted; equals the highest token id.                                                                                                                                                                          |
| `ownerOf`, `balanceOf`, `name`, `symbol`, `tokenURI`, `supportsInterface`, `getApproved`, `isApprovedForAll` | view | Standard ERC-721 / ERC-165. `getApproved` is always `address(0)` and `isApprovedForAll` always `false` because approvals cannot be set. |
| `transferFrom`, `safeTransferFrom` (both), `approve`, `setApprovalForAll` | write | Always revert with `Soulbound()`. The ABI still lists them because they are part of ERC-721. |

### Eligibility and lapsed semantics

- **Eligibility is a live balance check**, not a snapshot. `isEligible` reflects the caller's balance
  at the moment it is called. Buying MCLUB from the pool and then holding at least `threshold` is all
  that is required. Tokens are never locked, escrowed or moved by the badge contract.
- **One badge per address, forever.** A second `mint()` from the same address reverts even after
  the holder lapsed. There is no burn, so an address can never "reset" and mint again.
- **Lapsing.** If a badge holder's balance later drops below `threshold` (they sold or transferred
  MCLUB), the badge is kept: `ownerOf` and `hasBadge` are unchanged, `isEligible` becomes false and
  `isLapsed` becomes true. If the balance rises back to the threshold, `isLapsed` returns to false
  with no transaction needed.
- **Balances can requalify other addresses.** Because the check is live, the same MCLUB can be moved
  after minting to let a second address mint. The first address is then reported lapsed. This is
  the intended design (the badge proves membership at mint time; `isLapsed` is the ongoing
  signal), and the site should always display lapsed status next to each member.
- **Contracts can hold badges.** `mint()` uses `_mint`, not `_safeMint`, so a contract without
  `onERC721Received` can mint. There is no receiver callback and therefore no reentrancy surface in
  `mint()`; the only external call is the `balanceOf` view on the token.

### Event used by the site to list members

```solidity
event BadgeMinted(address indexed member, uint256 indexed tokenId);
```

Emitted exactly once per mint, in the same transaction as, and right after, the standard ERC-721
`Transfer(address(0), member, tokenId)`. To build the member list:

1. Query `BadgeMinted` logs on the badge address from its deployment block (topic0 =
   `keccak256("BadgeMinted(address,uint256)")`). Both `member` and `tokenId` are indexed, so the
   list can be built from topics alone with no data decoding.
2. Because badges cannot be transferred or burned, the set of `member` addresses in those logs is
   the complete and final member list; no `Transfer` events other than mints will ever exist.
3. For each member, call `isLapsed(member)` (or `isEligible`) to mark lapsed members. This is a
   view over the current token balance and should be re-read, not cached.

The ERC-721 `Transfer` event from `address(0)` is also emitted for marketplace/indexer
compatibility and carries the same information.

### Errors

| Error                                                     | When                                                  |
| --------------------------------------------------------- | ----------------------------------------------------- |
| `NotEligible(address account, uint256 balance, uint256 required)` | `mint()` with balance below threshold          |
| `AlreadyMember(address account, uint256 tokenId)`         | `mint()` from an address that already has a badge     |
| `Soulbound()`                                             | any transfer or approval call                         |
| `InvalidConfiguration()`                                  | constructor with zero token address or zero threshold |
| `ERC721NonexistentToken(uint256)` and other OZ errors     | standard ERC-721 misuse (e.g. `ownerOf` of id 0)      |

## Deployment parameters for the launch manifest

This assignment does not deploy. The manifest assignment writes `launch.json`; these are the values
the contracts require:

- Token: `MembershipToken`, no constructor arguments, 18 decimals, supply `10^27` minted to the
  factory. Compatible with the token-floor checks (whole supply to deployer, no mint path, no
  forbidden opcodes).
- Application contract: `MembershipBadge` with `constructorArgs = ["$token", <threshold>]`.
  The threshold is a plain `uint256` in minor units. No `$owner` is needed: the badge has no owner.
- Dependency order: token first, then badge. The badge's constructor only stores the token address
  and does not call it, so nothing about the token has to be initialised before the badge deploys.
- Runtime size is well under the EIP-170 limit: the badge about 4.7 KB, the token about 1.7 KB.

## Operational responsibilities and assumptions

- **No admin.** After deployment nobody, including the factory or the project owner, can change the
  threshold, mint tokens, pause, upgrade, or revoke badges. Fixing a wrong threshold means a new
  badge deployment and a new handoff to the site.
- **Threshold units.** Whoever sets the manifest threshold must express it in 18-decimal minor
  units. `100` means 100 wei of MCLUB, not 100 tokens.
- **Pool seeding and publication** are the launch's job. The site links to the pool from the
  handoff; the contracts have no knowledge of the pool.
- **Indexing.** The site is static and should read `BadgeMinted` logs via public RPC from the
  badge's deployment block onward, and `isLapsed` per member at render time.
- Tests passing (`forge test`) do not constitute an audit. An independent adversarial review is a
  separate step of the workflow before launch.
