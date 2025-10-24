// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import {TenexiumProtocol} from "../../contracts/core/TenexiumProtocol.sol";
import {console} from "forge-std/console.sol";

contract DeployImplementation is Script {
    function run() external {
        // ✅ Fetch the PRIVATE_KEY from environment and ensure it starts with "0x"
        string memory rawPrivateKey = vm.envString("PRIVATE_KEY");
        string memory prefixedPrivateKey = rawPrivateKey;

        if (bytes(rawPrivateKey).length < 2 || bytes(rawPrivateKey)[0] != "0" || bytes(rawPrivateKey)[1] != "x") {
            prefixedPrivateKey = string(abi.encodePacked("0x", rawPrivateKey));
        }

        uint256 deployerPrivateKey = vm.parseUint(prefixedPrivateKey);
        vm.startBroadcast(deployerPrivateKey);

        // ✅ Deploy the new implementation
        TenexiumProtocol newImpl = new TenexiumProtocol();
        console.log(" New implementation deployed at:", address(newImpl));
        vm.stopBroadcast();
    }
}
