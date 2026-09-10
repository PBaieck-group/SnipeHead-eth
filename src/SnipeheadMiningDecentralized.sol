// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title SnipeheadMiningDecentralized
/// @notice Ethereum mining contract for SnipeHead (SHD). Same reward-reserve
///         accounting as the original mining contract, plus EIP-2612 permit
///         support so users can mine/deposit without a separate approve()
///         transaction (the SHD token on Ethereum implements ERC20Permit).
contract SnipeheadMiningDecentralized is ReentrancyGuard {
    using SafeERC20 for IERC20;

    // Ethereum SHD token — verified contract, ERC20 + ERC20Permit.
    // https://etherscan.io/address/0xa1e1a6cB1F694e41a5C270542dF233673665FCd5#code
    IERC20 public constant shdToken = IERC20(0xa1e1a6cB1F694e41a5C270542dF233673665FCd5);
    IERC20Permit public constant shdTokenPermit = IERC20Permit(0xa1e1a6cB1F694e41a5C270542dF233673665FCd5);

    struct UserInfo {
        uint256 minedAmount;  // Amount of SHD currently mined by user
        uint256 rewardDebt;   // Used to calculate pending rewards correctly
    }

    uint256 public immutable rewardRate = 31771820820; // Fixed forever

    uint256 public lastRewardBlock;
    uint256 public accRewardPerShare; // Accumulated rewards per share (scaled by 1e18)

    mapping(address => UserInfo) public userInfo;
    uint256 public totalMined;

    // ── Separate accounting ─────────────────────────────────────────────────
    // rewardReserve tracks SHD deposited specifically for rewards via deposit().
    // totalMined tracks SHD mined by users via mine().
    // The two pools never overlap: rewards are only paid from rewardReserve.
    uint256 public rewardReserve;

    // Events
    event Deposited(address indexed from, uint256 amount);
    event Mined(address indexed user, uint256 amount);
    event Unmined(address indexed user, uint256 amount);
    event RewardClaimed(address indexed user, uint256 reward);
    // Emitted only if the contract ever pays out less than it owes — should
    // never fire under normal operation, since accrual is capped to
    // rewardReserve. Kept as a visible tripwire instead of silently
    // truncating the payout.
    event RewardShortfall(address indexed user, uint256 owed, uint256 paid);

    constructor() {
        lastRewardBlock = block.number;
    }

    // ── Update global reward variables ────────────────────────────────────────
    // updatePool() caps the reward it can accrue to what is actually sitting
    // in rewardReserve, preventing the pool from promising more than it can
    // pay and thereby protecting miner principal.
    function updatePool() public {
        if (block.number <= lastRewardBlock || totalMined == 0) {
            lastRewardBlock = block.number;
            return;
        }

        uint256 blocks = block.number - lastRewardBlock;
        uint256 theoreticalReward = (blocks * rewardRate * totalMined) / 1e18;

        // Cap accrual to whatever reward tokens are actually available.
        uint256 actualReward = theoreticalReward > rewardReserve
            ? rewardReserve
            : theoreticalReward;

        if (actualReward > 0) {
            // Round the same way accRewardPerShare does, THEN only pull that
            // rounded-down amount out of rewardReserve. If we instead
            // subtracted the pre-rounding actualReward, any remainder lost to
            // integer division here would be permanently burned out of
            // rewardReserve without ever becoming claimable by anyone.
            uint256 perShareDelta = (actualReward * 1e18) / totalMined;
            accRewardPerShare += perShareDelta;
            // Earmark those tokens so safeSHDTransfer knows they are spoken for.
            rewardReserve -= (perShareDelta * totalMined) / 1e18;
        }

        lastRewardBlock = block.number;
    }

    // ── View pending rewards for a user ───────────────────────────────────────
    function pendingRewards(address _user) public view returns (uint256) {
        UserInfo storage user = userInfo[_user];
        uint256 acc = accRewardPerShare;

        if (block.number > lastRewardBlock && totalMined != 0) {
            uint256 blocks = block.number - lastRewardBlock;
            uint256 theoreticalReward = (blocks * rewardRate * totalMined) / 1e18;

            uint256 actualReward = theoreticalReward > rewardReserve
                ? rewardReserve
                : theoreticalReward;

            if (actualReward > 0) {
                acc += (actualReward * 1e18) / totalMined;
            }
        }

        return (user.minedAmount * acc) / 1e18 - user.rewardDebt;
    }

    // ── Anyone can fund the reward pool (approve-first flow) ─────────────────
    function deposit(uint256 _amount) external nonReentrant {
        _deposit(_amount);
    }

    // ── Fund the reward pool using an EIP-2612 permit signature ──────────────
    // Lets the depositor skip a separate approve() transaction: they sign a
    // permit off-chain and this function submits it, then pulls the tokens.
    function depositWithPermit(
        uint256 _amount,
        uint256 _deadline,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) external nonReentrant {
        // A signed permit is visible in the mempool before this tx lands, so
        // anyone can front-run it by calling permit() on the token directly
        // with the same (v, r, s). That's harmless (it just sets the
        // allowance this contract needed anyway), but if we called permit()
        // unconditionally here it would then revert on a reused nonce and
        // grief this transaction. try/catch absorbs that: if permit()
        // fails, we fall through and rely on the allowance already being
        // sufficient from the front-run (or from a prior approve()).
        try shdTokenPermit.permit(msg.sender, address(this), _amount, _deadline, _v, _r, _s) {} catch {}
        _deposit(_amount);
    }

    function _deposit(uint256 _amount) private {
        if (_amount == 0) revert ZeroAmount();

        uint256 balanceBefore = shdToken.balanceOf(address(this));
        shdToken.safeTransferFrom(msg.sender, address(this), _amount);
        uint256 actualReceived = shdToken.balanceOf(address(this)) - balanceBefore;

        if (actualReceived == 0) revert NoTokensReceived();

        // Credit exclusively to the reward reserve — NOT to totalMined.
        rewardReserve += actualReceived;

        emit Deposited(msg.sender, actualReceived);
    }

    // ── Mine SHD tokens (approve-first flow) ──────────────────────────────────
    function mine(uint256 _amount) external nonReentrant {
        _mine(_amount);
    }

    // ── Mine SHD tokens using an EIP-2612 permit signature ────────────────────
    // Lets the miner skip a separate approve() transaction: they sign a
    // permit off-chain and this function submits it, then pulls the tokens.
    function mineWithPermit(
        uint256 _amount,
        uint256 _deadline,
        uint8 _v,
        bytes32 _r,
        bytes32 _s
    ) external nonReentrant {
        // See depositWithPermit: front-running the permit signature is
        // harmless but must not be allowed to grief/revert this tx.
        try shdTokenPermit.permit(msg.sender, address(this), _amount, _deadline, _v, _r, _s) {} catch {}
        _mine(_amount);
    }

    function _mine(uint256 _amount) private {
        if (_amount == 0) revert ZeroAmount();

        updatePool();

        UserInfo storage user = userInfo[msg.sender];

        // Claim any pending rewards before adding more mine.
        if (user.minedAmount > 0) {
            uint256 pending = (user.minedAmount * accRewardPerShare) / 1e18 - user.rewardDebt;
            if (pending > 0) {
                safeSHDTransfer(msg.sender, pending);
                emit RewardClaimed(msg.sender, pending);
            }
        }

        uint256 balanceBefore = shdToken.balanceOf(address(this));
        shdToken.safeTransferFrom(msg.sender, address(this), _amount);
        uint256 actualReceived = shdToken.balanceOf(address(this)) - balanceBefore;

        if (actualReceived == 0) revert NoTokensReceived();

        user.minedAmount += actualReceived;
        totalMined += actualReceived;
        user.rewardDebt = (user.minedAmount * accRewardPerShare) / 1e18;

        emit Mined(msg.sender, actualReceived);
    }

    // ── Unmine SHD tokens ───────────────────────────────────────────
    // Returns exactly the mined principal from the mining portion of the
    // balance. The reward reserve is never touched here.
    function unmine(uint256 _amount) external nonReentrant {
        UserInfo storage user = userInfo[msg.sender];
        if (_amount == 0 || user.minedAmount < _amount) revert InsufficientAmount();

        updatePool();

        // Claim pending rewards before unmining.
        uint256 pending = (user.minedAmount * accRewardPerShare) / 1e18 - user.rewardDebt;
        if (pending > 0) {
            safeSHDTransfer(msg.sender, pending);
            emit RewardClaimed(msg.sender, pending);
        }

        user.minedAmount -= _amount;
        totalMined -= _amount;
        user.rewardDebt = (user.minedAmount * accRewardPerShare) / 1e18;

        shdToken.safeTransfer(msg.sender, _amount);

        emit Unmined(msg.sender, _amount);
    }

    // ── Claim rewards without unmining ───────────────────────────────────────
    function claimRewards() external nonReentrant {
        updatePool();
        UserInfo storage user = userInfo[msg.sender];

        uint256 pending = (user.minedAmount * accRewardPerShare) / 1e18 - user.rewardDebt;
        if (pending == 0) revert NoRewardsToClaim();

        user.rewardDebt = (user.minedAmount * accRewardPerShare) / 1e18;
        safeSHDTransfer(msg.sender, pending);
        emit RewardClaimed(msg.sender, pending);
    }

    // ── View helpers ──────────────────────────────────────────────────────────

    // Total SHD held by the contract (mined principal + reward reserve).
    function getContractSHDBalance() public view returns (uint256) {
        return shdToken.balanceOf(address(this));
    }

    // Remaining SHD available for future rewards.
    function getRewardReserve() public view returns (uint256) {
        return rewardReserve;
    }

    // ── Internal safe transfer ────────────────────────────────────────────────
    // Transfers come from the contract balance but the amount is already
    // bounded by accRewardPerShare which was itself bounded by rewardReserve
    // in updatePool(). Miner principal is therefore never reachable by this
    // path under normal operation.
    function safeSHDTransfer(address _to, uint256 _amount) private {
        uint256 bal = shdToken.balanceOf(address(this));
        uint256 transferAmount = _amount > bal ? bal : _amount;
        if (transferAmount == 0) revert InsufficientBalance();

        // Should be unreachable under normal operation — accrual is capped
        // to rewardReserve, so bal should always cover _amount. Recorded
        // on-chain rather than silently swallowed in case that invariant
        // is ever broken.
        if (transferAmount < _amount) {
            emit RewardShortfall(_to, _amount, transferAmount);
        }

        shdToken.safeTransfer(_to, transferAmount);
    }

    // Custom errors (cheaper gas than require strings)
    error ZeroAmount();
    error InsufficientAmount();
    error NoTokensReceived();
    error NoRewardsToClaim();
    error InsufficientBalance();
}
