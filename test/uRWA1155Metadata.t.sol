// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {uRWA1155Metadata} from "../src/rwa/modules/erc1155/uRWA1155Metadata.sol";

contract uRWA1155MetadataTest is Test {
    uRWA1155Metadata public metadata;

    address public admin = address(0x123);
    address public user1 = address(0x456);
    address public user2 = address(0x789);

    uint256 public constant TOKEN_ID_1 = 1;
    uint256 public constant TOKEN_ID_2 = 2;

    function setUp() public {
        vm.prank(admin);
        metadata = new uRWA1155Metadata("https://example.com/metadata/{id}", admin);
    }

    // ============ UNIT TESTS ============

    function test_Constructor() public {
        assertEq(metadata.uri(TOKEN_ID_1), "https://example.com/metadata/{id}");
        assertTrue(metadata.hasRole(metadata.DEFAULT_ADMIN_ROLE(), admin));
    }

    function test_SetDocument() public {
        bytes32 docName = keccak256("KYC_DOCUMENT");
        string memory docUri = "https://example.com/kyc.pdf";
        bytes32 docHash = keccak256("document content");

        vm.prank(admin);
        metadata.setDocument(TOKEN_ID_1, docName, docUri, docHash);

        (string memory retrievedUri, bytes32 retrievedHash, uint256 updateTime) = metadata.getDocument(docName, TOKEN_ID_1);
        assertEq(retrievedUri, docUri);
        assertEq(retrievedHash, docHash);
        assertTrue(updateTime > 0);

        // Check document is in the list for this token ID
        bytes32[] memory allDocs = metadata.getAllDocuments(TOKEN_ID_1);
        assertEq(allDocs.length, 1);
        assertEq(allDocs[0], docName);

        // Check other token ID has no documents
        bytes32[] memory allDocsToken2 = metadata.getAllDocuments(TOKEN_ID_2);
        assertEq(allDocsToken2.length, 0);
    }

    function test_RemoveDocument() public {
        // First set a document
        bytes32 docName = keccak256("KYC_DOCUMENT");
        string memory docUri = "https://example.com/kyc.pdf";
        bytes32 docHash = keccak256("document content");

        vm.prank(admin);
        metadata.setDocument(TOKEN_ID_1, docName, docUri, docHash);

        // Now remove it
        vm.prank(admin);
        metadata.removeDocument(docName, TOKEN_ID_1);

        (string memory retrievedUri, bytes32 retrievedHash, uint256 updateTime) = metadata.getDocument(docName, TOKEN_ID_1);
        assertEq(retrievedUri, ""); // Should be empty
        assertEq(retrievedHash, bytes32(0)); // Should be zero
        assertTrue(updateTime > 0); // Update time should still be set

        // Check document is removed from the list
        bytes32[] memory allDocs = metadata.getAllDocuments(TOKEN_ID_1);
        assertEq(allDocs.length, 0);
    }

    function test_MultipleDocumentsPerTokenId() public {
        // Set multiple documents for token ID 1
        bytes32 docName1 = keccak256("KYC_DOCUMENT");
        bytes32 docName2 = keccak256("AUDIT_REPORT");
        bytes32 docName3 = keccak256("LEGAL_AGREEMENT");

        vm.prank(admin);
        metadata.setDocument(TOKEN_ID_1, docName1, "uri1", keccak256("hash1"));

        vm.prank(admin);
        metadata.setDocument(TOKEN_ID_1, docName2, "uri2", keccak256("hash2"));

        vm.prank(admin);
        metadata.setDocument(TOKEN_ID_1, docName3, "uri3", keccak256("hash3"));

        // Check all documents are present for token ID 1
        bytes32[] memory allDocs = metadata.getAllDocuments(TOKEN_ID_1);
        assertEq(allDocs.length, 3);

        // Set documents for token ID 2
        vm.prank(admin);
        metadata.setDocument(TOKEN_ID_2, docName1, "uri1_token2", keccak256("hash1_token2"));

        // Check token ID 2 has its own documents
        bytes32[] memory allDocsToken2 = metadata.getAllDocuments(TOKEN_ID_2);
        assertEq(allDocsToken2.length, 1);
        assertEq(allDocsToken2[0], docName1);

        // Remove document from token ID 1
        vm.prank(admin);
        metadata.removeDocument(docName2, TOKEN_ID_1);

        allDocs = metadata.getAllDocuments(TOKEN_ID_1);
        assertEq(allDocs.length, 2);

        // Check token ID 2 still has its document
        allDocsToken2 = metadata.getAllDocuments(TOKEN_ID_2);
        assertEq(allDocsToken2.length, 1);
    }

    function test_UpdateDocument() public {
        bytes32 docName = keccak256("KYC_DOCUMENT");

        // Set initial document
        vm.prank(admin);
        metadata.setDocument(TOKEN_ID_1, docName, "uri1", keccak256("hash1"));

        (string memory uri1, bytes32 hash1, uint256 time1) = metadata.getDocument(docName, TOKEN_ID_1);

        // Update document
        vm.prank(admin);
        metadata.setDocument(TOKEN_ID_1, docName, "uri2", keccak256("hash2"));

        (string memory uri2, bytes32 hash2, uint256 time2) = metadata.getDocument(docName, TOKEN_ID_1);

        assertEq(uri2, "uri2");
        assertEq(hash2, keccak256("hash2"));
        assertTrue(time2 > time1);

        // Check only one document in list (not duplicated)
        bytes32[] memory allDocs = metadata.getAllDocuments(TOKEN_ID_1);
        assertEq(allDocs.length, 1);
        assertEq(allDocs[0], docName);
    }

    // ============ FUZZ TESTS ============

    function testFuzz_SetDocument(uint256 tokenId, bytes32 docName, string memory docUri, bytes32 docHash) public {
        // Ensure docName is not empty and tokenId is reasonable
        vm.assume(docName != bytes32(0));
        tokenId = bound(tokenId, 1, 1000);

        vm.prank(admin);
        metadata.setDocument(tokenId, docName, docUri, docHash);

        (string memory retrievedUri, bytes32 retrievedHash, uint256 updateTime) = metadata.getDocument(docName, tokenId);
        assertEq(retrievedUri, docUri);
        assertEq(retrievedHash, docHash);
        assertTrue(updateTime > 0);
    }

    function testFuzz_MultipleTokenIds(uint256 numTokens) public {
        numTokens = bound(numTokens, 1, 20);

        for (uint256 i = 1; i <= numTokens; i++) {
            bytes32 docName = keccak256(abi.encode("doc", i));
            vm.prank(admin);
            metadata.setDocument(i, docName, string(abi.encode("uri", i)), keccak256(abi.encode("hash", i)));

            bytes32[] memory docs = metadata.getAllDocuments(i);
            assertEq(docs.length, 1);
            assertEq(docs[0], docName);
        }

        // Verify each token has its own document
        for (uint256 i = 1; i <= numTokens; i++) {
            bytes32[] memory docs = metadata.getAllDocuments(i);
            assertEq(docs.length, 1);
        }
    }

    // ============ GAS TESTS ============

    function testGas_SetDocument() public {
        bytes32 docName = keccak256("KYC_DOCUMENT");
        string memory docUri = "https://example.com/kyc.pdf";
        bytes32 docHash = keccak256("document content");

        uint256 gasStart = gasleft();
        vm.prank(admin);
        metadata.setDocument(TOKEN_ID_1, docName, docUri, docHash);
        uint256 gasUsed = gasStart - gasleft();

        console.log("Gas used for setDocument:", gasUsed);
        assertTrue(gasUsed < 150000);
    }

    function testGas_RemoveDocument() public {
        // Setup: set document first
        bytes32 docName = keccak256("KYC_DOCUMENT");
        vm.prank(admin);
        metadata.setDocument(TOKEN_ID_1, docName, "uri", keccak256("hash"));

        uint256 gasStart = gasleft();
        vm.prank(admin);
        metadata.removeDocument(docName, TOKEN_ID_1);
        uint256 gasUsed = gasStart - gasleft();

        console.log("Gas used for removeDocument:", gasUsed);
        assertTrue(gasUsed < 100000);
    }

    function testGas_GetDocument() public {
        bytes32 docName = keccak256("KYC_DOCUMENT");
        vm.prank(admin);
        metadata.setDocument(TOKEN_ID_1, docName, "uri", keccak256("hash"));

        uint256 gasStart = gasleft();
        metadata.getDocument(docName, TOKEN_ID_1);
        uint256 gasUsed = gasStart - gasleft();

        console.log("Gas used for getDocument:", gasUsed);
        assertTrue(gasUsed < 50000);
    }

    // ============ REVERT TESTS ============

    function testRevert_SetDocumentNotAdmin() public {
        bytes32 docName = keccak256("KYC_DOCUMENT");

        vm.prank(user1); // Not admin
        vm.expectRevert();
        metadata.setDocument(TOKEN_ID_1, docName, "uri", keccak256("hash"));
    }

    function testRevert_RemoveDocumentNotAdmin() public {
        bytes32 docName = keccak256("KYC_DOCUMENT");
        vm.prank(admin);
        metadata.setDocument(TOKEN_ID_1, docName, "uri", keccak256("hash"));

        vm.prank(user1); // Not admin
        vm.expectRevert();
        metadata.removeDocument(docName, TOKEN_ID_1);
    }

    function testRevert_RemoveNonExistentDocument() public {
        bytes32 docName = keccak256("NON_EXISTENT");

        vm.prank(admin);
        // Should not revert - just removes from empty state
        metadata.removeDocument(docName, TOKEN_ID_1);

        // Verify it's still "removed" (empty)
        (string memory uri, bytes32 hash, uint256 time) = metadata.getDocument(docName, TOKEN_ID_1);
        assertEq(uri, "");
        assertEq(hash, bytes32(0));
        assertTrue(time > 0);
    }

    function testRevert_GetDocumentNonExistent() public {
        bytes32 docName = keccak256("NON_EXISTENT");

        (string memory uri, bytes32 hash, uint256 time) = metadata.getDocument(docName, TOKEN_ID_1);
        assertEq(uri, "");
        assertEq(hash, bytes32(0));
        assertEq(time, 0);
    }
}