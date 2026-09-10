// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Test} from "forge-std/Test.sol";
import {SnipeHeadNFT} from "../src/SnipeHeadNFT.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC721Enumerable} from "@openzeppelin/contracts/token/ERC721/extensions/IERC721Enumerable.sol";
import {IERC2981} from "@openzeppelin/contracts/interfaces/IERC2981.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

contract SnipeHeadNFTTest is Test {
    SnipeHeadNFT nft;

    address owner = makeAddr("owner");
    address royaltyReceiver = makeAddr("royaltyReceiver");
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");

    uint96 constant ROYALTY_BPS = 250; // 2.5%
    uint256 constant PRICE = 0.05 ether;

    function setUp() public {
        vm.prank(owner);
        nft = new SnipeHeadNFT(owner, royaltyReceiver, ROYALTY_BPS);
    }

    // ---------- Deployment / Initial State ----------

    function test_InitialState() public view {
        assertEq(nft.owner(), owner);
        assertEq(nft.name(), "SnipeHead NFT");
        assertEq(nft.symbol(), "SNFT");
        assertTrue(nft.mintingActive());          // starts active
        assertEq(nft.mintPrice(), PRICE);
        assertEq(nft.totalMinted(), 0);
        assertEq(nft.MAX_SUPPLY(), 35);
        assertEq(nft.MAX_PER_WALLET(), 2);
    }

    function test_RoyaltyInfo() public view {
        (address receiver, uint256 amount) = nft.royaltyInfo(1, 10_000 ether);
        assertEq(receiver, royaltyReceiver);
        assertEq(amount, (10_000 ether * ROYALTY_BPS) / 10_000);
    }

    // ---------- Public Mint - Happy Paths ----------

    function test_PublicMint_Success() public {
        vm.deal(alice, PRICE);

        vm.prank(alice);
        nft.mint{value: PRICE}(1);

        assertEq(nft.ownerOf(1), alice);
        assertEq(nft.totalMinted(), 1);
        assertEq(nft.mintedPerWallet(alice), 1);
        assertEq(address(nft).balance, PRICE);
    }

    function test_PublicMint_MaxPerWallet() public {
        vm.deal(alice, PRICE * 2);

        vm.prank(alice);
        nft.mint{value: PRICE * 2}(2);

        assertEq(nft.balanceOf(alice), 2);
        assertEq(nft.ownerOf(1), alice);
        assertEq(nft.ownerOf(2), alice);
        assertEq(nft.mintedPerWallet(alice), 2);
    }

    // ---------- Payment Validation ----------

    function test_RevertWhen_IncorrectPayment_Underpay() public {
        vm.deal(alice, PRICE);

        vm.prank(alice);
        vm.expectRevert("Incorrect ETH sent");
        nft.mint{value: PRICE - 1}(1);
    }

    function test_RevertWhen_IncorrectPayment_Overpay() public {
        vm.deal(alice, PRICE + 1 ether);

        vm.prank(alice);
        vm.expectRevert("Incorrect ETH sent");
        nft.mint{value: PRICE + 1}(1);
    }

    function test_RevertWhen_ZeroQuantity() public {
        vm.prank(alice);
        vm.expectRevert("Quantity must be > 0");
        nft.mint{value: 0}(0);
    }

    // ---------- Per-wallet Cap ----------

    function test_RevertWhen_ExceedsPerWalletCap() public {
        vm.deal(alice, PRICE * 3);

        vm.startPrank(alice);
        nft.mint{value: PRICE * 2}(2);
        vm.expectRevert("Exceeds per-wallet limit");
        nft.mint{value: PRICE}(1);
        vm.stopPrank();
    }

    function test_PerWalletCap_IndependentBetweenWallets() public {
        vm.deal(alice, PRICE * 2);
        vm.deal(bob, PRICE * 2);

        vm.prank(alice);
        nft.mint{value: PRICE * 2}(2);

        vm.prank(bob);
        nft.mint{value: PRICE * 2}(2);

        assertEq(nft.balanceOf(alice), 2);
        assertEq(nft.balanceOf(bob), 2);
    }

    // ---------- Max Supply ----------

    function test_RevertWhen_ExceedsMaxSupply() public {
        // Fill entire supply with ownerMint to distinct addresses
        for (uint256 i = 0; i < 35; i++) {
            address minter = address(uint160(1000 + i));
            vm.prank(owner);
            nft.ownerMint(minter, 1);
        }

        assertEq(nft.totalMinted(), 35);

        vm.deal(alice, PRICE);
        vm.prank(alice);
        vm.expectRevert("Exceeds max supply");
        nft.mint{value: PRICE}(1);

        vm.prank(owner);
        vm.expectRevert("Exceeds max supply");
        nft.ownerMint(alice, 1);
    }

    function test_PublicMint_ExactRemainingSupply() public {
        // Leave exactly 2 tokens
        for (uint256 i = 0; i < 33; i++) {
            address minter = address(uint160(2000 + i));
            vm.prank(owner);
            nft.ownerMint(minter, 1);
        }

        vm.deal(alice, PRICE * 2);
        vm.prank(alice);
        nft.mint{value: PRICE * 2}(2);

        assertEq(nft.totalMinted(), 35);

        vm.deal(bob, PRICE);
        vm.prank(bob);
        vm.expectRevert("Exceeds max supply");
        nft.mint{value: PRICE}(1);
    }

    function test_Mint_LastToken_Succeeds_ThenFails() public {
        // Mint 34 tokens via ownerMint
        for (uint256 i = 0; i < 34; i++) {
            address minter = address(uint160(3000 + i));
            vm.prank(owner);
            nft.ownerMint(minter, 1);
        }
        assertEq(nft.totalMinted(), 34);

        // Mint the final (35th) token
        vm.deal(alice, PRICE);
        vm.prank(alice);
        nft.mint{value: PRICE}(1);

        assertEq(nft.totalMinted(), 35);
        assertEq(nft.ownerOf(35), alice);

        // Any further mint must fail
        vm.deal(bob, PRICE);
        vm.prank(bob);
        vm.expectRevert("Exceeds max supply");
        nft.mint{value: PRICE}(1);

        vm.prank(owner);
        vm.expectRevert("Exceeds max supply");
        nft.ownerMint(bob, 1);
    }

    // ---------- Owner Mint ----------

    function test_OwnerMint_Success() public {
        vm.prank(owner);
        nft.ownerMint(alice, 3);

        assertEq(nft.balanceOf(alice), 3);
        assertEq(nft.totalMinted(), 3);
        assertEq(nft.mintedPerWallet(alice), 0); // does not count toward public limit
    }

    function test_RevertWhen_NonOwnerCallsOwnerMint() public {
        vm.prank(alice);
        vm.expectRevert();
        nft.ownerMint(alice, 1);
    }

    function test_OwnerMint_DoesNotAffectPublicCap() public {
        vm.prank(owner);
        nft.ownerMint(alice, 2); // reserve

        vm.deal(alice, PRICE * 2);
        vm.prank(alice);
        nft.mint{value: PRICE * 2}(2); // still allowed

        assertEq(nft.balanceOf(alice), 4);
        assertEq(nft.mintedPerWallet(alice), 2);
    }

    function test_OwnerMint_WorksWhilePublicMintingPaused() public {
        vm.prank(owner);
        nft.setMintingActive(false);

        // Public mint should fail
        vm.deal(alice, PRICE);
        vm.prank(alice);
        vm.expectRevert("Minting not active");
        nft.mint{value: PRICE}(1);

        // Owner mint should still succeed
        vm.prank(owner);
        nft.ownerMint(bob, 2);

        assertEq(nft.balanceOf(bob), 2);
        assertEq(nft.totalMinted(), 2);
    }

    function test_RevertWhen_OwnerMintToZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert();
        nft.ownerMint(address(0), 1);
    }

    function test_OwnerMint_ToContract_WithReceiver() public {
        GoodReceiver good = new GoodReceiver();
        vm.prank(owner);
        nft.ownerMint(address(good), 1);
        assertEq(nft.ownerOf(1), address(good));
    }

    function test_RevertWhen_OwnerMintToContract_WithoutReceiver() public {
        NonReceiver bad = new NonReceiver();
        vm.prank(owner);
        vm.expectRevert();
        nft.ownerMint(address(bad), 1);
    }

    // ---------- tokenURI ----------

    function test_TokenURI_Padding() public {
        vm.prank(owner);
        nft.ownerMint(owner, 12);

        assertEq(
            nft.tokenURI(1),
            "ipfs://bafybeiaathkuhqmyfvjssilwqeri57cbe3n3ely7ga2iipqhxjtx52k4ju/001.json"
        );
        assertEq(
            nft.tokenURI(9),
            "ipfs://bafybeiaathkuhqmyfvjssilwqeri57cbe3n3ely7ga2iipqhxjtx52k4ju/009.json"
        );
        assertEq(
            nft.tokenURI(12),
            "ipfs://bafybeiaathkuhqmyfvjssilwqeri57cbe3n3ely7ga2iipqhxjtx52k4ju/012.json"
        );
    }

    function test_TokenURI_LastToken() public {
        // Mint all the way to token 35
        for (uint256 i = 0; i < 35; i++) {
            address minter = address(uint160(4000 + i));
            vm.prank(owner);
            nft.ownerMint(minter, 1);
        }

        assertEq(
            nft.tokenURI(35),
            "ipfs://bafybeiaathkuhqmyfvjssilwqeri57cbe3n3ely7ga2iipqhxjtx52k4ju/035.json"
        );
    }

    function test_RevertWhen_TokenURI_Nonexistent() public {
        vm.expectRevert();
        nft.tokenURI(1);
    }

    // ---------- Owner Controls ----------

    function test_SetMintPrice() public {
        uint256 newPrice = 0.08 ether;
        vm.prank(owner);
        nft.setMintPrice(newPrice);
        assertEq(nft.mintPrice(), newPrice);

        vm.deal(alice, newPrice);
        vm.prank(alice);
        nft.mint{value: newPrice}(1);
        assertEq(nft.balanceOf(alice), 1);
    }

    function test_RevertWhen_NonOwnerSetsMintPrice() public {
        vm.prank(alice);
        vm.expectRevert();
        nft.setMintPrice(1 ether);
    }

    function test_SetMintingActive_CanPauseAndUnpause() public {
        vm.prank(owner);
        nft.setMintingActive(false);

        vm.deal(alice, PRICE);
        vm.prank(alice);
        vm.expectRevert("Minting not active");
        nft.mint{value: PRICE}(1);

        vm.prank(owner);
        nft.setMintingActive(true);

        vm.prank(alice);
        nft.mint{value: PRICE}(1);
        assertEq(nft.balanceOf(alice), 1);
    }

    function test_RevertWhen_MintingPaused() public {
        vm.prank(owner);
        nft.setMintingActive(false);

        vm.deal(alice, PRICE);
        vm.prank(alice);
        vm.expectRevert("Minting not active");
        nft.mint{value: PRICE}(1);
    }

    function test_SetDefaultRoyalty() public {
        address newReceiver = makeAddr("newReceiver");
        uint96 newBps = 100; // 1%

        vm.prank(owner);
        nft.setDefaultRoyalty(newReceiver, newBps);

        (address receiver, uint256 amount) = nft.royaltyInfo(1, 10_000 ether);
        assertEq(receiver, newReceiver);
        assertEq(amount, (10_000 ether * newBps) / 10_000);
    }

    // ---------- Withdraw ----------

    function test_Withdraw_Success() public {
        vm.deal(alice, PRICE);
        vm.prank(alice);
        nft.mint{value: PRICE}(1);

        uint256 ownerBalBefore = owner.balance;

        vm.prank(owner);
        nft.withdraw();

        assertEq(address(nft).balance, 0);
        assertEq(owner.balance, ownerBalBefore + PRICE);
    }

    function test_RevertWhen_NonOwnerWithdraws() public {
        vm.prank(alice);
        vm.expectRevert();
        nft.withdraw();
    }

    function test_RevertWhen_WithdrawWithZeroBalance() public {
        vm.prank(owner);
        vm.expectRevert("Nothing to withdraw");
        nft.withdraw();
    }

    function test_Withdraw_FollowsCurrentOwner() public {
        vm.deal(alice, PRICE);
        vm.prank(alice);
        nft.mint{value: PRICE}(1);

        vm.prank(owner);
        nft.transferOwnership(bob);

        uint256 bobBalBefore = bob.balance;

        vm.prank(bob);
        nft.withdraw();

        assertEq(bob.balance, bobBalBefore + PRICE);
        assertEq(address(nft).balance, 0);
    }

    // ---------- Ownership ----------

    function test_TransferOwnership() public {
        vm.prank(owner);
        nft.transferOwnership(alice);
        assertEq(nft.owner(), alice);
    }

    function test_RenounceOwnership_LocksAdminAndFunds() public {
        vm.deal(alice, PRICE);
        vm.prank(alice);
        nft.mint{value: PRICE}(1);

        vm.prank(owner);
        nft.renounceOwnership();

        assertEq(nft.owner(), address(0));

        // Admin functions locked
        vm.expectRevert();
        nft.setMintingActive(false);

        // Funds permanently locked
        vm.prank(owner);
        vm.expectRevert();
        nft.withdraw();

        assertEq(address(nft).balance, PRICE);
    }

    // ---------- Reentrancy ----------

    function test_Reentrancy_BlockedOnMint() public {
        MaliciousMinter attacker = new MaliciousMinter(nft, PRICE);
        vm.deal(address(attacker), PRICE * 2);

        vm.expectRevert();
        attacker.attack();

        assertEq(nft.balanceOf(address(attacker)), 0);
    }

    // ---------- supportsInterface ----------

    function test_SupportsInterface() public view {
        assertTrue(nft.supportsInterface(type(IERC721).interfaceId));
        assertTrue(nft.supportsInterface(type(IERC721Enumerable).interfaceId));
        assertTrue(nft.supportsInterface(type(IERC2981).interfaceId));
        assertTrue(nft.supportsInterface(type(IERC165).interfaceId));
        assertFalse(nft.supportsInterface(0xffffffff));
    }

    // ---------- Enumeration consistency ----------

    function test_Enumeration_ConsistentAfterMixedMints() public {
        vm.prank(owner);
        nft.ownerMint(alice, 2); // tokens 1-2

        vm.deal(bob, PRICE * 2);
        vm.prank(bob);
        nft.mint{value: PRICE * 2}(2); // tokens 3-4

        vm.prank(owner);
        nft.ownerMint(bob, 1); // token 5

        vm.deal(alice, PRICE * 2);
        vm.prank(alice);
        nft.mint{value: PRICE * 2}(2); // tokens 6-7

        assertEq(nft.totalSupply(), 7);
        assertEq(nft.totalMinted(), 7);

        // Global enumeration
        bool[8] memory seen;
        for (uint256 i = 0; i < 7; i++) {
            uint256 tokenId = nft.tokenByIndex(i);
            assertFalse(seen[tokenId]);
            seen[tokenId] = true;
        }
        for (uint256 id = 1; id <= 7; id++) {
            assertTrue(seen[id]);
        }

        assertEq(nft.balanceOf(alice), 4);
        assertEq(nft.balanceOf(bob), 3);
    }

    // ---------- Fuzz tests ----------

    function testFuzz_PublicMint_ValidQuantity(uint8 quantityRaw) public {
        uint256 quantity = bound(quantityRaw, 1, 2);
        vm.deal(alice, PRICE * quantity);

        vm.prank(alice);
        nft.mint{value: PRICE * quantity}(quantity);

        assertEq(nft.balanceOf(alice), quantity);
        assertEq(nft.mintedPerWallet(alice), quantity);
    }

    function testFuzz_RevertWhen_PaymentNotExact(uint96 offsetRaw) public {
        uint256 offset = bound(uint256(offsetRaw), 1, 5 ether);

        vm.deal(alice, PRICE + offset);
        vm.prank(alice);
        vm.expectRevert("Incorrect ETH sent");
        nft.mint{value: PRICE + offset}(1);

        if (offset < PRICE) {
            vm.deal(bob, PRICE - offset);
            vm.prank(bob);
            vm.expectRevert("Incorrect ETH sent");
            nft.mint{value: PRICE - offset}(1);
        }
    }
}

// ---------- Helper Contracts ----------

contract MaliciousMinter {
    SnipeHeadNFT public target;
    uint256 public price;
    bool public attacking;

    constructor(SnipeHeadNFT _target, uint256 _price) {
        target = _target;
        price = _price;
    }

    function attack() external {
        attacking = true;
        target.mint{value: price}(1);
    }

    function onERC721Received(address, address, uint256, bytes calldata) external returns (bytes4) {
        if (attacking) {
            attacking = false;
            target.mint{value: price}(1); // should be blocked by nonReentrant
        }
        return this.onERC721Received.selector;
    }
}

contract GoodReceiver is IERC721Receiver {
    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }
}

contract NonReceiver {}