// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {uRWA20Metadata} from "../src/rwa/modules/erc20/uRWA20Metadata.sol";

contract uRWA20MetadataTest is Test {
    uRWA20Metadata public metadata;

    address public admin = address(0x123);
    address public user1 = address(0x456);
    address public user2 = address(0x789);

    function setUp() public {
        vm.prank(admin);
        metadata = new uRWA20Metadata("Test Token", "TEST", admin);
    }

    // ============ UNIT TESTS ============

    function test_Constructor() public {
        assertEq(metadata.name(), "Test Token");
        assertEq(metadata.symbol(), "TEST");
        assertTrue(metadata.hasRole(metadata.DEFAULT_ADMIN_ROLE(), admin));
    }

    function test_SetDocument() public {
        bytes32 docName = keccak256("KYC_DOCUMENT");
        string memory docUri = "https://example.com/kyc.pdf";
        bytes32 docHash = keccak256("document content");

        vm.prank(admin);
        metadata.setDocument(docName, docUri, docHash);

        (string memory retrievedUri, bytes32 retrievedHash, uint256 updateTime) = metadata.getDocument(docName);
        assertEq(retrievedUri, docUri);
        assertEq(retrievedHash, docHash);
        assertTrue(updateTime > 0);

        // Check document is in the list
        bytes32[] memory allDocs = metadata.getAllDocuments();
        assertEq(allDocs.length, 1);
        assertEq(allDocs[0], docName);
    }

    function test_RemoveDocument() public {
        // First set a document
        bytes32 docName = keccak256("KYC_DOCUMENT");
        string memory docUri = "https://example.com/kyc.pdf";
        bytes32 docHash = keccak256("document content");

        vm.prank(admin);
        metadata.setDocument(docName, docUri, docHash);

        // Now remove it
        vm.prank(admin);
        metadata.removeDocument(docName);

        (string memory retrievedUri, bytes32 retrievedHash, uint256 updateTime) = metadata.getDocument(docName);
        assertEq(retrievedUri, ""); // Should be empty
        assertEq(retrievedHash, bytes32(0)); // Should be zero
        assertTrue(updateTime > 0); // Update time should still be set

        // Check document is removed from the list
        bytes32[] memory allDocs = metadata.getAllDocuments();
        assertEq(allDocs.length, 0);
    }

    function test_MultipleDocuments() public {
        // Set multiple documents
        bytes32 docName1 = keccak256("KYC_DOCUMENT");
        bytes32 docName2 = keccak256("AUDIT_REPORT");
        bytes32 docName3 = keccak256("LEGAL_AGREEMENT");

        vm.prank(admin);
        metadata.setDocument(docName1, "uri1", keccak256("hash1"));

        vm.prank(admin);
        metadata.setDocument(docName2, "uri2", keccak256("hash2"));

        vm.prank(admin);
        metadata.setDocument(docName3, "uri3", keccak256("hash3"));

        // Check all documents are present
        bytes32[] memory allDocs = metadata.getAllDocuments();
        assertEq(allDocs.length, 3);

        // Remove middle document
        vm.prank(admin);
        metadata.removeDocument(docName2);

        allDocs = metadata.getAllDocuments();
        assertEq(allDocs.length, 2);

        // Check remaining documents
        bool foundDoc1 = false;
        bool foundDoc3 = false;
        for (uint256 i = 0; i < allDocs.length; i++) {
            if (allDocs[i] == docName1) foundDoc1 = true;
            if (allDocs[i] == docName3) foundDoc3 = true;
        }
        assertTrue(foundDoc1);
        assertTrue(foundDoc3);
    }

    function test_UpdateDocument() public {
        bytes32 docName = keccak256("KYC_DOCUMENT");

        // Set initial document
        vm.prank(admin);
        metadata.setDocument(docName, "uri1", keccak256("hash1"));

        (string memory uri1, bytes32 hash1, uint256 time1) = metadata.getDocument(docName);

        // Update document
        vm.prank(admin);
        metadata.setDocument(docName, "uri2", keccak256("hash2"));

        (string memory uri2, bytes32 hash2, uint256 time2) = metadata.getDocument(docName);

        assertEq(uri2, "uri2");
        assertEq(hash2, keccak256("hash2"));
        assertTrue(time2 > time1);

        // Check only one document in list (not duplicated)
        bytes32[] memory allDocs = metadata.getAllDocuments();
        assertEq(allDocs.length, 1);
        assertEq(allDocs[0], docName);
    }

    // ============ FUZZ TESTS ============

    function testFuzz_SetDocument(bytes32 docName, string memory docUri, bytes32 docHash) public {
        // Ensure docName is not empty
        vm.assume(docName != bytes32(0));

        vm.prank(admin);
        metadata.setDocument(docName, docUri, docHash);

        (string memory retrievedUri, bytes32 retrievedHash, uint256 updateTime) = metadata.getDocument(docName);
        assertEq(retrievedUri, docUri);
        assertEq(retrievedHash, docHash);
        assertTrue(updateTime > 0);
    }

    function testFuzz_MultipleDocuments(uint256 numDocs) public {
        numDocs = bound(numDocs, 1, 20);

        bytes32[] memory docNames = new bytes32[](numDocs);

        for (uint256 i = 0; i < numDocs; i++) {
            docNames[i] = keccak256(abi.encode("doc", i));
            vm.prank(admin);
            metadata.setDocument(docNames[i], string(abi.encode("uri", i)), keccak256(abi.encode("hash", i)));
        }

        bytes32[] memory allDocs = metadata.getAllDocuments();
        assertEq(allDocs.length, numDocs);

        // Remove half of them
        for (uint256 i = 0; i < numDocs / 2; i++) {
            vm.prank(admin);
            metadata.removeDocument(docNames[i]);
        }

        allDocs = metadata.getAllDocuments();
        assertEq(allDocs.length, numDocs - numDocs / 2);
    }

    // ============ GAS TESTS ============

    function testGas_SetDocument() public {
        bytes32 docName = keccak256("KYC_DOCUMENT");
        string memory docUri = "https://example.com/kyc.pdf";
        bytes32 docHash = keccak256("document content");

        uint256 gasStart = gasleft();
        vm.prank(admin);
        metadata.setDocument(docName, docUri, docHash);
        uint256 gasUsed = gasStart - gasleft();

        console.log("Gas used for setDocument:", gasUsed);
        assertTrue(gasUsed < 150000);
    }

    function testGas_RemoveDocument() public {
        // Setup: set document first
        bytes32 docName = keccak256("KYC_DOCUMENT");
        vm.prank(admin);
        metadata.setDocument(docName, "uri", keccak256("hash"));

        uint256 gasStart = gasleft();
        vm.prank(admin);
        metadata.removeDocument(docName);
        uint256 gasUsed = gasStart - gasleft();

        console.log("Gas used for removeDocument:", gasUsed);
        assertTrue(gasUsed < 100000);
    }

    function testGas_GetDocument() public {
        bytes32 docName = keccak256("KYC_DOCUMENT");
        vm.prank(admin);
        metadata.setDocument(docName, "uri", keccak256("hash"));

        uint256 gasStart = gasleft();
        metadata.getDocument(docName);
        uint256 gasUsed = gasStart - gasleft();

        console.log("Gas used for getDocument:", gasUsed);
        assertTrue(gasUsed < 50000);
    }

    // ============ REVERT TESTS ============

    function testRevert_SetDocumentNotAdmin() public {
        bytes32 docName = keccak256("KYC_DOCUMENT");

        vm.prank(user1); // Not admin
        vm.expectRevert();
        metadata.setDocument(docName, "uri", keccak256("hash"));
    }

    function testRevert_RemoveDocumentNotAdmin() public {
        bytes32 docName = keccak256("KYC_DOCUMENT");
        vm.prank(admin);
        metadata.setDocument(docName, "uri", keccak256("hash"));

        vm.prank(user1); // Not admin
        vm.expectRevert();
        metadata.removeDocument(docName);
    }

    function testRevert_RemoveNonExistentDocument() public {
        bytes32 docName = keccak256("NON_EXISTENT");

        vm.prank(admin);
        // Should not revert - just removes from empty state
        metadata.removeDocument(docName);

        // Verify it's still "removed" (empty)
        (string memory uri, bytes32 hash, uint256 time) = metadata.getDocument(docName);
        assertEq(uri, "");
        assertEq(hash, bytes32(0));
        assertTrue(time > 0);
    }

    function testRevert_GetDocumentNonExistent() public {
        bytes32 docName = keccak256("NON_EXISTENT");

        (string memory uri, bytes32 hash, uint256 time) = metadata.getDocument(docName);
        assertEq(uri, "");
        assertEq(hash, bytes32(0));
        assertEq(time, 0);
    }
}