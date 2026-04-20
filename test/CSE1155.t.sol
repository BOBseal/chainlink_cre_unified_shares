// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {CSE1155} from "../src/CSE1155.sol";
import {VaultCore} from "../src/vaultcore/core.sol";
import {uRWA1155Metadata} from "../src/rwa/modules/erc1155/uRWA1155Metadata.sol";
import {MockERC20} from "../src/rwa/mocks/MockERC20.sol";

contract CSE1155Test is Test {
    CSE1155 public cse1155;
    VaultCore public vaultCore;
    MockERC20 public mockUSDC;
    MockERC20 public mockWETH;

    address public trustedForwarder = address(0x123);
    address public user1 = address(0x456);
    address public user2 = address(0x789);
    address public operator = address(0xABC);

    uint256 public constant INITIAL_BALANCE = 1000000 * 10**18;

    bytes public constant TEST_METADATA = abi.encodePacked(
        bytes32("test-workflow-id"),
        bytes10("test-workf"),
        address(0x123) // trustedForwarder
    );

    function setUp() public {
        // Deploy contracts
        vaultCore = new VaultCore();
        cse1155 = new CSE1155(trustedForwarder, address(vaultCore), "https://example.com/metadata/{id}");

        // Set CSE1155 as allowed in vault
        vaultCore.setAllowed(address(cse1155), true);

        // Deploy mock tokens
        mockUSDC = new MockERC20("Mock USDC", "USDC", 6);
        mockWETH = new MockERC20("Mock WETH", "WETH", 18);

        // Fund users
        mockUSDC.mint(user1, INITIAL_BALANCE);
        mockWETH.mint(user1, INITIAL_BALANCE);
        mockUSDC.mint(user2, INITIAL_BALANCE);
        mockWETH.mint(user2, INITIAL_BALANCE);

        // Approve vault for token transfers
        vm.prank(user1);
        mockUSDC.approve(address(vaultCore), type(uint256).max);
        vm.prank(user1);
        mockWETH.approve(address(vaultCore), type(uint256).max);
        vm.prank(user2);
        mockUSDC.approve(address(vaultCore), type(uint256).max);
        vm.prank(user2);
        mockWETH.approve(address(vaultCore), type(uint256).max);
    }

    // ============ UNIT TESTS ============

    function test_Constructor() public {
        assertEq(address(cse1155.core()), address(vaultCore));
        assertEq(cse1155.tokenCounter(), 1);
        assertEq(cse1155.totalSharesIssued(), 0);
    }

    function test_MintBatch() public {
        address[] memory collaterals = new address[](2);
        collaterals[0] = address(mockUSDC);
        collaterals[1] = address(mockWETH);
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1000 * 10**6; // 1000 USDC
        amounts[1] = 1 * 10**18;   // 1 WETH
        uint256 sharesToMint = 1000 * 10**18;

        vm.prank(trustedForwarder);
        cse1155.onReport(TEST_METADATA, abi.encode(
            uint8(1), // actionCodeDepositMint
            user1,
            collaterals,
            amounts,
            sharesToMint
        ));

        // Check token was minted
        assertEq(cse1155.rwaToken().balanceOf(user1, 1), sharesToMint);
        assertEq(cse1155.tokenCounter(), 2);
        assertEq(cse1155.totalSharesIssued(), sharesToMint);

        // Check batch data
        CSE1155.DepositBatch1155 memory batch = cse1155.getBatch(1);
        assertEq(batch.initiatingUser, user1);
        assertEq(batch.collateralTokens.length, 2);
        assertEq(batch.collateralAmounts.length, 2);
        assertEq(batch.collateralTokens[0], address(mockUSDC));
        assertEq(batch.collateralAmounts[0], amounts[0]);
        assertEq(batch.sharesMinted, sharesToMint);
    }

    function test_DepositToExistingBatch() public {
        // First mint a batch
        address[] memory collaterals = new address[](2);
        collaterals[0] = address(mockUSDC);
        collaterals[1] = address(mockWETH);
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1000 * 10**6;
        amounts[1] = 1 * 10**18;
        uint256 sharesToMint = 1000 * 10**18;

        vm.prank(trustedForwarder);
        cse1155.onReport(TEST_METADATA, abi.encode(uint8(1), user1, collaterals, amounts, sharesToMint));

        // Now deposit to existing batch
        uint256[] memory additionalAmounts = new uint256[](2);
        additionalAmounts[0] = 500 * 10**6;  // Additional 500 USDC
        additionalAmounts[1] = 0.5 * 10**18; // Additional 0.5 WETH
        uint256 additionalShares = 500 * 10**18;

        vm.prank(trustedForwarder);
        cse1155.onReport(TEST_METADATA, abi.encode(
            uint8(2), // actionCodeDepositExisting
            user1,
            uint256(1), // tokenId
            collaterals,
            additionalAmounts,
            additionalShares
        ));

        // Check balances increased
        assertEq(cse1155.rwaToken().balanceOf(user1, 1), sharesToMint + additionalShares);
        assertEq(cse1155.totalSharesIssued(), sharesToMint + additionalShares);

        // Check batch data updated
        CSE1155.DepositBatch1155 memory batch = cse1155.getBatch(1);
        assertEq(batch.collateralAmounts[0], amounts[0] + additionalAmounts[0]);
        assertEq(batch.collateralAmounts[1], amounts[1] + additionalAmounts[1]);
        assertEq(batch.sharesMinted, sharesToMint + additionalShares);
    }

    function test_WithdrawFromBatch() public {
        // Setup: mint a batch
        address[] memory collaterals = new address[](2);
        collaterals[0] = address(mockUSDC);
        collaterals[1] = address(mockWETH);
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1000 * 10**6;
        amounts[1] = 1 * 10**18;
        uint256 sharesToMint = 1000 * 10**18;

        vm.prank(trustedForwarder);
        cse1155.onReport(TEST_METADATA, abi.encode(uint8(1), user1, collaterals, amounts, sharesToMint));

        // Now withdraw half the shares
        uint256 sharesToBurn = sharesToMint / 2;

        vm.prank(trustedForwarder);
        cse1155.onReport(TEST_METADATA, abi.encode(
            uint8(3), // actionCodeWithdraw
            user1,
            uint256(1), // tokenId
            sharesToBurn,
            user2 // receiver
        ));

        // Check share balance reduced
        assertEq(cse1155.rwaToken().balanceOf(user1, 1), sharesToMint - sharesToBurn);

        // Check batch data updated
        CSE1155.DepositBatch1155 memory batch = cse1155.getBatch(1);
        assertEq(batch.sharesMinted, sharesToMint - sharesToBurn);
        assertEq(batch.collateralAmounts[0], amounts[0] / 2);
        assertEq(batch.collateralAmounts[1], amounts[1] / 2);

        // Check user2 received the collateral
        assertEq(mockUSDC.balanceOf(user2), INITIAL_BALANCE + amounts[0] / 2);
        assertEq(mockWETH.balanceOf(user2), INITIAL_BALANCE + amounts[1] / 2);
    }

    function test_OperatorCall() public {
        // Grant FREEZING_ROLE to operator
        vm.prank(trustedForwarder);
        cse1155.onReport(TEST_METADATA, abi.encode(
            uint8(4), // actionCodeOperatorCall
            address(cse1155.rwaToken()),
            operator,
            keccak256("FREEZING_ROLE")
        ));

        // Check operator has the role
        assertTrue(cse1155.rwaToken().hasRole(keccak256("FREEZING_ROLE"), operator));
    }

    function test_DocumentAction() public {
        // Mint a batch first
        address[] memory collaterals = new address[](1);
        collaterals[0] = address(mockUSDC);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1000 * 10**6;
        uint256 sharesToMint = 1000 * 10**18;

        vm.prank(trustedForwarder);
        cse1155.onReport(TEST_METADATA, abi.encode(uint8(1), user1, collaterals, amounts, sharesToMint));

        // Set document
        bytes32 docName = keccak256("KYC_DOCUMENT");
        string memory docUri = "https://example.com/kyc.pdf";
        bytes32 docHash = keccak256("document content");

        vm.prank(trustedForwarder);
        cse1155.onReport(TEST_METADATA, abi.encode(
            uint8(5), // actionCodeDocumentAction
            address(cse1155.rwaToken()),
            uint256(1), // tokenId
            docName,
            docUri,
            docHash,
            false // not removal
        ));

        // Check document was set
        (string memory retrievedUri, bytes32 retrievedHash, uint256 updateTime) = cse1155.rwaToken().getDocument(docName, 1);
        assertEq(retrievedUri, docUri);
        assertEq(retrievedHash, docHash);
        assertTrue(updateTime > 0);
    }

    // ============ FUZZ TESTS ============

    function testFuzz_MintBatch(uint256 amount1, uint256 amount2, uint256 shares) public {
        amount1 = bound(amount1, 1, 1000000 * 10**6);
        amount2 = bound(amount2, 1, 1000 * 10**18);
        shares = bound(shares, 1, 1000000 * 10**18);

        // Mint tokens to user
        mockUSDC.mint(user1, amount1);
        mockWETH.mint(user1, amount2);

        address[] memory collaterals = new address[](2);
        collaterals[0] = address(mockUSDC);
        collaterals[1] = address(mockWETH);
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = amount1;
        amounts[1] = amount2;

        vm.prank(trustedForwarder);
        cse1155.onReport(TEST_METADATA, abi.encode(uint8(1), user1, collaterals, amounts, shares));

        // Verify
        assertEq(cse1155.rwaToken().balanceOf(user1, 1), shares);
        assertEq(cse1155.totalSharesIssued(), shares);

        CSE1155.DepositBatch1155 memory batch = cse1155.getBatch(1);
        assertEq(batch.collateralAmounts[0], amount1);
        assertEq(batch.collateralAmounts[1], amount2);
        assertEq(batch.sharesMinted, shares);
    }

    function testFuzz_DepositToExistingBatch(uint256 additionalAmount1, uint256 additionalAmount2, uint256 additionalShares) public {
        // Setup initial batch
        uint256 initialAmount1 = 1000 * 10**6;
        uint256 initialAmount2 = 1 * 10**18;
        uint256 initialShares = 1000 * 10**18;

        mockUSDC.mint(user1, initialAmount1);
        mockWETH.mint(user1, initialAmount2);

        address[] memory collaterals = new address[](2);
        collaterals[0] = address(mockUSDC);
        collaterals[1] = address(mockWETH);
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = initialAmount1;
        amounts[1] = initialAmount2;

        vm.prank(trustedForwarder);
        cse1155.onReport(TEST_METADATA, abi.encode(uint8(1), user1, collaterals, amounts, initialShares));

        // Fuzz additional deposit
        additionalAmount1 = bound(additionalAmount1, 1, 1000000 * 10**6);
        additionalAmount2 = bound(additionalAmount2, 1, 1000 * 10**18);
        additionalShares = bound(additionalShares, 1, 1000000 * 10**18);

        mockUSDC.mint(user1, additionalAmount1);
        mockWETH.mint(user1, additionalAmount2);

        uint256[] memory additionalAmounts = new uint256[](2);
        additionalAmounts[0] = additionalAmount1;
        additionalAmounts[1] = additionalAmount2;

        vm.prank(trustedForwarder);
        cse1155.onReport(TEST_METADATA, abi.encode(uint8(2), user1, uint256(1), collaterals, additionalAmounts, additionalShares));

        // Verify
        assertEq(cse1155.rwaToken().balanceOf(user1, 1), initialShares + additionalShares);
        assertEq(cse1155.totalSharesIssued(), initialShares + additionalShares);

        CSE1155.DepositBatch1155 memory batch = cse1155.getBatch(1);
        assertEq(batch.collateralAmounts[0], initialAmount1 + additionalAmount1);
        assertEq(batch.collateralAmounts[1], initialAmount2 + additionalAmount2);
        assertEq(batch.sharesMinted, initialShares + additionalShares);
    }

    // ============ GAS TESTS ============

    function testGas_MintBatch() public {
        address[] memory collaterals = new address[](2);
        collaterals[0] = address(mockUSDC);
        collaterals[1] = address(mockWETH);
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1000 * 10**6;
        amounts[1] = 1 * 10**18;
        uint256 sharesToMint = 1000 * 10**18;

        uint256 gasStart = gasleft();
        vm.prank(trustedForwarder);
        cse1155.onReport(TEST_METADATA, abi.encode(uint8(1), user1, collaterals, amounts, sharesToMint));
        uint256 gasUsed = gasStart - gasleft();

        console.log("Gas used for mintBatch:", gasUsed);
        assertTrue(gasUsed < 500000);
    }

    function testGas_WithdrawFromBatch() public {
        // Setup: mint batch first
        address[] memory collaterals = new address[](2);
        collaterals[0] = address(mockUSDC);
        collaterals[1] = address(mockWETH);
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1000 * 10**6;
        amounts[1] = 1 * 10**18;
        uint256 sharesToMint = 1000 * 10**18;

        vm.prank(trustedForwarder);
        cse1155.onReport(TEST_METADATA, abi.encode(uint8(1), user1, collaterals, amounts, sharesToMint));

        uint256 gasStart = gasleft();
        vm.prank(trustedForwarder);
        cse1155.onReport(TEST_METADATA, abi.encode(uint8(3), user1, uint256(1), sharesToMint / 2, user2));
        uint256 gasUsed = gasStart - gasleft();

        console.log("Gas used for withdrawFromBatch:", gasUsed);
        assertTrue(gasUsed < 300000);
    }

    // ============ REVERT TESTS ============

    function testRevert_MintBatchInvalidUser() public {
        address[] memory collaterals = new address[](1);
        collaterals[0] = address(mockUSDC);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1000 * 10**6;

        vm.prank(trustedForwarder);
        vm.expectRevert("Invalid user address");
        cse1155.onReport(TEST_METADATA, abi.encode(uint8(1), address(0), collaterals, amounts, 1000 * 10**18));
    }

    function testRevert_MintBatchArrayLengthMismatch() public {
        address[] memory collaterals = new address[](2);
        collaterals[0] = address(mockUSDC);
        collaterals[1] = address(mockWETH);
        uint256[] memory amounts = new uint256[](1); // Wrong length
        amounts[0] = 1000 * 10**6;

        vm.prank(trustedForwarder);
        vm.expectRevert("Array length mismatch");
        cse1155.onReport(TEST_METADATA, abi.encode(uint8(1), user1, collaterals, amounts, 1000 * 10**18));
    }

    function testRevert_MintBatchNoCollaterals() public {
        address[] memory collaterals = new address[](0);
        uint256[] memory amounts = new uint256[](0);

        vm.prank(trustedForwarder);
        vm.expectRevert("Must deposit at least one collateral");
        cse1155.onReport(TEST_METADATA, abi.encode(uint8(1), user1, collaterals, amounts, 1000 * 10**18));
    }

    function testRevert_MintBatchZeroShares() public {
        address[] memory collaterals = new address[](1);
        collaterals[0] = address(mockUSDC);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1000 * 10**6;

        vm.prank(trustedForwarder);
        vm.expectRevert("Shares must be greater than 0");
        cse1155.onReport(TEST_METADATA, abi.encode(uint8(1), user1, collaterals, amounts, 0));
    }

    function testRevert_MintBatchZeroAmount() public {
        address[] memory collaterals = new address[](1);
        collaterals[0] = address(mockUSDC);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 0; // Zero amount

        vm.prank(trustedForwarder);
        vm.expectRevert("Amount must be greater than 0");
        cse1155.onReport(TEST_METADATA, abi.encode(uint8(1), user1, collaterals, amounts, 1000 * 10**18));
    }

    function testRevert_DepositToExistingBatchInvalidUser() public {
        address[] memory collaterals = new address[](1);
        collaterals[0] = address(mockUSDC);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1000 * 10**6;

        vm.prank(trustedForwarder);
        vm.expectRevert("Invalid user address");
        cse1155.onReport(TEST_METADATA, abi.encode(uint8(2), address(0), uint256(1), collaterals, amounts, 1000 * 10**18));
    }

    function testRevert_DepositToExistingBatchInvalidTokenId() public {
        address[] memory collaterals = new address[](1);
        collaterals[0] = address(mockUSDC);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1000 * 10**6;

        vm.prank(trustedForwarder);
        vm.expectRevert("Invalid tokenId - batch does not exist");
        cse1155.onReport(TEST_METADATA, abi.encode(uint8(2), user1, uint256(999), collaterals, amounts, 1000 * 10**18));
    }

    function testRevert_DepositToExistingBatchUnauthorizedUser() public {
        // Mint batch as user1
        address[] memory collaterals = new address[](1);
        collaterals[0] = address(mockUSDC);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1000 * 10**6;

        vm.prank(trustedForwarder);
        cse1155.onReport(TEST_METADATA, abi.encode(uint8(1), user1, collaterals, amounts, 1000 * 10**18));

        // Try to deposit as user2
        vm.prank(trustedForwarder);
        vm.expectRevert("Only batch initiator can deposit to existing batch");
        cse1155.onReport(TEST_METADATA, abi.encode(uint8(2), user2, uint256(1), collaterals, amounts, 1000 * 10**18));
    }

    function testRevert_WithdrawFromBatchInvalidUser() public {
        vm.prank(trustedForwarder);
        vm.expectRevert("Invalid user");
        cse1155.onReport(TEST_METADATA, abi.encode(uint8(3), address(0), uint256(1), 1000 * 10**18, user2));
    }

    function testRevert_WithdrawFromBatchInvalidReceiver() public {
        vm.prank(trustedForwarder);
        vm.expectRevert("Invalid receiver");
        cse1155.onReport(TEST_METADATA, abi.encode(uint8(3), user1, uint256(1), 1000 * 10**18, address(0)));
    }

    function testRevert_WithdrawFromBatchZeroShares() public {
        vm.prank(trustedForwarder);
        vm.expectRevert("Burn amount must be greater than 0");
        cse1155.onReport(TEST_METADATA, abi.encode(uint8(3), user1, uint256(1), 0, user2));
    }

    function testRevert_WithdrawFromBatchInsufficientBalance() public {
        // Mint batch first
        address[] memory collaterals = new address[](1);
        collaterals[0] = address(mockUSDC);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1000 * 10**6;

        vm.prank(trustedForwarder);
        cse1155.onReport(TEST_METADATA, abi.encode(uint8(1), user1, collaterals, amounts, 1000 * 10**18));

        // Try to withdraw more than balance
        vm.prank(trustedForwarder);
        vm.expectRevert("Insufficient share balance");
        cse1155.onReport(TEST_METADATA, abi.encode(uint8(3), user1, uint256(1), 2000 * 10**18, user2));
    }

    function testRevert_OperatorCallInvalidToken() public {
        vm.prank(trustedForwarder);
        vm.expectRevert("Invalid share token");
        cse1155.onReport(TEST_METADATA, abi.encode(
            uint8(4),
            address(0x123), // Wrong token address
            operator,
            keccak256("FREEZING_ROLE")
        ));
    }

    function testRevert_OperatorCallInvalidOperator() public {
        vm.prank(trustedForwarder);
        vm.expectRevert("Invalid operator");
        cse1155.onReport(TEST_METADATA, abi.encode(
            uint8(4),
            address(cse1155.rwaToken()),
            address(0), // Invalid operator
            keccak256("FREEZING_ROLE")
        ));
    }

    function testRevert_OperatorCallProtectedRole() public {
        vm.prank(trustedForwarder);
        vm.expectRevert("Cannot transfer minter role");
        cse1155.onReport(TEST_METADATA, abi.encode(
            uint8(4),
            address(cse1155.rwaToken()),
            operator,
            keccak256("MINTER_ROLE")
        ));
    }

    function testRevert_DocumentActionInvalidToken() public {
        vm.prank(trustedForwarder);
        vm.expectRevert("Invalid share token");
        cse1155.onReport(TEST_METADATA, abi.encode(
            uint8(5),
            address(0x123), // Wrong token address
            uint256(1),
            bytes32("test"),
            "uri",
            bytes32("hash"),
            false
        ));
    }
}