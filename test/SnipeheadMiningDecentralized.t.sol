// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/SnipeheadMiningDecentralized.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";

// ============================================================
// Mock ERC20 + ERC20Permit
// ============================================================
contract MockSHD is IERC20, IERC20Permit {
    mapping(address => uint256) public override balanceOf;
    mapping(address => mapping(address => uint256)) public override allowance;
    mapping(address => uint256) public override nonces;
    uint256 public totalSupply;

    string public constant name = "SnipeHead";
    string public constant symbol = "SHD";
    uint8 public constant decimals = 18;

    bytes32 public constant DOMAIN_TYPEHASH =
        keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
    bytes32 public constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    function DOMAIN_SEPARATOR() public view override returns (bytes32) {
        return keccak256(
            abi.encode(DOMAIN_TYPEHASH, keccak256(bytes(name)), keccak256(bytes("1")), block.chainid, address(this))
        );
    }

    function permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        external
        override
    {
        require(block.timestamp <= deadline, "PERMIT_DEADLINE_EXPIRED");

        bytes32 structHash = keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, nonces[owner]++, deadline));

        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR(), structHash));
        address recovered = ecrecover(digest, v, r, s);
        require(recovered != address(0) && recovered == owner, "INVALID_SIGNATURE");

        allowance[owner][spender] = value;
        emit Approval(owner, spender, value);
    }

    function transfer(address to, uint256 value) external override returns (bool) {
        require(balanceOf[msg.sender] >= value, "ERC20: transfer amount exceeds balance");
        unchecked {
            balanceOf[msg.sender] -= value;
            balanceOf[to] += value;
        }
        emit Transfer(msg.sender, to, value);
        return true;
    }

    function transferFrom(address from, address to, uint256 value) external override returns (bool) {
        uint256 cur = allowance[from][msg.sender];
        if (cur != type(uint256).max) {
            require(cur >= value, "ERC20: insufficient allowance");
            unchecked {
                allowance[from][msg.sender] -= value;
            }
        }
        require(balanceOf[from] >= value, "ERC20: transfer amount exceeds balance");
        unchecked {
            balanceOf[from] -= value;
            balanceOf[to] += value;
        }
        emit Transfer(from, to, value);
        return true;
    }

    function approve(address spender, uint256 value) external override returns (bool) {
        allowance[msg.sender][spender] = value;
        emit Approval(msg.sender, spender, value);
        return true;
    }

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
        emit Transfer(address(0), to, amount);
    }
}

// ============================================================
// Test suite
// ============================================================
contract SnipeheadMiningDecentralizedTest is Test {
    // ── Constants ────────────────────────────────────────────
    address public constant HARDCODED_SHD = 0xa1e1a6cB1F694e41a5C270542dF233673665FCd5;
    uint256 public constant REWARD_RATE = 31_771_820_820;
    uint256 public constant RESERVE_SEED = 500_000_000 ether;

    uint256 public constant AMOUNT_1K = 1_000 ether;
    uint256 public constant AMOUNT_10K = 10_000 ether;
    uint256 public constant AMOUNT_50K = 50_000 ether;
    uint256 public constant AMOUNT_100K = 100_000 ether;
    uint256 public constant AMOUNT_1M = 1_000_000 ether;
    uint256 public constant AMOUNT_10M = 10_000_000 ether;
    uint256 public constant AMOUNT_50M = 50_000_000 ether;
    uint256 public constant AMOUNT_100M = 100_000_000 ether;
    uint256 public constant AMOUNT_200M = 200_000_000 ether;
    uint256 public constant AMOUNT_500M = 500_000_000 ether;

    // ── Actors ───────────────────────────────────────────────
    address public owner;
    address public user1;
    address public user2;
    address public funder;

    // ── Contracts ────────────────────────────────────────────
    SnipeheadMiningDecentralized public mining;
    MockSHD public shd;

    function setUp() public {
        owner = address(this);
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        funder = makeAddr("funder");

        // Deploy mock at the hardcoded address
        bytes memory mockCode = vm.getDeployedCode("SnipeheadMiningDecentralized.t.sol:MockSHD");
        vm.etch(HARDCODED_SHD, mockCode);
        shd = MockSHD(HARDCODED_SHD);

        // Mint balances
        shd.mint(owner, 1_000_000_000 ether);
        shd.mint(user1, 600_000_000 ether);
        shd.mint(user2, 100_000_000 ether);
        shd.mint(funder, 500_000_000 ether);

        mining = new SnipeheadMiningDecentralized();

        // Approvals
        vm.prank(user1);
        shd.approve(address(mining), type(uint256).max);
        vm.prank(user2);
        shd.approve(address(mining), type(uint256).max);
        vm.prank(funder);
        shd.approve(address(mining), type(uint256).max);
        shd.approve(address(mining), type(uint256).max);

        // Seed reward reserve
        vm.prank(funder);
        mining.deposit(RESERVE_SEED);
    }

    // ============================================================
    // Helpers
    // ============================================================
    function _expectedReward(uint256 blocks, uint256 staked, uint256 reserve) internal pure returns (uint256) {
        uint256 theoretical = (blocks * REWARD_RATE * staked) / 1e18;
        return theoretical > reserve ? reserve : theoretical;
    }

    function _signPermit(
        uint256 privateKey,
        address owner_,
        address spender,
        uint256 value,
        uint256 nonce,
        uint256 deadline
    ) internal view returns (uint8 v, bytes32 r, bytes32 s) {
        bytes32 structHash = keccak256(
            abi.encode(
                keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"),
                owner_,
                spender,
                value,
                nonce,
                deadline
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", shd.DOMAIN_SEPARATOR(), structHash));
        return vm.sign(privateKey, digest);
    }

    // ============================================================
    // Constructor
    // ============================================================
    function test_Constructor_SetsCorrectValues() public view {
        assertEq(address(mining.shdToken()), HARDCODED_SHD);
        assertEq(mining.lastRewardBlock(), block.number);
        assertEq(mining.accRewardPerShare(), 0);
        assertEq(mining.totalMined(), 0);
    }

    // ============================================================
    // deposit()
    // ============================================================
    function test_Deposit_CreditsRewardReserve() public view {
        assertEq(mining.getRewardReserve(), RESERVE_SEED);
    }

    function test_Deposit_DoesNotAffectTotalMined() public view {
        assertEq(mining.totalMined(), 0);
    }

    function test_Deposit_AnyoneCanFund() public {
        uint256 reserveBefore = mining.getRewardReserve();
        vm.prank(user2);
        mining.deposit(AMOUNT_1M);
        assertEq(mining.getRewardReserve(), reserveBefore + AMOUNT_1M);
    }

    function test_Deposit_RevertsOnZeroAmount() public {
        vm.expectRevert(SnipeheadMiningDecentralized.ZeroAmount.selector);
        mining.deposit(0);
    }

    function test_Deposit_EmitsEvent() public {
        vm.expectEmit(true, false, false, true);
        emit SnipeheadMiningDecentralized.Deposited(user2, AMOUNT_1K);
        vm.prank(user2);
        mining.deposit(AMOUNT_1K);
    }

    // ============================================================
    // depositWithPermit()
    // ============================================================
    function test_DepositWithPermit() public {
        uint256 privateKey = 0xA11CE;
        address signer = vm.addr(privateKey);

        shd.mint(signer, AMOUNT_10K);

        uint256 amount = 5_000 ether;
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = shd.nonces(signer);

        (uint8 v, bytes32 r, bytes32 s) = _signPermit(privateKey, signer, address(mining), amount, nonce, deadline);

        uint256 reserveBefore = mining.getRewardReserve();

        vm.prank(signer);
        mining.depositWithPermit(amount, deadline, v, r, s);

        assertEq(mining.getRewardReserve(), reserveBefore + amount);
    }

    // ============================================================
    // Security — principal never at risk
    // ============================================================
    function test_Security_PrincipalSafeWhenReserveEmpty() public {
        vm.prank(user1);
        mining.mine(AMOUNT_100M);

        vm.roll(block.number + 1_000_000);

        uint256 balBefore = shd.balanceOf(user1);

        vm.prank(user1);
        mining.unmine(AMOUNT_100M);

        assertGe(shd.balanceOf(user1), balBefore + AMOUNT_100M);
    }

    function test_Security_TwoStakers_BothRecoverPrincipal() public {
        vm.prank(user1);
        mining.mine(AMOUNT_100M);

        vm.prank(user2);
        mining.mine(AMOUNT_50M);

        vm.roll(block.number + 500_000);

        uint256 u1Before = shd.balanceOf(user1);
        uint256 u2Before = shd.balanceOf(user2);

        vm.prank(user1);
        mining.unmine(AMOUNT_100M);

        vm.prank(user2);
        mining.unmine(AMOUNT_50M);

        assertGe(shd.balanceOf(user1), u1Before + AMOUNT_100M);
        assertGe(shd.balanceOf(user2), u2Before + AMOUNT_50M);
    }

    function test_Security_StakedTokensNotPartOfReserve() public {
        uint256 reserveBefore = mining.getRewardReserve();

        vm.prank(user1);
        mining.mine(AMOUNT_200M);

        assertEq(mining.getRewardReserve(), reserveBefore);
    }

    // ============================================================
    // Reserve cap
    // ============================================================
    function test_ReserveCap_PendingRewardsCapAtReserve() public {
        vm.prank(user1);
        mining.mine(AMOUNT_100M);

        vm.roll(block.number + 10_000_000);

        uint256 pending = mining.pendingRewards(user1);
        assertLe(pending, RESERVE_SEED);
    }

    function test_ReserveCap_NoNewRewardsAfterReserveExhausted() public {
        vm.prank(user1);
        mining.mine(AMOUNT_100M);

        vm.roll(block.number + 160_000_000);
        mining.updatePool();
        assertEq(mining.getRewardReserve(), 0);

        uint256 accBefore = mining.accRewardPerShare();

        vm.roll(block.number + 1_000);
        mining.updatePool();

        assertEq(mining.accRewardPerShare(), accBefore);
    }

    // ============================================================
    // mine()  — WITHOUT permit
    // ============================================================
    function test_Mine_WithoutPermit() public {
        // This is the normal approve + mine flow
        vm.prank(user1);
        mining.mine(AMOUNT_1K);

        assertEq(mining.totalMined(), AMOUNT_1K);
        (uint256 minedAmount,) = mining.userInfo(user1);
        assertEq(minedAmount, AMOUNT_1K);
    }

    function test_Mine_RevertsOnZeroAmount() public {
        vm.expectRevert(SnipeheadMiningDecentralized.ZeroAmount.selector);
        vm.prank(user1);
        mining.mine(0);
    }

    function test_Mine_EmitsEvent() public {
        vm.expectEmit(true, false, false, true);
        emit SnipeheadMiningDecentralized.Mined(user1, 500 ether);
        vm.prank(user1);
        mining.mine(500 ether);
    }

    // ============================================================
    // mineWithPermit()
    // ============================================================
    function test_MineWithPermit() public {
        uint256 privateKey = 0xB0B;
        address signer = vm.addr(privateKey);

        shd.mint(signer, AMOUNT_50K);

        uint256 amount = 20_000 ether;
        uint256 deadline = block.timestamp + 1 hours;
        uint256 nonce = shd.nonces(signer);

        (uint8 v, bytes32 r, bytes32 s) = _signPermit(privateKey, signer, address(mining), amount, nonce, deadline);

        vm.prank(signer);
        mining.mineWithPermit(amount, deadline, v, r, s);

        (uint256 minedAmount,) = mining.userInfo(signer);
        assertEq(minedAmount, amount);
        assertEq(mining.totalMined(), amount);
    }

    // ============================================================
    // unmine()
    // ============================================================
    function test_Unmine_UnstakesAndClaimsRewards() public {
        vm.prank(user1);
        mining.mine(10 ether);

        vm.roll(block.number + 30);

        uint256 pending = mining.pendingRewards(user1);
        uint256 balBefore = shd.balanceOf(user1);

        vm.prank(user1);
        mining.unmine(4 ether);

        (uint256 minedAmount,) = mining.userInfo(user1);
        assertEq(minedAmount, 6 ether);
        assertEq(mining.totalMined(), 6 ether);
        assertEq(shd.balanceOf(user1), balBefore + 4 ether + pending);
    }

    function test_Unmine_RevertsOnInsufficientAmount() public {
        vm.prank(user1);
        mining.mine(10 ether);

        vm.expectRevert(SnipeheadMiningDecentralized.InsufficientAmount.selector);
        vm.prank(user1);
        mining.unmine(20 ether);
    }

    // ============================================================
    // claimRewards()
    // ============================================================
    function test_ClaimRewards_WorksCorrectly() public {
        vm.prank(user1);
        mining.mine(10 ether);

        vm.roll(block.number + 100);

        uint256 pending = mining.pendingRewards(user1);
        uint256 balBefore = shd.balanceOf(user1);

        vm.prank(user1);
        mining.claimRewards();

        assertEq(shd.balanceOf(user1), balBefore + pending);
        assertEq(mining.pendingRewards(user1), 0);
    }

    function test_ClaimRewards_RevertsWhenNoPendingRewards() public {
        vm.prank(user1);
        mining.mine(10 ether);

        vm.expectRevert(SnipeheadMiningDecentralized.NoRewardsToClaim.selector);
        vm.prank(user1);
        mining.claimRewards();
    }

    // ============================================================
    // Multi-user fairness
    // ============================================================
    function test_MultiUser_ProportionalRewards() public {
        vm.prank(user1);
        mining.mine(AMOUNT_200M);

        vm.prank(user2);
        mining.mine(AMOUNT_100M);

        vm.roll(block.number + 100);

        uint256 pending1 = mining.pendingRewards(user1);
        uint256 pending2 = mining.pendingRewards(user2);

        assertApproxEqAbs(pending1, pending2 * 2, 1);
    }

    function test_MultiUser_LateJoinerOnlyEarnsFromJoinBlock() public {
        vm.prank(user1);
        mining.mine(AMOUNT_10M);

        vm.roll(block.number + 50);

        vm.prank(user2);
        mining.mine(AMOUNT_10M);

        vm.roll(block.number + 50);

        uint256 pending1 = mining.pendingRewards(user1);
        uint256 pending2 = mining.pendingRewards(user2);

        assertGt(pending1, pending2);
    }

    // ============================================================
    // updatePool edge cases
    // ============================================================
    function test_UpdatePool_NoOpWhenSameBlock() public {
        vm.prank(user1);
        mining.mine(10 ether);

        uint256 accBefore = mining.accRewardPerShare();
        mining.updatePool();
        assertEq(mining.accRewardPerShare(), accBefore);
    }

    function test_UpdatePool_NoOpWhenTotalMinedIsZero() public {
        vm.roll(block.number + 100);
        mining.updatePool();
        assertEq(mining.accRewardPerShare(), 0);
    }

    // ============================================================
    // Fuzz tests
    // ============================================================
    function testFuzz_MineAndUnmine(uint256 amount) public {
        amount = bound(amount, 1 ether, 100_000_000 ether);

        uint256 balBefore = shd.balanceOf(user1);

        vm.prank(user1);
        mining.mine(amount);

        (uint256 mined,) = mining.userInfo(user1);
        assertEq(mined, amount);
        assertEq(mining.totalMined(), amount);

        vm.prank(user1);
        mining.unmine(amount);

        (mined,) = mining.userInfo(user1);
        assertEq(mined, 0);
        assertEq(mining.totalMined(), 0);
        assertGe(shd.balanceOf(user1), balBefore); // got principal back (+ possible rewards)
    }

    function testFuzz_Deposit(uint256 amount) public {
        amount = bound(amount, 1 ether, 50_000_000 ether);

        uint256 reserveBefore = mining.getRewardReserve();

        vm.prank(user2);
        mining.deposit(amount);

        assertEq(mining.getRewardReserve(), reserveBefore + amount);
        assertEq(mining.totalMined(), 0); // deposit never affects totalMined
    }

    // ============================================================
    // Simple invariant-style test
    // ============================================================
    function test_Invariant_ContractBalanceCoversPrincipalAndReserve() public {
        vm.prank(user1);
        mining.mine(AMOUNT_100M);

        vm.prank(user2);
        mining.mine(AMOUNT_50M);

        vm.roll(block.number + 200);
        mining.updatePool();

        uint256 contractBal = mining.getContractSHDBalance();
        uint256 totalMined = mining.totalMined();
        uint256 reserve = mining.getRewardReserve();

        // Contract must always hold at least the mined principal + remaining reserve
        assertGe(contractBal, totalMined + reserve);
    }
}
