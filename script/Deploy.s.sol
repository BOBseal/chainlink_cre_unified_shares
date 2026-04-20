// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {VaultCore} from "../src/vaultcore/core.sol";
import {CSE20} from "../src/CSE20.sol";
import {CSE721} from "../src/CSE721.sol";
import {CSE1155} from "../src/CSE1155.sol";

contract Deploy is Script {
    function run() external { 
        ////// SEPOLIA CONFIGURATION - UPDATE FOR OTHER NETWORKS //////
        address trustedForwarder = 0x15fC6ae953E024d975e77382eEeC56A9101f9F88;
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        string memory cse721Name = "Share Token 721";

        string memory cse721Symbol = "SHARE721";

        string memory cse1155Uri = "0x00";

        vm.startBroadcast(deployerKey);

        VaultCore core = new VaultCore();
        CSE20 cse20 = new CSE20(trustedForwarder, address(core));
        CSE721 cse721 = new CSE721(trustedForwarder, address(core), cse721Name, cse721Symbol);
        CSE1155 cse1155 = new CSE1155(trustedForwarder, address(core), cse1155Uri);

        core.setAllowed(address(cse20), true);
        core.setAllowed(address(cse721), true);
        core.setAllowed(address(cse1155), true);

        vm.stopBroadcast();

        console.log("VaultCore:", address(core));
        console.log("CSE20:", address(cse20));
        console.log("CSE721:", address(cse721));
        console.log("CSE1155:", address(cse1155));
    }
}
