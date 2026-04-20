// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {CSE20} from "../src/CSE20.sol";
import {VaultCore} from "../src/vaultcore/core.sol";
import {uRWA20Metadata} from "../src/rwa/modules/erc20/uRWA20Metadata.sol";
import {MockERC20} from "../src/rwa/mocks/MockERC20.sol";

contract CSE20Test is Test {
    CSE20 public cse20;
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
        cse20 = new CSE20(trustedForwarder, address(vaultCore));

        // Set CSE20 as allowed in vault
        vaultCore.setAllowed(address(cse20), true);

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

        // Deploy a test tokenizer for use in tests
        address[] memory collaterals = new address[](2);
        collaterals[0] = address(mockUSDC);
        collaterals[1] = address(mockWETH);

        vm.startPrank(trustedForwarder);
        cse20.onReport(TEST_METADATA, abi.encode(
            uint8(1), // actionCodeDeploy
            "Test Token",
            "TEST",
            collaterals,
            user1
        ));

        // Whitelist test users for RWA compliance
        (address tokenizer,,,,) = cse20.getVaultInfo(1);
        uRWA20Metadata token = uRWA20Metadata(tokenizer);
        
        // Grant WHITELIST_ROLE to this contract via operator call
        cse20.onReport(TEST_METADATA, abi.encode(
            uint8(4), // actionCodeOperatorCall
            tokenizer,
            address(this),
            token.WHITELIST_ROLE()
        ));
        vm.stopPrank();

        // Whitelist users
        token.changeWhitelist(user1, true);
        token.changeWhitelist(user2, true);
        token.changeWhitelist(operator, true);
    }

    // ============ UNIT TESTS ============

    function test_Constructor() public view {
        assertEq(address(cse20.core()), address(vaultCore));
        assertEq(cse20.tokenizerId(), 2); // 2 because one was deployed in setUp
    }

    function test_DeployTokenizer() public {
        address[] memory collaterals = new address[](2);
        collaterals[0] = address(mockUSDC);
        collaterals[1] = address(mockWETH);

        bytes memory metadata = abi.encodePacked(
            bytes32("test-workflow-id"),
            bytes10("test-workf"),
            trustedForwarder
        );

        vm.startPrank(trustedForwarder);
        cse20.onReport(metadata, abi.encode(
            uint8(1), // actionCodeDeploy
            "Test Token 2",
            "TEST2",
            collaterals,
            user2
        ));

        // Check vault was created (ID 2 since ID 1 was created in setUp)
        (address shareToken, address deployer, address[] memory vaultCollaterals, uint256 totalShares, bool isActive) = cse20.getVaultInfo(2);
        assertTrue(isActive);
        assertEq(deployer, user2);
        assertEq(vaultCollaterals.length, 2);
        assertEq(vaultCollaterals[0], address(mockUSDC));
        assertEq(vaultCollaterals[1], address(mockWETH));
        assertEq(totalShares, 0);

        // Check share token was deployed
        assertTrue(shareToken != address(0));
        assertEq(cse20.shareTokenToVault(shareToken), 2);

        // Check user tokenizers
        uint256[] memory userVaults = cse20.getUserTokenizerIds(user2);
        assertEq(userVaults.length, 1);
        assertEq(userVaults[0], 2);

        // Grant WHITELIST_ROLE to this contract for the new token
        cse20.onReport(metadata, abi.encode(
            uint8(4), // actionCodeOperatorCall
            shareToken,
            address(this),
            uRWA20Metadata(shareToken).WHITELIST_ROLE()
        ));
        vm.stopPrank();

        // Whitelist user2 for the new token
        uRWA20Metadata token = uRWA20Metadata(shareToken);
        token.changeWhitelist(user2, true);
    }

    function test_DepositAndMintShares() public {
        // First deploy tokenizer
        address[] memory collaterals = new address[](2);
        collaterals[0] = address(mockUSDC);
        collaterals[1] = address(mockWETH);

        vm.prank(trustedForwarder);
        cse20.onReport(TEST_METADATA, abi.encode(
            uint8(1), // actionCodeDeploy
            "Test Token",
            "TEST",
            collaterals,
            user1
        ));

        // Now deposit and mint shares
        address[] memory depositCollaterals = new address[](2);
        depositCollaterals[0] = address(mockUSDC);
        depositCollaterals[1] = address(mockWETH);
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1000 * 10**6; // 1000 USDC
        amounts[1] = 1 * 10**18;   // 1 WETH
        uint256 sharesToMint = 1000 * 10**18;

        vm.prank(trustedForwarder);
        cse20.onReport(TEST_METADATA, abi.encode(
            uint8(2), // actionCodeDeposit
            uint256(1), // vaultId
            user1,
            depositCollaterals,
            amounts,
            sharesToMint
        ));

        // Check balances
        (address shareToken, , , uint256 totalShares, ) = cse20.getVaultInfo(1);
        assertEq(uRWA20Metadata(shareToken).balanceOf(user1), sharesToMint);

        // Check vault collateral balances
        assertEq(cse20.getCollateralBalance(1, address(mockUSDC)), amounts[0]);
        assertEq(cse20.getCollateralBalance(1, address(mockWETH)), amounts[1]);

        // Check vault total shares
        (, , , uint256 vaultTotalShares, ) = cse20.getVaultInfo(1);
        assertEq(vaultTotalShares, sharesToMint);
    }

    function test_RedeemShares() public {
        // Setup: deploy tokenizer and deposit
        address[] memory collaterals = new address[](2);
        collaterals[0] = address(mockUSDC);
        collaterals[1] = address(mockWETH);

        vm.prank(trustedForwarder);
        cse20.onReport(TEST_METADATA, abi.encode(
            uint8(1), // actionCodeDeploy
            "Test Token",
            "TEST",
            collaterals,
            user1
        ));

        address[] memory depositCollaterals = new address[](2);
        depositCollaterals[0] = address(mockUSDC);
        depositCollaterals[1] = address(mockWETH);
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1000 * 10**6; // 1000 USDC
        amounts[1] = 1 * 10**18;   // 1 WETH
        uint256 sharesToMint = 1000 * 10**18;

        vm.prank(trustedForwarder);
        cse20.onReport(TEST_METADATA, abi.encode(
            uint8(2), // actionCodeDeposit
            uint256(1),
            user1,
            depositCollaterals,
            amounts,
            sharesToMint
        ));

        // Now redeem half the shares
        uint256 sharesToBurn = sharesToMint / 2;

        vm.prank(trustedForwarder);
        cse20.onReport(TEST_METADATA, abi.encode(
            uint8(3), // actionCodeWithdraw
            uint256(1), // vaultId
            user1,
            sharesToBurn,
            user2 // receiver
        ));

        // Check share balance reduced
        (address shareToken, , , uint256 totalShares, ) = cse20.getVaultInfo(1);
        assertEq(uRWA20Metadata(shareToken).balanceOf(user1), sharesToMint - sharesToBurn);

        // Check vault collateral balances reduced proportionally
        assertEq(cse20.getCollateralBalance(1, address(mockUSDC)), amounts[0] / 2);
        assertEq(cse20.getCollateralBalance(1, address(mockWETH)), amounts[1] / 2);

        // Check vault total shares reduced
        (, , , uint256 vaultTotalSharesAfter, ) = cse20.getVaultInfo(1);
        assertEq(vaultTotalSharesAfter, sharesToMint - sharesToBurn);

        // Check user2 received the collateral
        assertEq(mockUSDC.balanceOf(user2), INITIAL_BALANCE + amounts[0] / 2);
        assertEq(mockWETH.balanceOf(user2), INITIAL_BALANCE + amounts[1] / 2);
    }

    function test_OperatorCall() public {
        // Deploy tokenizer first
        address[] memory collaterals = new address[](1);
        collaterals[0] = address(mockUSDC);

        vm.prank(trustedForwarder);
        cse20.onReport(TEST_METADATA, abi.encode(
            uint8(1),
            "Test Token",
            "TEST",
            collaterals,
            user1
        ));

        (address shareToken, , , , ) = cse20.getVaultInfo(1);

        // Grant FREEZING_ROLE to operator
        vm.prank(trustedForwarder);
        cse20.onReport(TEST_METADATA, abi.encode(
            uint8(4), // actionCodeOperatorCall
            shareToken,
            operator,
            keccak256("FREEZING_ROLE")
        ));

        // Check operator has the role
        assertTrue(uRWA20Metadata(shareToken).hasRole(keccak256("FREEZING_ROLE"), operator));
    }

    function test_DocumentAction() public {
        // Deploy tokenizer first
        address[] memory collaterals = new address[](1);
        collaterals[0] = address(mockUSDC);

        vm.prank(trustedForwarder);
        cse20.onReport(TEST_METADATA, abi.encode(
            uint8(1),
            "Test Token",
            "TEST",
            collaterals,
            user1
        ));

        (address shareToken, , , , ) = cse20.getVaultInfo(1);

        // Set document
        bytes32 docName = keccak256("KYC_DOCUMENT");
        string memory docUri = "https://example.com/kyc.pdf";
        bytes32 docHash = keccak256("document content");

        vm.prank(trustedForwarder);
        cse20.onReport(TEST_METADATA, abi.encode(
            uint8(5), // actionCodeDocumentAction
            shareToken,
            docName,
            docUri,
            docHash,
            false // not removal
        ));

        // Check document was set
        (string memory retrievedUri, bytes32 retrievedHash, uint256 updateTime) = uRWA20Metadata(shareToken).getDocument(docName);
        assertEq(retrievedUri, docUri);
        assertEq(retrievedHash, docHash);
        assertTrue(updateTime > 0);
    }

    // ============ FUZZ TESTS ============

    function testFuzz_DeployTokenizer(uint256 numCollaterals) public {
        numCollaterals = bound(numCollaterals, 1, 10);

        address[] memory collaterals = new address[](numCollaterals);
        for (uint256 i = 0; i < numCollaterals; i++) {
            MockERC20 token = new MockERC20(string(abi.encodePacked("Token", i)), string(abi.encodePacked("T", i)), 18);
            collaterals[i] = address(token);
        }

        vm.prank(trustedForwarder);
        cse20.onReport(TEST_METADATA, abi.encode(
            uint8(1),
            "Fuzz Token",
            "FUZZ",
            collaterals,
            user1
        ));

        (address shareToken, address deployer, address[] memory vaultCollaterals, , bool isActive) = cse20.getVaultInfo(2);
        assertTrue(isActive);
        assertEq(deployer, user1);
        assertEq(vaultCollaterals.length, numCollaterals);
        assertTrue(shareToken != address(0));
    }

    function testFuzz_DepositAndMintShares(uint256 amount1, uint256 amount2, uint256 shares) public {
        amount1 = bound(amount1, 1, 1000000 * 10**6);
        amount2 = bound(amount2, 1, 1000 * 10**18);
        shares = bound(shares, 1, 1000000 * 10**18);

        // Deploy tokenizer
        address[] memory collaterals = new address[](2);
        collaterals[0] = address(mockUSDC);
        collaterals[1] = address(mockWETH);

        vm.prank(trustedForwarder);
        cse20.onReport(TEST_METADATA, abi.encode(uint8(1), "Test", "TEST", collaterals, user1));

        // Mint tokens to user
        mockUSDC.mint(user1, amount1);
        mockWETH.mint(user1, amount2);

        // Deposit
        address[] memory depositCollaterals = new address[](2);
        depositCollaterals[0] = address(mockUSDC);
        depositCollaterals[1] = address(mockWETH);
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = amount1;
        amounts[1] = amount2;

        vm.prank(trustedForwarder);
        cse20.onReport(TEST_METADATA, abi.encode(uint8(2), uint256(1), user1, depositCollaterals, amounts, shares));

        // Verify
        (address shareToken, , , , ) = cse20.getVaultInfo(1);
        assertEq(uRWA20Metadata(shareToken).balanceOf(user1), shares);
        assertEq(cse20.getCollateralBalance(1, address(mockUSDC)), amount1);
        assertEq(cse20.getCollateralBalance(1, address(mockWETH)), amount2);
    }

    // ============ GAS TESTS ============

    function testGas_DeployTokenizer() public {
        address[] memory collaterals = new address[](2);
        collaterals[0] = address(mockUSDC);
        collaterals[1] = address(mockWETH);

        uint256 gasStart = gasleft();
        vm.prank(trustedForwarder);
        cse20.onReport(TEST_METADATA, abi.encode(uint8(1), "Test Token", "TEST", collaterals, user1));
        uint256 gasUsed = gasStart - gasleft();

        console.log("Gas used for deployTokenizer:", gasUsed);
        assertTrue(gasUsed < 3000000); // Reasonable gas limit for deployment
    }

    function testGas_DepositAndMintShares() public {
        // Setup
        address[] memory collaterals = new address[](2);
        collaterals[0] = address(mockUSDC);
        collaterals[1] = address(mockWETH);

        vm.prank(trustedForwarder);
        cse20.onReport(TEST_METADATA, abi.encode(uint8(1), "Test", "TEST", collaterals, user1));

        address[] memory depositCollaterals = new address[](2);
        depositCollaterals[0] = address(mockUSDC);
        depositCollaterals[1] = address(mockWETH);
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1000 * 10**6;
        amounts[1] = 1 * 10**18;

        uint256 gasStart = gasleft();
        vm.prank(trustedForwarder);
        cse20.onReport(TEST_METADATA, abi.encode(uint8(2), uint256(1), user1, depositCollaterals, amounts, 1000 * 10**18));
        uint256 gasUsed = gasStart - gasleft();

        console.log("Gas used for depositAndMintShares:", gasUsed);
        assertTrue(gasUsed < 300000);
    }

    function testGas_RedeemShares() public {
        // Setup with deposit
        address[] memory collaterals = new address[](2);
        collaterals[0] = address(mockUSDC);
        collaterals[1] = address(mockWETH);

        vm.prank(trustedForwarder);
        cse20.onReport(TEST_METADATA, abi.encode(uint8(1), "Test", "TEST", collaterals, user1));

        address[] memory depositCollaterals = new address[](2);
        depositCollaterals[0] = address(mockUSDC);
        depositCollaterals[1] = address(mockWETH);
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 1000 * 10**6;
        amounts[1] = 1 * 10**18;
        uint256 sharesToMint = 1000 * 10**18;

        vm.prank(trustedForwarder);
        cse20.onReport(TEST_METADATA, abi.encode(uint8(2), uint256(1), user1, depositCollaterals, amounts, sharesToMint));

        uint256 gasStart = gasleft();
        vm.prank(trustedForwarder);
        cse20.onReport(TEST_METADATA, abi.encode(uint8(3), uint256(1), user1, sharesToMint / 2, user2));
        uint256 gasUsed = gasStart - gasleft();

        console.log("Gas used for redeemShares:", gasUsed);
        assertTrue(gasUsed < 250000);
    }

    // ============ REVERT TESTS ============

    function testRevert_DeployTokenizerEmptyName() public {
        address[] memory collaterals = new address[](1);
        collaterals[0] = address(mockUSDC);

        vm.prank(trustedForwarder);
        vm.expectRevert("Name cannot be empty");
        cse20.onReport(TEST_METADATA, abi.encode(uint8(1), "", "TEST", collaterals, user1));
    }

    function testRevert_DeployTokenizerEmptySymbol() public {
        address[] memory collaterals = new address[](1);
        collaterals[0] = address(mockUSDC);

        vm.prank(trustedForwarder);
        vm.expectRevert("Symbol cannot be empty");
        cse20.onReport(TEST_METADATA, abi.encode(uint8(1), "Test", "", collaterals, user1));
    }

    function testRevert_DeployTokenizerNoCollaterals() public {
        address[] memory collaterals = new address[](0);

        vm.prank(trustedForwarder);
        vm.expectRevert("Must add at least one collateral");
        cse20.onReport(TEST_METADATA, abi.encode(uint8(1), "Test", "TEST", collaterals, user1));
    }

    function testRevert_DepositInvalidVault() public {
        address[] memory depositCollaterals = new address[](1);
        depositCollaterals[0] = address(mockUSDC);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1000 * 10**6;

        vm.prank(trustedForwarder);
        vm.expectRevert("Vault not found or inactive");
        cse20.onReport(TEST_METADATA, abi.encode(uint8(2), uint256(999), user1, depositCollaterals, amounts, 1000 * 10**18));
    }

    function testRevert_DepositUnauthorizedUser() public {
        // Deploy tokenizer as user1
        address[] memory collaterals = new address[](1);
        collaterals[0] = address(mockUSDC);

        vm.prank(trustedForwarder);
        cse20.onReport(TEST_METADATA, abi.encode(uint8(1), "Test", "TEST", collaterals, user1));

        // Try to deposit as user2
        address[] memory depositCollaterals = new address[](1);
        depositCollaterals[0] = address(mockUSDC);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1000 * 10**6;

        vm.prank(trustedForwarder);
        vm.expectRevert("Only vault deployer can mint shares");
        cse20.onReport(TEST_METADATA, abi.encode(uint8(2), uint256(1), user2, depositCollaterals, amounts, 1000 * 10**18));
    }

    function testRevert_WithdrawInsufficientShares() public {
        // Setup deposit
        address[] memory collaterals = new address[](1);
        collaterals[0] = address(mockUSDC);

        vm.prank(trustedForwarder);
        cse20.onReport(TEST_METADATA, abi.encode(uint8(1), "Test", "TEST", collaterals, user1));

        address[] memory depositCollaterals = new address[](1);
        depositCollaterals[0] = address(mockUSDC);
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = 1000 * 10**6;
        uint256 sharesToMint = 1000 * 10**18;

        vm.prank(trustedForwarder);
        cse20.onReport(TEST_METADATA, abi.encode(uint8(2), uint256(1), user1, depositCollaterals, amounts, sharesToMint));

        // Try to withdraw more than balance
        vm.prank(trustedForwarder);
        vm.expectRevert("Insufficient share balance");
        cse20.onReport(TEST_METADATA, abi.encode(uint8(3), uint256(1), user1, sharesToMint + 1, user2));
    }

    function testRevert_OperatorCallInvalidToken() public {
        vm.prank(trustedForwarder);
        vm.expectRevert("Invalid share token");
        cse20.onReport(TEST_METADATA, abi.encode(
            uint8(4),
            address(0x123), // invalid token
            operator,
            keccak256("FREEZING_ROLE")
        ));
    }

    function testRevert_OperatorCallProtectedRole() public {
        // Deploy tokenizer
        address[] memory collaterals = new address[](1);
        collaterals[0] = address(mockUSDC);

        vm.prank(trustedForwarder);
        cse20.onReport(TEST_METADATA, abi.encode(uint8(1), "Test", "TEST", collaterals, user1));

        (address shareToken, , , , ) = cse20.getVaultInfo(1);

        // Try to grant MINTER_ROLE
        vm.prank(trustedForwarder);
        vm.expectRevert("Cannot transfer minter role");
        cse20.onReport(TEST_METADATA, abi.encode(
            uint8(4),
            shareToken,
            operator,
            keccak256("MINTER_ROLE")
        ));
    }
}