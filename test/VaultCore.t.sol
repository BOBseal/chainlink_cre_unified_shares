// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {VaultCore} from "../src/vaultcore/core.sol";
import {MockERC20} from "../src/rwa/mocks/MockERC20.sol";

contract VaultCoreTest is Test {
    VaultCore public vaultCore;
    MockERC20 public mockUSDC;
    MockERC20 public mockWETH;

    address public owner = address(0x123);
    address public allowedVault = address(0x456);
    address public notAllowedVault = address(0x789);
    address public user1 = address(0xABC);
    address public user2 = address(0xDEF);

    uint256 public constant INITIAL_BALANCE = 1000000 * 10**18;

    function setUp() public {
        // Deploy contracts
        vm.prank(owner);
        vaultCore = new VaultCore();

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

        // Set allowed vault
        vm.prank(owner);
        vaultCore.setAllowed(allowedVault, true);
    }

    // ============ UNIT TESTS ============

    function test_Constructor() public {
        assertEq(vaultCore.owner(), owner);
    }

    function test_SetAllowed() public {
        // Test setting allowed
        vm.prank(owner);
        vaultCore.setAllowed(notAllowedVault, true);
        assertTrue(vaultCore.allowed(notAllowedVault));

        // Test setting not allowed
        vm.prank(owner);
        vaultCore.setAllowed(notAllowedVault, false);
        assertFalse(vaultCore.allowed(notAllowedVault));
    }

    function test_Deposit() public {
        uint256 depositAmount = 1000 * 10**6; // 1000 USDC

        vm.prank(allowedVault);
        bool success = vaultCore.deposit(user1, address(mockUSDC), depositAmount);

        assertTrue(success);
        assertEq(mockUSDC.balanceOf(address(vaultCore)), depositAmount);
        assertEq(mockUSDC.balanceOf(user1), INITIAL_BALANCE - depositAmount);
    }

    function test_Withdraw() public {
        // First deposit
        uint256 depositAmount = 1000 * 10**6;
        vm.prank(allowedVault);
        vaultCore.deposit(user1, address(mockUSDC), depositAmount);

        // Now withdraw
        uint256 withdrawAmount = 500 * 10**6;
        vm.prank(allowedVault);
        bool success = vaultCore.withdraw(user2, address(mockUSDC), withdrawAmount);

        assertTrue(success);
        assertEq(mockUSDC.balanceOf(address(vaultCore)), depositAmount - withdrawAmount);
        assertEq(mockUSDC.balanceOf(user2), INITIAL_BALANCE + withdrawAmount);
    }

    function test_MultipleDepositsAndWithdrawals() public {
        // Multiple deposits
        uint256 deposit1 = 1000 * 10**6;
        uint256 deposit2 = 500 * 10**18;

        vm.prank(allowedVault);
        vaultCore.deposit(user1, address(mockUSDC), deposit1);

        vm.prank(allowedVault);
        vaultCore.deposit(user1, address(mockWETH), deposit2);

        assertEq(mockUSDC.balanceOf(address(vaultCore)), deposit1);
        assertEq(mockWETH.balanceOf(address(vaultCore)), deposit2);

        // Multiple withdrawals
        uint256 withdraw1 = 500 * 10**6;
        uint256 withdraw2 = 250 * 10**18;

        vm.prank(allowedVault);
        vaultCore.withdraw(user2, address(mockUSDC), withdraw1);

        vm.prank(allowedVault);
        vaultCore.withdraw(user2, address(mockWETH), withdraw2);

        assertEq(mockUSDC.balanceOf(address(vaultCore)), deposit1 - withdraw1);
        assertEq(mockWETH.balanceOf(address(vaultCore)), deposit2 - withdraw2);
        assertEq(mockUSDC.balanceOf(user2), INITIAL_BALANCE + withdraw1);
        assertEq(mockWETH.balanceOf(user2), INITIAL_BALANCE + withdraw2);
    }

    // ============ FUZZ TESTS ============

    function testFuzz_Deposit(uint256 amount) public {
        amount = bound(amount, 1, INITIAL_BALANCE);

        vm.prank(allowedVault);
        bool success = vaultCore.deposit(user1, address(mockUSDC), amount);

        assertTrue(success);
        assertEq(mockUSDC.balanceOf(address(vaultCore)), amount);
        assertEq(mockUSDC.balanceOf(user1), INITIAL_BALANCE - amount);
    }

    function testFuzz_Withdraw(uint256 depositAmount, uint256 withdrawAmount) public {
        depositAmount = bound(depositAmount, 1, INITIAL_BALANCE);
        withdrawAmount = bound(withdrawAmount, 1, depositAmount);

        // Deposit first
        vm.prank(allowedVault);
        vaultCore.deposit(user1, address(mockUSDC), depositAmount);

        // Withdraw
        vm.prank(allowedVault);
        bool success = vaultCore.withdraw(user2, address(mockUSDC), withdrawAmount);

        assertTrue(success);
        assertEq(mockUSDC.balanceOf(address(vaultCore)), depositAmount - withdrawAmount);
        assertEq(mockUSDC.balanceOf(user2), INITIAL_BALANCE + withdrawAmount);
    }

    function testFuzz_MultipleOperations(uint256 numOperations) public {
        numOperations = bound(numOperations, 1, 20);

        uint256 vaultBalance = 0;

        for (uint256 i = 0; i < numOperations; i++) {
            uint256 amount = uint256(keccak256(abi.encode(i))) % INITIAL_BALANCE + 1;

            // Deposit
            vm.prank(allowedVault);
            vaultCore.deposit(user1, address(mockUSDC), amount);
            vaultBalance += amount;

            // Withdraw half
            uint256 withdrawAmount = amount / 2;
            if (withdrawAmount > 0) {
                vm.prank(allowedVault);
                vaultCore.withdraw(user2, address(mockUSDC), withdrawAmount);
                vaultBalance -= withdrawAmount;
            }
        }

        assertEq(mockUSDC.balanceOf(address(vaultCore)), vaultBalance);
    }

    // ============ GAS TESTS ============

    function testGas_Deposit() public {
        uint256 depositAmount = 1000 * 10**6;

        uint256 gasStart = gasleft();
        vm.prank(allowedVault);
        vaultCore.deposit(user1, address(mockUSDC), depositAmount);
        uint256 gasUsed = gasStart - gasleft();

        console.log("Gas used for deposit:", gasUsed);
        assertTrue(gasUsed < 100000);
    }

    function testGas_Withdraw() public {
        // Setup deposit
        uint256 depositAmount = 1000 * 10**6;
        vm.prank(allowedVault);
        vaultCore.deposit(user1, address(mockUSDC), depositAmount);

        uint256 gasStart = gasleft();
        vm.prank(allowedVault);
        vaultCore.withdraw(user2, address(mockUSDC), depositAmount);
        uint256 gasUsed = gasStart - gasleft();

        console.log("Gas used for withdraw:", gasUsed);
        assertTrue(gasUsed < 80000);
    }

    function testGas_SetAllowed() public {
        uint256 gasStart = gasleft();
        vm.prank(owner);
        vaultCore.setAllowed(notAllowedVault, true);
        uint256 gasUsed = gasStart - gasleft();

        console.log("Gas used for setAllowed:", gasUsed);
        assertTrue(gasUsed < 50000);
    }

    // ============ REVERT TESTS ============

    function testRevert_SetAllowedNotOwner() public {
        vm.prank(user1); // Not owner
        vm.expectRevert();
        vaultCore.setAllowed(notAllowedVault, true);
    }

    function testRevert_DepositNotAllowed() public {
        vm.prank(notAllowedVault);
        vm.expectRevert(VaultCore.notAllowed.selector);
        vaultCore.deposit(user1, address(mockUSDC), 1000 * 10**6);
    }

    function testRevert_WithdrawNotAllowed() public {
        vm.prank(notAllowedVault);
        vm.expectRevert(VaultCore.notAllowed.selector);
        vaultCore.withdraw(user2, address(mockUSDC), 1000 * 10**6);
    }

    function testRevert_DepositInsufficientBalance() public {
        uint256 hugeAmount = INITIAL_BALANCE * 2;

        vm.prank(allowedVault);
        vm.expectRevert(); // SafeERC20 will revert on insufficient balance
        vaultCore.deposit(user1, address(mockUSDC), hugeAmount);
    }

    function testRevert_DepositNoApproval() public {
        // Remove approval
        vm.prank(user1);
        mockUSDC.approve(address(vaultCore), 0);

        vm.prank(allowedVault);
        vm.expectRevert(); // SafeERC20 will revert on insufficient allowance
        vaultCore.deposit(user1, address(mockUSDC), 1000 * 10**6);
    }

    function testRevert_WithdrawInsufficientBalance() public {
        vm.prank(allowedVault);
        vm.expectRevert(); // SafeERC20 will revert on insufficient balance
        vaultCore.withdraw(user2, address(mockUSDC), 1000 * 10**6);
    }
}