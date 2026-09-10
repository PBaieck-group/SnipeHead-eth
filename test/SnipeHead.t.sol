// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test, console2} from "forge-std/Test.sol";
import {SnipeHead} from "../src/SnipeHead.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract SnipeHeadTest is Test {
    SnipeHead public token;

    address public owner = makeAddr("owner");
    address public alice = makeAddr("alice");
    address public bob   = makeAddr("bob");
    address public zero  = address(0);

    uint256 public constant TOTAL_SUPPLY = 1_000_000_000 * 1e18;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function setUp() public {
        token = new SnipeHead(owner);
    }

    // ─────────────────────────────────────────────
    //  Constructor / Metadata
    // ─────────────────────────────────────────────

    function test_Constructor_MintsCorrectSupply() public view {
        assertEq(token.totalSupply(), TOTAL_SUPPLY);
        assertEq(token.balanceOf(owner), TOTAL_SUPPLY);
        assertEq(token.name(), "SnipeHead");
        assertEq(token.symbol(), "SHD");
        assertEq(token.decimals(), 18);
    }

    // ─────────────────────────────────────────────
    //  Transfers
    // ─────────────────────────────────────────────

    function test_Transfer() public {
        vm.expectEmit(true, true, false, true);
        emit Transfer(owner, alice, 1_000 ether);

        vm.prank(owner);
        bool success = token.transfer(alice, 1_000 ether);
        assertTrue(success);

        assertEq(token.balanceOf(alice), 1_000 ether);
        assertEq(token.balanceOf(owner), TOTAL_SUPPLY - 1_000 ether);
    }

    function test_Transfer_ZeroAmount() public {
        vm.prank(owner);
        bool success = token.transfer(alice, 0);
        assertTrue(success);
        assertEq(token.balanceOf(alice), 0);
    }

    function test_Transfer_ToSelf() public {
        uint256 before = token.balanceOf(owner);

        vm.prank(owner);
        token.transfer(owner, 5_000 ether);

        assertEq(token.balanceOf(owner), before);
    }

    function test_Transfer_RevertsWhenInsufficientBalance() public {
        vm.prank(alice);
        vm.expectRevert();
        token.transfer(bob, 1 ether);
    }

    function test_Transfer_RevertsToZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert();
        token.transfer(zero, 100 ether);
    }

    function test_TransferFrom() public {
        vm.prank(owner);
        token.approve(alice, 5_000 ether);

        vm.expectEmit(true, true, false, true);
        emit Transfer(owner, bob, 5_000 ether);

        vm.prank(alice);
        bool success = token.transferFrom(owner, bob, 5_000 ether);
        assertTrue(success);

        assertEq(token.balanceOf(bob), 5_000 ether);
        assertEq(token.allowance(owner, alice), 0);
    }

    // ─────────────────────────────────────────────
    //  Approvals
    // ─────────────────────────────────────────────

    function test_Approve() public {
        vm.expectEmit(true, true, false, true);
        emit Approval(owner, alice, 10_000 ether);

        vm.prank(owner);
        bool success = token.approve(alice, 10_000 ether);
        assertTrue(success);
        assertEq(token.allowance(owner, alice), 10_000 ether);
    }

    function test_Approve_Infinite() public {
        vm.prank(owner);
        token.approve(alice, type(uint256).max);

        assertEq(token.allowance(owner, alice), type(uint256).max);

        // TransferFrom should not reduce infinite allowance
        vm.prank(alice);
        token.transferFrom(owner, bob, 1_000 ether);

        assertEq(token.allowance(owner, alice), type(uint256).max);
    }

    // ─────────────────────────────────────────────
    //  ERC20Permit
    // ─────────────────────────────────────────────

    function test_Permit() public {
        uint256 privateKey = 0xA11CE;
        address signer = vm.addr(privateKey);

        vm.prank(owner);
        token.transfer(signer, 100_000 ether);

        uint256 value = 25_000 ether;
        uint256 nonce = token.nonces(signer);
        uint256 deadline = block.timestamp + 1 hours;

        (uint8 v, bytes32 r, bytes32 s) = _signPermit(privateKey, signer, alice, value, nonce, deadline);

        token.permit(signer, alice, value, deadline, v, r, s);

        assertEq(token.allowance(signer, alice), value);
        assertEq(token.nonces(signer), nonce + 1);
    }

    function test_Permit_ThenTransferFrom() public {
        uint256 privateKey = 0xA11CE;
        address signer = vm.addr(privateKey);

        vm.prank(owner);
        token.transfer(signer, 50_000 ether);

        uint256 value = 20_000 ether;
        uint256 deadline = block.timestamp + 1 hours;

        (uint8 v, bytes32 r, bytes32 s) = _signPermit(privateKey, signer, alice, value, 0, deadline);
        token.permit(signer, alice, value, deadline, v, r, s);

        vm.prank(alice);
        token.transferFrom(signer, bob, value);

        assertEq(token.balanceOf(bob), value);
        assertEq(token.allowance(signer, alice), 0);
    }

    function test_Permit_RevertsWhenExpired() public {
        uint256 privateKey = 0xB0B;
        address signer = vm.addr(privateKey);

        vm.prank(owner);
        token.transfer(signer, 10_000 ether);

        uint256 deadline = block.timestamp - 1;

        (uint8 v, bytes32 r, bytes32 s) = _signPermit(privateKey, signer, alice, 1_000 ether, 0, deadline);

        vm.expectRevert();
        token.permit(signer, alice, 1_000 ether, deadline, v, r, s);
    }

    function test_Permit_RevertsWrongNonce() public {
        uint256 privateKey = 0xC0DE;
        address signer = vm.addr(privateKey);

        vm.prank(owner);
        token.transfer(signer, 10_000 ether);

        // Sign with wrong nonce
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(privateKey, signer, alice, 1_000 ether, 99, block.timestamp + 1 hours);

        vm.expectRevert();
        token.permit(signer, alice, 1_000 ether, block.timestamp + 1 hours, v, r, s);
    }

    // ─────────────────────────────────────────────
    //  Multiple operations
    // ─────────────────────────────────────────────

    function test_MultipleTransfers() public {
        vm.startPrank(owner);
        token.transfer(alice, 10_000 ether);
        token.transfer(bob, 20_000 ether);
        token.transfer(alice, 5_000 ether);
        vm.stopPrank();

        assertEq(token.balanceOf(alice), 15_000 ether);
        assertEq(token.balanceOf(bob), 20_000 ether);
        assertEq(token.balanceOf(owner), TOTAL_SUPPLY - 35_000 ether);
    }

    // ─────────────────────────────────────────────
    //  Domain Separator
    // ─────────────────────────────────────────────

    function test_DomainSeparator_IsStable() public view {
        bytes32 domain1 = token.DOMAIN_SEPARATOR();
        bytes32 domain2 = token.DOMAIN_SEPARATOR();
        assertEq(domain1, domain2);
        assertTrue(domain1 != bytes32(0));
    }

    // ─────────────────────────────────────────────
    //  Fuzz tests
    // ─────────────────────────────────────────────

    function testFuzz_Transfer(uint256 amount) public {
        amount = bound(amount, 0, TOTAL_SUPPLY);

        vm.prank(owner);
        token.transfer(alice, amount);

        assertEq(token.balanceOf(alice), amount);
        assertEq(token.balanceOf(owner), TOTAL_SUPPLY - amount);
    }

    function testFuzz_ApproveAndTransferFrom(uint256 amount) public {
        amount = bound(amount, 1, TOTAL_SUPPLY);

        vm.prank(owner);
        token.approve(alice, amount);

        vm.prank(alice);
        token.transferFrom(owner, bob, amount);

        assertEq(token.balanceOf(bob), amount);
        assertEq(token.allowance(owner, alice), 0);
    }

    // ─────────────────────────────────────────────
    //  Helpers
    // ─────────────────────────────────────────────

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

        bytes32 digest = keccak256(
            abi.encodePacked("\x19\x01", token.DOMAIN_SEPARATOR(), structHash)
        );

        return vm.sign(privateKey, digest);
    }
}