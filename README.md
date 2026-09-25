# Membership Club: token-gated soulbound badge

Foundry project for a token-gated membership club on Sepolia.

- `MembershipToken` (`MCLUB`): fixed-supply ERC-20, 1,000,000,000 tokens with 18 decimals, minted
  once to the deployer in the constructor. No mint, owner or admin path afterwards.
- `MembershipBadge` (`MBADGE`): soulbound ERC-721. Any address holding at least `threshold` MCLUB can
  call `mint()` once to receive a badge. Transfers and approvals always revert. If a holder later
  drops below the threshold the badge stays but `isLapsed(holder)` reports `true`. Each mint emits
  `BadgeMinted(member, tokenId)` so a site can build the member list from logs.

Full integration notes, constructor parameters, eligibility/lapsed semantics and the member-list
event are in [`docs/contracts.md`](docs/contracts.md). ABI JSON is in [`docs/abi/`](docs/abi/).

## Layout

```
src/MembershipToken.sol        fixed-supply ERC-20
src/MembershipBadge.sol        soulbound ERC-721 badge
test/MembershipToken.t.sol     token tests
test/MembershipBadge.t.sol     badge tests (eligibility, mint, lapsed, soulbound, runtime shape)
docs/abi/*.json                exported ABIs (forge inspect <Contract> abi --json)
docs/contracts.md              integration notes
lib/forge-std                  vendored forge-std 1.11.0 (src only, plain files)
lib/openzeppelin-contracts     vendored OpenZeppelin Contracts 5.4.0 (contracts only, plain files)
```

Dependencies are committed as ordinary files, not git submodules, so the project builds and tests
offline from a plain checkout.

## Build and test

```
forge build
forge test
forge fmt --check
```

Compiler: solc 0.8.26, optimizer 200 runs, `bytecode_hash = "none"`, `evm_version = "cancun"`.
`ffi` is off and `fs_permissions` is empty.

## Deployment

Deployment on Sepolia, pool seeding and publication are done by the control plane's `evm_project`
launch through the ProjectFactory, described by `launch.json` from the manifest assignment. This
repository does not deploy anything and contains no scripts that broadcast transactions.

Manifest inputs the contracts require:

| Contract          | Constructor args              | Notes                                                 |
| ----------------- | ----------------------------- | ----------------------------------------------------- |
| `MembershipToken` | none                          | 18 decimals, supply `10^27` minted to `msg.sender`    |
| `MembershipBadge` | `["$token", <threshold>]`     | threshold in 18-decimal minor units, must be non-zero |

The badge has no owner, so `$owner` is not used. There is no admin path: a wrong threshold can only be
fixed by deploying a new badge contract.

## Security notes

- Neither contract uses `DELEGATECALL`, `CALLCODE`, `SELFDESTRUCT`, proxies or initialisers.
- The badge never takes custody of tokens; eligibility is a live `balanceOf` read.
- `mint()` uses `_mint` (no receiver callback), so there is no reentrancy surface.
- Passing tests are not an audit. The workflow's independent adversarial review is a separate step.
