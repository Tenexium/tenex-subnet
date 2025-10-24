// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {TenexiumProtocol} from "../../contracts/core/TenexiumProtocol.sol";
import {DeployConfig} from "./DeployConfig.s.sol";
import {console} from "forge-std/console.sol";

contract DeployTenexiumProtocol is Script, DeployConfig {
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

        // ✅ Encode the constructor arguments
        bytes memory initCalldata = abi.encodeWithSelector(
            TenexiumProtocol.initialize.selector,
            MAX_LEVERAGE, // maxLeverage: 10x
            LIQUIDATION_THRESHOLD, // liquidation threshold: 110%
            MIN_LIQUIDITY_THRESHOLD, // minLiquidity: 100 TAO
            MAX_UTILIZATION_RATE, // maxUtil: 90%
            LIQUIDITY_BUFFER_RATIO, // buffer: 20%
            USER_COOLDOWN_BLOCKS, // user cooldown: 10 blocks
            LP_COOLDOWN_BLOCKS, // LP cooldown: 10 blocks
            BUYBACK_RATE, // buyback rate: 50%
            BUYBACK_INTERVAL_BLOCKS, // buyback interval: 7200 blocks
            BUYBACK_EXECUTION_THRESHOLD, // buyback execution threshold: 1 TAO
            VESTING_DURATION_BLOCKS, // vesting duration: ~12 months
            CLIFF_DURATION_BLOCKS, // cliff: ~3 months
            BASE_TRADING_FEE, // trading fee: 0.3%
            BORROWING_FEE_RATE, // borrowing baseline: 0.005%
            BASE_LIQUIDATION_FEE, // liquidation fee: 2%
            getTradingFeeDistribution(), // trading fee distribution
            getBorrowingFeeDistribution(), // borrowing fee distribution
            getLiquidationFeeDistribution(), // liquidation fee distribution
            getTierThresholds(), // tier thresholds
            getTierFeeDiscounts(), // tier fee discounts
            getTierMaxLeverages(), // tier leverage limits
            PROTOCOL_VALIDATOR_HOTKEY // protocol validator hotkey
        );

        vm.startBroadcast(deployerPrivateKey);
        // ✅ Deploy the proxy
        ERC1967Proxy proxy = new ERC1967Proxy(address(newImpl), initCalldata);
        console.log(" Proxy deployed at:", address(proxy));
        console.log(" Implementation deployed at:", address(newImpl));
        vm.stopBroadcast();
    }
}
