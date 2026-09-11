# SnipeHead (SHD)

> The token, the mine, the NFT — and the legend behind the name.

SnipeHead is an ERC-20 token (`SHD`) with a decentralized, deposit-funded mining/staking contract and a limited-edition companion NFT collection (`SNFT`), deployed on Ethereum Mainnet.

---

## 📜 The Legend

> Once upon a time, there was a boy everyone called Snipehead.
>
> At school, the other kids teased him because his head was shaped like a snipehead. They laughed, pointed, and made jokes about him. But Snipehead never fought back. He turned the other cheek and kept his head held high.
>
> Then one day, an emergency struck the school.
>
> When everyone else was scared and didn't know what to do, Snipehead stepped forward. His enormous head, the very thing everyone had once made fun of, became the thing that saved them.
>
> He used his giant head to shield the kids and help everyone get to safety.
>
> From that day forward, nobody laughed at him anymore. They called him by a new name: **SNIPEHEAD THE GREAT.**
>
> And they learned that the thing that makes you different might just be the thing that makes you great.

---

## 🧱 Contracts

| Contract | File | Description |
|---|---|---|
| **SnipeHead** | [`SnipeHead.sol`](https://github.com/PBaieck-group/SnipeHead-eth/blob/main/src/SnipeHead.sol) | The `SHD` ERC-20 token (`ERC20` + `ERC20Permit`). Fixed supply of 1,000,000,000 SHD, minted entirely to the deployer/recipient at construction. |
| **SnipeheadMiningDecentralized** | [`SnipeheadMiningDecentralized.sol`](https://github.com/PBaieck-group/SnipeHead-eth/blob/main/src/SnipeheadMiningDecentralized.sol) | A reentrancy-guarded staking ("mining") contract for `SHD`. Anyone can fund a reward reserve via `deposit()`; stakers `mine()` SHD and accrue rewards from that reserve at a fixed per-block rate, capped so the contract never promises more than it holds. Supports EIP-2612 `permit()` flows to skip a separate `approve()` transaction. |
| **SnipeHeadNFT** | [`SnipeHeadNFT.sol`](https://github.com/PBaieck-group/SnipeHead-eth/blob/main/src/SnipeHeadNFT.sol) | A capped, 35-supply `ERC721` collection (`SNFT`) with `ERC721Enumerable`, `ERC721URIStorage`, and `ERC2981` royalties. Public mint is capped at 2 per wallet; owner reserve mints share the same hard cap. Metadata is served from IPFS. |
| **Addresses** | [`Addresses.sol`](https://github.com/PBaieck-group/SnipeHead-eth/blob/main/src/Addresses.sol) | Shared library of deployed Ethereum Mainnet contract addresses, for easy reference/import across scripts and other contracts. |

### Tests

Each core contract has a companion [Foundry](https://book.getfoundry.sh/) test suite:

- [`SnipeHead.t.sol`](https://github.com/PBaieck-group/SnipeHead-eth/blob/main/test/SnipeHead.t.sol)
- [`SnipeheadMiningDecentralized.t.sol`](https://github.com/PBaieck-group/SnipeHead-eth/blob/main/test/SnipeheadMiningDecentralized.t.sol)
- [`SnipeHeadNFT.t.sol`](https://github.com/PBaieck-group/SnipeHead-eth/blob/main/test/SnipeHeadNFT.t.sol)

### Front-end

- [`index.html`](https://github.com/PBaieck-group/SnipeHead-eth/blob/main/dApps/SnipeheadMining/index.html) — a lightweight, single-file dApp for interacting with the mining contract's reward pool (deposit/fund flow) directly from a browser wallet.

#### 🌐 IPFS Fallback

If [snipehead.xyz](https://snipehead.xyz) is ever unreachable, both dApps are also hosted directly on IPFS and can be run from any browser without relying on the main site:

| dApp | IPFS Link |
|---|---|
| ⛏️ Mining dApp | [bafybeibmc5fipcyunvlofyf47ileagkl7hgbnwrapbbjjgkspiwgiqswtm](https://bafybeibmc5fipcyunvlofyf47ileagkl7hgbnwrapbbjjgkspiwgiqswtm.ipfs.inbrowser.link/) |
| 🖼️ NFT dApp | [bafybeia6n6uyxr5mbuwseezxczugvjdotjipb7y4dnrxif6cirxsnrizie](https://bafybeia6n6uyxr5mbuwseezxczugvjdotjipb7y4dnrxif6cirxsnrizie.ipfs.inbrowser.link/) |

> Since these load straight from IPFS, always double-check the CID matches what's listed here before connecting your wallet or sending funds.

---

## 🚀 Getting Started

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation) (`forge`, `cast`, `anvil`)
- An Ethereum RPC endpoint (e.g. via [Alchemy](https://www.alchemy.com/) or [Infura](https://www.infura.io/))

### Installation

```bash
git clone https://github.com/PBaieck-group/SnipeHead-eth.git
cd SnipeHead-eth
forge install
```

### Build

```bash
forge build
```

### Test

```bash
forge test -vvv
```

### Deploy

```bash
forge create src/SnipeHead.sol:SnipeHead \
  --rpc-url <RPC_URL> \
  --private-key <PRIVATE_KEY> \
  --constructor-args <RECIPIENT_ADDRESS>
```

> Repeat for `SnipeheadMiningDecentralized` and `SnipeHeadNFT` with their respective constructor arguments, then update [`Addresses.sol`](https://github.com/PBaieck-group/SnipeHead-eth/blob/main/src/Addresses.sol) with the deployed addresses.

---

## 🪙 Token Details

| | |
|---|---|
| Name | SnipeHead |
| Symbol | `SHD` |
| Standard | ERC-20 + ERC-2612 (Permit) |
| Decimals | 18 |
| Total Supply | 1,000,000,000 SHD (fixed at deploy, no further minting) |
| Network | Ethereum Mainnet |

## ⛏️ Mining / Staking

- **`mine(amount)`** — deposit `SHD` to start mining; auto-claims any pending rewards first.
- **`mineWithPermit(...)`** — same as above, but uses an off-chain EIP-2612 signature instead of a prior `approve()` call.
- **`unmine(amount)`** — withdraw previously mined principal; auto-claims pending rewards first.
- **`claimRewards()`** — claim pending rewards without unmining.
- **`deposit(amount)` / `depositWithPermit(...)`** — anyone can top up the reward reserve that pays out miners.
- Rewards accrue at a fixed rate per block (`rewardRate`), strictly capped to whatever is actually sitting in the reward reserve — the contract can never promise more than it can pay, and miner principal is never touched to pay rewards.

## 🖼️ NFT Collection

| | |
|---|---|
| Name | SnipeHead NFT |
| Symbol | `SNFT` |
| Standard | ERC-721 + Enumerable + URIStorage + ERC-2981 (Royalties) |
| Max Supply | 35 |
| Per-Wallet Limit | 2 (public mint only) |
| Mint Price | **0.05 ETH** |
| Metadata | Hosted on IPFS |

Owner controls include `setMintPrice`, `setMintingActive`, `setDefaultRoyalty`, `ownerMint` (reserve/giveaway mints, sharing the same 35-token cap), and `withdraw` (pulls contract ETH balance to the owner).

---

## 🔗 Deployed Addresses (Ethereum Mainnet)

See [`Addresses.sol`](https://github.com/PBaieck-group/SnipeHead-eth/blob/main/src/Addresses.sol) for the canonical, on-chain-importable reference.

| Contract | Address |
|---|---|
| `SHD_TOKEN` | `0xa1e1a6cB1F694e41a5C270542dF233673665FCd5` |
| `MINING_CONTRACT` | `0x0AF20FaC296a4f19C68acC64FB850b699D6869e3` |
| `SNFT_CONTRACT` | `0xE85eB0a14E185968B2a947d98feA023F8e80AB3a` |

---

## 🔒 Security

- Built on [OpenZeppelin Contracts](https://github.com/OpenZeppelin/openzeppelin-contracts) (`^5.x`).
- `ReentrancyGuard` on all state-changing external entry points in the mining and NFT contracts.
- Reward accrual in the mining contract is strictly capped to the funded reserve — it can never accrue more than it can pay out.
- Effects-before-interactions ordering used around external calls (e.g. NFT minting loop).
- Custom errors used throughout the mining contract for gas efficiency.

Found a security issue? Please report it responsibly — see the `@custom:security-contact` in [`SnipeHead.sol`](https://github.com/PBaieck-group/SnipeHead-eth/blob/main/src/SnipeHead.sol).

> ⚠️ These contracts have not been externally audited. Use at your own risk.

---

## 📄 License

MIT — see individual file headers (`SPDX-License-Identifier: MIT`).
