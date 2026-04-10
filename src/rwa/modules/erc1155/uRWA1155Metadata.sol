// SPDX-License-Identifier: MIT
pragma solidity ^0.8.29;

import {uRWA1155} from "../../uRWA1155.sol";

contract uRWA1155Metadata is uRWA1155 {

    event DocumentRemoved(uint indexed id,bytes32 indexed _name, string _uri, bytes32 _documentHash);
    event DocumentUpdated(uint indexed id,bytes32 indexed _name, string _uri, bytes32 _documentHash);

    mapping(uint256 => mapping(bytes32 => string)) private _documents;
    mapping(uint256 => mapping(bytes32 => bytes32)) private _documentHashes;
    mapping(uint256 => mapping(bytes32 => uint32)) private _documentUpdates;
    mapping(uint256 => mapping(bytes32 => uint256)) private _documentIndex;
    mapping(uint256 => bytes32[]) private _documentNames;

    constructor(string memory _uri, address initialAdmin)
        uRWA1155(_uri, initialAdmin)
    {}

    function getDocument(bytes32 _name , uint256 id) external view returns (string memory, bytes32, uint256) {
        return (_documents[id][_name], _documentHashes[id][_name], _documentUpdates[id][_name]);
    }

    function setDocument(uint256 id ,bytes32 _name, string memory _uri, bytes32 _documentHash) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _documents[id][_name] = _uri;
        _documentHashes[id][_name] = _documentHash;
        _documentUpdates[id][_name] = uint32(block.timestamp);
        _documentNames[id].push(_name);
        _documentIndex[id][_name] = _documentNames[id].length - 1;
        emit DocumentUpdated(id,_name, _uri, _documentHash);
    }

    function removeDocument(bytes32 _name, uint256 id) public onlyRole(DEFAULT_ADMIN_ROLE){
        string memory uri = _documents[id][_name];
        bytes32 documentHash = _documentHashes[id][_name];
        delete _documents[id][_name];
        delete _documentHashes[id][_name];
        _documentUpdates[id][_name] = uint32(block.timestamp); // instead of deleting, we mark when it was deleted as latest update
        _documentNames[id][_documentIndex[id][_name]] = _documentNames[id][_documentNames[id].length - 1];
        _documentNames[id].pop();
        emit DocumentRemoved(id,_name, uri, documentHash);
    }

    function getAllDocuments(uint256 id) external view returns (bytes32[] memory) {
        return _documentNames[id];
    }
}