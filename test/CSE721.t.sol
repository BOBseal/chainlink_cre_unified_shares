// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {CSE721} from "../src/CSE721.sol";
import {VaultCore} from "../src/vaultcore/core.sol";
import {uRWA721} from "../src/rwa/uRWA721.sol";
import {MockERC20} from "../src/rwa/mocks/MockERC20.sol";

contract CSE721Test is Test {
    CSE721 public cse721;
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
        cse721 = new CSE721(trustedForwarder, address(vaultCore), "CSE721 Share", "CSE721");

        // Set CSE721 as allowed in vault
        vaultCore.setAllowed(address(cse721), true);

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

        // Grant WHITELIST_ROLE to this contract and whitelist users
        vm.startPrank(trustedForwarder);
        cse721.onReport(TEST_METADATA, abi.encode(
            uint8(3), // actionCodeOperatorCall
            address(cse721.rwaToken()),
            address(this),
            cse721.rwaToken().WHITELIST_ROLE()
        ));
        vm.stopPrank();

        cse721.rwaToken().changeWhitelist(user1, true);
        cse721.rwaToken().changeWhitelist(user2, true);
        cse721.rwaToken().changeWhitelist(operator, true);
    }

    // ============ UNIT TESTS ============

    function test_Constructor() public {
        assertEq(address(cse721.core()), address(vaultCore));
        assertEq(cse721.tokenCounter(), 1);
        assertEq(address(cse721.rwaToken()), address(cse721.rwaToken()));
    }

    function test_MintToken() public {
        address[] memory collaterals = new address[](2);
        collaterals[0] = address(mockUSDC);
        collaterals[1] = address(mockWETH);
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1000 * 10**6; // 1000 USDC
        amounts[1] = 1 * 10**18;   // 1 WETH

        vm.prank(trustedForwarder);
        cse721.onReport(TEST_METADATA, abi.encode(
            uint8(1), // actionCodeDepositMint
            user1,
            collaterals,
            amounts
        ));

        // Check token was minted
        assertEq(cse721.rwaToken().ownerOf(1), user1);
        assertEq(cse721.tokenCounter(), 2);

        // Check deposit data
        CSE721.DepositToken721 memory deposit = cse721.getDepositToken(1);
        assertTrue(deposit.exists);
        assertEq(deposit.initiatingUser, user1);
        assertEq(deposit.collateralTokens.length, 2);
        assertEq(deposit.collateralAmounts.length, 2);
        assertEq(deposit.collateralTokens[0], address(mockUSDC));
        assertEq(deposit.collateralAmounts[0], amounts[0]);
    }

    function test_WithdrawToken() public {
        // First mint a token
        address[] memory collaterals = new address[](2);
        collaterals[0] = address(mockUSDC);
        collaterals[1] = address(mockWETH);
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1000 * 10**6;
        amounts[1] = 1 * 10**18;

        vm.prank(trustedForwarder);
        cse721.onReport(TEST_METADATA, abi.encode(uint8(1), user1, collaterals, amounts));

        // Approve CSE721 to burn the token
        vm.startPrank(user1);
        cse721.rwaToken().approve(address(cse721), 1);
        vm.stopPrank();

        // Now withdraw the token
        vm.prank(trustedForwarder);
        cse721.onReport(TEST_METADATA, abi.encode(
            uint8(2), // actionCodeWithdraw
            user1,
            uint256(1), // tokenId
            user2 // receiver
        ));

        // Check token was burned
        vm.expectRevert();
        cse721.rwaToken().ownerOf(1);

        // Check deposit data was deleted
        CSE721.DepositToken721 memory deposit = cse721.getDepositToken(1);
        assertFalse(deposit.exists);

        // Check user2 received the collateral
        assertEq(mockUSDC.balanceOf(user2), INITIAL_BALANCE + amounts[0]);
        assertEq(mockWETH.balanceOf(user2), INITIAL_BALANCE + amounts[1]);
    }

    function test_OperatorCall() public {
        // Grant FREEZING_ROLE to operator
        vm.startPrank(trustedForwarder);
        cse721.onReport(TEST_METADATA, abi.encode(
            uint8(3), // actionCodeOperatorCall
            address(cse721.rwaToken()),
            operator,
            keccak256("FREEZING_ROLE")
        ));
        vm.stopPrank();

        // Check operator has the role
        assertTrue(cse721.rwaToken().hasRole(keccak256("FREEZING_ROLE"), operator));
    }

    function test_DocumentActionNotSupported() public {
        vm.expectRevert("Document actions not supported for ERC721 shares");
        vm.startPrank(trustedForwarder);
        cse721.onReport(TEST_METADATA, abi.encode(
            uint8(4), // actionCodeDocumentAction
            address(cse721.rwaToken()),
            bytes32("test"),
            "uri",
            bytes32("hash"),
            false
        ));
        vm.stopPrank();
    }

    // ============ FUZZ TESTS ============

    function testFuzz_MintToken(uint256 amount1, uint256 amount2) public {
        amount1 = bound(amount1, 1, 1000000 * 10**6);
        amount2 = bound(amount2, 1, 1000 * 10**18);

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
        cse721.onReport(TEST_METADATA, abi.encode(uint8(1), user1, collaterals, amounts));

        // Verify token was minted
        assertEq(cse721.rwaToken().ownerOf(1), user1);

        // Verify deposit data
        CSE721.DepositToken721 memory deposit = cse721.getDepositToken(1);
        assertTrue(deposit.exists);
        assertEq(deposit.collateralAmounts[0], amount1);
        assertEq(deposit.collateralAmounts[1], amount2);
    }

    function testFuzz_MultipleMints(uint256 numMints) public {
        numMints = bound(numMints, 1, 20);

        for (uint256 i = 0; i < numMints; i++) {
            address user = address(uint160(uint256(keccak256(abi.encode(i)))));
            mockUSDC.mint(user, 1000 * 10**6);
            mockWETH.mint(user, 1 * 10**18);

            vm.prank(user);
            mockUSDC.approve(address(vaultCore), type(uint256).max);
            vm.prank(user);
            mockWETH.approve(address(vaultCore), type(uint256).max);

            // Whitelist the user
            cse721.rwaToken().changeWhitelist(user, true);

            address[] memory collaterals = new address[](2);
            collaterals[0] = address(mockUSDC);
            collaterals[1] = address(mockWETH);
            uint256[] memory amounts = new uint256[](2);
            amounts[0] = 1000 * 10**6;
            amounts[1] = 1 * 10**18;

            vm.prank(trustedForwarder);
            cse721.onReport(TEST_METADATA, abi.encode(uint8(1), user, collaterals, amounts));

            assertEq(cse721.rwaToken().ownerOf(i + 1), user);
        }

        assertEq(cse721.tokenCounter(), numMints + 1);
    }

    // ============ GAS TESTS ============

    function testGas_MintToken() public {
        address[] memory collaterals = new address[](2);
        collaterals[0] = address(mockUSDC);
        collaterals[1] = address(mockWETH);
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1000 * 10**6;
        amounts[1] = 1 * 10**18;

        uint256 gasStart = gasleft();
        vm.prank(trustedForwarder);
        cse721.onReport(TEST_METADATA, abi.encode(uint8(1), user1, collaterals, amounts));
        uint256 gasUsed = gasStart - gasleft();

        console.log("Gas used for mintToken:", gasUsed);
        assertTrue(gasUsed < 400000);
    }

    function testGas_WithdrawToken() public {
        // Setup: mint token first
        address[] memory collaterals = new address[](2);
        collaterals[0] = address(mockUSDC);
        collaterals[1] = address(mockWETH);
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1000 * 10**6;
        amounts[1] = 1 * 10**18;

        vm.prank(trustedForwarder);
        cse721.onReport(TEST_METADATA, abi.encode(uint8(1), user1, collaterals, amounts));

        // Approve CSE721 to burn the token
        vm.startPrank(user1);
        cse721.rwaToken().approve(address(cse721), 1);
        vm.stopPrank();

        uint256 gasStart = gasleft();
        vm.prank(trustedForwarder);
        cse721.onReport(TEST_METADATA, abi.encode(uint8(2), user1, uint256(1), user2));
        uint256 gasUsed = gasStart - gasleft();

        console.log("Gas used for withdrawToken:", gasUsed);
        assertTrue(gasUsed < 200000);
    }

    // ============ REVERT TESTS ============

    function testRevert_MintTokenInvalidUser() public {
        address[] memory collaterals = new address[](1);
        collaterals[0] = address(mockUSDC);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1000 * 10**6;

        vm.prank(trustedForwarder);
        vm.expectRevert("Invalid user address");
        cse721.onReport(TEST_METADATA, abi.encode(uint8(1), address(0), collaterals, amounts));
    }

    function testRevert_MintTokenArrayLengthMismatch() public {
        address[] memory collaterals = new address[](2);
        collaterals[0] = address(mockUSDC);
        collaterals[1] = address(mockWETH);
        uint256[] memory amounts = new uint256[](1); // Wrong length
        amounts[0] = 1000 * 10**6;

        vm.prank(trustedForwarder);
        vm.expectRevert("Array length mismatch");
        cse721.onReport(TEST_METADATA, abi.encode(uint8(1), user1, collaterals, amounts));
    }

    function testRevert_MintTokenNoCollaterals() public {
        address[] memory collaterals = new address[](0);
        uint256[] memory amounts = new uint256[](0);

        vm.prank(trustedForwarder);
        vm.expectRevert("Must deposit at least one collateral");
        cse721.onReport(TEST_METADATA, abi.encode(uint8(1), user1, collaterals, amounts));
    }

    function testRevert_MintTokenInvalidCollateral() public {
        address[] memory collaterals = new address[](1);
        collaterals[0] = address(0); // Invalid collateral
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1000 * 10**6;

        vm.prank(trustedForwarder);
        vm.expectRevert("Invalid collateral address");
        cse721.onReport(TEST_METADATA, abi.encode(uint8(1), user1, collaterals, amounts));
    }

    function testRevert_MintTokenZeroAmount() public {
        address[] memory collaterals = new address[](1);
        collaterals[0] = address(mockUSDC);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 0; // Zero amount

        vm.prank(trustedForwarder);
        vm.expectRevert("Amount must be greater than 0");
        cse721.onReport(TEST_METADATA, abi.encode(uint8(1), user1, collaterals, amounts));
    }

    function testRevert_WithdrawTokenInvalidUser() public {
        vm.prank(trustedForwarder);
        vm.expectRevert("Invalid user");
        cse721.onReport(TEST_METADATA, abi.encode(uint8(2), address(0), uint256(1), user2));
    }

    function testRevert_WithdrawTokenInvalidReceiver() public {
        vm.prank(trustedForwarder);
        vm.expectRevert("Invalid receiver");
        cse721.onReport(TEST_METADATA, abi.encode(uint8(2), user1, uint256(1), address(0)));
    }

    function testRevert_WithdrawTokenInvalidTokenId() public {
        vm.prank(trustedForwarder);
        vm.expectRevert("Invalid tokenId");
        cse721.onReport(TEST_METADATA, abi.encode(uint8(2), user1, uint256(999), user2));
    }

    function testRevert_WithdrawTokenNotOwner() public {
        // Mint token to user1
        address[] memory collaterals = new address[](1);
        collaterals[0] = address(mockUSDC);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1000 * 10**6;

        vm.prank(trustedForwarder);
        cse721.onReport(TEST_METADATA, abi.encode(uint8(1), user1, collaterals, amounts));

        // Try to withdraw as user2
        vm.prank(trustedForwarder);
        vm.expectRevert("Insufficient share ownership");
        cse721.onReport(TEST_METADATA, abi.encode(uint8(2), user2, uint256(1), user2));
    }

    function testRevert_OperatorCallInvalidToken() public {
        vm.prank(trustedForwarder);
        vm.expectRevert("Invalid share token");
        cse721.onReport(TEST_METADATA, abi.encode(
            uint8(3),
            address(0x123), // Wrong token address
            operator,
            keccak256("FREEZING_ROLE")
        ));
    }

    function testRevert_OperatorCallInvalidOperator() public {
        vm.startPrank(trustedForwarder);
        vm.expectRevert("Invalid operator");
        cse721.onReport(TEST_METADATA, abi.encode(
            uint8(3),
            address(cse721.rwaToken()),
            address(0), // Invalid operator
            keccak256("FREEZING_ROLE")
        ));
        vm.stopPrank();
    }

    function testRevert_OperatorCallProtectedRole() public {
        vm.expectRevert("Cannot transfer minter role");
        vm.startPrank(trustedForwarder);
        cse721.onReport(TEST_METADATA, abi.encode(
            uint8(3),
            address(cse721.rwaToken()),
            operator,
            keccak256("MINTER_ROLE")
        ));
        vm.stopPrank();
    }
}