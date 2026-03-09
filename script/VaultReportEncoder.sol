// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
 * @title VaultReportEncoder
 * @notice Helper contract for encoding reports to send to Vault via CRE
 * @dev This is NOT deployed on-chain; it's a utility for off-chain report generation
 *
 * Usage:
 * - Use these functions to encode reports in your CRE workflow
 * - Pass the encoded bytes to your CRE workflow's EVM write output
 * - The Vault will decode and process the report through _processReport()
 *
 * Reference: Vault.sol action codes
 *   ACTION_MINT_SHARES_ERC20 = 0
 *   ACTION_DEPLOY_ERC20 = 1
 *   ACTION_REDEEM_SHARES_ERC20 = 2
 *   ACTION_MINT_SHARES_1155 = 3
 *   ACTION_DEPOSIT_EXISTING_1155 = 4
 *   ACTION_REDEEM_SHARES_1155 = 5
 */

// Note: This is a reference implementation
// In your CRE workflow, use the equivalent encoding logic
// Example (JavaScript):
//   const report = ethers.AbiCoder.defaultAbiCoder().encode(
//     ['uint8', 'uint256', 'address', 'address[]', 'uint256[]', 'uint256'],
//     [0, vaultId, user, collaterals, amounts, sharesToMint]
//   );

contract VaultReportEncoder {
    // ============================================================================
    // Report Encoding Functions
    // ============================================================================

    /**
     * @notice Encodes a report for ACTION_MINT_SHARES_ERC20
     * @param vaultId The vault ID to deposit into
     * @param user The user address performing the action
     * @param collaterals Array of collateral token addresses
     * @param amounts Array of collateral amounts (must match collaterals length)
     * @param sharesToMint Number of shares to mint
     * @return The encoded report bytes
     *
     * Action Code: 0 (ACTION_MINT_SHARES_ERC20)
     * Used when: Depositing collateral to receive ERC20 shares
     */
    function encodeMintSharesERC20(
        uint256 vaultId,
        address user,
        address[] memory collaterals,
        uint256[] memory amounts,
        uint256 sharesToMint
    ) internal pure returns (bytes memory) {
        return abi.encode(uint8(0), vaultId, user, collaterals, amounts, sharesToMint);
    }

    /**
     * @notice Encodes a report for ACTION_DEPLOY_ERC20
     * @param name The name of the new ERC20 token
     * @param symbol The symbol of the new ERC20 token
     * @param collaterals Array of collateral token addresses backing the tokenizer
     * @param user The user (deployer) address
     * @return The encoded report bytes
     *
     * Action Code: 1 (ACTION_DEPLOY_ERC20)
     * Used when: Creating a new ERC20 tokenizer for specific collaterals
     */
    function encodeDeployERC20(
        string memory name,
        string memory symbol,
        address[] memory collaterals,
        address user
    ) internal pure returns (bytes memory) {
        return abi.encode(uint8(1), name, symbol, collaterals, user);
    }

    /**
     * @notice Encodes a report for ACTION_REDEEM_SHARES_ERC20
     * @param vaultId The vault ID to redeem from
     * @param user The user address redeeming shares
     * @param sharesToBurn Number of shares to burn
     * @param receiver Address to receive the redeemed collateral
     * @return The encoded report bytes
     *
     * Action Code: 2 (ACTION_REDEEM_SHARES_ERC20)
     * Used when: Burning ERC20 shares to receive collateral back
     */
    function encodeRedeemSharesERC20(
        uint256 vaultId,
        address user,
        uint256 sharesToBurn,
        address receiver
    ) internal pure returns (bytes memory) {
        return abi.encode(uint8(2), vaultId, user, sharesToBurn, receiver);
    }

    /**
     * @notice Encodes a report for ACTION_MINT_SHARES_1155
     * @param user The user address performing the action
     * @param collaterals Array of collateral token addresses
     * @param amounts Array of collateral amounts
     * @param sharesToMint Number of shares to mint
     * @return The encoded report bytes
     *
     * Action Code: 3 (ACTION_MINT_SHARES_1155)
     * Used when: Creating a new ERC1155 batch with collateral
     * Note: tokenId parameter is unused in this action
     */
    function encodeMintShares1155(
        address user,
        address[] memory collaterals,
        uint256[] memory amounts,
        uint256 sharesToMint
    ) internal pure returns (bytes memory) {
        return abi.encode(uint8(3), uint256(0), user, collaterals, amounts, sharesToMint);
    }

    /**
     * @notice Encodes a report for ACTION_DEPOSIT_EXISTING_1155
     * @param tokenId The ERC1155 token ID to deposit into
     * @param user The user address performing the action
     * @param collaterals Array of collateral token addresses
     * @param amounts Array of collateral amounts
     * @param sharesToMint Number of shares to mint
     * @return The encoded report bytes
     *
     * Action Code: 4 (ACTION_DEPOSIT_EXISTING_1155)
     * Used when: Adding collateral to an existing ERC1155 batch
     */
    function encodeDepositExisting1155(
        uint256 tokenId,
        address user,
        address[] memory collaterals,
        uint256[] memory amounts,
        uint256 sharesToMint
    ) internal pure returns (bytes memory) {
        return abi.encode(uint8(4), tokenId, user, collaterals, amounts, sharesToMint);
    }

    /**
     * @notice Encodes a report for ACTION_REDEEM_SHARES_1155
     * @param tokenId The ERC1155 token ID to redeem
     * @param user The user address redeeming shares
     * @param sharesToBurn Number of shares to burn
     * @param receiver Address to receive the redeemed collateral
     * @return The encoded report bytes
     *
     * Action Code: 5 (ACTION_REDEEM_SHARES_1155)
     * Used when: Burning ERC1155 shares to receive collateral back
     */
    function encodeRedeemShares1155(
        uint256 tokenId,
        address user,
        uint256 sharesToBurn,
        address receiver
    ) internal pure returns (bytes memory) {
        return abi.encode(uint8(5), tokenId, user, sharesToBurn, receiver);
    }

    // ============================================================================
    // Utility Functions
    // ============================================================================

    /**
     * @notice Validates collaterals and amounts arrays match
     * @param collaterals Array of collateral addresses
     * @param amounts Array of collateral amounts
     * @return True if arrays are equal length
     */
    function validateCollateralsAndAmounts(
        address[] memory collaterals,
        uint256[] memory amounts
    ) internal pure returns (bool) {
        require(
            collaterals.length == amounts.length,
            "Collaterals and amounts length mismatch"
        );
        require(collaterals.length > 0, "Collaterals array is empty");
        return true;
    }

    /**
     * @notice Decodes an action code from a report
     * @param report The encoded report bytes
     * @return actionCode The action code (0-5)
     */
    function decodeActionCode(bytes memory report) internal pure returns (uint8 actionCode) {
        require(report.length >= 1, "Report too short");
        actionCode = uint8(report[0]);
    }
}

// ============================================================================
// EXAMPLE USAGE IN CRE WORKFLOW
// ============================================================================

/**
 * JavaScript Example for encoding reports in your CRE workflow:
 *
 * const ethers = require('ethers');
 *
 * // Encode ACTION_MINT_SHARES_ERC20
 * function encodeMintSharesERC20(vaultId, user, collaterals, amounts, sharesToMint) {
 *   const abiCoder = ethers.AbiCoder.defaultAbiCoder();
 *   return abiCoder.encode(
 *     ['uint8', 'uint256', 'address', 'address[]', 'uint256[]', 'uint256'],
 *     [0, vaultId, user, collaterals, amounts, sharesToMint]
 *   );
 * }
 *
 * // Example usage:
 * const vaultId = 1;
 * const user = "0x1234...";
 * const collaterals = ["0xDEF...token1", "0xABC...token2"];
 * const amounts = ["1000000000000000000", "2000000000000000000"]; // 1 and 2 tokens
 * const sharesToMint = "5000000000000000000"; // 5 shares
 *
 * const report = encodeMintSharesERC20(vaultId, user, collaterals, amounts, sharesToMint);
 *
 * // Use report in EVM write capability:
 * return {
 *   target_address: "0xVaultAddress...",
 *   report_data: report,
 *   function_selector: "onReport"
 * };
 */

/**
 * Solidity Example for encoding in your CRE workflow (if using custom contract):
 *
 * contract WorkflowReportGenerator {
 *   function generateMintReport(
 *     uint256 vaultId,
 *     address user,
 *     address[] memory collaterals,
 *     uint256[] memory amounts,
 *     uint256 sharesToMint
 *   ) external pure returns (bytes memory) {
 *     return abi.encode(
 *       uint8(0),
 *       vaultId,
 *       user,
 *       collaterals,
 *       amounts,
 *       sharesToMint
 *     );
 *   }
 * }
 */
